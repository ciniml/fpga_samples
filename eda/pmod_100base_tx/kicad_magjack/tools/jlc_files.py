#!/usr/bin/env python3
"""JLCPCB assembly files from the KiCad exports in out/:
out/<N>_bom_full.csv (kicad-cli sch export bom, with the LCSC field) and
out/<N>_pos.csv (kicad-cli pcb export pos) ->
out/jlc/<N>_jlc_bom.csv (Comment, Designator, Footprint, LCSC Part #) and
out/jlc/<N>_jlc_cpl.csv (Designator, Mid X, Mid Y, Layer, Rotation).
Parts without an LCSC number (J1, the Pmod header) are left out. J2 (MagJack,
through hole) is left out too unless --with-tht is given (JLC Standard PCBA
only; hand soldering it is easy). Rotations are KiCad's: check U1 pin 1 and
J2 in JLC's placement preview."""
import csv, os, re, sys


def refs_of(s):
    # kicad-cli writes runs as ranges ("R9-R12"); JLC wants every designator
    out = []
    for x in (t.strip() for t in s.split(',')):
        m = re.fullmatch(r'([A-Z]+)(\d+)-\1(\d+)', x)
        out += [f'{m[1]}{i}' for i in range(int(m[2]), int(m[3]) + 1)] if m else [x]
    return out


N, OUT = sys.argv[1], sys.argv[2]
THT = set() if '--with-tht' in sys.argv else {'J2'}
os.makedirs(f'{OUT}/jlc', exist_ok=True)
lcsc = {}
rows = []
with open(f'{OUT}/{N}_bom_full.csv', newline='') as f:
    for r in csv.DictReader(f):
        refs = [x for x in refs_of(r['Reference']) if x not in THT]
        if not r.get('LCSC') or not refs:
            continue
        for x in refs:
            lcsc[x] = r['LCSC']
        rows.append([r['Value'], ','.join(refs), r['Footprint'].split(':')[-1], r['LCSC']])
with open(f'{OUT}/jlc/{N}_jlc_bom.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['Comment', 'Designator', 'Footprint', 'LCSC Part #'])
    w.writerows(rows)
with open(f'{OUT}/{N}_pos.csv', newline='') as f, open(f'{OUT}/jlc/{N}_jlc_cpl.csv', 'w', newline='') as g:
    w = csv.writer(g)
    w.writerow(['Designator', 'Mid X', 'Mid Y', 'Layer', 'Rotation'])
    for r in csv.DictReader(f):
        if r['Ref'] in lcsc:
            w.writerow([r['Ref'], f"{float(r['PosX']):.4f}mm", f"{float(r['PosY']):.4f}mm",
                        'Top' if r['Side'] == 'top' else 'Bottom', f"{float(r['Rot']) % 360:g}"])
print(f'jlc: {len(lcsc)} placements, {len(rows)} BOM lines')
