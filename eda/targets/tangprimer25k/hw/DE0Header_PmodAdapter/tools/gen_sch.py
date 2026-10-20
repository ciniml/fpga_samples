#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate DE0Header_PmodAdapter.kicad_sch.

Tang Primer 25K Dock 40-pin header (J3 on the Dock, DE0 compatible; the
adapter's J1 is the mating 2x20 socket) -> four Pmod host sockets + two
small extra headers, 5 V -> 3.3 V LDO for the Pmods (the header has no
3.3 V pin). The pin map is tools/pinmap.py.
"""
import os
import uuid
import sexp
from sexp import q
import pinmap as pm

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'DE0Header_PmodAdapter'
SYMDIR = '/usr/share/kicad/symbols'
NS = uuid.UUID('1d2f8e44-6a0b-4f61-8c3e-2b7a9d5e0c31')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(map(str, k))))


ROOT = uid('root')


def libsym(lib, name):
    """library symbol as embedded in a schematic; a derived symbol (extends) is flattened:
    the parent's graphics / pins with the child's properties"""
    s = list(sexp.lib_symbol(f'{SYMDIR}/{lib}.kicad_sym', name))
    ext = sexp.find(s, 'extends')
    if ext:
        parent = list(sexp.lib_symbol(f'{SYMDIR}/{lib}.kicad_sym', ext[1].strip('"')))
        pname = ext[1].strip('"')
        props = sexp.find_all(s, 'property')
        flat = [parent[0], parent[1]]
        for e in parent[2:]:
            if isinstance(e, list) and e and e[0] == 'property':
                continue
            if isinstance(e, list) and e and e[0] == 'symbol':
                e = [e[0], e[1].replace(pname, name)] + e[2:]
            flat.append(e)
        # properties first (after the head items that are not sub-symbols)
        head = [e for e in flat[2:] if not (isinstance(e, list) and e and e[0] == 'symbol')]
        subs = [e for e in flat[2:] if isinstance(e, list) and e and e[0] == 'symbol']
        s = [flat[0], flat[1]] + head + props + subs
    s[1] = q(f'{lib}:{name}')
    return s


def pin_table(sym):
    out = {}
    for sub in sexp.find_all(sym, 'symbol'):
        for p in sexp.find_all(sub, 'pin'):
            at = sexp.find(p, 'at')
            out[sexp.find(p, 'number')[1].strip('"')] = (float(at[1]), float(at[2]), int(float(at[3])))
    return out


items = []
lib = {}
counters = {'#PWR': 0, '#FLG': 0}


def prop(name, val, x, y, hide=False, angle=0):
    h = ' (hide yes)' if hide else ''
    return f'(property {q(name)} {q(val)} (at {x:.2f} {y:.2f} {angle}) (effects (font (size 1.27 1.27)){h}))'


def place(lib_id, ref, value, x, y, footprint='', ref_xy=None, val_xy=None, desc='', extra=None, rot=0):
    sym = lib[lib_id]
    pins = pin_table(sym)
    rx, ry = ref_xy if ref_xy else (x, y - 2.54)
    vx, vy = val_xy if val_xy else (x, y + 2.54)
    power = ref.startswith('#')
    props = [prop('Reference', ref, rx, ry, hide=power), prop('Value', value, vx, vy),
             prop('Footprint', footprint, x, y, hide=True), prop('Datasheet', '~', x, y, hide=True),
             prop('Description', desc, x, y, hide=True)]
    for k, v in (extra or {}).items():
        props.append(prop(k, v, x, y, hide=True))
    pin_s = ' '.join(f'(pin {q(n)} (uuid {uid(ref, "pin", n)}))' for n in pins)
    txt = (f'(symbol (lib_id {q(lib_id)}) (at {x:.2f} {y:.2f} {rot}) (unit 1) (exclude_from_sim no) '
           f'(in_bom {"no" if power else "yes"}) (on_board {"no" if power else "yes"}) (dnp no) (uuid {uid(ref)}) '
           + ' '.join(props) + ' ' + pin_s +
           f' (instances (project {q(NAME)} (path {q("/" + ROOT)} (reference {q(ref)}) (unit 1)))))')
    items.append(sexp.parse(txt)[0])
    return {n: (x + px, y - py, a) for n, (px, py, a) in pins.items()}


def wire(x1, y1, x2, y2):
    items.append(sexp.parse(f'(wire (pts (xy {x1:.2f} {y1:.2f}) (xy {x2:.2f} {y2:.2f})) '
                            f'(stroke (width 0) (type default)) (uuid {uid("w", x1, y1, x2, y2)}))')[0])


def label(name, x, y, angle):
    just = 'left bottom' if angle in (0, 90) else 'right bottom'
    items.append(sexp.parse(f'(label {q(name)} (at {x:.2f} {y:.2f} {angle}) '
                            f'(effects (font (size 1.27 1.27)) (justify {just})) (uuid {uid("l", name, x, y)}))')[0])


def power(net, x, y):
    lid = {'GND': 'power:GND', '+3V3': 'power:+3V3', '+5V': 'power:+5V'}[net]
    counters['#PWR'] += 1
    ref = f'#PWR{counters["#PWR"]:02d}'
    place(lid, ref, net, x, y, val_xy=(x, y + 5.08 if net == 'GND' else y - 5.08))


def flag(x, y, rot=0):
    counters['#FLG'] += 1
    ref = f'#FLG{counters["#FLG"]:02d}'
    place('power:PWR_FLAG', ref, 'PWR_FLAG', x, y, rot=rot, val_xy=(x, y - 3.81 if rot == 0 else y + 3.81))


OUT = {0: (-1, 0, 180), 180: (1, 0, 0), 90: (0, 1, 270), 270: (0, -1, 90)}


def connect(pins, num, net, stub=2.54):
    x, y, a = pins[str(num)]
    dx, dy, la = OUT[a]
    ex, ey = x + dx * stub, y + dy * stub
    wire(x, y, ex, ey)
    label(net, ex, ey, la)


def tie(net, x, y):
    """a label of a power net wired to its power symbol"""
    if net == 'GND':
        wire(x, y, x, y + 2.54)
        label(net, x, y, 90)
        power(net, x, y + 2.54)
    else:
        wire(x, y, x, y - 2.54)
        label(net, x, y, 270)
        power(net, x, y - 2.54)


def text(s, x, y, size=1.27):
    items.append(sexp.parse(f'(text {q(s)} (exclude_from_sim no) (at {x:.2f} {y:.2f} 0) '
                            f'(effects (font (size {size} {size})) (justify left)) (uuid {uid("t", s)}))')[0])


PARTS = {
    'J1': dict(value='2x20 female 2.54 (to Dock J3)', fp='Connector_PinSocket_2.54mm:PinSocket_2x20_P2.54mm_Vertical',
               desc='2x20 2.54 mm female socket, 8.5 mm, mounted on the bottom side', mpn='BOOMELE 2.54-2*20P', lcsc='C5124634'),
    'PMOD': dict(value='Pmod host', fp='Connector_PinSocket_2.54mm:PinSocket_2x06_P2.54mm_Horizontal',
                 desc='Pmod host: 2x6 2.54 mm right-angle female socket', mpn='Hong Cheng HC-PM254-8.5H-2x6PW', lcsc='C22373932'),
    'J6': dict(value='EXT1 2x2', fp='Connector_PinHeader_2.54mm:PinHeader_2x02_P2.54mm_Vertical',
               desc='2x2 2.54 mm pin header', mpn='BOOMELE 2.54-2*2PPin', lcsc='C66690'),
    'J7': dict(value='EXT2 2x3', fp='Connector_PinHeader_2.54mm:PinHeader_2x03_P2.54mm_Vertical',
               desc='2x3 2.54 mm pin header', mpn='BOOMELE 2.54-2*3PPin', lcsc='C65114'),
    'U1': dict(value='AMS1117-3.3', fp='Package_TO_SOT_SMD:SOT-223-3_TabPin2',
               desc='3.3 V 1 A LDO (5 V from the header pin 11)', mpn='AMS AMS1117-3.3', lcsc='C6186'),
    'C1': dict(value='10u', fp='Capacitor_SMD:C_0805_2012Metric', desc='10 uF 25 V X5R 0805 (LDO input)',
               mpn='Samsung CL21A106KAYNNNE', lcsc='C15850'),
    'C2': dict(value='22u', fp='Capacitor_SMD:C_0805_2012Metric', desc='22 uF 25 V X5R 0805 (LDO output)',
               mpn='Samsung CL21A226MAQNNNE', lcsc='C45783'),
    'CDEC': dict(value='100n', fp='Capacitor_SMD:C_0402_1005Metric', desc='100 nF 16 V X7R 0402 (Pmod 3.3 V)',
                 mpn='Samsung CL05B104KO5NNNC', lcsc='C1525'),
}


def part(ref, key, lid, x, y, **kw):
    p = PARTS[key]
    return place(lid, ref, p['value'], x, y, footprint=p['fp'], desc=p['desc'],
                 extra={'MPN': p['mpn'], 'LCSC': p['lcsc']}, **kw)


def build():
    for lid in ('Connector_Generic:Conn_02x20_Odd_Even', 'Connector_Generic:Conn_02x06_Odd_Even',
                'Connector_Generic:Conn_02x02_Odd_Even', 'Connector_Generic:Conn_02x03_Odd_Even',
                'Regulator_Linear:AMS1117-3.3', 'Device:C', 'power:GND', 'power:+3V3', 'power:+5V', 'power:PWR_FLAG'):
        lib[lid] = libsym(*lid.split(':'))

    # J1: the mating socket of the Dock's 40-pin header
    j1 = part('J1', 'J1', 'Connector_Generic:Conn_02x20_Odd_Even', 88.9, 101.6,
              ref_xy=(90.17, 74.93), val_xy=(90.17, 129.54))
    for pin, n in pm.header_nets().items():
        connect(j1, pin, n, stub=5.08)

    # Pmod sockets J2..J5 (Pmod A..D)
    for i, slot in enumerate(pm.PMODS):
        y = 50.8 + i * 38.1
        sp = part(f'J{2 + i}', 'PMOD', 'Connector_Generic:Conn_02x06_Odd_Even', 203.2, y,
                  ref_xy=(204.47, y - 10.16), val_xy=(204.47, y + 12.7))
        sp_val = f'PMOD {slot} ({pm.SLOT_NAME[slot]})'
        items[-1] = sexp.parse(sexp.dump(items[-1]).replace('"Pmod host"', q(sp_val), 1))[0]
        for pmod_pin, n in pm.pmod_nets(slot).items():
            connect(sp, pm.pmod_socket_pin(pmod_pin), n, stub=5.08)
        text(f'Pmod {slot}: socket pin = 13-2p (p = 1..6), 14-2(p-6) (p = 7..12)', 182.88, y + 17.78, 1.0)

    j6 = part('J6', 'J6', 'Connector_Generic:Conn_02x02_Odd_Even', 279.4, 50.8, ref_xy=(280.67, 45.72), val_xy=(280.67, 55.88))
    for pin, n in pm.EXT1.items():
        connect(j6, pin, n, stub=5.08)
    j7 = part('J7', 'J7', 'Connector_Generic:Conn_02x03_Odd_Even', 279.4, 76.2, ref_xy=(280.67, 68.58), val_xy=(280.67, 83.82))
    for pin, n in pm.EXT2.items():
        connect(j7, pin, n, stub=5.08)

    # 5 V -> 3.3 V
    u1 = part('U1', 'U1', 'Regulator_Linear:AMS1117-3.3', 279.4, 116.84, ref_xy=(279.4, 110.49), val_xy=(279.4, 123.19))
    connect(u1, 3, '+5V', stub=5.08)
    connect(u1, 2, '+3V3', stub=5.08)
    connect(u1, 1, 'GND', stub=2.54)
    c1 = part('C1', 'C1', 'Device:C', 259.08, 134.62, ref_xy=(261.62, 133.35), val_xy=(261.62, 135.89))
    connect(c1, 1, '+5V')
    connect(c1, 2, 'GND')
    c2 = part('C2', 'C2', 'Device:C', 299.72, 134.62, ref_xy=(302.26, 133.35), val_xy=(302.26, 135.89))
    connect(c2, 1, '+3V3')
    connect(c2, 2, 'GND')
    for i in range(4):
        x = 254.0 + i * 15.24
        c = part(f'C{3 + i}', 'CDEC', 'Device:C', x, 160.02, ref_xy=(x + 2.54, 158.75), val_xy=(x + 2.54, 161.29))
        connect(c, 1, '+3V3')
        connect(c, 2, 'GND')
    text('C3..C6: one per Pmod socket, next to its 3.3 V pins', 254.0, 172.72, 1.0)

    # power-net ties and flags
    tie('GND', 330.2, 50.8)
    tie('+3V3', 345.44, 50.8)
    tie('+5V', 360.68, 50.8)
    wire(330.2, 76.2, 330.2, 81.28)
    power('GND', 330.2, 81.28)
    flag(330.2, 76.2)
    wire(360.68, 76.2, 360.68, 71.12)
    power('+5V', 360.68, 71.12)
    flag(360.68, 76.2, rot=180)

    notes = [
        'Tang Primer 25K Dock 40-pin header (J3 on the Dock, DE0 compatible) -> 4 Pmod host sockets (pmod3..pmod6).',
        'Header pins 11 = +5V, 12 = GND; no 3.3 V pin: U1 makes the Pmods 3.3 V from +5V.',
        'Pins (2k-1, 2k) are GW5A true LVDS pairs (even = P, odd = N), except 17/18 (A1/E1) and 19/20 (D1/E3).',
        'Each pair lands on a Pmod column: P = Pmod pin n, N = pin n+6. LVDS_* nets are routed as 100 ohm pairs.',
        'Pmod B column 4 carries A1 / E1 (single-ended); EXT1 = D1, E3; EXT2 = F7/F6 and J11/J10 pairs.',
        'Bank 2 pairs (A, B1, C1) have no on-chip differential termination on GW5A (use external 100 ohm for LVDS inputs).',
    ]
    for i, s in enumerate(notes):
        text(s, 30.48, 190.5 + i * 3.81)


def write_sch():
    lib_s = '(lib_symbols ' + ' '.join(sexp.dump(s, 2) for s in lib.values()) + ')'
    body = '\n\t'.join(sexp.dump(it, 1) for it in items)
    txt = f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0")
\t(uuid {ROOT})
\t(paper "A3")
\t(title_block (title "Tang Primer 25K 40-pin header to Pmod adapter") (date "2026-10-20") (rev "A") (company "fpga_samples / eda/targets/tangprimer25k") (comment 1 "Kenta Ida (@ciniml)"))
\t{lib_s}
\t{body}
\t(sheet_instances (path "/" (page "1")))
\t(embedded_fonts no)
)
'''
    open(os.path.join(PRJ, NAME + '.kicad_sch'), 'w').write(txt)


if __name__ == '__main__':
    build()
    write_sch()
    print('wrote', NAME + '.kicad_sch')
