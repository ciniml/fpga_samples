#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Check the schematic and the board (ERC, DRC with schematic parity) and
# write the fabrication outputs to fab/ (Gerbers + drill zip, BOM,
# placement, schematic PDF, board images) from the files as they are.
#
# The KiCad files are the master once they are edited in KiCad;
# `--regen` rebuilds them from
# tools/gen_sch.py / gen_pcb.py first, which DISCARDS those edits.
set -euo pipefail
cd "$(dirname "$0")/.."
N=DE0Header_PmodAdapter
export TMPDIR=${TMPDIR:-/tmp}
if [ "${1:-}" = "--regen" ]; then
    python3 tools/gen_sch.py
    python3 tools/gen_pcb.py 2>&1 | grep -v 'assert' || true
fi
mkdir -p fab/gerber
# library-table warnings are environment dependent (headless kicad-cli without global tables)
kicad-cli sch erc --severity-all -o fab/erc.rpt $N.kicad_sch >/dev/null
kicad-cli pcb drc --schematic-parity --refill-zones --severity-all -o fab/drc.rpt $N.kicad_pcb >/dev/null
for f in fab/erc.rpt fab/drc.rpt; do
    if grep '^\[' "$f" | grep -qv 'lib_symbol_issues\|footprint_link_issues\|lib_footprint_issues'; then
        echo "== $f:"; grep '^\[' "$f" | grep -v 'lib_symbol_issues\|footprint_link_issues\|lib_footprint_issues' | sort | uniq -c
        exit 1
    fi
done
grep -h 'unconnected\|parity' fab/drc.rpt || true
rm -f fab/gerber/*
kicad-cli pcb export gerbers --layers F.Cu,B.Cu,F.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts \
    --subtract-soldermask --no-x2 -o fab/gerber/ $N.kicad_pcb >/dev/null
kicad-cli pcb export drill --format excellon --excellon-separate-th -o fab/gerber/ $N.kicad_pcb >/dev/null
(cd fab/gerber && rm -f ../${N}_gerber.zip && zip -q ../${N}_gerber.zip *)
kicad-cli pcb export pos --side both --format csv --units mm --use-drill-file-origin -o fab/${N}_pos.csv $N.kicad_pcb >/dev/null
kicad-cli sch export bom --fields 'Reference,Value,Footprint,${QUANTITY},LCSC,MPN,Description' \
    --group-by Value,Footprint --ref-range-delimiter '' --exclude-dnp -o fab/${N}_bom.csv $N.kicad_sch >/dev/null
kicad-cli sch export bom --fields 'Reference,Value,Footprint,${QUANTITY},LCSC,MPN' \
    --group-by Value,Footprint,LCSC --ref-range-delimiter '' --exclude-dnp -o fab/${N}_bom_full.csv $N.kicad_sch >/dev/null
python3 tools/jlc_files.py $N fab
python3 tools/ports_csv.py
kicad-cli sch export pdf -o fab/${N}_schematic.pdf $N.kicad_sch >/dev/null
kicad-cli pcb render --side top --width 1600 --height 1000 --perspective --rotate "-50,0,15" --zoom 1.0 \
    -o fab/${N}_3d.png $N.kicad_pcb >/dev/null
kicad-cli pcb render --side top --width 1600 --height 800 -o fab/${N}_top.png $N.kicad_pcb >/dev/null
kicad-cli pcb render --side bottom --width 1600 --height 800 -o fab/${N}_bottom.png $N.kicad_pcb >/dev/null
ls fab
