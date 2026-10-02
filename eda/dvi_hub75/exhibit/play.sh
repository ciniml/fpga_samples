#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Play videos on the HUB75 panels: full screen on the FPGA's HDMI output
# (found by its EDID name), each 128x128 video in the top-left corner, the
# rest black, sound to the same HDMI port.
#
#   ./play.sh                    loop videos/*.mp4 (made by prepare.sh)
#   ./play.sh file.mp4 ...       loop the given (prepared) files
#   ./play.sh --pattern          test pattern + 1 kHz tone
#
# Run it in the desktop session (or with DISPLAY=:0 from ssh). q / Esc in
# the player window, or Ctrl+C here, stops it.
set -u
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
SINK_NAME="FPGA"          # EDID monitor name: "FPGA HDMI RX" / "FPGA DVI RX"
W=1280 H=720 SIZE=128

log() { echo "[play] $*"; }

# ---- the FPGA's output: xrandr name and position ----------------------
find_output() {
    xrandr --verbose | python3 -c '
import re, sys
out = None; edid = {}; cur = None; geo = {}; conn = {}
for line in sys.stdin:
    m = re.match(r"^(\S+) (connected|disconnected)( primary)? ?(\d+x\d+\+\d+\+\d+)?", line)
    if m:
        out = m.group(1); conn[out] = m.group(2) == "connected"; geo[out] = m.group(4); edid[out] = ""; cur = None
        continue
    if re.match(r"^\s+EDID:", line):
        cur = out; continue
    if cur and re.match(r"^\s+[0-9a-f]{32}$", line):
        edid[cur] += line.strip(); continue
    cur = None
for o, e in edid.items():
    b = bytes.fromhex(e)
    for d in range(54, 126, 18):
        if len(b) >= d + 18 and b[d:d+3] == b"\0\0\0" and b[d+3] == 0xFC:
            name = b[d+5:d+18].split(b"\n")[0].decode(errors="replace").strip()
            if name.startswith(sys.argv[1]):
                print(o, geo[o] or "-", name)
                sys.exit(0)
sys.exit(1)
' "$SINK_NAME"
}

info=$(find_output) || { log "no connected output with an EDID name starting with '$SINK_NAME' (is the FPGA powered and the HDMI cable in?)"; exit 1; }
read -r OUT GEO NAME <<<"$info"
if [ "$GEO" = "-" ] || [ "${GEO%%+*}" != "${W}x${H}" ]; then
    log "$OUT ($NAME): setting ${W}x${H}@60"
    xrandr --output "$OUT" --mode "${W}x${H}" --rate 60 || exit 1
    sleep 2
    read -r OUT GEO NAME <<<"$(find_output)"
fi
X=$(echo "$GEO" | cut -d+ -f2); Y=$(echo "$GEO" | cut -d+ -f3)
log "panel output: $OUT ($NAME) at $GEO"

# ---- sound to the same HDMI port --------------------------------------
# PulseAudio names HDMI ports after the ELD (EDID) monitor name.
set_audio() {
    local card port n profile sink
    read -r card port < <(pactl list cards | awk -v want="$SINK_NAME" '
        /^Card #/ { card = "" }
        /^\tName: / { card = $2 }
        /^\t\thdmi-output-[0-9]+:/ { port = $1; sub(":", "", port) }
        /device.product.name = / && index($0, want) && port != "" { print card, port; exit }')
    if [ -z "${card:-}" ]; then
        log "audio: no HDMI port named '$SINK_NAME*' (sound stays on the default output)"
        return
    fi
    n=${port#hdmi-output-}
    profile="output:hdmi-stereo"; [ "$n" != 0 ] && profile="output:hdmi-stereo-extra$n"
    pactl set-card-profile "$card" "$profile" || return
    sink=$(pactl list short sinks | awk -v c="${card#alsa_card.}" 'index($2, c) && index($2, "hdmi") { print $2; exit }')
    [ -n "$sink" ] && pactl set-default-sink "$sink" && pactl set-sink-mute "$sink" 0 && pactl set-sink-volume "$sink" 100%
    log "audio: $card $profile -> ${sink:-?}"
}
set_audio

# no screen blanking while playing
xset s off s noblank -dpms 2>/dev/null

# 128x128 picture in the top-left of a black 1280x720 frame, RGB so that
# the pixels reach the panel without chroma subsampling
VF="scale=${SIZE}:${SIZE}:flags=area,pad=${W}:${H}:0:0:black,format=rgb24"
PLAYER=(ffplay -hide_banner -loglevel warning -fs -left "$X" -top "$Y" -window_title dvi_hub75)

if [ "${1:-}" = "--pattern" ]; then
    exec "${PLAYER[@]}" -f lavfi \
        "testsrc2=size=${SIZE}x${SIZE}:rate=60,pad=${W}:${H}:0:0:black,format=rgb24[out0];sine=frequency=1000:sample_rate=48000,volume=0.5[out1]"
fi

if [ $# -gt 0 ]; then files=("$@"); else files=(videos/*.mp4); fi
[ -e "${files[0]}" ] || { log "no videos (put prepared files in videos/: ./prepare.sh <input>...)"; exit 1; }

if [ ${#files[@]} -eq 1 ]; then
    log "playing ${files[0]} (loop)"
    exec "${PLAYER[@]}" -loop 0 -vf "$VF" "${files[0]}"
fi
# several files: one seamless loop through the concat demuxer
list=$(mktemp --suffix=.txt)
trap 'rm -f "$list"' EXIT
for f in "${files[@]}"; do printf "file '%s'\n" "$(realpath "$f")" >>"$list"; done
log "playing ${#files[@]} files (loop)"
"${PLAYER[@]}" -loop 0 -f concat -safe 0 -i "$list" -vf "$VF"
