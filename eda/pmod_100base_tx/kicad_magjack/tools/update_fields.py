#!/usr/bin/env python3
"""Push Value / MPN / Manufacturer / LCSC / Description from design.py into the
existing .kicad_pcb without regenerating it (gen_pcb.py would drop the
Freerouting tracks). Footprints and nets are not touched."""
import os
import sys
import pcbnew
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS, NAME

path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), NAME + '.kicad_pcb')
board = pcbnew.LoadBoard(path)
n = 0
for p in PARTS:
    fp = board.FindFootprintByReference(p['ref'])
    if fp is None:
        sys.exit(f"{p['ref']} not on the board")
    if fp.GetFPIDAsString() != p['fp']:
        sys.exit(f"{p['ref']}: footprint {fp.GetFPIDAsString()} != {p['fp']} (needs gen_pcb + route)")
    fp.SetValue(p['value'])
    for k, v in (('MPN', p['mpn']), ('Manufacturer', p['mfr']), ('LCSC', p['lcsc']), ('Description', p['desc'])):
        fp.SetField(k, v)
        fld = fp.GetField(k)
        if fld:
            fld.SetVisible(False)
            fld.SetLayer(pcbnew.F_Fab)
    n += 1
board.Save(path)
print(f'update_fields: {n} footprints')
