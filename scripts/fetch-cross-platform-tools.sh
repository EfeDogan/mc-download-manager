#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/CrossPlatform/app/src-tauri/binaries"
VERSION="2026.08.19"
if [[ $# -gt 0 ]]; then
  TARGET="$1"
else
  RUSTC_BIN="$(command -v rustc || true)"
  if [[ -z "$RUSTC_BIN" && -x "${CARGO_HOME:-$HOME/.cargo}/bin/rustc" ]]; then
    RUSTC_BIN="${CARGO_HOME:-$HOME/.cargo}/bin/rustc"
  fi
  if [[ -z "$RUSTC_BIN" ]]; then
    echo "rustc was not found; pass the target triple as the first argument" >&2
    exit 1
  fi
  TARGET="$($RUSTC_BIN --print host-tuple)"
fi

case "$TARGET" in
  x86_64-unknown-linux-gnu)
    ASSET="yt-dlp_linux"
    DEST="$OUT/yt-dlp-$TARGET"
    SHA256="58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a"
    ;;
  x86_64-pc-windows-msvc)
    ASSET="yt-dlp.exe"
    DEST="$OUT/yt-dlp-$TARGET.exe"
    SHA256="66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a"
    ;;
  *)
    echo "Unsupported cross-platform desktop target: $TARGET" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT"
if [[ -f "$DEST" ]] && printf '%s  %s\n' "$SHA256" "$DEST" | sha256sum --check --status; then
  echo "yt-dlp $VERSION already verified for $TARGET"
  exit 0
fi

PART="$DEST.part"
curl --fail --location --retry 3 \
  "https://github.com/yt-dlp/yt-dlp/releases/download/$VERSION/$ASSET" \
  --output "$PART"
printf '%s  %s\n' "$SHA256" "$PART" | sha256sum --check
mv "$PART" "$DEST"
chmod 0755 "$DEST"
echo "Downloaded and verified yt-dlp $VERSION for $TARGET"
