#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# fill zones + DRC (with schematic parity)
cd "$(dirname "$0")/.."
N=$(basename *.kicad_pro .kicad_pro)
python3 - $N <<'P' 2>&1 | grep -v assert
import sys, pcbnew
f=sys.argv[1]+'.kicad_pcb'
b=pcbnew.LoadBoard(f)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
b.Save(f)
P
kicad-cli pcb drc --schematic-parity --severity-all -o out/drc.rpt $N.kicad_pcb 2>&1 | grep -v assert | tail -3
