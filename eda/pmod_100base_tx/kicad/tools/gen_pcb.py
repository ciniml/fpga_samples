#!/usr/bin/env python3
"""Generate pmod_100base_tx.kicad_pcb: placement, critical hand routing, outline, silk, zones.

Board coordinates below are relative to the board's top-left corner (X right, Y down, mm).
Pmod plug on the left edge (pins point -X, pin 1 at the top), RJ45 on the right edge.

Remaining nets (+3V3, VB, VTH_A/B, PWM_A/B, BS_*) are routed afterwards by route.py
(Freerouting) on top of the locked hand-routed tracks.
"""
import os
import sys

import pcbnew

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from design import PARTS  # noqa: E402
from gen_sch import uid, NAME  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
FPDIR = '/usr/share/kicad/footprints/'
OX, OY = 100.0, 100.0
W, L = 20.32, 48.2          # board width (Y) / length (X)
XO = 40.0                   # RJ45 pin-1 X (front face at XO+8 = right edge)

F, B = pcbnew.F_Cu, pcbnew.B_Cu


def P(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))


# ------------------------------------------------------------------ placement
# ref: (x, y, rot_deg)  -- rot follows KiCad convention (CCW positive, Y down)
PLACE = {
    'J1': (6.58, 3.81, 0),
    'J2': (XO, 6.604, -90),
    'U1': (30.8, 9.4, 0),
    # RX taps (0603, pin1 = RD side to the east)
    'C7': (22.0, 1.6, 180), 'C6': (22.0, 3.3, 180), 'C8': (22.0, 5.0, 180), 'C9': (22.0, 6.7, 180),
    # termination
    'R7': (25.0, 5.15, -90), 'R8': (25.0, 7.05, -90), 'C5': (27.0, 6.1, 0),
    # Rb
    'R10': (12.0, 1.3, 0), 'R9': (12.0, 5.08, 0), 'R11': (15.0, 5.08, 0), 'R12': (17.6, 8.55, 0),
    # TX
    'R1': (9.6, 11.43, 0), 'R2': (9.6, 12.7, 0),
    'R3': (11.6, 12.1, -90), 'C1': (12.7, 12.1, -90),
    'R4': (11.6, 15.28, -90), 'C2': (12.7, 15.28, -90),
    'L1': (16.0, 13.1, 0), 'R5': (16.0, 11.6, 0), 'R6': (16.0, 14.6, 0),
    'C3': (19.1, 11.6, 0), 'C4': (19.1, 14.6, 0),
    # bias block
    'R15': (9.3, 8.89, 0), 'C12': (11.3, 8.89, 0), 'R16': (14.0, 8.89, 0),
    'R17': (9.3, 10.16, 0), 'C13': (11.3, 10.16, 0), 'R18': (14.0, 10.16, 0),
    'R13': (23.2, 10.3, 0), 'R14': (25.2, 10.3, 0),
    'C10': (23.6, 12.0, 0), 'C11': (26.0, 12.0, 0),
    # 3.3 V decoupling near J1 6/12
    'C14': (10.1, 18.6, 0), 'C15': (9.6, 16.9, 0), 'C16': (14.6, 17.4, 0),
    # Bob Smith pocket (right of the TD rise, left of the RJ45 body)
    'R19': (29.9, 12.55, -90), 'R20': (31.0, 12.55, -90), 'R21': (29.9, 14.45, 90), 'R22': (31.0, 14.45, 90),
    'C17': (30.45, 17.75, -90),
    'R23': (23.5, 15.6, 90), 'R24': (24.5, 18.5, 0), 'R25': (27.5, 3.2, 90), 'R26': (27.9, 9.75, 0),
}


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = os.path.join(PRJ, 'lib', 'pmod_100base_tx.pretty') if lib == NAME else FPDIR + lib + '.pretty'
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
        if name not in ('GND', '+3V3') and not name.startswith('/'):
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
        for k, v in (('MPN', p['mpn']), ('Manufacturer', p['mfr']), ('Description', p['desc'])):
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
            if n:
                pad.SetNet(net(n))
        if p['ref'] == 'J2':
            for m in fp.Models():
                m.m_Filename = m.m_Filename.replace('RJHSE5380', 'RJHSE538X')
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
    w_line = 0.2      # line side / taps / TX
    w_fine = 0.15     # through the RJ45 pin field

    # ---------------- RJ45 -> TVS (line side) ----------------
    # RD_P: pin 3 (front row) passes between rear-row pins 2 and 4, then to TVS pad 10 (IO1 pass-through)
    j3 = pp('J2', '3')
    track('RD_P', [j3, (37.2, j3[1]), (36.9, 8.3), (31.6, 8.3), (31.185, 8.4)], w_fine)
    j6 = pp('J2', '6')
    track('RD_N', [j6, (33.8, j6[1]), (33.8, 8.9), pp('U1', '9')], w_fine)
    # TD on the bottom layer under the RJ45 body (crosses below RD), vias next to TVS pads 7/6
    j1, j2 = pp('J2', '1'), pp('J2', '2')
    track('TD_P', [j1, (j1[0] - 0.6, 6.35), (32.0, 6.35), (32.0, 9.9)], w_line, B)
    via('TD_P', (32.0, 9.9))
    track('TD_P', [(32.0, 9.9), pp('U1', '7')], w_line)
    track('TD_N', [j2, (32.9, j2[1]), (32.9, 10.6)], w_line, B)
    via('TD_N', (32.9, 10.6))
    track('TD_N', [(32.9, 10.6), (31.8, 10.6), (31.6, 10.4), pp('U1', '6')], w_line)
    # TVS flow-through: IO pads to their NC partners, GND pads 3-8 joined + via
    for a, b in (('1', '10'), ('2', '9'), ('4', '7'), ('5', '6'), ('3', '8')):
        n = fps['U1'].FindPadByNumber(a).GetNetname()
        track(n, [pp('U1', a), pp('U1', b)], 0.2)
    track('GND', [pp('U1', '3'), (29.6, 9.4), (29.2, 9.75)], 0.2)
    via('GND', (29.2, 9.75))

    # ---------------- TVS -> termination -> taps ----------------
    track('RD_P', [pp('U1', '1'), (30.1, 8.4), (29.9, 8.2), (29.9, 6.75), (27.4, 4.25), (27.3, 4.15), (23.6, 4.15)], w_line)
    track('RD_P', [(23.6, 3.3), (23.6, 5.0)], w_line)
    track('RD_P', [pp('C6', '1'), (23.6, 3.3)], w_line)
    track('RD_P', [pp('C8', '1'), (23.6, 5.0)], w_line)
    track('RD_P', [pp('R7', '1'), (pp('R7', '1')[0], 4.15)], w_line)
    track('RD_N', [pp('U1', '2'), (24.0, 8.9), (22.775, 7.675), pp('C9', '1')], w_line)
    track('RD_N', [pp('R8', '2'), (pp('R8', '2')[0], 8.9)], w_line)
    track('RD_CT', [pp('R7', '2'), pp('R8', '1')], w_line)
    track('RD_CT', [pp('C5', '1'), (pp('R7', '2')[0], pp('C5', '1')[1])], w_line)
    track('GND', [pp('C5', '2'), (pp('C5', '2')[0], 7.3)], 0.3)
    via('GND', (pp('C5', '2')[0], 7.3))
    # RD_N upper branch to C7: hop under the RD_P trunk on the bottom layer
    track('RD_N', [(25.9, 8.9), (25.9, 7.9)], w_line)
    via('RD_N', (25.9, 7.9))
    track('RD_N', [(25.9, 7.9), (25.9, 2.9)], w_line, B)
    via('RD_N', (25.9, 2.9))
    track('RD_N', [(25.9, 2.9), (25.9, 2.5), (25.0, 1.6), pp('C7', '1')], w_line)

    # taps to the Pmod (A on 1/7, B on 2/8); N pins reached through the row gaps
    track('A_N', [pp('C7', '2'), (20.2, 2.6), (4.04, 2.6), pp('J1', '7')], w_line)
    track('A_P', [pp('C6', '2'), (20.7, 3.81), pp('J1', '1')], w_line)
    track('B_P', [pp('C8', '2'), (19.9, 6.35), pp('J1', '2')], w_line)
    track('B_N', [pp('C9', '2'), (20.3, 7.62), (4.04, 7.62), pp('J1', '8')], w_line)
    # Rb taps
    track('A_N', [pp('R10', '1'), (pp('R10', '1')[0], 2.6)], w_line)
    track('A_P', [pp('R9', '1'), (pp('R9', '1')[0], 3.81)], w_line)
    track('B_P', [pp('R11', '1'), (pp('R11', '1')[0], 6.35)], w_line)
    track('B_N', [pp('R12', '1'), (pp('R12', '1')[0], 7.62)], w_line)

    # ---------------- TX ----------------
    track('TX_P', [pp('J1', '4'), pp('R1', '1')], w_line)
    track('TX_N', [pp('J1', '10'), (4.04, 12.7), pp('R2', '1')], w_line)
    r1b, r2b = pp('R1', '2'), pp('R2', '2')
    track('TXP_DRV', [r1b, (14.6, 11.43), (14.6, 12.45), (14.85, 12.7), pp('L1', '1')], w_line)
    track('TXP_DRV', [pp('R3', '1'), (pp('R3', '1')[0], 11.43)], w_line)
    track('TXP_DRV', [pp('C1', '1'), (pp('C1', '1')[0], 11.43)], w_line)
    track('TXP_DRV', [(14.6, 11.43), (14.77, 11.6), pp('R5', '1')], w_line)
    track('TXN_DRV', [r2b, (10.4, 13.0), (10.4, 14.4), (10.8, 14.8), (14.6, 14.8), (14.6, 13.75), (14.85, 13.5), pp('L1', '3')], w_line)
    track('TXN_DRV', [pp('R4', '1'), (pp('R4', '1')[0], 14.8)], w_line)
    track('TXN_DRV', [pp('C2', '1'), (pp('C2', '1')[0], 14.8)], w_line)
    track('TXN_DRV', [(14.6, 14.8), (14.8, 14.6), pp('R6', '1')], w_line)
    track('GND', [pp('R3', '2'), (11.6, 13.0), (12.15, 13.4)], 0.25)
    track('GND', [pp('C1', '2'), (12.7, 13.0), (12.15, 13.4)], 0.25)
    via('GND', (12.15, 13.45))
    track('GND', [pp('R4', '2'), (11.6, 16.2), (12.15, 16.6)], 0.25)
    track('GND', [pp('C2', '2'), (12.7, 16.2), (12.15, 16.6)], 0.25)
    via('GND', (12.15, 16.65))
    l2, l4 = pp('L1', '2'), pp('L1', '4')
    track('TXP_C', [l2, (17.2, 12.7), (17.5, 12.4), (17.5, 11.6), pp('C3', '1')], w_line)
    track('TXP_C', [pp('R5', '2'), (17.5, 11.6)], w_line)
    track('TXN_C', [l4, (17.2, 13.5), (17.5, 13.8), (17.5, 14.6), pp('C4', '1')], w_line)
    track('TXN_C', [pp('R6', '2'), (17.5, 14.6)], w_line)
    # TD: down to the bottom strip, east, up to the TVS lower pads
    track('TD_P', [pp('C3', '2'), (21.6, 11.6), (21.6, 16.6), (27.8, 16.6), (27.8, 12.15), (30.05, 9.9), pp('U1', '4')], w_line)
    track('TD_N', [pp('C4', '2'), (20.6, 14.6), (20.6, 17.6), (28.6, 17.6), (28.6, 12.05), (30.25, 10.4), pp('U1', '5')], w_line)

    # ---------------- GND vias next to the remaining GND pads ----------------
    gvias = {'C10': (0, 0.95), 'C11': (0, 0.95), 'C12': (0.7, 0), 'C13': (0.7, 0), 'R14': (0.8, 0),
             'C14': (0, 0.95), 'C15': (0, -0.95), 'C16': (0, 0.95), 'C17': (-1.3, 0)}
    # +3V3 to the VB divider: one short bottom-layer hop under the TX/TD lines
    track('+3V3', [pp('C16', '1'), (pp('C16', '1')[0], 16.3), (17.8, 16.3)], 0.25)
    via('+3V3', (17.8, 16.3))
    track('+3V3', [(17.8, 16.3), (21.75, 10.3)], 0.25, B)
    via('+3V3', (21.75, 10.3))
    track('+3V3', [(21.75, 10.3), pp('R13', '1')], 0.25)
    # VB to R9 (A_P bias): bottom hop under the B pair
    track('VB', [pp('R9', '2'), (13.3, 5.08)], 0.2)
    via('VB', (13.3, 5.08))
    track('VB', [(13.3, 5.08), (13.3, 6.9), (15.3, 8.9)], 0.2, B)
    via('VB', (15.3, 8.9))
    track('VB', [(15.3, 8.9), pp('R16', '2')], 0.2)
    # 1M line-side bleeders
    track('TD_P', [pp('R23', '1'), (23.5, 16.6)], 0.2)
    track('GND', [pp('R23', '2'), (23.5, 14.3)], 0.25)
    via('GND', (23.5, 14.3))
    track('TD_N', [pp('R24', '1'), (pp('R24', '1')[0], 17.6)], 0.2)
    track('GND', [pp('R24', '2'), (25.9, 18.5)], 0.25)
    via('GND', (25.9, 18.5))
    track('RD_P', [pp('R25', '1'), (27.5, 4.15)], 0.2)
    track('GND', [pp('R25', '2'), (27.5, 1.8)], 0.25)
    via('GND', (27.5, 1.8))
    track('RD_N', [pp('R26', '1'), (pp('R26', '1')[0], 8.9)], 0.2)
    track('GND', [pp('R26', '2'), (29.2, 9.75)], 0.25)
    # Bob Smith midpoint: R19-R22 pin 2 + C17 pin 1
    track('BS_MID', [pp('R19', '2'), pp('R21', '2')], 0.2)
    track('BS_MID', [pp('R20', '2'), pp('R22', '2')], 0.2)
    track('BS_MID', [(29.9, 13.5), (31.0, 13.5)], 0.2)
    track('BS_MID', [(30.45, 13.5), pp('C17', '1')], 0.15)
    # PWM from the header to the RC filters
    track('PWM_A', [pp('J1', '3'), pp('R15', '1')], w_line)
    track('PWM_B', [pp('J1', '9'), (4.04, 10.16), pp('R17', '1')], w_line)
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

    # Pmod pin-1 marker and signal names (west of the RX/TX lines, east of the header)
    text('1', 8.1, 0.75, 0.8)
    seg((7.7, 1.25), (8.5, 1.25), pcbnew.F_SilkS, 0.15)
    text('A', 8.6, 3.2, 0.8)
    text('B', 8.6, 5.75, 0.8)
    text('TX', 8.5, 13.55, 0.8)
    text('100BASE-TX direct', 18.3, 19.65, 0.8)
    # back side: full pinout and notes
    text('Pmod 100BASE-TX PHY Rev.A', 22.0, 2.0, 0.9, 0, pcbnew.B_SilkS)
    text('1/7 A  2/8 B  3/9 PWM_A/B  4/10 TX_P/N', 24.0, 4.0, 0.8, 0, pcbnew.B_SilkS)
    text('Peer must have magnetics. TVS: TPD4E02B04', 24.0, 15.6, 0.8, 0, pcbnew.B_SilkS)
    text('L1 DNP (R5/R6 0R)  Bob Smith opt.', 24.0, 17.4, 0.8, 0, pcbnew.B_SilkS)
    text('RJ45 (no magnetics): TD 1/2  RD 3/6', 22.0, 6.0, 0.8, 0, pcbnew.B_SilkS)
    text('NOT PoE TOLERANT -', 22.0, 8.6, 1.0, 0, pcbnew.B_SilkS)
    text('do not connect to passive PoE', 22.0, 10.2, 1.0, 0, pcbnew.B_SilkS)

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

    # keep autorouted traces from sneaking between the pads of the line-side caps C3/C4
    ka = pcbnew.ZONE(board)
    ka.SetIsRuleArea(True)
    ka.SetLayer(F)
    ka.SetDoNotAllowTracks(True)
    ka.SetDoNotAllowVias(True)
    ka.SetDoNotAllowPads(False)
    ka.SetDoNotAllowFootprints(False)
    ka.SetDoNotAllowZoneFills(False)
    ka.SetZoneName('no_track_under_C3_C4')
    ol = ka.Outline()
    ol.NewOutline()
    for (x, y) in ((18.6, 11.0), (19.4, 11.0), (19.4, 15.2), (18.6, 15.2)):
        ol.Append(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))
    board.Add(ka)

    out = os.path.join(PRJ, NAME + '.kicad_pcb')
    board.Save(out)
    # stock footprint points at a non-existent RJHSE5380 model; the RJHSE538X body is identical
    txt = open(out).read().replace('RJ45_Amphenol_RJHSE5380.step', 'RJ45_Amphenol_RJHSE538X.step')
    open(out, 'w').write(txt)
    print('saved', out)


if __name__ == '__main__':
    main()
