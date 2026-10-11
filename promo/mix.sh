#!/bin/bash
# mix.sh <lang>: voice + ducked music → loudness-normalised (-14 LUFS) AAC, muxed with out/video_<lang>.mp4
set -euo pipefail
cd "$(dirname "$0")"
lang=$1
graph="[0:a]highpass=f=70,acompressor=threshold=-22dB:ratio=2.5:attack=5:release=150:makeup=2,asplit=2[vm][vsc];
[1:a]volume=-12dB[mus];
[mus][vsc]sidechaincompress=threshold=0.025:ratio=4:attack=20:release=380[duck];
[vm]pan=stereo|c0=c0|c1=c0[vst];
[vst][duck]amix=inputs=2:normalize=0"
# pass 1: measure
stats=$(ffmpeg -hide_banner -i audio/$lang/voice.wav -i audio/$lang/music.wav -filter_complex "$graph,loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
get() { echo "$stats" | grep "\"$1\"" | sed 's/.*: "\(.*\)".*/\1/'; }
ln="loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):measured_thresh=$(get input_thresh):offset=$(get target_offset):linear=true"
# pass 2: apply and mux
ffmpeg -v error -y -i audio/$lang/voice.wav -i audio/$lang/music.wav -filter_complex "$graph,$ln,aresample=48000[a]" -map "[a]" -c:a pcm_s16le audio/$lang/mix.wav
ffmpeg -v error -y -i out/video_$lang.mp4 -i audio/$lang/mix.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest -movflags +faststart \
  -metadata title="MC Download Manager" -metadata:s:a:0 language=$([ $lang = tr ] && echo tur || echo eng) "out/MC-Download-Manager-$lang.mp4"
ffmpeg -hide_banner -i audio/$lang/mix.wav -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tail -2
