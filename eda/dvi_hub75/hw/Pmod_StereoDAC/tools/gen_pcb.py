#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_StereoDAC.kicad_pcb from the schematic's netlist.

Board 20.32 x 33.6 mm (one Pmod wide), 2 layers, 1.6 mm. Coordinates
below are relative to the top-left corner (y down). The Pmod header is on
the bottom edge (pin 1 left, as the other Pmod boards); the 3.5 mm jack
(PJ-313D, SMD) on the top edge with its plug opening facing out (the
2.5 mm nose overhangs the edge). The two channels are columns above
Pmod pin 1 (L) and pin 6's position (R): series parts in the column,
signal flowing up to the jack, shunt parts beside it, each grounded
through its own via into the solid B.Cu ground.
"""
import math
import os
import subprocess
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import sexp  # noqa: E402

NAME = 'Pmod_StereoDAC'
X0, Y0 = 100.0, 80.0          # board origin on the page
W, H = 20.32, 33.6
FPDIR = '/usr/share/kicad/footprints'
TMP = os.environ.get('TMPDIR', '/tmp')
W_SIG, W_GND = 0.25, 0.4

def mm(v):
    return pcbnew.FromMM(v)


def pt(x, y):
    return pcbnew.VECTOR2I(mm(X0 + x), mm(Y0 + y))


# ---------------------------------------------------------------- netlist
def read_netlist():
    net_file = os.path.join(TMP, NAME + '.net')
    subprocess.run(['kicad-cli', 'sch', 'export', 'netlist', '--format', 'kicadsexpr', '-o', net_file,
                    os.path.join(PRJ, NAME + '.kicad_sch')], check=True, capture_output=True)
    t = sexp.parse(open(net_file).read())[0]
    comps = {}
    for c in sexp.find_all(sexp.find(t, 'components'), 'comp'):
        ref = sexp.find(c, 'ref')[1].strip('"')
        comps[ref] = {
            'value': sexp.find(c, 'value')[1].strip('"'),
            'footprint': sexp.find(c, 'footprint')[1].strip('"'),
            'uuid': sexp.find(c, 'tstamps')[1].strip('"'),
            'fields': {},
        }
        d = sexp.find(c, 'description')
        if d:
            comps[ref]['fields']['Description'] = d[1].strip('"')
        fl = sexp.find(c, 'fields')
        for f in sexp.find_all(fl or [], 'field'):
            fname = sexp.find(f, 'name')[1].strip('"')
            if fname not in ('Footprint', 'Datasheet', 'Description') and len(f) > 2:
                comps[ref]['fields'][fname] = f[2].strip('"')
    nets = {}
    for n in sexp.find_all(sexp.find(t, 'nets'), 'net'):
        name = sexp.find(n, 'name')[1].strip('"')
        for node in sexp.find_all(n, 'node'):
            nets[(sexp.find(node, 'ref')[1].strip('"'), sexp.find(node, 'pin')[1].strip('"'))] = name
    return comps, nets


# ---------------------------------------------------------------- helpers
board = None
netinfo = {}


def net(name):
    if name not in netinfo:
        ni = pcbnew.NETINFO_ITEM(board, name)
        board.Add(ni)
        netinfo[name] = ni
    return netinfo[name]


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = os.path.join(PRJ, 'Local', 'local.pretty') if lib == 'local' else os.path.join(FPDIR, lib + '.pretty')
    fp = pcbnew.FootprintLoad(path, name)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def place(ref, x, y, rot, comps, nets, pin_target=None):
    """place a footprint; with pin_target=(pad, x, y) try the four rotations
    and keep the one that puts that pad nearest the target"""
    c = comps[ref]
    fp = load_fp(c['footprint'])
    fp.SetReference(ref)
    fp.SetValue(c['value'])
    fp.SetPath(pcbnew.KIID_PATH('/' + c['uuid']))
    fp.SetSheetfile(NAME + '.kicad_sch')
    fp.SetSheetname('')
    for k, v in c['fields'].items():
        fp.SetField(k, v)
        if k != 'Description':
            fp.GetField(k).SetVisible(False)
    fp.Reference().SetVisible(False)     # tiny board: designators on the Fab layer only
    board.Add(fp)
    fp.SetPosition(pt(x, y))
    if pin_target:
        pn, tx, ty = pin_target
        best = None
        for r in (0, 90, 180, 270):
            fp.SetOrientationDegrees(r)
            p = [p for p in fp.Pads() if p.GetNumber() == pn][0].GetPosition()
            d = math.hypot(pcbnew.ToMM(p.x) - X0 - tx, pcbnew.ToMM(p.y) - Y0 - ty)
            if best is None or d < best[0]:
                best = (d, r)
        rot = best[1]
    fp.SetOrientationDegrees(rot)
    for p in fp.Pads():
        n = nets.get((ref, p.GetNumber()))
        if n:
            p.SetNet(net(n))
    return fp


def pad_xy(fp, num):
    p = [p for p in fp.Pads() if p.GetNumber() == num][0].GetPosition()
    return (round(pcbnew.ToMM(p.x) - X0, 4), round(pcbnew.ToMM(p.y) - Y0, 4))


def track(points, netname, width, layer=pcbnew.F_Cu):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        t = pcbnew.PCB_TRACK(board)
        t.SetStart(pt(x1, y1))
        t.SetEnd(pt(x2, y2))
        t.SetWidth(mm(width))
        t.SetLayer(layer)
        t.SetNet(net(netname))
        board.Add(t)


def via(x, y, netname, dia=0.6, drill=0.3):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pt(x, y))
    v.SetWidth(mm(dia))
    v.SetDrill(mm(drill))
    v.SetNet(net(netname))
    board.Add(v)


def offset_polyline(pts, d):
    """offset a polyline by d (positive = to the right when looking along
    +x on a vertical-up path, i.e. the +x side of upward segments), miter joins"""
    def seg_off(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L          # left normal in y-down coordinates ... flipped below
        return (-nx * d, -ny * d)
    out = []
    n = len(pts)
    for i in range(n):
        if i == 0:
            o = seg_off(pts[0], pts[1])
            out.append((pts[0][0] + o[0], pts[0][1] + o[1]))
        elif i == n - 1:
            o = seg_off(pts[-2], pts[-1])
            out.append((pts[-1][0] + o[0], pts[-1][1] + o[1]))
        else:
            o1 = seg_off(pts[i - 1], pts[i])
            o2 = seg_off(pts[i], pts[i + 1])
            # intersection of the two offset lines
            a1 = (pts[i - 1][0] + o1[0], pts[i - 1][1] + o1[1])
            d1 = (pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            a2 = (pts[i][0] + o2[0], pts[i][1] + o2[1])
            d2 = (pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            den = d1[0] * d2[1] - d1[1] * d2[0]
            t = ((a2[0] - a1[0]) * d2[1] - (a2[1] - a1[1]) * d2[0]) / den
            out.append((a1[0] + d1[0] * t, a1[1] + d1[1] * t))
    return out


def silk(text, x, y, layer=pcbnew.F_SilkS, size=0.8, thick=0.15, rot=0, mirror=None):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(pt(x, y))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(thick))
    t.SetTextAngleDegrees(rot)
    if layer == pcbnew.B_SilkS:
        t.SetMirrored(True)
    board.Add(t)


def edge_line(x1, y1, x2, y2):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(pt(x1, y1))
    s.SetEnd(pt(x2, y2))
    s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(mm(0.05))
    board.Add(s)


def zone(layer, netname, inset=0.0):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(net(netname))
    c, e = 1.27, 0.3
    poly = [(c + e, e), (W - c - e, e), (W - e, c + e), (W - e, H - c - e), (W - c - e, H - e), (c + e, H - e),
            (e, H - c - e), (e, c + e)]
    ol = z.Outline()
    ol.NewOutline()
    for x, y in poly:
        ol.Append(mm(X0 + x), mm(Y0 + y))
    z.SetLocalClearance(mm(0.25))
    z.SetMinThickness(mm(0.2))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(mm(0.25))
    z.SetThermalReliefSpokeWidth(mm(0.3))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    board.Add(z)
    return z


# ---------------------------------------------------------------- board

def pads_xy(fp, num):
    return [(round(pcbnew.ToMM(p.GetPosition().x) - X0, 4), round(pcbnew.ToMM(p.GetPosition().y) - Y0, 4))
            for p in fp.Pads() if p.GetNumber() == num]


def build():
    global board
    comps, nets = read_netlist()
    board = pcbnew.NewBoard(os.path.join(PRJ, NAME + '.kicad_pcb'))
    board.SetCopperLayerCount(2)
    board.GetDesignSettings().SetAuxOrigin(pt(0, H))
    c = 1.27
    poly = [(c, 0), (W - c, 0), (W, c), (W, H - c), (W - c, H), (c, H), (0, H - c), (0, c), (c, 0)]
    for a, b in zip(poly, poly[1:]):
        edge_line(*a, *b)

    # ---- connectors ----
    j1 = place('J1', 3.81, H - 6.35, 90, comps, nets)             # Pmod, pin 1 left, pins 1..6 inner row
    jx = W / 2
    j2 = place('J2', jx, 0.0, 0, comps, nets, pin_target=('T', jx + 3.625, 8.5))   # housing front on the top edge
    P = lambda fp, n: pad_xy(fp, n)  # noqa: E731
    for n in ('1', '2', '7'):
        print('J1', n, P(j1, n))
    for n in ('S', 'R', 'T'):
        print('J2', n, pads_xy(j2, n))

    # ---- the two filter columns: L above Pmod pin 1, R mirrored ----
    xl = P(j1, '1')[0]
    xr = W - xl
    chans = (('L', xl, +1, ('R1', 'C1', 'R2', 'C2', 'C3', 'R3'), 'T'),
             ('R', xr, -1, ('R11', 'C11', 'R12', 'C12', 'C13', 'R13'), 'R'))
    # series parts (vertical, 0603 / 0805 courtyards stacked between the jack's (y 11.75) and the header's)
    # (J3, the 3-pin line-out header, sits in the row y_j3 between the jack and the filters)
    y_j3 = 13.6
    y_r1, y_r2, y_c3 = 23.5, 20.5, 17.2
    y_c1, y_c2, y_r3 = 22.0, 18.9, 16.2          # shunt parts (horizontal), on the board-centre side
    so = 2.5                                     # shunt offset from the column (clear of the 0805 C3 courtyard)
    J3 = place('J3', W / 2 - 2.54, y_j3, 90, comps, nets, pin_target=('3', W / 2 + 2.54, y_j3))   # origin = pin 1
    print('J3', [P(J3, n) for n in ('1', '2', '3')])
    for ch, x, s, (r1, c1, r2, c2, c3, r3), jpin in chans:
        a, f1, f2, out = f'/AUDIO_{ch}', f'/{ch}_F1', f'/{ch}_F2', f'/{ch}_OUT'
        R1 = place(r1, x, y_r1, 90, comps, nets, pin_target=('1', x, y_r1 + 1))
        R2 = place(r2, x, y_r2, 90, comps, nets, pin_target=('1', x, y_r2 + 1))
        C3 = place(c3, x, y_c3, 90, comps, nets, pin_target=('1', x, y_c3 + 1))
        # shunts: C1 / C2 towards the board centre, R3 towards the edge
        C1 = place(c1, x + s * so, y_c1, 0, comps, nets, pin_target=('1', x, y_c1))
        C2 = place(c2, x + s * so, y_c2, 0, comps, nets, pin_target=('1', x, y_c2))
        R3 = place(r3, x + s * so, y_r3, 0, comps, nets, pin_target=('1', x, y_r3))
        # series path
        if ch == 'L':
            track([P(j1, '1'), P(R1, '1')], a, W_SIG)
        else:
            p2 = P(j1, '2')
            yb = P(j1, '2')[1] - 1.55
            track([p2, (p2[0], yb), (x, yb), P(R1, '1')], a, W_SIG)
        track([P(R1, '2'), P(R2, '1')], f1, W_SIG)
        track([P(R2, '2'), P(C3, '1')], f2, W_SIG)
        # shunt taps on the column
        for fp, netn, yy in ((C1, f1, y_c1), (C2, f2, y_c2)):
            pa = P(fp, '1')
            track([(x, yy), pa], netn, W_SIG)
            pg = P(fp, '2')
            vx = pg[0] + s * 1.0
            track([pg, (vx, pg[1])], 'GND', W_GND)
            via(vx, pg[1], 'GND')
        # output: up the column to the jack contact, R3 bleeder tapped on the way
        pj = [p for p in pads_xy(j2, jpin) if (p[0] - W / 2) * s < 0][0]      # the leg on this channel's side
        po = P(C3, '2')
        edge_x = pj[0] - s * 0.875                                         # pad edge facing the column
        track([po, (x, pj[1]), (edge_x, pj[1]), pj], out, W_SIG)
        pr = P(R3, '1')
        track([(x, y_r3), pr], out, W_SIG)
        track([(x, y_j3), P(J3, '1' if ch == 'L' else '3')], out, W_SIG)        # header tap
        pg = P(R3, '2')
        vx = pg[0] + s * 1.0
        track([pg, (vx, pg[1])], 'GND', W_GND)
        via(vx, pg[1], 'GND')

    # ---- ground stitching (the sleeve legs sit in the F.Cu ground fill) ----
    for x, y in ((W / 2, 17.6), (W / 2, 21.2), (W / 2, 24.2), (1.2, 26.1), (W - 1.2, 26.1), (1.2, 12.0), (W - 1.2, 12.0),
                 (1.2, 18.1), (W - 1.2, 18.1), (W / 2, 5.5)):
        via(x, y, 'GND')

    zone(pcbnew.F_Cu, 'GND')
    zone(pcbnew.B_Cu, 'GND')

    # ---- silkscreen ----
    silk('L', 1.4, 20.6, size=1.0)
    silk('R', W - 1.4, 20.6, size=1.0)
    j3l = [P(J3, n) for n in ('1', '2', '3')]
    silk('L', j3l[0][0] - 2.25, y_j3, size=0.9)
    silk('R', j3l[2][0] + 2.25, y_j3, size=0.9)
    silk('G', j3l[1][0], y_j3 + 2.3, size=0.9)
    bl = pcbnew.B_SilkS
    # back, top band: logo at the board's left (x 1..7), name / revision / date right of the jack's posts
    for i, s_ in enumerate(('Pmod', 'Stereo DAC', 'Rev.A', '2026-10-20')):
        silk(s_, 15.4, 1.9 + i * 1.45, layer=bl, size=0.9, thick=0.15)
    silk('Kenta Ida (@ciniml)', W / 2, 10.3, layer=bl, size=1.0, thick=0.15)
    silk('Pmod 1:L 2:R 5,11:GND', W / 2, 11.75, layer=bl, size=0.8, thick=0.15)

    # logo on the back (board only, not in BOM / placement)
    lg = load_fp('local:logo')
    lg.SetReference('LOGO1')
    lg.SetValue('logo')
    lg.Reference().SetVisible(False)
    lg.Value().SetVisible(False)
    lg.SetAttributes(pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    board.Add(lg)
    lg.SetPosition(pt(4.3, 4.3))
    lg.Flip(pt(4.3, 4.3), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)

    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    board.Save(os.path.join(PRJ, NAME + '.kicad_pcb'))
    print('saved')


if __name__ == '__main__':
    build()
