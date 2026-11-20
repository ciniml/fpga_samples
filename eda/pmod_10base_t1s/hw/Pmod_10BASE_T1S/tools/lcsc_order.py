#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Parts order list for LCSC (https://www.lcsc.com/bom) for N boards.

  python3 tools/lcsc_order.py 5      -> fab/lcsc/Pmod_10BASE_T1S_lcsc_<N>pcs.csv

Takes the LCSC numbers from the schematic (kicad-cli BOM export) plus the
hand-soldered parts listed in EXTRA. DNP parts are bought too, as
hand-soldered options (they share a line with the fitted parts of the same
LCSC number, noted per line), and asks LCSC for the current minimum
order quantity, unit price (at the ordered quantity) and stock, so it needs
network access (it is not part of build.sh). Quantity per line:
N x per-board + spares (SPARE), rounded up to LCSC's minimum order.
The schematic's LCSC numbers are chosen for JLC assembly (JLC and LCSC
keep separate stock); when LCSC itself is short of one, the first
equivalent in ALT that has the stock is ordered instead (noted per line).
The upload columns LCSC's BOM tool maps are "LCSC Part Number" and
"Quantity"; the rest is for the reader.
"""
import csv
import datetime
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'Pmod_10BASE_T1S'

# parts without an LCSC field in the schematic (not JLC-assembled)
EXTRA = [  # (designators, per board, LCSC, note)
    ('J1', 1, 'C41417354', 'Pmod plug, hand soldered; check pin length / body against the Pmod footprint before use'),
]
# equivalents to buy from LCSC when the schematic's part is out of stock there
ALT = {
    'C25105': ['C138002'],             # 33R 1% 0402: YAGEO RC0402FR-0733RL
    'C25744': ['C60490', 'C25531'],    # 10k 0402: YAGEO RC0402FR-0710KL, UNI-ROYAL 5% (pull-up only)
}
# spares on top of N x per-board (small passives are covered by the minimum order anyway)
SPARE = {'J1': 1, 'J2': 1, 'U1': 1}


def lcsc(code):
    req = urllib.request.Request(f'https://wmsc.lcsc.com/ftps/wm/product/detail?productCode={code}',
                                 headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
    d = json.load(urllib.request.urlopen(req, timeout=30))['result']
    if d is None:          # not sold by LCSC itself (JLC-only stock)
        return {'mpn': '', 'brand': '', 'stock': 0, 'min': 1, 'prices': [], 'desc': ''}
    prices = sorted((int(p['ladder']), float(p['productPrice'])) for p in d.get('productPriceList') or [])
    return {'mpn': d.get('productModel', ''), 'brand': d.get('brandNameEn', ''), 'stock': int(d.get('stockNumber') or 0),
            'min': int(d.get('minBuyNumber') or 1), 'prices': prices, 'desc': d.get('productIntroEn', '') or d.get('productDescEn', '')}


def unit_price(prices, qty):
    up = prices[0][1] if prices else 0.0
    for ladder, p in prices:
        if qty >= ladder:
            up = p
    return up


def main():
    boards = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    with tempfile.TemporaryDirectory() as td:
        bom = os.path.join(td, 'bom.csv')
        subprocess.run(['kicad-cli', 'sch', 'export', 'bom', '--fields', 'Reference,Value,${QUANTITY},LCSC,${DNP}',
                        '--group-by', 'LCSC,${DNP}', '-o', bom, os.path.join(PRJ, NAME + '.kicad_sch')],
                       check=True, capture_output=True)
        merged = {}  # LCSC -> [refs, per board, DNP refs]
        with open(bom, newline='') as f:
            for r in csv.DictReader(f):
                if r['LCSC']:
                    m = merged.setdefault(r['LCSC'], [[], 0, []])
                    m[0].append(r['Reference'])
                    m[1] += int(r['QUANTITY'])
                    if r['DNP']:
                        m[2].append(r['Reference'])
        lines = [(','.join(refs), qty, code, f'DNP, hand soldered option: {",".join(dnp)}' if dnp else '')
                 for code, (refs, qty, dnp) in merged.items()]
    lines += EXTRA
    out = []
    total = 0.0
    for refs, per_board, code, note in lines:
        spare = sum(SPARE.get(x.strip(), 0) for x in refs.split(','))
        need = boards * per_board + spare
        info = lcsc(code)
        if info['stock'] < max(need, info['min']):
            for alt in ALT.get(code, []):
                ai = lcsc(alt)
                if ai['stock'] >= max(need, ai['min']):
                    note = (note + '; ' if note else '') + f'{code} ({info["mpn"]}) out of stock at LCSC ({info["stock"]}), equivalent ordered'
                    code, info = alt, ai
                    break
        qty = max(need, info['min'])
        up = unit_price(info['prices'], qty)
        total += up * qty
        if qty > info['stock']:
            note = (note + '; ' if note else '') + f'NOT ENOUGH STOCK ({info["stock"]})'
        out.append([code, qty, info['mpn'], info['brand'], refs, per_board, need, info['min'], f'{up:.4f}', f'{up * qty:.2f}',
                    info['stock'], note])
    os.makedirs(os.path.join(PRJ, 'fab', 'lcsc'), exist_ok=True)
    path = os.path.join(PRJ, 'fab', 'lcsc', f'{NAME}_lcsc_{boards}pcs.csv')
    with open(path, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['LCSC Part Number', 'Quantity', 'Manufacture Part Number', 'Manufacturer', 'Designator',
                    'Qty per board', f'Needed ({boards} boards + spares)', 'LCSC min. order', 'Unit price (USD)',
                    'Ext. price (USD)', 'LCSC stock', 'Note'])
        w.writerows(out)
    print(f'{path}: {len(out)} lines, about ${total:.2f} for {boards} boards (prices / stock as of {datetime.date.today()})')
    for r in out:
        print('  ', r[0], r[1], r[2], r[4], r[8], r[9], r[11])


if __name__ == '__main__':
    main()
