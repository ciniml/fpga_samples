#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_10BASE_T1S.kicad_pcb from the schematic's netlist.

Board 20.32 x 44 mm (one Pmod slot wide), 2 layers 1.6 mm (B.Cu: GND pour).
Board coordinates below are relative to the top-left corner (y down),
component side up: the Pmod plug on the top edge (pins point up, Digilent
pin 1 at the right end), the screw terminal J2 on the bottom edge (wire
entry facing down).

Floor plan: TX chain on the left under Pmod pins 4 / 10 (R1 / R2, C1 / C2,
U1 TMUX1511, R5 / R6), RX taps and the VB / VTH network on the right under
pins 1-3 / 7-9 (1k series resistors right at the Pmod), TRX_P / TRX_N meet
in the middle at the ESD array U2, then the CMC L1, the DC-block caps C9 /
C10, the termination (JP1, R20-R24, C11) and J2. 12.5 MBd: nothing is
length matched; the line nets get 0.3 mm tracks.

This script places the parts, draws the outline, the GND pour and the silk;
the copper is routed by circuitpnr (tools/build.sh --regen).
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
import silk as silk_back  # noqa: E402

NAME = 'Pmod_10BASE_T1S'
X0, Y0 = 100.0, 80.0          # board origin on the page
W, H = 20.32, 44.0
FPDIR = '/usr/share/kicad/footprints'
TMP = os.environ.get('TMPDIR', '/tmp')

YP = 6.35                      # Pmod row 1..6 (7..12 at YP - 2.54, towards the edge)
JX = 16.51                     # Pmod pin-1 x (plug centre 10.16)
VIA_S = (0.45, 0.2)
JT = (7.91, H - 4.7)           # J2 pin 1 (body 10.7 x 8.0, wire entry on the bottom edge)

# 0402s in the dense rows: designators on the Fab layer only (as Pmod_DVI / Pmod_GbE)
FAB_ONLY = {'R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'C1', 'C2', 'C13', 'R8', 'R9', 'R10', 'R11', 'R12', 'R13',
            'R14', 'R15', 'R16', 'R17', 'R18', 'R19', 'C4', 'C5', 'C7', 'C8', 'R20', 'R21', 'R22'}

# (x, y, rotation) per reference
PLACE = {
    'J1': (JX, YP, 270),
    # power entry under Pmod 5 / 6, TX_EN pull-down
    'C12': (1.3, 9.9, 90), 'C13': (3.0, 9.7, 90), 'R7': (4.3, 9.7, 90),
    # TX chain under Pmod 4 / 10
    'R1': (7.6, 9.7, 90), 'R2': (8.9, 9.7, 90),
    'C1': (7.6, 11.9, 90), 'C2': (8.9, 11.9, 90),
    'U1': (4.6, 16.0, 180), 'C3': (2.0, 20.0, 0),
    'R3': (9.7, 15.0, 90), 'R4': (9.7, 17.0, 90),
    'R5': (5.6, 20.4, 90), 'R6': (7.0, 20.4, 90),
    # RX: 1k series resistors right under the Pmod pins, then the taps and the bias network
    'R18': (11.4, 9.7, 90), 'R15': (13.2, 9.7, 90), 'R11': (14.5, 9.7, 90), 'R10': (16.5, 9.7, 90),
    'R13': (17.8, 9.7, 90),
    'R19': (11.4, 12.2, 90), 'C8': (12.6, 12.2, 90), 'R14': (13.8, 12.2, 90), 'C5': (15.0, 12.2, 90),
    'C4': (17.2, 12.2, 90), 'R12': (18.4, 12.2, 90),
    'R8': (12.6, 15.0, 90), 'R9': (13.8, 15.0, 90), 'R16': (16.0, 15.0, 90), 'R17': (17.2, 15.0, 90),
    'C7': (18.4, 15.0, 90), 'C6': (16.6, 17.4, 0),
    # line: ESD, CMC, DC block
    'U2': (9.66, 21.6, 270), 'L1': (10.16, 25.4, 270),
    'C9': (12.2, 29.6, 270), 'C10': (8.1, 29.6, 270),
    # termination and probe header
    'R20': (13.6, 31.6, 0), 'R21': (13.6, 32.8, 0), 'C11': (16.4, 32.2, 90), 'R22': (17.9, 32.2, 90),
    'R23': (6.4, 32.0, 0), 'R24': (6.4, 33.8, 0),
    'JP1': (2.0, 28.0, 0), 'J3': (18.6, 22.6, 0),
    'J2': (JT[0], JT[1], 0),
}


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
            'dnp': any(sexp.find(pr, 'name')[1].strip('"') == 'dnp' for pr in sexp.find_all(c, 'property')),
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
COMPS, NETS = None, None
FP = {}


def net(name):
    if name not in netinfo:
        ni = pcbnew.NETINFO_ITEM(board, name)
        board.Add(ni)
        netinfo[name] = ni
    return netinfo[name]


def nn(name):
    """schematic net name as it appears in the netlist"""
    return name if name in ('GND', '+3V3') else '/' + name


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = os.path.join(PRJ, 'Local', 'local.pretty') if lib == 'local' else os.path.join(FPDIR, lib + '.pretty')
    fp = pcbnew.FootprintLoad(path, name)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def place(ref, x, y, rot=0):
    c = COMPS[ref]
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
    # designators are placed afterwards by `cpnr labels` (tools/build.sh --regen)
    fp.Value().SetVisible(False)
    fp.Reference().SetVisible(ref not in FAB_ONLY)
    fp.SetDNP(c['dnp'])
    board.Add(fp)
    fp.SetPosition(pt(x, y))
    fp.SetOrientationDegrees(rot)
    for p in fp.Pads():
        n = NETS.get((ref, p.GetNumber()))
        if n:
            p.SetNet(net(n))
    FP[ref] = fp
    return fp


def edge_line(x1, y1, x2, y2):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(pt(x1, y1))
    s.SetEnd(pt(x2, y2))
    s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(mm(0.05))
    board.Add(s)


def zone(layer, netname, poly=None, clearance=0.25, priority=0):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(net(nn(netname)))
    if poly is None:
        c, e = 1.27, 0.3
        poly = [(c + e, e), (W - c - e, e), (W - e, c + e), (W - e, H - c - e), (W - c - e, H - e),
                (c + e, H - e), (e, H - c - e), (e, c + e)]
    ol = z.Outline()
    ol.NewOutline()
    for x, y in poly:
        ol.Append(mm(X0 + x), mm(Y0 + y))
    z.SetLocalClearance(mm(clearance))
    z.SetMinThickness(mm(0.2))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(mm(0.25))
    z.SetThermalReliefSpokeWidth(mm(0.3))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    z.SetAssignedPriority(priority)
    board.Add(z)
    return z


def silk(text, x, y, layer=pcbnew.F_SilkS, size=0.8, thick=0.12, rot=0):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(text)
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(thick))
    t.SetTextAngleDegrees(rot)
    if layer == pcbnew.B_SilkS:
        t.SetMirrored(True)
    t.SetPosition(pt(x, y))
    board.Add(t)


def silk_line(x1, y1, x2, y2, w=0.15):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(pt(x1, y1))
    s.SetEnd(pt(x2, y2))
    s.SetLayer(pcbnew.F_SilkS)
    s.SetWidth(mm(w))
    board.Add(s)



def pad_of(ref, netname):
    """the pad number of `ref` on net `netname` (first match)"""
    for (r, n), nm in NETS.items():
        if r == ref and nm.lstrip('/') == netname.lstrip('/'):
            return n
    raise KeyError((ref, netname))


def P(ref, num):
    p = [p for p in FP[ref].Pads() if p.GetNumber() == num][0].GetPosition()
    return (round(pcbnew.ToMM(p.x) - X0, 4), round(pcbnew.ToMM(p.y) - Y0, 4))


def PN(ref, netname):
    return P(ref, pad_of(ref, netname))


def track(points, netname, width, layer=pcbnew.F_Cu):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if abs(x1 - x2) < 1e-6 and abs(y1 - y2) < 1e-6:
            continue
        t = pcbnew.PCB_TRACK(board)
        t.SetStart(pt(x1, y1))
        t.SetEnd(pt(x2, y2))
        t.SetWidth(mm(width))
        t.SetLayer(layer)
        t.SetNet(net(nn(netname)))
        board.Add(t)


def via(x, y, netname, size=VIA_S):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pt(x, y))
    v.SetWidth(mm(size[0]))
    v.SetDrill(mm(size[1]))
    v.SetNet(net(nn(netname)))
    board.Add(v)


def plen(points):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))


def build():
    global board, COMPS, NETS
    COMPS, NETS = read_netlist()
    missing = set(COMPS) - set(PLACE)
    if missing:
        raise SystemExit('no placement for ' + ' '.join(sorted(missing)))
    board = pcbnew.NewBoard(os.path.join(PRJ, NAME + '.kicad_pcb'))
    board.SetCopperLayerCount(2)
    ds = board.GetDesignSettings()
    ds.SetAuxOrigin(pt(0, H))
    ds.m_HoleClearance = mm(0.2)
    ds.m_HoleToHoleMin = mm(0.25)
    ds.m_CopperEdgeClearance = mm(0.2)

    c = 1.27
    poly = [(c, 0), (W - c, 0), (W, c), (W, H - c), (W - c, H), (c, H), (0, H - c), (0, c), (c, 0)]
    for a, b in zip(poly, poly[1:]):
        edge_line(*a, *b)

    for ref, (x, y, r) in PLACE.items():
        place(ref, x, y, r)

    # ---- hand-routed: the ESD array is flow-through, each line runs straight across its pad pair ----
    # and on (lower pad of each pair) into the CMC, then from the CMC to the DC-block caps
    for p1, p2, nm, lp in (('1', '10', 'TRX_P', '1'), ('2', '9', 'TRX_N', '2')):
        a, c = P('U2', p1), P('U2', p2)
        track([a, c], nm, 0.25)
        lo = max(a, c, key=lambda q: q[1])
        l = P('L1', lp)
        track([lo, (lo[0], lo[1] + 0.5), (l[0], lo[1] + 0.5 + abs(l[0] - lo[0])), l], nm, 0.25)
    for lp, cref, nm in (('4', 'C9', 'CM_P'), ('3', 'C10', 'CM_N')):
        l, c = P('L1', lp), PN(cref, nm)
        track([l, (l[0], l[1] + 0.6), (c[0], l[1] + 0.6 + abs(c[0] - l[0])), c], nm, 0.3)

    # ---- silkscreen ----
    silk('TERM', 2.0, 25.6, size=0.8, thick=0.12)
    silk('+', JT[0], JT[1] - 5.0, size=1.0, thick=0.15)
    silk('-', JT[0] + 5.0, JT[1] - 5.0, size=1.0, thick=0.15)
    silk_back.apply(board, silk_back.load_logo(PRJ))   # logo, name / Rev / date / author, pinout

    # ---- planes ----
    zone(pcbnew.B_Cu, 'GND')

    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    board.Save(os.path.join(PRJ, NAME + '.kicad_pcb'))
    print('saved')


if __name__ == '__main__':
    build()
