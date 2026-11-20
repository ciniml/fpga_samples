#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""JLCPCB assembly files from the KiCad exports in fab/:
fab/<N>_bom_full.csv (kicad-cli sch export bom, with the LCSC field) and
fab/<N>_pos.csv (kicad-cli pcb export pos) ->
fab/jlc/<N>_jlc_bom.csv (Comment, Designator, Footprint, LCSC Part #) and
fab/jlc/<N>_jlc_cpl.csv (Designator, Mid X, Mid Y, Layer, Rotation).
Parts without an LCSC number (J1, the Pmod header: hand soldered) are left
out of both, and so is J2 (MagJack, through hole: hand soldered) unless
--with-tht is given (JLC Standard PCBA only). Rotations are KiCad's; check
U1 pin 1 in JLC's placement preview."""
import csv, os, re, sys
N, FAB = sys.argv[1], sys.argv[2]
THT = set() if '--with-tht' in sys.argv else {'J2'}
os.makedirs(f'{FAB}/jlc', exist_ok=True)
lcsc = {}
rows = []
with open(f'{FAB}/{N}_bom_full.csv', newline='') as f:
    for r in csv.DictReader(f):
        if not r.get('LCSC'):
            continue
        refs = []
        for x in r['Reference'].split(','):
            x = x.strip()
            m = re.fullmatch(r'([A-Z]+)(\d+)-\1?(\d+)', x)    # KiCad 10 writes ranges (C1-C8)
            refs += [f'{m[1]}{k}' for k in range(int(m[2]), int(m[3]) + 1)] if m else [x]
        refs = [x for x in refs if x not in THT]
        if not refs:
            continue
        for x in refs:
            lcsc[x] = r['LCSC']
        rows.append([r['Value'], ','.join(refs), r['Footprint'].split(':')[-1], r['LCSC']])
with open(f'{FAB}/jlc/{N}_jlc_bom.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['Comment', 'Designator', 'Footprint', 'LCSC Part #'])
    w.writerows(rows)
with open(f'{FAB}/{N}_pos.csv', newline='') as f, open(f'{FAB}/jlc/{N}_jlc_cpl.csv', 'w', newline='') as g:
    w = csv.writer(g)
    w.writerow(['Designator', 'Mid X', 'Mid Y', 'Layer', 'Rotation'])
    for r in csv.DictReader(f):
        if r['Ref'] in lcsc:
            w.writerow([r['Ref'], f"{float(r['PosX']):.4f}mm", f"{float(r['PosY']):.4f}mm",
                        'Top' if r['Side'] == 'top' else 'Bottom', f"{float(r['Rot']) % 360:g}"])
print(f'jlc: {len(lcsc)} placements, {len(rows)} BOM lines')
