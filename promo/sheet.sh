#!/bin/bash
# sheet.sh <lang> → out/sheet_<lang>_N.png (2x2 grids of the rendered stills, in time order)
cd "$(dirname "$0")/out"
lang=$1
files=($(ls still_${lang}_*.png | sed "s/still_${lang}_//;s/.png//" | sort -n))
n=0
for ((g=0; g<${#files[@]}; g+=4)); do
  a=(); for k in 0 1 2 3; do f=${files[$((g+k))]}; [ -n "$f" ] && a+=(-i still_${lang}_$f.png) || a+=(-f lavfi -i color=black:s=1920x1080:d=1); done
  ffmpeg -v error -y "${a[@]}" -filter_complex "[0]scale=960:-1[a];[1]scale=960:-1[b];[2]scale=960:-1[c];[3]scale=960:-1[d];[a][b][c][d]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0" -frames:v 1 sheet_${lang}_$n.png
  n=$((n+1))
done
