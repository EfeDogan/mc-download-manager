#!/bin/zsh
# Release build + (optional) Developer ID signing/notarization + DMG.
#
#   scripts/build.sh                 → build/MC Download Manager <version>.dmg (ad-hoc signed)
#   CODESIGN_IDENTITY="Developer ID Application: Ad Soyad (TEAMID)" scripts/build.sh
#   ... + NOTARY_PROFILE=<notarytool keychain profili>  → notarize + staple
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MC Download Manager"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
EXPORT="$BUILD/release"
IDENTITY="${CODESIGN_IDENTITY:--}"          # "-" = ad-hoc
VERSION="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)"

echo "▶ Tools (yt-dlp, ffmpeg)"
[[ -x Tools/yt-dlp && -x Tools/ffmpeg ]] || scripts/fetch-tools.sh

echo "▶ Icons"
swiftc -O scripts/make_icons.swift -o "$BUILD/make_icons" 2>/dev/null
"$BUILD/make_icons" "$BUILD/icons" >/dev/null
cp "$BUILD"/icons/ext/*.png Extension/icons/
mkdir -p App/Assets.xcassets/AppIcon.appiconset
cp "$BUILD"/icons/AppIcon.iconset/*.png App/Assets.xcassets/AppIcon.appiconset/

if command -v xcodegen >/dev/null; then
  echo "▶ Xcode project (xcodegen)"
  xcodegen generate >/dev/null
fi

echo "▶ xcodebuild (Release)"
rm -rf "$EXPORT"
xcodebuild -project MCDownloadManager.xcodeproj -scheme MCDownloadManager -configuration Release \
  -derivedDataPath "$DERIVED" \
  CONFIGURATION_BUILD_DIR="$EXPORT" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" \
  build 2>&1 | grep -E "error:|warning: Tools|BUILD" || true

APP="$EXPORT/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "✗ App was not produced"; exit 1; }

echo "▶ Code signing ($IDENTITY)"
HELPER_ENT="$BUILD/helpers.entitlements"
cat > "$HELPER_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.cs.allow-jit</key><true/>
</dict></plist>
PLIST
# Inside-out: helper binaries → extension → app
for bin in "$APP/Contents/Helpers/"*; do
  [[ -f "$bin" ]] && codesign --force --options runtime --timestamp=none --entitlements "$HELPER_ENT" --sign "$IDENTITY" "$bin"
done
codesign --force --options runtime --timestamp=none \
  --entitlements SafariExtension/SafariExtension.entitlements \
  --sign "$IDENTITY" "$APP/Contents/PlugIns/$APP_NAME Extension.appex"
codesign --force --options runtime --timestamp=none \
  --entitlements App/App.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature verified"

echo "▶ DMG"
DMG="$BUILD/$APP_NAME $VERSION.dmg"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<TXT
MC Download Manager $VERSION

1) Drag "MC Download Manager.app" to the Applications folder.
2) If macOS blocks the first launch: System Settings ▸ Privacy & Security ▸ "Open Anyway".
3) Safari: Settings ▸ Extensions ▸ enable MC Download Manager.
   Chrome: chrome://extensions ▸ Developer mode ▸ "Load unpacked" ▸ pick the folder shown in
           the app under Settings ▸ Browser ▸ "Show Folder".

--- Türkçe ---
1) "MC Download Manager.app" simgesini Applications klasörüne sürükleyin.
2) İlk açılışta macOS uyarı verirse: Sistem Ayarları ▸ Gizlilik ve Güvenlik ▸ "Yine de Aç".
3) Safari: Ayarlar ▸ Uzantılar ▸ MC Download Manager'ı etkinleştirin.
   Chrome: chrome://extensions ▸ Geliştirici modu ▸ "Paketlenmemiş öğe yükle" ▸
           uygulama içindeki Ayarlar ▸ Tarayıcı ▸ "Klasörü Göster" ile açılan klasörü seçin.
TXT
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

if [[ -n "${NOTARY_PROFILE:-}" && "$IDENTITY" != "-" ]]; then
  echo "▶ Notarization ($NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "✓ Ready: $DMG"
du -h "$DMG" | cut -f1
