#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Switch what the panels show: stops the current player and starts play.sh
# in the background (log: play.log).
#
#   ./show.sh hanshin    videos/*.mp4
#   ./show.sh demos      demos/*.mp4
#   ./show.sh all        demos, then videos
#   ./show.sh pattern    test pattern + 1 kHz
#   ./show.sh stop
set -u
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:1}"
# stop our player only: ffplay processes with the dvi_hub75 window title
# (play.sh ends with its player)
for pid in $(pgrep -x ffplay); do
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- "-window_title dvi_hub75" && kill "$pid"
done
sleep 0.5
shopt -s nullglob
case "${1:-}" in
    hanshin) args=(videos/*.mp4) ;;
    demos)   args=(demos/*.mp4) ;;
    all)     args=(demos/*.mp4 videos/*.mp4) ;;
    pattern) args=(--pattern) ;;
    stop)    echo "[show] stopped"; exit 0 ;;
    *)       sed -n '8,15p' "$0"; exit 1 ;;
esac
[ ${#args[@]} -gt 0 ] || { echo "[show] nothing to play for '$1'"; exit 1; }
setsid nohup ./play.sh "${args[@]}" >play.log 2>&1 </dev/null &
echo "[show] $1"
