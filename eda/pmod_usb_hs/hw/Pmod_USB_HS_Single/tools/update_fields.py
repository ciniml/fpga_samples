#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Push the schematic's fields (Value, LCSC, MPN, Description, ...) into the
KiCad-edited .kicad_pcb without regenerating it (gen_pcb.py would drop the GUI
edits). Footprints, nets and copper are not touched; the CRLF line endings of
the GUI save are kept. Run after tools/gen_sch.py."""
import os
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_pcb import NAME, PRJ, read_netlist  # noqa: E402

path = os.path.join(PRJ, NAME + '.kicad_pcb')
comps, _ = read_netlist()
crlf = b'\r\n' in open(path, 'rb').read(4096)
board = pcbnew.LoadBoard(path)
n = 0
for ref, c in comps.items():
    fp = board.FindFootprintByReference(ref)
    if fp is None:
        sys.exit(f'{ref} not on the board')
    if fp.GetFPIDAsString() != c['footprint']:
        sys.exit(f"{ref}: footprint {fp.GetFPIDAsString()} != {c['footprint']} (needs a layout change)")
    fp.SetValue(c['value'])
    for k, v in c['fields'].items():
        fp.SetField(k, v)
        if k != 'Description':
            fp.GetField(k).SetVisible(False)
    n += 1
board.Save(path)
if crlf:
    data = open(path, 'rb').read()
    open(path, 'wb').write(data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))
print(f'update_fields: {n} footprints')
