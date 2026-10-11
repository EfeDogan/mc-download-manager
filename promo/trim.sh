#!/bin/bash
# trim.sh <lang>: strips leading/trailing silence from audio/<lang>/<scene>.wav → <scene>_trim.wav
set -euo pipefail
cd "$(dirname "$0")/audio/$1"
for f in *.wav; do
  case $f in *_trim.wav|voice.wav|music.wav|mix.wav) continue;; esac
  ffmpeg -v error -y -i "$f" -af "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse" "${f%.wav}_trim.wav"
done
