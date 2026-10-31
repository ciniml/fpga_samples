#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# ERC/DRC reports + schematic PDF, PCB PDF, BOM CSV, layout PNG/SVG, 3D renders into out/
cd "$(dirname "$0")/.."
N=$(basename *.kicad_pro .kicad_pro)
kicad-cli sch erc --severity-all -o out/erc.rpt $N.kicad_sch 2>&1 | grep -i found
kicad-cli pcb drc --schematic-parity --severity-all -o out/drc.rpt $N.kicad_pcb 2>&1 | grep -i found
kicad-cli sch export pdf -o out/${N}_sch.pdf $N.kicad_sch >/dev/null 2>&1
kicad-cli sch export bom --fields 'Reference,Value,Footprint,MPN,Manufacturer,Description,${QUANTITY},${DNP}' \
  --labels 'Refs,Value,Footprint,MPN,Manufacturer,Description,Qty,DNP' --group-by 'Value,Footprint,MPN,${DNP}' \
  -o out/${N}_bom.csv $N.kicad_sch >/dev/null 2>&1
kicad-cli pcb export pdf --mode-multipage --layers F.Cu,B.Cu,F.Silkscreen,B.Silkscreen,F.Fab,Edge.Cuts \
  --common-layers Edge.Cuts -o out/${N}_pcb.pdf $N.kicad_pcb >/dev/null 2>&1
kicad-cli pcb render --side top --quality high --width 1600 --height 800 -o out/render_top.png $N.kicad_pcb >/dev/null 2>&1
kicad-cli pcb render --rotate '-45,0,30' --perspective --width 1600 --height 1000 --zoom 1.3 -o out/render_iso.png $N.kicad_pcb >/dev/null 2>&1
sh tools/view.sh
ls out
