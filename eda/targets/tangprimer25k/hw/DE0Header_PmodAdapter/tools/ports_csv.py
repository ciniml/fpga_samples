#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Write eda/targets/tangprimer25k/de0header_adapter_pmod_ports.csv (same
format as pmod_ports.csv: pmod_pin,fpga_pin) for the adapter's slots
pmod3..pmod6 and the extra headers ext1 (2x2) / ext2 (2x3, header pin numbers)."""
import os
import pinmap as pm
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', '..', 'de0header_adapter_pmod_ports.csv')
rows = []
for slot in pm.PMODS:
    by_pin = {}
    for s_, col, pp, pn, kind in pm.ROUTES:
        if s_ == slot:
            by_pin[col] = pm.HDR[pp]
            by_pin[col + 6] = pm.HDR[pn]
    for p in sorted(by_pin):
        rows.append((f'{pm.SLOT_NAME[slot]}_{p}', by_pin[p]))
for name, d in (('ext1', pm.EXT1), ('ext2', pm.EXT2)):
    for pin, net in sorted(d.items()):
        if net.startswith(('LVDS', 'IO')):
            # header pin of the net
            hp = [h for h, n in pm.header_nets().items() if n == net][0]
            rows.append((f'{name}_{pin}', pm.HDR[hp]))
with open(os.path.normpath(OUT), 'w') as f:
    f.write('pmod_pin,fpga_pin\n')
    for a, b in rows:
        f.write(f'{a},{b}\n')
print(os.path.normpath(OUT), len(rows))
