#!/usr/bin/env python3
"""Generate pmod_100base_tx_magjack.kicad_pcb (MagJack HR911105A variant).

Board coordinates relative to the top-left corner (X right, Y down, mm).
Pmod plug on the left edge (pins point -X, pin 1 at the top), MagJack on the right edge
(opening +X).  FPGA-side placement follows the transformerless board (../../kicad).
Remaining nets are routed afterwards by route.py (Freerouting).
"""
import os
import sys

import pcbnew

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS, NAME  # noqa: E402
from gen_sch import uid  # noqa: E402
import silk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
FPDIR = '/usr/share/kicad/footprints/'
OX, OY = 100.0, 100.0
XO = 34.0                   # MagJack front pin column X
Y1 = 14.6                   # MagJack pin-1 Y
W, L = 20.32, XO + 17.76 + 0.24   # body front face at XO+17.76

F, B = pcbnew.F_Cu, pcbnew.B_Cu


def P(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))


PLACE = {
    'J1': (6.58, 3.81, 0),
    'J2': (XO, Y1, 90),
    'U1': (25.4, 11.6, 0),
    'C17': (28.5, 10.8, 180), 'C18': (28.5, 9.52, 180),
    # RX taps (0603, pin1 = RD side to the east)
    'C7': (20.0, 1.6, 180), 'C6': (20.0, 3.3, 180), 'C8': (20.0, 5.0, 180), 'C9': (20.0, 6.7, 180),
    # termination
    'R7': (22.5, 9.3, 0), 'R8': (23.4, 8.2, 0), 'C5': (22.95, 10.4, 0),
    # Rb
    'R10': (12.0, 1.3, 0), 'R9': (12.0, 5.08, 0), 'R11': (15.0, 5.08, 0), 'R12': (16.6, 8.55, 0),
    # PWM filters
    'R15': (9.3, 8.89, 0), 'C12': (11.3, 8.89, 0), 'R16': (14.0, 8.89, 0),
    'R17': (9.3, 10.16, 0), 'C13': (11.3, 10.16, 0), 'R18': (14.0, 10.16, 0),
    # TX
    'R1': (9.6, 11.43, 0), 'R2': (9.6, 12.7, 0),
    'R3': (11.6, 12.1, -90), 'C1': (12.7, 12.1, -90),
    'R4': (11.6, 15.28, -90), 'C2': (12.7, 15.28, -90),
    'C3': (19.1, 11.6, 0), 'C4': (19.1, 14.6, 0),
    # VB divider + 3.3 V decoupling (bottom-left)
    'R13': (16.5, 17.0, 0), 'R14': (18.5, 17.0, 0), 'C10': (17.5, 18.8, 0), 'C11': (17.5, 15.9, 0),
    'C14': (10.1, 18.6, 0), 'C15': (9.6, 16.9, 0), 'C16': (14.6, 17.4, 180),
}


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = os.path.join(PRJ, 'lib', 'pmod_100base_tx.pretty') if lib == 'pmod_100base_tx' else FPDIR + lib + '.pretty'
    fp = pcbnew.FootprintLoad(path, name)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def main():
    board = pcbnew.BOARD()
    ds = board.GetDesignSettings()
    ds.SetCopperLayerCount(2)
    nc = ds.m_NetSettings.GetDefaultNetclass()
    nc.SetClearance(pcbnew.FromMM(0.15))
    nc.SetTrackWidth(pcbnew.FromMM(0.2))
    nc.SetViaDiameter(pcbnew.FromMM(0.6))
    nc.SetViaDrill(pcbnew.FromMM(0.3))
    ds.m_TrackMinWidth = pcbnew.FromMM(0.127)
    ds.m_ViasMinSize = pcbnew.FromMM(0.5)
    ds.m_MinThroughDrill = pcbnew.FromMM(0.3)
    ds.m_MinClearance = pcbnew.FromMM(0.127)
    ds.m_CopperEdgeClearance = pcbnew.FromMM(0.3)
    ds.m_HoleClearance = pcbnew.FromMM(0.2)

    nets = {}

    def net(name):
        if name not in ('GND', '+3V3') and not name.startswith(('/', 'unconnected-')):
            name = '/' + name     # schematic local labels live on the root sheet
        if name not in nets:
            n = pcbnew.NETINFO_ITEM(board, name)
            board.Add(n)
            nets[name] = n
        return nets[name]

    fps = {}
    for p in PARTS:
        fp = load_fp(p['fp'])
        fp.SetReference(p['ref'])
        fp.SetValue(p['value'])
        for k, v in (('MPN', p['mpn']), ('Manufacturer', p['mfr']), ('LCSC', p['lcsc']), ('Description', p['desc'])):
            fp.SetField(k, v)
            fld = fp.GetField(k)
            if fld:
                fld.SetVisible(False)
                fld.SetLayer(pcbnew.F_Fab)
        fp.SetPath(pcbnew.KIID_PATH('/' + uid('sym', p['ref'])))
        fp.SetSheetname('/')
        fp.SetSheetfile(NAME + '.kicad_sch')
        if p['dnp']:
            fp.SetDNP(True)
        x, y, r = PLACE[p['ref']]
        fp.SetPosition(P(x, y))
        fp.SetOrientationDegrees(r)
        for pad in fp.Pads():
            n = p['pins'].get(pad.GetNumber())
            if n is None and pad.GetNumber() in p['pins']:
                n = 'unconnected-(%s-%sPad%s)' % (p['ref'], 'NC-' if pad.GetNumber() == '7' else '', pad.GetNumber())
            if n:
                pad.SetNet(net(n))
        board.Add(fp)
        fps[p['ref']] = fp
    for n in ('GND', '+3V3'):
        net(n)

    # reference text: small, on silk, centred on part (adjusted below for crowded areas)
    for ref, fp in fps.items():
        t = fp.Reference()
        t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(0.6), pcbnew.FromMM(0.6)))
        t.SetTextThickness(pcbnew.FromMM(0.1))
        t.SetLayer(pcbnew.F_Fab)   # silk refs would not fit; keep them on Fab
        fp.Value().SetLayer(pcbnew.F_Fab)
        fp.Value().SetVisible(False)

    # ------------------------------------------------------------------ routing helpers
    def track(name, pts, w=0.2, layer=F):
        for a, b in zip(pts, pts[1:]):
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(P(*a))
            t.SetEnd(P(*b))
            t.SetWidth(pcbnew.FromMM(w))
            t.SetLayer(layer)
            t.SetNet(net(name))
            t.SetLocked(True)
            board.Add(t)

    def via(name, pos, d=0.6, drill=0.3):
        v = pcbnew.PCB_VIA(board)
        v.SetPosition(P(*pos))
        v.SetWidth(pcbnew.FromMM(d))
        v.SetDrill(pcbnew.FromMM(drill))
        v.SetNet(net(name))
        v.SetLocked(True)
        board.Add(v)

    def padpos(ref, num):
        for pad in fps[ref].Pads():
            if pad.GetNumber() == num:
                c = pad.GetPosition()
                return (round(pcbnew.ToMM(c.x) - OX, 4), round(pcbnew.ToMM(c.y) - OY, 4))
        raise KeyError((ref, num))

    pp = padpos
    w = 0.2

    # ---------------- MagJack PHY pins -> TVS (flow-through) ----------------
    track('RD_N', [pp('J2', '6'), (26.5, 8.26), (26.5, 10.6), pp('U1', '10')], w)
    track('RD_P', [pp('J2', '3'), (27.0, 12.06), (26.03, 11.1), pp('U1', '9')], w)
    track('TD_N', [pp('J2', '2'), (27.3, 13.34), (26.06, 12.1), pp('U1', '7')], w)
    track('TD_P', [pp('J2', '1'), (27.785, 14.6), (25.785, 12.6)], w)
    for a, b in (('1', '10'), ('2', '9'), ('4', '7'), ('5', '6'), ('3', '8')):
        n = fps['U1'].FindPadByNumber(a).GetNetname()
        track(n, [pp('U1', a), pp('U1', b)], 0.2)
    track('GND', [pp('U1', '3'), (24.2, 11.6), (23.6, 11.85)], 0.2)
    via('GND', (23.6, 11.85))
    # centre taps: AC ground right behind the jack
    track('TCT', [pp('J2', '4'), pp('C17', '1')], w)
    track('RCT', [pp('J2', '5'), pp('C18', '1')], w)
    for c in ('C17', 'C18'):
        g = pp(c, '2')
        track('GND', [g, (27.2, g[1])], 0.3)
        via('GND', (27.2, g[1]))

    # ---------------- TVS -> termination -> taps ----------------
    # RD_N: outer (C7 top, C9 bottom); RD_P: middle (C6, C8) with a bottom hop under RD_N's C9 branch
    track('RD_N', [pp('U1', '1'), (25.0, 9.6), (24.4, 9.0), (24.4, 1.0), (21.3, 1.0), pp('C7', '1')], w)
    track('RD_N', [(24.4, 6.7), pp('C9', '1')], w)
    track('RD_N', [pp('R8', '2'), (24.4, pp('R8', '2')[1])], w)
    track('RD_P', [pp('U1', '2'), (21.8, 11.1), (21.8, 7.6)], w)
    via('RD_P', (21.8, 7.6))
    track('RD_P', [(21.8, 7.6), (21.8, 5.8)], w, B)
    via('RD_P', (21.8, 5.8))
    track('RD_P', [(21.8, 5.8), (21.8, 3.3), pp('C6', '1')], w)
    track('RD_P', [pp('C8', '1'), (21.8, 5.0)], w)
    track('RD_P', [pp('R7', '1'), (21.8, pp('R7', '1')[1])], w)
    track('RD_CT', [pp('R7', '2'), pp('R8', '1')], w)
    track('RD_CT', [pp('C5', '1'), pp('R7', '2')], w)
    track('GND', [pp('C5', '2'), (24.0, 10.45)], 0.25)
    via('GND', (24.0, 10.45))

    # taps to the Pmod (A on 1/7, B on 2/8); N pins reached through the row gaps
    track('A_N', [pp('C7', '2'), (18.2, 2.6), (4.04, 2.6), pp('J1', '7')], w)
    track('A_P', [pp('C6', '2'), (18.7, 3.81), pp('J1', '1')], w)
    track('B_P', [pp('C8', '2'), (17.9, 6.35), pp('J1', '2')], w)
    track('B_N', [pp('C9', '2'), (18.3, 7.62), (4.04, 7.62), pp('J1', '8')], w)
    track('A_N', [pp('R10', '1'), (pp('R10', '1')[0], 2.6)], w)
    track('A_P', [pp('R9', '1'), (pp('R9', '1')[0], 3.81)], w)
    track('B_P', [pp('R11', '1'), (pp('R11', '1')[0], 6.35)], w)
    track('B_N', [pp('R12', '1'), (pp('R12', '1')[0], 7.62)], w)

    # ---------------- TX ----------------
    track('TX_P', [pp('J1', '4'), pp('R1', '1')], w)
    track('TX_N', [pp('J1', '10'), (4.04, 12.7), pp('R2', '1')], w)
    track('TXP_DRV', [pp('R1', '2'), (17.9, 11.43), (18.07, 11.6), pp('C3', '1')], w)
    track('TXP_DRV', [pp('R3', '1'), (pp('R3', '1')[0], 11.43)], w)
    track('TXP_DRV', [pp('C1', '1'), (pp('C1', '1')[0], 11.43)], w)
    track('TXN_DRV', [pp('R2', '2'), (10.4, 13.0), (10.4, 14.4), (10.8, 14.8), (17.9, 14.8), (18.1, 14.6), pp('C4', '1')], w)
    track('TXN_DRV', [pp('R4', '1'), (pp('R4', '1')[0], 14.8)], w)
    track('TXN_DRV', [pp('C2', '1'), (pp('C2', '1')[0], 14.8)], w)
    track('GND', [pp('R3', '2'), (11.6, 13.0), (12.15, 13.4)], 0.25)
    track('GND', [pp('C1', '2'), (12.7, 13.0), (12.15, 13.4)], 0.25)
    via('GND', (12.15, 13.45))
    track('GND', [pp('R4', '2'), (11.6, 16.2), (12.15, 16.6)], 0.25)
    track('GND', [pp('C2', '2'), (12.7, 16.2), (12.15, 16.6)], 0.25)
    via('GND', (12.15, 16.65))
    # TD to the TVS; TD_P/TD_N swap order (P is south at the jack) -> TD_P hops under TD_N
    track('TD_N', [pp('C4', '2'), (22.2, 14.6), (24.7, 12.1), pp('U1', '4')], w)
    track('TD_P', [pp('C3', '2'), (20.9, 11.6), (20.9, 12.4)], w)
    via('TD_P', (20.9, 12.4))
    track('TD_P', [(20.9, 12.4), (21.7, 15.8)], w, B)
    via('TD_P', (21.7, 15.8))
    track('TD_P', [(21.7, 15.8), (24.9, 12.6), pp('U1', '5')], w)

    # ---------------- PWM, VB, 3.3 V ----------------
    track('PWM_A', [pp('J1', '3'), pp('R15', '1')], w)
    track('PWM_B', [pp('J1', '9'), (4.04, 10.16), pp('R17', '1')], w)
    track('VB', [pp('R9', '2'), (13.3, 5.08)], w)
    via('VB', (13.3, 5.08))
    track('VB', [(13.3, 5.08), (13.3, 6.9), (15.3, 8.9)], w, B)
    via('VB', (15.3, 8.9))
    track('VB', [(15.3, 8.9), pp('R16', '2')], w)
    track('VB', [(15.3, 8.9), (16.2, 9.8), (16.2, 15.9)], w, B)
    via('VB', (16.2, 15.9))
    track('VB', [(16.2, 15.9), pp('C11', '1'), (17.0, 17.0)], w)
    track('VB', [pp('R13', '2'), pp('R14', '1')], w)
    track('VB', [pp('C10', '1'), pp('R13', '2')], w)
    track('+3V3', [pp('C16', '1'), pp('R13', '1')], 0.25)
    track('GND', [pp('R14', '2'), (19.0, 17.95)], 0.3)
    via('GND', (19.0, 17.95))
    track('GND', [pp('C10', '2'), (19.0, 17.95)], 0.3)
    track('GND', [pp('C11', '2'), (18.9, 15.9)], 0.3)
    via('GND', (18.9, 15.9))
    gvias = {'C12': (0.7, 0), 'C13': (0.7, 0), 'C14': (0, 0.95), 'C15': (0, -0.95), 'C16': (0, 0.95)}
    for ref, (dx, dy) in gvias.items():
        for pad in fps[ref].Pads():
            if pad.GetNetname() == 'GND':
                c = pad.GetPosition()
                x, y = pcbnew.ToMM(c.x) - OX, pcbnew.ToMM(c.y) - OY
                track('GND', [(x, y), (x + dx, y + dy)], 0.3)
                via('GND', (x + dx, y + dy))

    # ------------------------------------------------------------------ outline + silk
    def seg(a, b, layer, w=0.1):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(P(*a))
        s.SetEnd(P(*b))
        s.SetLayer(layer)
        s.SetWidth(pcbnew.FromMM(w))
        board.Add(s)

    pts = [(0, 0), (L, 0), (L, W), (0, W), (0, 0)]
    for a, b in zip(pts, pts[1:]):
        seg(a, b, pcbnew.Edge_Cuts, 0.05)

    def text(s, x, y, size=0.8, rot=0, layer=pcbnew.F_SilkS, just=None):
        t = pcbnew.PCB_TEXT(board)
        t.SetText(s)
        t.SetPosition(P(x, y))
        t.SetLayer(layer)
        t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
        t.SetTextThickness(pcbnew.FromMM(0.12 if size < 1 else 0.15))
        t.SetTextAngleDegrees(rot)
        if just == 'left':
            t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_LEFT)
        if layer == pcbnew.B_SilkS:
            t.SetMirrored(True)
        board.Add(t)

    # Pmod pin-1 marker and signal names
    text('1', 8.1, 0.75, 0.8)
    seg((7.7, 1.25), (8.5, 1.25), pcbnew.F_SilkS, 0.15)
    text('A', 8.6, 3.2, 0.8)
    text('B', 8.6, 5.75, 0.8)
    text('TX', 8.5, 13.55, 0.8)
    text('100BASE-TX MagJack', 26.0, 19.45, 0.8)
    # back side: pinout, notes, logo, name / revision / date / author (tools/silk.py)
    silk.apply(board, load_fp('pmod_100base_tx:logo'))

    # ------------------------------------------------------------------ zones (GND both layers)
    for layer, prio in ((B, 0), (F, 0)):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNet(net('GND'))
        z.SetAssignedPriority(prio)
        z.SetLocalClearance(pcbnew.FromMM(0.25))
        z.SetMinThickness(pcbnew.FromMM(0.2))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(pcbnew.FromMM(0.25))
        z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.3))
        z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
        ol = z.Outline()
        ol.NewOutline()
        for (x, y) in ((0.2, 0.2), (L - 0.2, 0.2), (L - 0.2, W - 0.2), (0.2, W - 0.2)):
            ol.Append(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))
        board.Add(z)

    out = os.path.join(PRJ, NAME + '.kicad_pcb')
    board.Save(out)
    print('saved', out)


if __name__ == '__main__':
    main()
