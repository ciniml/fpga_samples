#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_USB_HS_Single.kicad_pcb from the schematic's netlist.

Board 22.86 x 27.94 mm, 2 layers, 1.6 mm. Board coordinates below are
relative to the top-left corner (y down); the Pmod header is on the bottom
edge (as Pmod_USB_HS_Single / TangFPGAExtensions Pmod_DisplayPort), the USB-C
receptacle on the top edge.

The receptacle's single pad row interleaves D+ / D- (B6 D+, A7 D-, A6 D+,
B7 D-): B6-A6 are joined over the pad row (under the connector body),
B7 hops under D+ on B.Cu to the A7 trunk. Below the ESD diodes D+ / D- run
as a coupled pair (USB netclass, 0.1661 / 0.127 mm) on F.Cu over the solid
B.Cu ground to the TN710 network just above the header: D+ fans out to
R6 (dx series), the comparator Pmod 2 (straight), R2 (term) -> Pmod 3 and
R1 (pull-up) -> Pmod 4; D- to R7 (dx series, beside R6) and R3. The dx pair
(R6 / R7 -> Pmod 1 / 7) runs coupled down the left of the header and
enters between the rows, splitting symmetrically to the two pins. R3 ->
Pmod 9 from below the header rows. VREF reaches Pmod 8 between the rows on
B.Cu, VBUS_DET Pmod 10 between the rows on F.Cu.
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

NAME = 'Pmod_USB_HS_Single'
X0, Y0 = 100.0, 80.0          # board origin on the page
W, H = 22.86, 27.94
FPDIR = '/usr/share/kicad/footprints'
TMP = os.environ.get('TMPDIR', '/tmp')

W_PAIR, GAP = 0.1661, 0.127
S_PAIR = W_PAIR + GAP          # centre spacing
W_SIG, W_PWR = 0.2, 0.4


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


def keepout_circle(c, r, n=16):
    z = pcbnew.ZONE(board)
    z.SetIsRuleArea(True)
    z.SetDoNotAllowZoneFills(True)
    z.SetDoNotAllowTracks(False)
    z.SetDoNotAllowVias(False)
    z.SetDoNotAllowPads(False)
    z.SetDoNotAllowFootprints(False)
    ls = pcbnew.LSET()
    ls.AddLayer(pcbnew.F_Cu)
    ls.AddLayer(pcbnew.B_Cu)
    z.SetLayerSet(ls)
    ol = z.Outline()
    ol.NewOutline()
    for i in range(n):
        a = 2 * math.pi * i / n
        ol.Append(c.x + mm(r * math.cos(a)), c.y + mm(r * math.sin(a)))
    board.Add(z)


# ---------------------------------------------------------------- board
def build():
    global board
    comps, nets = read_netlist()
    board = pcbnew.NewBoard(os.path.join(PRJ, NAME + '.kicad_pcb'))
    board.SetCopperLayerCount(2)
    ds = board.GetDesignSettings()
    ds.SetAuxOrigin(pt(0, H))
    ds.m_HoleClearance = mm(0.25)      # as the project rules (the zone fill uses it)
    ds.m_HoleToHoleMin = mm(0.25)
    ds.m_CopperEdgeClearance = mm(0.2)

    c = 1.27
    poly = [(c, 0), (W - c, 0), (W, c), (W, H - c), (W - c, H), (c, H), (0, H - c), (0, c), (c, 0)]
    for a, b in zip(poly, poly[1:]):
        edge_line(*a, *b)

    # ---- parts ----
    YT = H - 6.35                 # Pmod row 1..6 (row 7..12 at YT + 2.54, towards the edge)
    j1 = place('J1', 5.08, YT, 90, comps, nets)
    cx = W / 2
    j2 = place('J2', cx, 3.0, 180, comps, nets)       # opening at the top edge, pad row at y = 7.045
    d1 = place('D1', 12.03, 10.6, 0, comps, nets, pin_target=('1', 11.68, 10.6))
    d2 = place('D2', 10.25, 10.6, 0, comps, nets, pin_target=('1', 10.6, 10.6))
    yr = YT - 2.99                # network resistors (pad 1 up)
    r6 = place('R6', 3.4, yr, 90, comps, nets, pin_target=('1', 3.4, yr - 1))
    r2 = place('R2', 10.16, yr, 90, comps, nets, pin_target=('1', 10.16, yr - 1))
    r1 = place('R1', 12.7, yr, 90, comps, nets, pin_target=('1', 12.7, yr - 1))
    r7 = place('R7', 2.3, yr, 90, comps, nets, pin_target=('1', 2.3, yr - 1))
    r3 = place('R3', 1.2, yr, 90, comps, nets, pin_target=('1', 1.2, yr - 1))
    r10 = place('R10', 13.45, 10.6, 90, comps, nets, pin_target=('1', 13.45, 9.6))
    r11 = place('R11', 9.0, 10.4, 90, comps, nets, pin_target=('1', 9.0, 9.4))
    r12 = place('R12', 16.0, 11.2, 90, comps, nets, pin_target=('1', 16.0, 10.2))
    r13 = place('R13', 16.0, 13.1, 90, comps, nets, pin_target=('1', 16.0, 12.0))
    c5 = place('C5', 16.6, 9.42, 0, comps, nets, pin_target=('1', 15.6, 9.42))
    r8 = place('R8', 21.4, YT + 1.01, 0, comps, nets, pin_target=('2', 20.4, YT + 1.01))
    r9 = place('R9', 21.4, YT + 2.31, 0, comps, nets, pin_target=('1', 20.4, YT + 2.31))
    c1 = place('C1', 21.4, YT + 3.61, 0, comps, nets, pin_target=('1', 20.4, YT + 3.61))
    c3 = place('C3', 21.4, YT - 2.79, 0, comps, nets, pin_target=('1', 20.4, YT - 2.79))
    c4 = place('C4', 21.4, YT - 1.29, 0, comps, nets, pin_target=('1', 20.4, YT - 1.29))

    P = lambda fp, n: pad_xy(fp, n)  # noqa: E731
    for n in ('1', '2', '7', '12'):
        print('J1', n, P(j1, n))
    for n in ('A6', 'B6', 'A7', 'B7', 'A5', 'B5', 'A4', 'A9', 'A1', 'B1'):
        print('J2', n, P(j2, n))

    DP, DN = '/USB_DP', '/USB_DN'
    yp = P(j2, 'A6')[1]           # pad row centre
    xA6, xB6, xA7, xB7 = P(j2, 'A6')[0], P(j2, 'B6')[0], P(j2, 'A7')[0], P(j2, 'B7')[0]
    assert xB6 < xA7 < xA6 < xB7, (xB6, xA7, xA6, xB7)

    # ---- connector: D+ B6-A6 over the pad row, D- B7 under D+ on B.Cu ----
    y_over = yp - 1.345
    track([(xB6, yp), (xB6, y_over), (xA6, y_over), (xA6, yp)], DP, W_PAIR)
    track([(xA6, yp), (xA6, 10.6)], DP, W_PAIR)                       # D+ trunk to D1
    vdn = (xA7 - 0.58, 9.5)
    track([(xA7, yp), (xA7, 8.55), (vdn[0], 8.55 + 0.58), vdn], DN, W_PAIR)
    via(*vdn, DN)
    track([vdn, (vdn[0], 10.6)], DN, W_PAIR)                          # D- trunk to D2
    vb7 = (xB7 + 0.57, 8.95)
    track([(xB7, yp), (xB7, 8.4), (vb7[0] - 0.02, vb7[1] - 0.02), vb7], DN, W_PAIR)
    via(*vb7, DN)
    track([vb7, vdn], DN, W_PAIR, pcbnew.B_Cu)

    # ---- ESD -> coupled pair -> TN710 network ----
    cx0 = (vdn[0] + xA6) / 2
    xn0, xp0 = cx0 - S_PAIR / 2, cx0 + S_PAIR / 2
    track([(xA6, 10.6), (xA6, 10.6 + 0.2), (xp0, 10.8 + (xA6 - xp0)), (xp0, 11.0 + (xA6 - xp0))], DP, W_PAIR)
    track([(vdn[0], 10.6), (vdn[0], 10.8), (xn0, 10.8 + (xn0 - vdn[0])), (xn0, 11.0 + (xn0 - vdn[0]))], DN,
          W_PAIR)
    y0 = 11.0 + (xA6 - xp0)
    x_cmp = P(j1, '2')[0]                        # comparator straight down to Pmod 2
    xc_end = x_cmp - S_PAIR / 2
    y_bus = yr - 1.5
    centre = [(cx0, y0), (cx0, y0 + 0.2), (xc_end, y0 + 0.2 + (cx0 - xc_end)), (xc_end, y_bus)]
    p_path = offset_polyline(centre, +S_PAIR / 2)
    n_path = offset_polyline(centre[:3], -S_PAIR / 2)
    track(p_path, DP, W_PAIR)
    track(n_path, DN, W_PAIR)
    # D+ bus: R6 / comparator / R2 / R1
    x6, x2, x1 = P(r6, '1')[0], P(r2, '1')[0], P(r1, '1')[0]
    track([(x6, y_bus), (x1, y_bus)], DP, W_PAIR)
    for r in (r6, r2, r1):
        track([(P(r, '1')[0], y_bus), P(r, '1')], DP, W_PAIR)
    track([(x_cmp, y_bus), P(j1, '2')], DP, W_PAIR)
    # D- to the left: R7 / R3
    ne = n_path[-1]
    x_dn = P(r7, '1')[0]
    y_dn = P(r7, '1')[1] - 0.6
    track([ne, (x_dn, ne[1]), P(r7, '1')], DN, W_PAIR)
    track([(x_dn, y_dn), (P(r3, '1')[0], y_dn), P(r3, '1')], DN, W_PAIR)
    # dx pair: R6 / R7 side by side, coupled down the left of the header, then a horizontal approach
    # between the rows that splits symmetrically (P up to Pmod 1, N down to Pmod 7)
    y_low = P(j1, '7')[1] + 1.27                 # below the outer header row
    y_mid = YT + 1.27                            # between the header rows
    x7 = P(j1, '7')[0]
    xpc = (P(r6, '2')[0] + P(r7, '2')[0]) / 2    # pair centre line
    ys = P(r6, '2')[1] + 0.6                     # end of the fan-in below the resistors
    xs = x7 - 1.12                               # split point
    centre = [(xpc, ys), (xpc, y_mid - 0.4), (xpc + 0.4, y_mid), (xs, y_mid)]
    p_path = offset_polyline(centre, +S_PAIR / 2)
    n_path = offset_polyline(centre, -S_PAIR / 2)
    track([P(r6, '2'), (P(r6, '2')[0], ys - 0.3)] + [p_path[0]], '/DX_P', W_PAIR)
    track([P(r7, '2'), (P(r7, '2')[0], ys - 0.3)] + [n_path[0]], '/DX_N', W_PAIR)
    track(p_path + [P(j1, '1')], '/DX_P', W_PAIR)
    track(n_path + [P(j1, '7')], '/DX_N', W_PAIR)
    track([P(r2, '2'), P(j1, '3')], '/TERM_DP', W_PAIR)
    track([P(r1, '2'), P(j1, '4')], '/PULLUP', W_SIG)
    # D- termination: down the left edge, under Pmod 7 / 8, into Pmod 9 from below
    x9, y9 = P(j1, '9')
    xr3 = P(r3, '2')[0]
    track([P(r3, '2'), (xr3, y_low - 1.2), (xr3 + 1.2, y_low), (x9, y_low), (x9, y9)], '/TERM_DN', W_PAIR)

    # ---- CC / VBUS ----
    xA5, xB5 = P(j2, 'A5')[0], P(j2, 'B5')[0]
    track([(xA5, yp), (xA5, 7.9), (13.45, 7.9 + 13.45 - xA5), P(r10, '1')], '/CC1', W_SIG)
    track([(xB5, yp), (xB5, 7.95), (9.0, 7.95 + xB5 - 9.0), P(r11, '1')], '/CC2', W_SIG)
    xA4 = P(j2, 'A4')[0]                         # right VBUS pad (A4/B9)
    xA9 = P(j2, 'A9')[0]                         # left VBUS pad (A9/B4)
    y_strap = 4.6
    xl, xr = xA9 + 0.24, xA4 - 0.28
    track([(xl, yp), (xl, y_strap), (xr, y_strap), (xr, yp)], '/VBUS', W_SIG)
    yv = 9.42
    track([(xA4, yp), (xA4, yv - 0.52), (xA4 + 0.52, yv), P(c5, '1')], '/VBUS', 0.3)
    track([(P(r12, '1')[0], yv), P(r12, '1')], '/VBUS', 0.3)
    track([P(r12, '2'), P(r13, '1')], '/VBUS_DET', W_SIG)
    ydet = (P(r12, '2')[1] + P(r13, '1')[1]) / 2
    x10, y10 = P(j1, '10')
    xg = x10 + 1.27                              # between Pmod 4 and 5
    track([(P(r12, '2')[0], ydet), (14.3, ydet), (14.3, YT - 1.69), (xg, YT - 1.69 + 14.3 - xg), (xg, y_mid),
           (x10, y10)], '/VBUS_DET', W_SIG)

    # ---- VREF (Pmod 8 between the rows on B.Cu: DC only, nothing fast above it) ----
    x8, y8 = P(j1, '8')
    xv = 20.2
    vvr = (19.4, y_mid)
    track([(x8, y8), (x8, y_mid), vvr], '/VREF', W_SIG, pcbnew.B_Cu)
    via(*vvr, '/VREF')
    track([vvr, (xv, y_mid), (xv, P(r8, '2')[1]), (xv, P(c1, '1')[1])], '/VREF', W_SIG)
    for fp, n in ((r8, '2'), (r9, '1'), (c1, '1')):
        track([(xv, P(fp, n)[1]), P(fp, n)], '/VREF', W_SIG)
    xg2 = P(r9, '2')[0]
    track([P(r9, '2'), (xg2, P(c1, '2')[1]), P(c1, '2'), (xg2, P(c1, '2')[1] + 0.9)], 'GND', 0.3)
    via(xg2, P(c1, '2')[1] + 0.9, 'GND')

    # ---- 3.3 V ----
    x6p, y6p = P(j1, '6')
    track([(x6p, y6p), P(j1, '12')], '+3V3', W_PWR)
    xt = 19.9
    track([(x6p, y6p), (xt, y6p), (xt, P(c3, '1')[1]), P(c3, '1')], '+3V3', W_PWR)
    track([(xt, P(c4, '1')[1]), P(c4, '1')], '+3V3', W_PWR)
    track([(xt, y6p), (P(r8, '1')[0], y6p), P(r8, '1')], '+3V3', 0.3)
    vg = (22.3, (P(c3, '2')[1] + P(c4, '2')[1]) / 2)
    track([P(c3, '2'), vg, P(c4, '2')], 'GND', 0.3)
    via(*vg, 'GND')

    # ---- ground: connector, ESD, Rd, dividers ----
    for n, vxy in (('A1', (P(j2, 'A1')[0] + 0.57, 8.5)), ('B1', (P(j2, 'B1')[0] - 0.57, 8.5))):
        x, y = P(j2, n)
        track([(x, y), (x, 7.93), vxy], 'GND', 0.3)
        via(*vxy, 'GND')
    for fp in (d1, d2):
        x, y = P(fp, '2')
        track([(x, y), (x, 11.4)], 'GND', 0.3)
        via(x, 11.4, 'GND')
    x, y = P(r11, '2')
    track([(x, y), (x, 11.4), (P(d2, '2')[0], 11.4)], 'GND', 0.3)
    x, y = P(r10, '2')
    track([(x, y), (x, 11.85)], 'GND', 0.3)
    via(x, 11.85, 'GND')
    x, y = P(r13, '2')
    track([(x, y), (x, 14.3)], 'GND', 0.3)
    via(x, 14.3, 'GND')
    x, y = P(c5, '2')
    track([(x, y), (x + 0.8, y)], 'GND', 0.3)
    via(x + 0.8, y, 'GND')
    for x, y in ((1.2, 9.6), (1.2, 12.6), (1.2, 15.6), (2.6, 26.2), (7.5, 26.6), (8.4, 12.0), (10.9, 15.2),
                 (13.2, 14.6), (15.6, 19.4), (18.6, 9.0), (21.2, 9.0), (21.2, 12.0), (21.2, 15.0),
                 (18.6, 15.6), (6.3, 9.6), (16.5, 6.3), (6.4, 6.3), (5.9, 16.2),
                 (6.35, YT - 2.09), (8.89, YT - 2.09), (11.43, YT - 2.09)):
        via(x, y, 'GND')

    # the receptacle's NPTH locating pegs: keep the pours away (the filler does not apply the hole clearance)
    for p in j2.Pads():
        if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH:
            keepout_circle(p.GetPosition(), pcbnew.ToMM(p.GetDrillSize().x) / 2 + 0.3)
    zone(pcbnew.F_Cu, 'GND')
    zone(pcbnew.B_Cu, 'GND')

    # ---- silkscreen ----
    silk('USB HS', 19.6, 3.6, size=0.9, thick=0.15)
    # tiny board: drop the pin-1 dots of the 0.6 x 1 mm diodes (they collide) and the receptacle's
    # outline segments that run off the top edge
    for fp in board.GetFootprints():
        ref = fp.GetReference()
        for g in list(fp.GraphicalItems()):
            if g.GetLayer() != pcbnew.F_SilkS or g.GetClass() == 'PCB_FIELD':
                continue
            if ref in ('D1', 'D2') or (ref == 'J2' and pcbnew.ToMM(g.GetBoundingBox().GetTop()) - Y0 < 1.5):
                fp.Remove(g)
    bl = pcbnew.B_SilkS
    lines = ['Pmod USB HS Single Rev.A', 'Single LVDS, D+ cmp only',
             '1 DX+ 2 D+ 3 TRM+ 4 PU', '7 DX- 8 VREF 9 TRM- 10 VBUS',
             'usb_phy_gowin_sl CMP1=1']
    for i, s in enumerate(lines):
        silk(s, W / 2, 10.0 + i * 1.18, layer=bl, size=0.8, thick=0.12)

    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    board.Save(os.path.join(PRJ, NAME + '.kicad_pcb'))
    print('saved')


if __name__ == '__main__':
    build()
