#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Parts order list for LCSC (https://www.lcsc.com/bom) for N boards.

  python3 tools/lcsc_order.py 5      -> out/lcsc/pmod_100base_tx_magjack_lcsc_<N>pcs.csv

Takes the LCSC numbers from the schematic (kicad-cli BOM export) plus the
hand-soldered parts listed in EXTRA, and asks LCSC for the current minimum
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
NAME = 'pmod_100base_tx_magjack'

# parts without an LCSC field in the schematic (not JLC-assembled)
EXTRA = [  # (designators, per board, LCSC, note)
    ('J1', 1, 'C41417354', 'hand soldered; check pin length / body against the Pmod footprint before use'),
]
# equivalents to buy from LCSC when the schematic's part is out of stock there
ALT = {
    'C52923': ['C326568', 'C325464'],  # 1 uF X5R 0402: YAGEO CC0402KRX5R8BB105 (25 V), CC0402KRX5R7BB105 (16 V)
    'C25879': ['C114762', 'C144773'],  # 2.2k 1% 0402: YAGEO RC0402FR-072K2L, AC0402FR-072K2L
}
# spares on top of N x per-board (small passives are covered by the minimum order anyway)
SPARE = {'J2': 1, 'J1': 1}


def lcsc(code):
    req = urllib.request.Request(f'https://wmsc.lcsc.com/ftps/wm/product/detail?productCode={code}',
                                 headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
    d = json.load(urllib.request.urlopen(req, timeout=30))['result']
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
        subprocess.run(['kicad-cli', 'sch', 'export', 'bom', '--fields', 'Reference,Value,${QUANTITY},LCSC',
                        '--group-by', 'LCSC', '--exclude-dnp', '-o', bom, os.path.join(PRJ, NAME + '.kicad_sch')],
                       check=True, capture_output=True)
        lines = []
        with open(bom, newline='') as f:
            for r in csv.DictReader(f):
                if r['LCSC']:
                    lines.append((r['Reference'], int(r['QUANTITY']), r['LCSC'], ''))
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
    os.makedirs(os.path.join(PRJ, 'out', 'lcsc'), exist_ok=True)
    path = os.path.join(PRJ, 'out', 'lcsc', f'{NAME}_lcsc_{boards}pcs.csv')
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
