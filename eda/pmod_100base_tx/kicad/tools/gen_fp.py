#!/usr/bin/env python3
"""Generate the project-local footprints into lib/pmod_100base_tx.pretty.

* Pmod_Peripheral_2x06_P2.54mm_Horizontal
    Male right-angle 2x6 plug for the peripheral side.  Derived from the stock
    PinHeader_2x06_P2.54mm_Horizontal, mirrored (pins point to -X) and renumbered to the
    Pmod Top/Bottom scheme: 1-6 = far (upper) row at X=0, 7-12 = near (lower) row at X=-2.54,
    pin 1 at the top.  Mates with the host footprint
    modretro_chromatic/.../Pmod_Host_2x06_P2.54mm_Horizontal (1-6 away from the edge, pin 1 top
    when the socket opens to +X).  Board edge = X -6.58 (front face of the plastic body).
* L_CommonModeChoke_2012Metric_FlowThrough
    0805/2012 4-terminal CMC (TDK ACM2012 / Murata DLW21 class) with pads renumbered so that the
    windings are 1->2 (top) and 3->4 (bottom), matching the Device:Filter_EMI_CommonMode symbol.
"""
import copy
import os

from sexp import Sym, dump, find, find1, parse

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'lib', 'pmod_100base_tx.pretty')
FP = '/usr/share/kicad/footprints/'

COORD_KEYS = ('at', 'start', 'end', 'center', 'mid', 'xy')


def mirror_x(x):
    if not isinstance(x, list):
        return
    if x and x[0] in COORD_KEYS and len(x) >= 3:
        x[1] = -float(x[1])
        if x[0] == 'at' and len(x) >= 4:
            x[3] = 0.0
    for e in x:
        if isinstance(e, list) and not (e and e[0] == 'model'):
            mirror_x(e)


def set_prop(fp, key, val):
    for p in find(fp, 'property'):
        if p[1] == key:
            p[2] = val


def pmod_peripheral():
    fp = parse(open(FP + 'Connector_PinHeader_2.54mm.pretty/PinHeader_2x06_P2.54mm_Horizontal.kicad_mod').read())[0]
    fp[1] = 'Pmod_Peripheral_2x06_P2.54mm_Horizontal'
    mirror_x(fp)
    for e in fp:
        if isinstance(e, list) and e[0] == 'pad':
            n = int(e[1])
            k = (n + 1) // 2
            e[1] = str(k if n % 2 else 6 + k)
            e[2] = Sym('thru_hole')
            e[3] = Sym('rect' if e[1] == '1' else 'oval')
        if isinstance(e, list) and e[0] == 'descr':
            e[1] = ('Pmod peripheral plug: 2x06 2.54 mm right-angle male header at the board edge, '
                    'Top/Bottom numbering (1-6 far/upper row, 7-12 near/lower row, 5/11 GND, 6/12 VCC), '
                    'pins point to -X, pin 1 at the top. Board edge (body front face) at X=-6.58 (Dwgs.User). '
                    'Mirror of the stock PinHeader_2x06_P2.54mm_Horizontal.')
        if isinstance(e, list) and e[0] == 'tags':
            e[1] = 'pmod peripheral plug right angle 2x06'
        if isinstance(e, list) and e[0] == 'model':
            find1(e, 'rotate')[1][1:] = [0, 0, 180]
            find1(e, 'offset')[1][1:] = [0, -12.7, 0]
    # drop silk that would sit beyond the board edge (pins/body outline outside the PCB)
    def xs(e):
        return [float(c[1]) for c in e if isinstance(c, list) and c and c[0] in ('start', 'end', 'xy')] + \
            [float(c[1]) for q in e if isinstance(q, list) and q and q[0] == 'pts' for c in q if isinstance(c, list)]
    fp[:] = [e for e in fp if not (isinstance(e, list) and e[0] in ('fp_line', 'fp_rect', 'fp_poly')
                                    and find1(e, 'layer') and find1(e, 'layer')[1] == 'F.SilkS'
                                    and min(xs(e) or [0]) < -6.3)]
    set_prop(fp, 'Value', 'Pmod_Peripheral_2x06_P2.54mm_Horizontal')
    for p in find(fp, 'property'):
        if p[1] in ('Reference', 'Value'):
            at = find1(p, 'at')
            at[1:] = [-3.81, -2.6 if p[1] == 'Reference' else 15.3, 0]
    # board-edge reference line + pin-1 label on silk
    idx = max(i for i, e in enumerate(fp) if isinstance(e, list) and e[0].startswith('fp_'))
    edge = [Sym('fp_line'), [Sym('start'), -6.58, -2.0], [Sym('end'), -6.58, 14.7],
            [Sym('stroke'), [Sym('width'), 0.1], [Sym('type'), Sym('dash')]],
            [Sym('layer'), 'Dwgs.User'], [Sym('uuid'), 'a1b2c3d4-0000-4000-8000-00000000e001']]
    fp.insert(idx + 1, edge)
    return fp


def cmc():
    fp = parse(open(FP + 'Inductor_SMD.pretty/L_CommonModeChoke_Coilank_ACM2012.kicad_mod').read())[0]
    fp[1] = 'L_CommonModeChoke_2012Metric_FlowThrough'
    ren = {'1': '1', '2': '3', '3': '4', '4': '2'}
    for e in fp:
        if isinstance(e, list) and e[0] == 'pad':
            e[1] = ren[e[1]]
        if isinstance(e, list) and e[0] == 'descr':
            e[1] = ('0805 (2.0x1.2 mm) 4-terminal common-mode choke, flow-through: winding 1->2 (top row), '
                    '3->4 (bottom row), pin 1 = dot. Pad geometry from Coilank ACM2012 (TDK ACM2012 compatible). '
                    'Check the winding/pad mapping against the chosen part datasheet.')
        if isinstance(e, list) and e[0] == 'model':
            pass
    set_prop(fp, 'Value', 'L_CommonModeChoke_2012Metric_FlowThrough')
    return fp


def main():
    os.makedirs(OUT, exist_ok=True)
    for fp in (pmod_peripheral(), cmc()):
        open(os.path.join(OUT, fp[1] + '.kicad_mod'), 'w').write(dump(fp) + '\n')


if __name__ == '__main__':
    main()
