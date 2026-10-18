#!/usr/bin/env python3
"""Generate lib/pmod_100base_tx.kicad_sym and pmod_100base_tx.kicad_sch from design.py.

Every pin gets a short wire stub ending in a net label (or a power symbol for GND/+3V3),
so the schematic is net-label style; blocks are annotated with text.
"""
import copy
import math
import os
import uuid

from sexp import Sym, dump, find, find1, get_symbol, load_lib
from design import PARTS

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'pmod_100base_tx'
KSYM = '/usr/share/kicad/symbols/'
NS = uuid.UUID('6f1b8a8e-1d1c-4a39-9a5e-100b45e7a000')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(str(x) for x in k)))


ROOT_UUID = uid('root')

# ---------------------------------------------------------------- symbol library
LOCAL = [  # (stock lib, stock name)
    ('Connector_Generic', 'Conn_02x06_Top_Bottom'),
    ('Device', 'Filter_EMI_CommonMode'),
    ('Connector', 'RJ45_Shielded'),
    ('Power_Protection', 'TPD4E02B04DQA'),
]


def flatten(lib, name):
    """Resolve (extends ...) into a standalone symbol."""
    s = copy.deepcopy(get_symbol(lib, name))
    ext = find1(s, 'extends')
    if not ext:
        return s
    parent = flatten(lib, ext[1])
    out = [Sym('symbol'), name]
    child_props = {p[1]: p for p in find(s, 'property')}
    for e in parent[2:]:
        if isinstance(e, list) and e[0] == 'property':
            out.append(child_props.pop(e[1], e))
        elif isinstance(e, list) and e[0] == 'symbol':
            e = copy.deepcopy(e)
            e[1] = e[1].replace(ext[1], name, 1)
            out.append(e)
        elif isinstance(e, list) and e[0] == 'embedded_fonts':
            continue
        else:
            out.append(e)
    # insert remaining child-only properties after the last property
    idx = max(i for i, e in enumerate(out) if isinstance(e, list) and e[0] == 'property') + 1
    for p in child_props.values():
        out.insert(idx, p)
        idx += 1
    out.append([Sym('embedded_fonts'), Sym('no')])
    return out


def set_prop(sym, key, val):
    for p in find(sym, 'property'):
        if p[1] == key:
            p[2] = val
            return


def build_local_lib():
    syms = []
    for lib, name in LOCAL:
        s = flatten(load_lib(KSYM + lib + '.kicad_sym'), name)
        if name == 'Filter_EMI_CommonMode':
            set_prop(s, 'Footprint', 'pmod_100base_tx:L_CommonModeChoke_2012Metric_FlowThrough')
        if name == 'Conn_02x06_Top_Bottom':
            set_prop(s, 'Footprint', 'pmod_100base_tx:Pmod_Peripheral_2x06_P2.54mm_Horizontal')
        if name == 'RJ45_Shielded':
            set_prop(s, 'Footprint', 'Connector_RJ:RJ45_Amphenol_RJHSE5380')
        syms.append(s)
    lib = [Sym('kicad_symbol_lib'), [Sym('version'), Sym('20251024')],
           [Sym('generator'), 'kicad_symbol_editor'], [Sym('generator_version'), '10.0']] + syms
    open(os.path.join(PRJ, 'lib', NAME + '.kicad_sym'), 'w').write(dump(lib) + '\n')
    return {name: s for (_, name), s in zip(LOCAL, syms)}


# ---------------------------------------------------------------- helpers
def libsym(lib_id, local):
    lib, name = lib_id.split(':')
    if lib == NAME:
        s = copy.deepcopy(local[name])
    else:
        s = flatten(load_lib(KSYM + lib + '.kicad_sym'), name)
    s[1] = lib_id
    return s


def pins_of(sym):
    out = {}

    def rec(x):
        for e in x:
            if isinstance(e, list):
                if e[0] == 'pin':
                    at = find1(e, 'at')
                    out.setdefault(find1(e, 'number')[1], []).append(
                        (float(at[1]), float(at[2]), float(at[3])))
                else:
                    rec(e)
    rec(sym)
    return out


def xf(px, py, x, y, rot):
    a = math.radians(rot)
    rx = px * math.cos(a) - py * math.sin(a)
    ry = px * math.sin(a) + py * math.cos(a)
    return (round(x + rx, 3), round(y - ry, 3))


def font(size=1.27, **kw):
    f = [Sym('font'), [Sym('size'), size, size]]
    if kw.get('bold'):
        f.append([Sym('bold'), Sym('yes')])
    e = [Sym('effects'), f]
    if kw.get('justify'):
        e.append([Sym('justify')] + [Sym(j) for j in kw['justify'].split()])
    if kw.get('hide'):
        e.append([Sym('hide'), Sym('yes')])
    return e


def prop(k, v, x, y, rot=0, hide=False, justify=None):
    p = [Sym('property'), k, v, [Sym('at'), x, y, rot]]
    if hide:
        p.append([Sym('hide'), Sym('yes')])
    p += [[Sym('show_name'), Sym('no')], [Sym('do_not_autoplace'), Sym('no')],
          font(justify=justify)]
    return p


items = []


def wire(a, b):
    items.append([Sym('wire'), [Sym('pts'), [Sym('xy'), a[0], a[1]], [Sym('xy'), b[0], b[1]]],
                  [Sym('stroke'), [Sym('width'), 0], [Sym('type'), Sym('default')]],
                  [Sym('uuid'), uid('w', a, b)]])


def label(name, p, ang):
    just = {0: 'left bottom', 90: 'left bottom', 180: 'right bottom', 270: 'right bottom'}[ang]
    items.append([Sym('label'), name, [Sym('at'), p[0], p[1], ang], font(justify=just),
                  [Sym('uuid'), uid('l', name, p)]])


def text(s, x, y, size=1.27, bold=False):
    items.append([Sym('text'), s, [Sym('exclude_from_sim'), Sym('no')], [Sym('at'), x, y, 0],
                  font(size, bold=bold, justify='left bottom'), [Sym('uuid'), uid('t', s, x, y)]])


pwr_n = [0]


def symbol_inst(lib_id, ref, value, x, y, rot, pins, props=(), dnp=False, in_bom=True,
                on_board=True, ref_hidden=False, val_hidden=False, ref_at=None, val_at=None,
                just='left', libdef=None):
    s = [Sym('symbol'), [Sym('lib_id'), lib_id], [Sym('at'), x, y, rot], [Sym('unit'), 1],
         [Sym('body_style'), 1], [Sym('exclude_from_sim'), Sym('no')],
         [Sym('in_bom'), Sym('yes' if in_bom else 'no')],
         [Sym('on_board'), Sym('yes' if on_board else 'no')],
         [Sym('in_pos_files'), Sym('yes' if on_board else 'no')],
         [Sym('dnp'), Sym('yes' if dnp else 'no')],
         [Sym('uuid'), uid('sym', ref)]]
    fa = (-rot) % 360
    if libdef is not None and ref_at is None:
        for pp in find(libdef, 'property'):
            at = find1(pp, 'at')
            j = find1(find1(pp, 'effects') or [], 'justify')
            jj = ' '.join(str(t) for t in j[1:]) if j else None
            if pp[1] == 'Reference':
                ref_at = xf(float(at[1]), float(at[2]), x, y, rot) + (jj,)
            if pp[1] == 'Value':
                val_at = xf(float(at[1]), float(at[2]), x, y, rot) + (jj,)
    ra = ref_at or (x + 2.54, y - 1.27)
    va = val_at or (x + 2.54, y + 1.27)
    s.append(prop('Reference', ref, ra[0], ra[1], fa, ref_hidden, ra[2] if len(ra) > 2 else just))
    s.append(prop('Value', value, va[0], va[1], fa, val_hidden, va[2] if len(va) > 2 else just))
    for k, v in props:
        s.append(prop(k, v, x, y, 0, True))
    for n in pins:
        s.append([Sym('pin'), n, [Sym('uuid'), uid('pin', ref, n)]])
    s.append([Sym('instances'), [Sym('project'), NAME,
              [Sym('path'), '/' + ROOT_UUID, [Sym('reference'), ref], [Sym('unit'), 1]]]])
    items.append(s)


def power(net, p, out=None):
    """out: stub direction (math degrees, y up); the symbol points the same way."""
    pwr_n[0] += 1
    ref = '#PWR%02d' % pwr_n[0]
    lib = 'power:GND' if net == 'GND' else 'power:+3V3'
    if out is None:
        out = 270 if net == 'GND' else 90
    rot = int((out - (270 if net == 'GND' else 90)) % 360)
    d = (round(math.cos(math.radians(out))), -round(math.sin(math.radians(out))))
    off = 4.6 if d[1] else 2.8
    va = (round(p[0] + d[0] * off, 2), round(p[1] + d[1] * off, 2),
          'left' if d[0] > 0 else 'right' if d[0] < 0 else None)
    symbol_inst(lib, ref, net, p[0], p[1], rot, ['1'], in_bom=False, on_board=False,
                ref_hidden=True, ref_at=(p[0], p[1]), val_at=va)
    syms_used.add(lib)


syms_used = set()


def main():
    local = build_local_lib()
    defs = {}
    for p in PARTS:
        syms_used.add(p['sym'])
    for p in PARTS:
        lib_id = p['sym']
        if lib_id not in defs:
            defs[lib_id] = libsym(lib_id, local)
        sym = defs[lib_id]
        x, y, rot = p['sch']
        pmap = pins_of(sym)
        two = len(pmap) == 2
        props = [('Footprint', p['fp']), ('Datasheet', ''), ('Description', p['desc']),
                 ('MPN', p['mpn']), ('Manufacturer', p['mfr'])]
        if two and rot == 90:
            ra, va = (x, y - 2.54, None), (x, y + 3.81, None)
        elif two:
            ra, va = (x + 2.54, y - 0.635), (x + 2.54, y + 1.905)
        else:
            ra = va = None
        symbol_inst(lib_id, p['ref'], p['value'], x, y, rot, list(pmap), props, dnp=p['dnp'],
                    ref_at=ra, val_at=va, libdef=sym)
        if not two:
            if ra is None:
                # put ref/value above the body
                pass
        done = set()
        for num, plist in pmap.items():
            net = p['pins'].get(num)
            if net is None:
                raise SystemExit('unassigned pin %s.%s' % (p['ref'], num))
            for (px, py, pa) in plist:
                end = xf(px, py, x, y, rot)
                if end in done:
                    continue
                done.add(end)
                out = (pa + 180 + rot) % 360
                L = 2.54
                d = (round(math.cos(math.radians(out)), 3), round(-math.sin(math.radians(out)), 3))
                tip = (round(end[0] + d[0] * L, 3), round(end[1] + d[1] * L, 3))
                wire(end, tip)
                if net in ('GND', '+3V3'):
                    if net == 'GND' and d[1] < 0:      # stub points up: extend sideways not needed
                        pass
                    power(net, tip, out)
                else:
                    ang = {(1, 0): 0, (-1, 0): 180, (0, -1): 90, (0, 1): 270}[(round(d[0]), round(d[1]))]
                    label(net, tip, ang)
    # power flags
    for net, pos in (('GND', (25.4, 109.22)), ('+3V3', (35.56, 109.22))):
        pwr_n[0] += 1
        symbol_inst('power:PWR_FLAG', '#FLG%02d' % pwr_n[0], 'PWR_FLAG', pos[0], pos[1], 0, ['1'],
                    in_bom=False, on_board=False, ref_hidden=True)
        syms_used.add('power:PWR_FLAG')
        power(net, pos)

    # annotations
    text('Pmod 100BASE-TX direct-attach PHY front end (transformerless) - see ../README.md', 25.4, 22.86, 2.0, True)
    text('Pmod J1: plugs into Tang Primer 25K pmod0 (3.3 V bank). 1-4 top row = P, 7-10 bottom row = N.\n'
         'A: 1/7 (F5/G5)  B: 2/8 (G7/G8)  PWM_A/B: 3/9 (H8/H7)  TX_P/N: 4/10 (H5/J5)  - verify by ball name.',
         25.4, 30.48)
    text('TX: LVCMOS33 x2 -> Rs 62R / Rp 120R (Thevenin 2V/50R each side) -> Cr 47pF -> [L1 CMC | R5/R6 0R]\n'
         '-> 0.1uF/100V series -> RJ45 1/2. Tune Rs for 0.95-1.05 V diff, Cr for 3-5 ns rise.', 25.4, 127.0)
    text('RX: RJ45 3/6 -> 2x49.9R termination, midpoint Ct to GND.\n'
         'Tap caps Ca 0.1uF/100V make 4 DC-isolated comparator inputs.\n'
         'A = (v > VTH_A-VB), B = (v > -(VTH_B-VB)), c = A^B = NRZI.', 152.4, 30.48)
    text('Bias: VB = 1.32 V. VTH = VB + (D*3.3-VB)*1k/4.3k  (-0.31 .. +0.46 V vs VB)', 152.4, 142.24)
    text('U1: flow-through ESD array, NC pads 10/9/7/6 carry the same line as IO 1/2/4/5.\n'
         'Line side caps rated 100 V. Bob Smith R19-R22/C17 optional.', 256.54, 30.48)
    text('3.3 V decoupling at J1', 25.4, 101.6)
    text('1M bleeders R23-R26: DC reference for the capacitor-coupled line nodes (cable discharge).\n'
         'NOT PoE TOLERANT - do not connect to passive PoE (line-side TVS clamps at ~4 V).', 121.92, 187.96)

    lib_symbols = [Sym('lib_symbols')]
    for lib_id in sorted(syms_used):
        lib_symbols.append(defs.get(lib_id) or libsym(lib_id, local))

    sch = [Sym('kicad_sch'), [Sym('version'), Sym('20260306')], [Sym('generator'), 'eeschema'],
           [Sym('generator_version'), '10.0'], [Sym('uuid'), ROOT_UUID], [Sym('paper'), 'A3'],
           [Sym('title_block'), [Sym('title'), 'Pmod 100BASE-TX direct-attach PHY'],
            [Sym('date'), '2026-10-10'], [Sym('rev'), 'Rev.A'], [Sym('company'), 'Kenta IDA'],
            [Sym('comment'), 1, 'Transformerless (capacitor coupled) 100BASE-TX front end for Tang Primer 25K'],
            [Sym('comment'), 2, 'Peer must have magnetics (normal switch / NIC). Not for board-to-board direct use.']],
           lib_symbols] + items + [
        [Sym('sheet_instances'), [Sym('path'), '/', [Sym('page'), '1']]],
        [Sym('embedded_fonts'), Sym('no')]]
    open(os.path.join(PRJ, NAME + '.kicad_sch'), 'w').write(dump(sch) + '\n')


if __name__ == '__main__':
    main()
