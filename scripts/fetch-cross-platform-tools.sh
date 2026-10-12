#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/CrossPlatform/app/src-tauri/binaries"
YTDLP_VERSION="2026.08.19"
DENO_VERSION="2.9.7"
FFMPEG_TAG="autobuild-2026-10-11-18-51"
FFMPEG_BUILD="N-127371-gd9242028a6"
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
    YTDLP_ASSET="yt-dlp_linux"
    YTDLP_DEST="$OUT/yt-dlp-$TARGET"
    YTDLP_SHA256="58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a"
    DENO_ASSET="deno-$TARGET.zip"
    DENO_MEMBER="deno"
    DENO_DEST="$OUT/deno-$TARGET"
    DENO_ARCHIVE_SHA256="c6527f24f4b16031d3ae4fa9f658d5f11534c8d84ce7dc8502420280919c3490"
    DENO_BINARY_SHA256="ce6a052beb97c2b92de67077e3f3924ba7c9661ede0d8dc2f66a116a3c841f21"
    FFMPEG_ASSET="ffmpeg-$FFMPEG_BUILD-linux64-gpl.tar.xz"
    FFMPEG_MEMBER="ffmpeg-$FFMPEG_BUILD-linux64-gpl/bin/ffmpeg"
    FFMPEG_LICENSE_MEMBER="ffmpeg-$FFMPEG_BUILD-linux64-gpl/LICENSE.txt"
    FFMPEG_DEST="$OUT/ffmpeg-$TARGET"
    FFMPEG_ARCHIVE_SHA256="a52cb01bd406d885baaacbe9960cf4c0f417ed12501db9d04cd73dc5c704a2e9"
    FFMPEG_BINARY_SHA256="85bb81de2a16b77ba780ec65e0f4e18b0f4844a9cbb1bf0bc987523603aca361"
    FFMPEG_ARCHIVE_KIND="tar"
    ;;
  x86_64-pc-windows-msvc)
    YTDLP_ASSET="yt-dlp.exe"
    YTDLP_DEST="$OUT/yt-dlp-$TARGET.exe"
    YTDLP_SHA256="66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a"
    DENO_ASSET="deno-$TARGET.zip"
    DENO_MEMBER="deno.exe"
    DENO_DEST="$OUT/deno-$TARGET.exe"
    DENO_ARCHIVE_SHA256="a0c3101b4158d1dfb7d6a78a7bf0f3de80c96bb423c152beec8beb22786f2238"
    DENO_BINARY_SHA256="e020f3e232bd16e33768dee528e5983349c962952051ced0a5d58ad42f5d9b33"
    FFMPEG_ASSET="ffmpeg-$FFMPEG_BUILD-win64-gpl.zip"
    FFMPEG_MEMBER="ffmpeg-$FFMPEG_BUILD-win64-gpl/bin/ffmpeg.exe"
    FFMPEG_LICENSE_MEMBER="ffmpeg-$FFMPEG_BUILD-win64-gpl/LICENSE.txt"
    FFMPEG_DEST="$OUT/ffmpeg-$TARGET.exe"
    FFMPEG_ARCHIVE_SHA256="8e730c0127962329c8744e41d6a6fd706444630192c8df7193705fb2ffd917e6"
    FFMPEG_BINARY_SHA256="06fd43f8889eea3325102dbed4b7042fe7410c496a09857eec77243b2e73565e"
    FFMPEG_ARCHIVE_KIND="zip"
    ;;
  *)
    echo "Unsupported cross-platform desktop target: $TARGET" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT"
if [[ -f "$YTDLP_DEST" ]] && printf '%s  %s\n' "$YTDLP_SHA256" "$YTDLP_DEST" | sha256sum --check --status; then
  echo "yt-dlp $YTDLP_VERSION already verified for $TARGET"
else
  YTDLP_PART="$YTDLP_DEST.part"
  curl --fail --location --retry 3 \
    "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/$YTDLP_ASSET" \
    --output "$YTDLP_PART"
  printf '%s  %s\n' "$YTDLP_SHA256" "$YTDLP_PART" | sha256sum --check
  mv "$YTDLP_PART" "$YTDLP_DEST"
  chmod 0755 "$YTDLP_DEST"
  echo "Downloaded and verified yt-dlp $YTDLP_VERSION for $TARGET"
fi

if [[ -f "$DENO_DEST" ]] && printf '%s  %s\n' "$DENO_BINARY_SHA256" "$DENO_DEST" | sha256sum --check --status; then
  echo "Deno $DENO_VERSION already verified for $TARGET"
else
  DENO_ARCHIVE="$DENO_DEST.zip.part"
  DENO_PART="$DENO_DEST.part"
  curl --fail --location --retry 3 \
    "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/$DENO_ASSET" \
    --output "$DENO_ARCHIVE"
  printf '%s  %s\n' "$DENO_ARCHIVE_SHA256" "$DENO_ARCHIVE" | sha256sum --check
  unzip -p "$DENO_ARCHIVE" "$DENO_MEMBER" > "$DENO_PART"
  printf '%s  %s\n' "$DENO_BINARY_SHA256" "$DENO_PART" | sha256sum --check
  mv "$DENO_PART" "$DENO_DEST"
  unlink "$DENO_ARCHIVE"
  chmod 0755 "$DENO_DEST"
  echo "Downloaded and verified Deno $DENO_VERSION for $TARGET"
fi

FFMPEG_LICENSE_DEST="$OUT/ffmpeg-license.txt"
FFMPEG_LICENSE_SHA256="8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903"
if [[ -f "$FFMPEG_DEST" ]] \
  && printf '%s  %s\n' "$FFMPEG_BINARY_SHA256" "$FFMPEG_DEST" | sha256sum --check --status \
  && [[ -f "$FFMPEG_LICENSE_DEST" ]] \
  && printf '%s  %s\n' "$FFMPEG_LICENSE_SHA256" "$FFMPEG_LICENSE_DEST" | sha256sum --check --status; then
  echo "FFmpeg $FFMPEG_BUILD already verified for $TARGET"
else
  FFMPEG_ARCHIVE="$FFMPEG_DEST.archive.part"
  FFMPEG_PART="$FFMPEG_DEST.part"
  FFMPEG_LICENSE_PART="$FFMPEG_LICENSE_DEST.part"
  curl --fail --location --retry 3 \
    "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/$FFMPEG_TAG/$FFMPEG_ASSET" \
    --output "$FFMPEG_ARCHIVE"
  printf '%s  %s\n' "$FFMPEG_ARCHIVE_SHA256" "$FFMPEG_ARCHIVE" | sha256sum --check
  if [[ "$FFMPEG_ARCHIVE_KIND" == "tar" ]]; then
    tar -xJOf "$FFMPEG_ARCHIVE" "$FFMPEG_MEMBER" > "$FFMPEG_PART"
    tar -xJOf "$FFMPEG_ARCHIVE" "$FFMPEG_LICENSE_MEMBER" > "$FFMPEG_LICENSE_PART"
  else
    unzip -p "$FFMPEG_ARCHIVE" "$FFMPEG_MEMBER" > "$FFMPEG_PART"
    unzip -p "$FFMPEG_ARCHIVE" "$FFMPEG_LICENSE_MEMBER" > "$FFMPEG_LICENSE_PART"
  fi
  printf '%s  %s\n' "$FFMPEG_BINARY_SHA256" "$FFMPEG_PART" | sha256sum --check
  printf '%s  %s\n' "$FFMPEG_LICENSE_SHA256" "$FFMPEG_LICENSE_PART" | sha256sum --check
  mv "$FFMPEG_PART" "$FFMPEG_DEST"
  mv "$FFMPEG_LICENSE_PART" "$FFMPEG_LICENSE_DEST"
  unlink "$FFMPEG_ARCHIVE"
  chmod 0755 "$FFMPEG_DEST"
  echo "Downloaded and verified FFmpeg $FFMPEG_BUILD for $TARGET"
fi
