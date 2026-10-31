#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# layout PNGs for human review: out/layout_top.png (F.Cu+silk), out/layout_bottom.png, out/render_*.png
cd "$(dirname "$0")/.."
kicad-cli pcb export svg --mode-single --fit-page-to-board --exclude-drawing-sheet --layers F.Cu,F.Silkscreen,F.Fab,Edge.Cuts -o out/layout_top.svg $(basename *.kicad_pcb) >/dev/null 2>&1
kicad-cli pcb export svg --mode-single --fit-page-to-board --exclude-drawing-sheet --mirror --layers B.Cu,B.Silkscreen,Edge.Cuts -o out/layout_bottom.svg $(basename *.kicad_pcb) >/dev/null 2>&1
for f in layout_top layout_bottom; do rsvg-convert -w 2400 -b white out/$f.svg -o out/$f.png; done
