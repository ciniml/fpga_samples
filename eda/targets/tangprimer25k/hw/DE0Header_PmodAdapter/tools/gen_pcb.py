#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate DE0Header_PmodAdapter.kicad_pcb from the schematic's netlist.

Board 91.44 x 45 mm, 2 layers, 1.6 mm. Coordinates below are relative to
the board's top-left corner, y down, in the same orientation as the Dock
seen from above (Dock schematic / ibom Tang_Primer_25K_Dock_60033): the
Dock's 40-pin header J3 sits along the Dock's top edge, pin 1 left, odd
pins on the inner row (towards the Dock), even pins on the outer row.
J1 (2x20 female, bottom side) mates with it at the bottom of this board;
the board extends outwards from the Dock and the four Pmod host sockets
face away from it along the top edge (pitch 22.86 mm as on the Dock).

Every header pair (2k-1, 2k) runs as a coupled pair (netclass Link,
0.1661 / 0.127 mm over the solid B.Cu ground) to one Pmod column: the
header's P (even, outer row) to Pmod pin n (top row), N to pin n+6. Both
ends have P and N stacked, so N passes beside P's pad on the right
(1.15 mm off its centre) and the pair keeps N on the right throughout.
Groups shift left / right with 45 degree runs and never cross.
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
import pinmap as pm  # noqa: E402

NAME = 'DE0Header_PmodAdapter'
X0, Y0 = 100.0, 60.0
W, H = 91.44, 45.0
FPDIR = '/usr/share/kicad/footprints'
TMP = os.environ.get('TMPDIR', '/tmp')

W_PAIR, GAP = 0.1661, 0.127
S_PAIR = W_PAIR + GAP
W_SE, S_SE = 0.2, 0.4
OFF = 1.15                      # N beside P's 1.7 mm pad
W_PWR = 0.6

# header J1 (Dock J3): pair k (pins 2k-1, 2k) column x, rows
YI = 42.0                       # inner row (odd pins, N)
YO = YI - 2.54                  # outer row (even pins, P)
X1 = 21.59                      # k = 1
def hx(pin):
    return X1 + ((pin - 1) // 2) * 2.54

# Pmod sockets: column 1 x, rows (top row = Pmod 1..6 = inner, further from the edge)
PMOD_X = {s: 5.08 + i * 22.86 for i, s in enumerate(pm.PMODS)}
PY_TOP, PY_BOT = 13.03, 10.49   # Pmod pins 1..6 / 7..12 (socket fronts 0.4 mm inside the edge)
EXT1_X = 44.45                  # EXT1 column 1 (rows as a Pmod)
EXT2_X, EXT2_YP = 67.31, 36.0   # EXT2 column 1, lower (P) row
Y_TURN = YI - 4.52              # where the groups start their 45 degree runs
Y_TURN_D = 32.0                 # Pmod D turns above EXT2
# Dock mounting holes on both sides of the 40-pin header (Dock iBOM: J9 / J11, 2.7 mm drill
# at (103.28, 70.95) / (161.27, 70.95); header pin 1 at (108.145, 72.525)): the same offsets
# from J1 pin 1 here, so M2.5 standoffs (11 mm: 8.5 mm socket + 2.5 mm header base) fix the
# board to the Dock
HOLE_DX = (-4.865, 53.125)
HOLE_DY = -1.575
HOLES = [(X1 + dx, YI + HOLE_DY) for dx in HOLE_DX]


def mm(v):
    return pcbnew.FromMM(v)


def pt(x, y):
    return pcbnew.VECTOR2I(mm(X0 + x), mm(Y0 + y))


def read_netlist():
    net_file = os.path.join(TMP, NAME + '.net')
    subprocess.run(['kicad-cli', 'sch', 'export', 'netlist', '--format', 'kicadsexpr', '-o', net_file,
                    os.path.join(PRJ, NAME + '.kicad_sch')], check=True, capture_output=True)
    t = sexp.parse(open(net_file).read())[0]
    comps = {}
    for c in sexp.find_all(sexp.find(t, 'components'), 'comp'):
        ref = sexp.find(c, 'ref')[1].strip('"')
        comps[ref] = {'value': sexp.find(c, 'value')[1].strip('"'), 'footprint': sexp.find(c, 'footprint')[1].strip('"'),
                      'uuid': sexp.find(c, 'tstamps')[1].strip('"'), 'fields': {}}
        d = sexp.find(c, 'description')
        if d:
            comps[ref]['fields']['Description'] = d[1].strip('"')
        for f in sexp.find_all(sexp.find(c, 'fields') or [], 'field'):
            fname = sexp.find(f, 'name')[1].strip('"')
            if fname not in ('Footprint', 'Datasheet', 'Description') and len(f) > 2:
                comps[ref]['fields'][fname] = f[2].strip('"')
    nets = {}
    for n in sexp.find_all(sexp.find(t, 'nets'), 'net'):
        name = sexp.find(n, 'name')[1].strip('"')
        for node in sexp.find_all(n, 'node'):
            nets[(sexp.find(node, 'ref')[1].strip('"'), sexp.find(node, 'pin')[1].strip('"'))] = name
    return comps, nets


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


def pad_xy(fp, num):
    p = [p for p in fp.Pads() if p.GetNumber() == str(num)][0].GetPosition()
    return (round(pcbnew.ToMM(p.x) - X0, 4), round(pcbnew.ToMM(p.y) - Y0, 4))


def place(ref, targets, comps, nets, bottom=False):
    """place so that every pad in targets {pad: (x, y)} lands on its target: tries the four
    rotations (after flipping to the bottom side if asked) and moves the part onto the first pad"""
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
    fp.Reference().SetVisible(False)
    board.Add(fp)
    fp.SetPosition(pt(0, 0))
    if bottom:
        fp.Flip(pt(0, 0), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    first = next(iter(targets))
    for r in (0, 90, 180, 270):
        fp.SetOrientationDegrees(r)
        fp.SetPosition(pt(0, 0))
        px, py = pad_xy(fp, first)
        tx, ty = targets[first]
        fp.SetPosition(pt(tx - px, ty - py))
        if all(math.hypot(pad_xy(fp, n)[0] - x, pad_xy(fp, n)[1] - y) < 1e-3 for n, (x, y) in targets.items()):
            break
    else:
        raise RuntimeError(f'{ref}: no orientation fits {targets}')
    for p in fp.Pads():
        n = nets.get((ref, p.GetNumber()))
        if n:
            p.SetNet(net(n))
    return fp


def track(points, netname, width, layer=pcbnew.F_Cu):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if abs(x1 - x2) < 1e-9 and abs(y1 - y2) < 1e-9:
            continue
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
    """offset by d: positive = towards -x on upward segments (miter joins)"""
    def seg_off(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        return (dy / L * d, -dx / L * d)
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
            a1 = (pts[i - 1][0] + o1[0], pts[i - 1][1] + o1[1])
            d1 = (pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            a2 = (pts[i][0] + o2[0], pts[i][1] + o2[1])
            d2 = (pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            den = d1[0] * d2[1] - d1[1] * d2[0]
            t = ((a2[0] - a1[0]) * d2[1] - (a2[1] - a1[1]) * d2[0]) / den
            out.append((a1[0] + d1[0] * t, a1[1] + d1[1] * t))
    return out


def route_pair(netp, netn, xs, xd, yd_p, y_turn, w, s):
    """header column xs (P outer row YO, N inner row YI) -> destination column xd
    (P at yd_p, N at yd_p - 2.54), N on the right of P all the way"""
    dp = OFF - s
    y_join = YO - 1.39
    y_join2 = yd_p + 1.39
    c0 = xs + OFF - s / 2
    D = xd - xs
    centre = [(c0, y_join)]
    if abs(D) > 1e-6:
        if y_turn < y_join:
            centre.append((c0, y_turn))
        else:
            y_turn = y_join
        assert y_turn - abs(D) >= y_join2 - 1e-6, (netp, y_turn, D, y_join2)
        centre.append((c0 + D, y_turn - abs(D)))
    centre.append((c0 + D, y_join2))
    p_path = offset_polyline(centre, +s / 2)
    n_path = offset_polyline(centre, -s / 2)
    # source end
    track([(xs, YO), (xs, y_join + dp), p_path[0]], netp, w)
    track([(xs, YI), (xs + OFF, YI - OFF), n_path[0]], netn, w)
    track(p_path, netp, w)
    track(n_path, netn, w)
    # destination end
    track([p_path[-1], (xd, y_join2 - dp), (xd, yd_p)], netp, w)
    track([n_path[-1], (xd + OFF, yd_p - 2.54 + OFF), (xd, yd_p - 2.54)], netn, w)


def silk(text, x, y, layer=pcbnew.F_SilkS, size=1.0, thick=0.15, just=None):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(pt(x, y))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(thick))
    if layer == pcbnew.B_SilkS:
        t.SetMirrored(True)
    if just == 'left':
        t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_LEFT if layer != pcbnew.B_SilkS else pcbnew.GR_TEXT_H_ALIGN_RIGHT)
    board.Add(t)
    return t


def edge_line(x1, y1, x2, y2):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(pt(x1, y1))
    s.SetEnd(pt(x2, y2))
    s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(mm(0.05))
    board.Add(s)


def zone(layer, netname):
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


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def stitching_vias(pitch=3.81, margin=0.55, keepout=()):
    obst = []
    for t in board.GetTracks():
        a, b = t.GetStart(), t.GetEnd()
        obst.append(('seg', pcbnew.ToMM(a.x) - X0, pcbnew.ToMM(a.y) - Y0, pcbnew.ToMM(b.x) - X0, pcbnew.ToMM(b.y) - Y0,
                     pcbnew.ToMM(t.GetWidth()) / 2))
    for fp in board.GetFootprints():
        for p in fp.Pads():
            c = p.GetPosition()
            r = math.hypot(pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())) / 2
            obst.append(('pad', pcbnew.ToMM(c.x) - X0, pcbnew.ToMM(c.y) - Y0, r))
    n = 0
    y = 2.0
    while y < H - 1.5:
        x = 2.0
        while x < W - 1.5:
            ok = not any(a <= x <= c and b <= y <= d for a, b, c, d in keepout)
            for o in (obst if ok else ()):
                if o[0] == 'seg':
                    if seg_dist(x, y, *o[1:5]) < o[5] + 0.3 + margin:
                        ok = False
                        break
                elif math.hypot(x - o[1], y - o[2]) < o[3] + 0.3 + margin:
                    ok = False
                    break
            if ok:
                via(x, y, 'GND')
                n += 1
            x += pitch
        y += pitch
    return n


def add_silk():
    out = []
    for slot in pm.PMODS:
        x1 = PMOD_X[slot]
        out.append(silk(f'PMOD {slot} ({pm.SLOT_NAME[slot]})', x1 + 6.35, 18.3))
        out.append(silk('1', x1 - 1.9, PY_TOP))
    out.append(silk('EXT1', EXT1_X + 1.27, 16.8))
    out.append(silk('EXT2', 83.0, 35.4))
    out.append(silk('F7 J11 GND', 83.0, 37.4, size=0.8))
    out.append(silk('F6 J10 3V3', 83.0, 31.6, size=0.8))
    out.append(silk('1', EXT2_X - 1.9, EXT2_YP))
    bl = pcbnew.B_SilkS
    lines = ['Tang Primer 25K', '40-pin (J3) to Pmod Adapter', 'Rev.A  2026-10-20', 'Kenta Ida (@ciniml)']
    for i, s in enumerate(lines):
        out.append(silk(s, 36.0, 17.0 + i * 1.6, layer=bl))
    table = ['A pmod3: 1 K1 2 L2 3 J4 4 G2 / 7 K2 8 L1 9 K4 10 G1',
             'B pmod4: 1 L4 2 B2 3 F2 4 E1 / 7 L3 8 C2 9 F1 10 A1',
             'C pmod5: 1 J1 2 G4 3 H1 4 K7 / 7 J2 8 H4 9 H2 10 J7',
             'D pmod6: 1 L7 2 L10 3 L9 4 J8 / 7 L8 8 K10 9 K9 10 K8',
             'EXT1: D1 3V3 / E3 GND   EXT2: F6 J10 3V3 / F7 J11 GND']
    for i, s in enumerate(table):
        out.append(silk(s, 45.72, 25.6 + i * 1.6, layer=bl, size=1.0))
    logo = load_fp('local:logo')
    logo.SetReference('LOGO1')
    logo.SetValue('logo')
    logo.Reference().SetVisible(False)
    logo.Value().SetVisible(False)
    logo.SetAttributes(pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    board.Add(logo)
    logo.SetPosition(pt(62.0, 19.4))
    logo.Flip(pt(62.0, 19.4), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    out.append(logo)
    return out


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

    # ---- parts ----
    j1 = place('J1', {1: (hx(1), YI), 2: (hx(2), YO), 3: (hx(3), YI)}, comps, nets, bottom=True)
    for pin in (39, 40, 11, 12):
        assert math.hypot(pad_xy(j1, pin)[0] - hx(pin), pad_xy(j1, pin)[1] - (YI if pin % 2 else YO)) < 1e-3, pin
    socks = {}
    for i, slot in enumerate(pm.PMODS):
        x1 = PMOD_X[slot]
        tg = {pm.pmod_socket_pin(1): (x1, PY_TOP), pm.pmod_socket_pin(7): (x1, PY_BOT), pm.pmod_socket_pin(6): (x1 + 12.7, PY_TOP)}
        socks[slot] = place(f'J{2 + i}', tg, comps, nets)
    place('J6', {1: (EXT1_X, PY_BOT), 2: (EXT1_X + 2.54, PY_BOT), 3: (EXT1_X, PY_TOP)}, comps, nets)
    place('J7', {1: (EXT2_X, EXT2_YP), 2: (EXT2_X, EXT2_YP - 2.54), 3: (EXT2_X + 2.54, EXT2_YP)}, comps, nets)
    u1 = place('U1', {'1': (6.35, 37.7), '3': (6.35, 42.3)}, comps, nets)
    c1 = place('C1', {'1': (3.0, 42.45), '2': (3.0, 40.55)}, comps, nets)
    # C2 right above U1's tab (right of the tab is H1)
    tabx0 = max(pcbnew.ToMM(p.GetPosition().x) - X0 for p in u1.Pads() if p.GetNumber() == '2')
    c2 = place('C2', {'1': (tabx0, 35.0), '2': (tabx0 + 1.9, 35.0)}, comps, nets)
    for i, (xh, yh) in enumerate(HOLES):
        h = load_fp('MountingHole:MountingHole_2.7mm_M2.5_ISO7380')   # button head, head 4.5 mm
        h.SetReference(f'H{i + 1}')
        h.Reference().SetVisible(False)
        h.SetAttributes(pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
        board.Add(h)
        h.SetPosition(pt(xh, yh))
    caps = {}
    for i, slot in enumerate(pm.PMODS):
        x5 = PMOD_X[slot] + 4 * 2.54
        xc = x5 + 1.27
        caps[slot] = place(f'C{3 + i}', {'2': (xc - 0.48, 15.6), '1': (xc + 0.48, 15.6)}, comps, nets)

    # ---- pairs ----
    for slot, col, pp, pn, kind in pm.ROUTES:
        w, s = (W_PAIR, S_PAIR) if kind == 'pair' else (W_SE, S_SE)
        netp, netn = '/' + pm.net(slot, col, 'P', pp), '/' + pm.net(slot, col, 'N', pn)
        xs = hx(pp)
        if slot in PMOD_X:
            # C and D turn at the same height (they both shift right: C must not run into D's lanes)
            route_pair(netp, netn, xs, PMOD_X[slot] + (col - 1) * 2.54, PY_TOP,
                       Y_TURN_D if slot in ('C', 'D') else Y_TURN, w, s)
        elif slot == 'X1':
            route_pair(netp, netn, xs, EXT1_X, PY_TOP, Y_TURN, w, s)
        else:
            route_pair(netp, netn, xs, EXT2_X + (col - 1) * 2.54, EXT2_YP, Y_TURN, w, s)

    # ---- power ----
    # +5V: header pin 11 (inner row) -> B.Cu along the bottom -> via -> U1 VIN / C1
    x11 = hx(11)
    vin = pad_xy(u1, '3')
    track([(x11, YI), (x11 - 0.9, 44.0), (4.6, 44.0)], '+5V', 0.5, pcbnew.B_Cu)
    via(4.6, 44.0, '+5V')
    track([(4.6, 44.0), (vin[0], 43.4), vin], '+5V', 0.5)
    track([pad_xy(c1, '1'), (vin[0], pad_xy(c1, '1')[1])], '+5V', 0.5)
    # +3V3: U1 tab -> C2 -> left edge -> bus under the Pmod sockets -> right edge -> EXT2
    tab = pad_xy(u1, '2')
    tabs = [p for p in u1.Pads() if p.GetNumber() == '2']
    tabx = max(pcbnew.ToMM(p.GetPosition().x) - X0 for p in tabs)
    taby = tab[1]
    track([(tabx, taby), (pad_xy(c2, '1')[0], pad_xy(c2, '1')[1])], '+3V3', W_PWR)
    track([tab, (tabx, taby)], '+3V3', W_PWR)      # pin 2 and the tab are separate pads
    track([(tabx, taby), (tabx, 36.0), (1.4, 36.0), (1.4, 4.0), (89.9, 4.0), (89.9, EXT2_YP - 2.54),
           (EXT2_X + 5.08, EXT2_YP - 2.54)], '+3V3', W_PWR)
    for slot in pm.PMODS:
        x6 = PMOD_X[slot] + 5 * 2.54
        track([(x6, 4.0), (x6, PY_BOT), (x6, PY_TOP)], '+3V3', 0.5)
        cap = caps[slot]
        track([pad_xy(cap, '1'), (x6, 15.6), (x6, PY_TOP)], '+3V3', 0.4)
        track([pad_xy(cap, '2'), (x6 - 2.54, 15.6), (x6 - 2.54, PY_TOP)], 'GND', 0.4)
    track([(EXT1_X + 2.54, 4.0), (EXT1_X + 2.54, PY_BOT)], '+3V3', 0.5)
    # GND: C1 / C2 / U1 GND to vias into the B.Cu plane
    for p, d in ((pad_xy(c1, '2'), (0, -1.0)), (pad_xy(c2, '2'), (0, 1.0)), (pad_xy(u1, '1'), (-1.6, 0))):
        track([p, (p[0] + d[0], p[1] + d[1])], 'GND', 0.4)
        via(p[0] + d[0], p[1] + d[1], 'GND')

    zone(pcbnew.F_Cu, 'GND')
    zone(pcbnew.B_Cu, 'GND')
    texts = add_silk()
    keep = [(x - 3.3, y - 3.3, x + 3.3, y + 3.3) for x, y in HOLES]
    for t in texts:
        bb = t.GetBoundingBox()
        keep.append((pcbnew.ToMM(bb.GetX()) - X0 - 0.5, pcbnew.ToMM(bb.GetY()) - Y0 - 0.5,
                     pcbnew.ToMM(bb.GetRight()) - X0 + 0.5, pcbnew.ToMM(bb.GetBottom()) - Y0 + 0.5))
    nv = stitching_vias(keepout=keep)

    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    board.Save(os.path.join(PRJ, NAME + '.kicad_pcb'))
    print('saved, stitching vias', nv)


if __name__ == '__main__':
    build()
