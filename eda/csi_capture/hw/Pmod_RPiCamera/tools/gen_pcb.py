#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_RPiCamera.kicad_pcb from the schematic's netlist.

Board 25.4 x 24.13 mm, 2 layers, 1.6 mm. Board coordinates below are
relative to the top-left corner (y down); the Pmod header is on the bottom
edge (as in TangFPGAExtensions Pmod_DisplayPort), the FFC connector on the
top edge with its cable opening facing out.

CSI pairs (netclass Link, 0.1661 / 0.127 mm, as Pmod_DisplayPort) run on
F.Cu only over the solid B.Cu ground: Pmod pins 2/8 (CLK), 3/9 (D1),
4/10 (D0) keep the FFC's left-to-right order (CLK, D1, D0), so the pairs
never cross. Inside a pair the P pad sits above the N pad at the Pmod and
left of it at the FFC: N runs up beside P's pad, ~2.5 mm longer (~17 ps,
negligible at <= 1 Gbps).
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

NAME = 'Pmod_RPiCamera'
X0, Y0 = 100.0, 80.0          # board origin on the page
W, H = 25.4, 24.13
FPDIR = '/usr/share/kicad/footprints'
TMP = os.environ.get('TMPDIR', '/tmp')

W_PAIR, GAP = 0.1661, 0.127
S_PAIR = W_PAIR + GAP          # centre spacing
W_SIG, W_PWR = 0.2, 0.5


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


def silk(text, x, y, layer=pcbnew.F_SilkS, size=0.8, thick=0.12, rot=0, mirror=None):
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
def build():
    global board
    comps, nets = read_netlist()
    board = pcbnew.NewBoard(os.path.join(PRJ, NAME + '.kicad_pcb'))
    board.SetCopperLayerCount(2)
    ds = board.GetDesignSettings()
    ds.SetAuxOrigin(pt(0, H))

    # outline: 1.27 mm chamfered corners
    c = 1.27
    poly = [(c, 0), (W - c, 0), (W, c), (W, H - c), (W - c, H), (c, H), (0, H - c), (0, c), (c, 0)]
    for a, b in zip(poly, poly[1:]):
        edge_line(*a, *b)

    # ---- parts ----
    # J1 Pmod: pad 1 at (6.35, H-6.35), pads 1..6 to the right, 7..12 towards the edge
    j1 = place('J1', 6.35, H - 6.35, 90, comps, nets)
    # J2 FFC, rotated 180: opening at the top edge, pads (pin 1 on the right) at y = 9.0
    j2 = place('J2', W / 2, 7.2, 180, comps, nets)
    f1 = place('F1', 1.9, 14.0, 90, comps, nets, pin_target=('1', 1.9, 15.0))
    c1 = place('C1', 3.9, 13.5, 90, comps, nets, pin_target=('1', 3.9, 12.5))
    r1 = place('R1', 3.6, 17.5, 0, comps, nets, pin_target=('1', 3.1, 17.5))
    r2 = place('R2', 8.4, 13.2, 0, comps, nets, pin_target=('1', 8.9, 13.2))
    r3 = place('R3', 9.7, 11.6, 90, comps, nets, pin_target=('1', 9.7, 12.1))

    P = lambda fp, n: pad_xy(fp, n)  # noqa: E731
    for n in ('1', '2', '7', '12'):
        print('J1', n, P(j1, n))
    for n in ('1', '15', 'MP'):
        print('J2', n, P(j2, n))

    # ---- CSI pairs ----
    yrow1 = P(j1, '1')[1]
    for (pp, pn, fp_p, fp_n, pname) in (('2', '8', '9', '8', 'CLK'), ('3', '9', '6', '5', 'D1'), ('4', '10', '3', '2', 'D0')):
        xp, _ = P(j1, pp)
        xf, yf = P(j2, fp_p)
        xfn, _ = P(j2, fp_n)
        assert abs(xfn - xf - 1.0) < 1e-3, (pname, xf, xfn)
        c0 = xp + 1.1 - S_PAIR / 2            # pair centre leaving the Pmod
        cf = xf + 0.5                          # pair centre at the FFC
        y_join = yrow1 - 1.39                  # P and N coupled from here up
        y0 = y_join - 0.59
        D = cf - c0
        centre = [(c0, y_join), (c0, y0), (c0 + D, y0 - D), (cf, 11.0)]
        p_path = offset_polyline(centre, +S_PAIR / 2)    # (+ = towards -x on upward segments)
        n_path = offset_polyline(centre, -S_PAIR / 2)
        np_ = f'/CSI_{pname}_P'
        nn_ = f'/CSI_{pname}_N'
        # Pmod side: P straight up out of its pad then 45 deg onto the pair, N beside P's pad
        xp_c = p_path[0][0]
        track([(xp, yrow1), (xp, y_join + (xp_c - xp)), (xp_c, y_join)], np_, W_PAIR)
        xn_c = n_path[0][0]
        ynp = P(j1, pn)[1]
        track([(xp, ynp), (xn_c, ynp - (xn_c - xp)), (xn_c, y_join)], nn_, W_PAIR)
        track(p_path, np_, W_PAIR)
        track(n_path, nn_, W_PAIR)
        # FFC fan-out
        pe, ne = p_path[-1], n_path[-1]
        track([pe, (xf, pe[1] - (pe[0] - xf)), (xf, yf)], np_, W_PAIR)
        track([ne, (xfn, ne[1] - (xfn - ne[0])), (xfn, yf)], nn_, W_PAIR)

    # ---- I2C ----
    x1, y1 = P(j1, '1')
    x7, y7 = P(j1, '7')
    xscl, yf = P(j2, '13')
    xsda, _ = P(j2, '14')
    track([(x1, y1), (x1, y1 - 1.18), (xscl, y1 - 1.18 - (xscl - x1)), (xscl, yf)], '/CAM_SCL', W_SIG)
    xs = x7 - 1.15
    track([(x7, y7), (xs, y7 - 1.15), (xs, 10.15 + (xsda - xs)), (xsda, 10.15), (xsda, yf)], '/CAM_SDA', W_SIG)
    # pull-ups
    track([P(r1, '2'), (xs, P(r1, '2')[1])], '/CAM_SDA', W_SIG)
    track([P(r2, '2'), (xscl, P(r2, '2')[1])], '/CAM_SCL', W_SIG)
    gx, gy = P(j2, '11')
    track([P(r3, '2'), (gx, gy)], '/CAM_GPIO', W_SIG)
    # R2 / R3 3.3 V side: via to a B.Cu strap to the 3.3 V trunk
    r2p = P(r2, '1')
    track([P(r3, '1'), r2p], '+3V3', 0.3)
    vy = r2p[1] + 0.95
    track([r2p, (r2p[0], vy)], '+3V3', 0.3)
    via(r2p[0], vy, '+3V3')
    trunk_x = P(f1, '1')[0]
    ystrap = 16.3
    track([(r2p[0], vy), (r2p[0] - (ystrap - vy), ystrap), (trunk_x, ystrap)], '+3V3', 0.4, pcbnew.B_Cu)
    via(trunk_x, ystrap, '+3V3')

    # ---- power ----
    f1a, f1b = P(f1, '1'), P(f1, '2')       # 1: +3V3 (bottom), 2: +3V3_CAM (top)
    y_bus = H - 1.43
    x6, y6 = P(j1, '6')
    x12, y12 = P(j1, '12')
    track([(x6, y6), (x12, y12), (x12, y_bus), (f1a[0], y_bus), f1a], '+3V3', W_PWR)
    track([P(r1, '1'), (f1a[0], P(r1, '1')[1])], '+3V3', 0.3)
    x15, _ = P(j2, '15')
    y_cam = 10.6
    track([f1b, (f1b[0], y_cam), (x15 - 0.75, y_cam), (x15, y_cam - 0.75), (x15, yf)], '/+3V3_CAM', W_PWR)
    c1a, c1b = P(c1, '1'), P(c1, '2')
    track([c1a, (f1b[0], c1a[1])], '/+3V3_CAM', 0.4)
    track([c1b, (c1b[0], c1b[1] + 1.0)], 'GND', 0.4)
    via(c1b[0], c1b[1] + 1.1, 'GND')

    # ---- ground ----
    for n in ('1', '4', '7', '10'):
        x, y = P(j2, n)
        track([(x, y), (x, 10.75)], 'GND', 0.3)
        via(x, 10.75, 'GND')
    for x, y in ((21.6, 11.6), (23.6, 11.6), (21.6, 14.4), (23.6, 14.4),
                 (23.4, 18.2), (23.4, 20.6), (17.8, 15.6), (1.2, 10.0), (11.0, 21.9), (15.0, 21.9)):
        via(x, y, 'GND')

    zone(pcbnew.F_Cu, 'GND')
    zone(pcbnew.B_Cu, 'GND')

    # ---- silkscreen ----
    silk('1', P(j2, '1')[0] + 1.3, 11.8, size=0.8)
    silk('CAM', 22.4, 17.0, size=0.9, thick=0.15)
    bl = pcbnew.B_SilkS
    lines = ['Pmod RPi Camera Rev.A', 'MIPI CSI-2 2-lane',
             '1 SCL 2 CLK+ 3 D1+ 4 D0+', '7 SDA 8 CLK- 9 D1- 10 D0-',
             'FFC: contacts DOWN (84952)', 'reversed? fit 84953 (UP)']
    for i, s in enumerate(lines):
        silk(s, W / 2, 10.3 + i * 1.18, layer=bl, size=0.8, thick=0.12)

    # refill and save
    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    board.Save(os.path.join(PRJ, NAME + '.kicad_pcb'))
    print('saved')


if __name__ == '__main__':
    build()
