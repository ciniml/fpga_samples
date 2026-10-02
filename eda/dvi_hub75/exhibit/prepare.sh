#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Convert videos for the panels: 128x128, 30 fps, H.264 4:4:4, AAC 48 kHz
# stereo (a silent track is added when the input has none), all with the
# same parameters so that play.sh can loop them seamlessly.
#
#   ./prepare.sh [--fit] input.mp4 ...     -> videos/<name>.mp4
#
#   default: the centre square of the picture, scaled to 128x128
#   --fit  : the whole picture, letterboxed (black bars)
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
mode=crop
if [ "${1:-}" = "--fit" ]; then mode=fit; shift; fi
[ $# -gt 0 ] || { sed -n '8,15p' "$0"; exit 1; }
mkdir -p "$dir/videos"
for in in "$@"; do
    out="$dir/videos/$(basename "${in%.*}").mp4"
    if [ $mode = crop ]; then
        vf="crop='min(iw,ih)':'min(iw,ih)',scale=128:128:flags=area,fps=30,format=yuv444p"
    else
        vf="scale=128:128:force_original_aspect_ratio=decrease:flags=area,pad=128:128:(ow-iw)/2:(oh-ih)/2:black,fps=30,format=yuv444p"
    fi
    if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$in" | grep -q .; then
        ffmpeg -hide_banner -loglevel error -y -i "$in" -vf "$vf" \
            -c:v libx264 -crf 14 -preset slow -c:a aac -b:a 192k -ar 48000 -ac 2 "$out"
    else
        ffmpeg -hide_banner -loglevel error -y -i "$in" -f lavfi -i anullsrc=r=48000:cl=stereo -shortest \
            -vf "$vf" -c:v libx264 -crf 14 -preset slow -c:a aac -b:a 192k -map 0:v -map 1:a "$out"
    fi
    echo "[prepare] $in -> $out"
done
