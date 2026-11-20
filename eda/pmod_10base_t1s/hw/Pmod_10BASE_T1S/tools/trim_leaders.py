#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Shorten the leader lines `cpnr labels` draws (groups cpnr:leader:<ref>) where
their end touches the outline silk of their own footprint: cpnr lets a leader end
on its part, KiCad DRC reports that as silk_overlap. The segment end nearest the
part is pulled back along the segment until it clears that silk by GAP.
The file is patched as text: a pcbnew save reorders the board so that cpnr no
longer recognises its leaders.
Usage: trim_leaders.py board.kicad_pcb"""
import math
import re
import sys

import pcbnew

GAP = 0.02     # mm between the leader and the footprint silk, edge to edge (board silk clearance is 0)
STEP = 0.01


def mm(v):
    return pcbnew.ToMM(v)


def num(v):
    return f'{v:.4f}'.rstrip('0').rstrip('.')


def silk_dist(fp, x, y, w):
    """edge-to-edge distance (mm) from a w-wide stroke end at (x, y) to the footprint's silk lines"""
    d = math.inf
    for it in fp.GraphicalItems():
        if it.GetLayer() != pcbnew.F_SilkS or it.GetClass() != 'PCB_SHAPE':
            continue
        sx, sy, ex, ey = (mm(v) for v in (it.GetStart().x, it.GetStart().y, it.GetEnd().x, it.GetEnd().y))
        dx, dy = ex - sx, ey - sy
        t = 0 if dx == dy == 0 else max(0, min(1, ((x - sx) * dx + (y - sy) * dy) / (dx * dx + dy * dy)))
        d = min(d, math.hypot(x - sx - t * dx, y - sy - t * dy) - (w + mm(it.GetWidth())) / 2)
    return d


path = sys.argv[1]
board = pcbnew.LoadBoard(path)
text = open(path, newline='').read()
n = 0
for g in board.Groups():
    if not g.GetName().startswith('cpnr:leader:'):
        continue
    fp = board.FindFootprintByReference(g.GetName().split(':')[-1])
    for it in g.GetItems():
        if it.GetClass() != 'PCB_SHAPE':
            continue
        w = mm(it.GetWidth())
        a = (mm(it.GetStart().x), mm(it.GetStart().y))
        b = (mm(it.GetEnd().x), mm(it.GetEnd().y))
        if silk_dist(fp, *a, w) < silk_dist(fp, *b, w):
            a, b = b, a                          # b: the end at the part
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if ln == 0 or silk_dist(fp, *b, w) >= GAP:
            continue
        ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        while ln > 2 * STEP and silk_dist(fp, *b, w) < GAP:
            ln -= STEP
            b = (a[0] + ux * ln, a[1] + uy * ln)
        key = 'end' if silk_dist(fp, mm(it.GetEnd().x), mm(it.GetEnd().y), w) < \
            silk_dist(fp, mm(it.GetStart().x), mm(it.GetStart().y), w) else 'start'
        pat = re.compile(r'(\(gr_line\s+(?:(?!\(gr_)[^"])*?\(' + key + r' )[-\d.]+ [-\d.]+(\)(?:(?!\(gr_).)*?\(uuid "'
                         + it.m_Uuid.AsString() + r'"\))', re.S)
        text, k = pat.subn(lambda m: f'{m.group(1)}{num(b[0])} {num(b[1])}{m.group(2)}', text)
        if k != 1:
            sys.exit(f'{g.GetName()}: segment {it.m_Uuid.AsString()} not found in the file')
        n += 1
open(path, 'w', newline='').write(text)
print(f'trim_leaders: {n} leader end(s) pulled back')
