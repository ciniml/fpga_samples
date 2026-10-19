#!/usr/bin/env python3
"""Autoroute the non-critical nets with Freerouting and merge the result into the board.

usage: route.py <freerouting.jar>

* Exports Specctra DSN from the board (hand-routed tracks are locked -> 'fix' wires).
* Removes the GND planes / GND net (GND is the poured zone on both layers + hand-placed vias).
* Runs Freerouting headless (xvfb-run), parses the .ses and adds only the new wires/vias of
  the nets listed in AUTO to the board (the hand-routed copper is left untouched).
"""
import os
import re
import subprocess
import sys
import tempfile

import pcbnew

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sexp import parse, find, find1  # noqa: E402

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PCB = os.path.join(PRJ, 'pmod_100base_tx.kicad_pcb')
AUTO = {'+3V3', '/VB', '/VTH_A', '/VTH_B', '/BS_4', '/BS_5', '/BS_7', '/BS_8', '/BS_MID'}


def strip_gnd(dsn):
    # keep the B.Cu GND plane (so GND pads/vias count as connected and GND copper is an obstacle),
    # drop the F.Cu fill plane so the top layer stays routable
    return re.sub(r'\(plane GND \(polygon F\.Cu [^)]*\)\)', '', dsn)


def main():
    jar = sys.argv[1]
    work = tempfile.mkdtemp(prefix='fr_')
    dsn, ses = os.path.join(work, 'b.dsn'), os.path.join(work, 'b.ses')
    board = pcbnew.LoadBoard(PCB)
    pcbnew.ExportSpecctraDSN(board, dsn)
    text = strip_gnd(open(dsn).read())
    open(dsn, 'w').write(text)
    subprocess.run(['xvfb-run', '-a', 'java', '-jar', jar, '-de', dsn, '-do', ses, '-mp', '40',
                    '-dct', '0'], check=False, timeout=900)
    t = parse(open(ses).read())[0]
    routes = find1(t, 'routes')
    res = find1(routes, 'resolution')
    scale = {'um': 1e-3, 'mm': 1.0, 'mil': 0.0254}[str(res[1])] / float(res[2])
    nets = {n.GetNetname(): n for n in board.GetNetInfo().NetsByName().values()}
    nw = find1(routes, 'network_out')
    added = 0
    for n in find(nw, 'net'):
        name = n[1]
        if name not in AUTO:
            continue
        for w in find(n, 'wire'):
            path = find1(w, 'path')
            layer = pcbnew.F_Cu if path[1] == 'F.Cu' else pcbnew.B_Cu
            width = float(path[2]) * scale
            xy = [float(v) * scale for v in path[3:]]
            pts = list(zip(xy[0::2], xy[1::2]))
            for a, b in zip(pts, pts[1:]):
                tr = pcbnew.PCB_TRACK(board)
                tr.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(a[0]), pcbnew.FromMM(-a[1])))
                tr.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(b[0]), pcbnew.FromMM(-b[1])))
                tr.SetWidth(pcbnew.FromMM(width))
                tr.SetLayer(layer)
                tr.SetNet(nets[name])
                board.Add(tr)
                added += 1
        for v in find(n, 'via'):
            pv = pcbnew.PCB_VIA(board)
            pv.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(float(v[2]) * scale), pcbnew.FromMM(-float(v[3]) * scale)))
            pv.SetWidth(pcbnew.FromMM(0.6))
            pv.SetDrill(pcbnew.FromMM(0.3))
            pv.SetNet(nets[name])
            board.Add(pv)
            added += 1
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    board.Save(PCB)
    print('added', added, 'items from', ses)


if __name__ == '__main__':
    main()
