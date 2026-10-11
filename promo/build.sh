#!/bin/bash
# build.sh <lang> [--tts]: full pipeline → out/MC-Download-Manager-<lang>.mp4
# --tts regenerates the voice with Gemini (needs GEMINI_API_KEY); otherwise the existing clips are reused.
set -euo pipefail
cd "$(dirname "$0")"
lang=$1
[ "${2:-}" = "--tts" ] && node tts.mjs "$lang"
./trim.sh "$lang"
node timeline.mjs "$lang"
node music.mjs "$lang"
node render.mjs "$lang"
./mix.sh "$lang"
