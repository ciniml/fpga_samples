#!/bin/sh
# fill zones + DRC (with schematic parity) + quick PNG of the copper
cd "$(dirname "$0")/.."
python3 - <<'P' 2>&1 | grep -v assert
import pcbnew
b=pcbnew.LoadBoard('pmod_100base_tx.kicad_pcb')
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
b.Save('pmod_100base_tx.kicad_pcb')
P
kicad-cli pcb drc --schematic-parity --severity-all -o out/drc.rpt pmod_100base_tx.kicad_pcb 2>&1 | grep -v assert | tail -3
