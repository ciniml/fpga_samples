#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_RPiCamera.kicad_sch (and Local/local.kicad_sym).

Pmod (12-pin, right angle) -> Raspberry Pi camera 15-pin 1.0 mm FFC,
2-lane MIPI CSI-2 straight through + I2C pull-ups + CAM_GPIO pull-up +
a polyfuse on the camera's 3.3 V. Netlist below (NETS / PARTS) is the
single source of truth; gen_pcb.py reads the schematic's netlist export.
"""
import os
import uuid
import sexp
from sexp import q

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'Pmod_RPiCamera'
SYMDIR = '/usr/share/kicad/symbols'
NS = uuid.UUID('6f1c2d1e-5a1b-4a0e-9d43-3c2b8f0e7a10')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(map(str, k))))


ROOT = uid('root')

# ---------------------------------------------------------------- symbols
FFC_PINS = ['GND', 'D0_N', 'D0_P', 'GND', 'D1_N', 'D1_P', 'GND', 'CLK_N', 'CLK_P', 'GND',
            'CAM_GPIO', 'CAM_CLK', 'SCL', 'SDA', '3V3']


def ffc_symbol(name):
    pins = []
    for i, pn in enumerate(FFC_PINS):
        y = 17.78 - 2.54 * i
        pins.append(f'(pin passive line (at -7.62 {y:.2f} 0) (length 5.08) '
                    f'(name {q(pn)} (effects (font (size 1.27 1.27)))) '
                    f'(number {q(i + 1)} (effects (font (size 1.27 1.27)))))')
    pins.append('(pin passive line (at 7.62 -25.4 90) (length 5.08) '
                '(name "MP" (effects (font (size 1.27 1.27)))) (number "MP" (effects (font (size 1.27 1.27)))))')
    txt = f'''(symbol {q(name)} (pin_names (offset 1.016)) (exclude_from_sim no) (in_bom yes) (on_board yes)
  (property "Reference" "J" (at 0 22.86 0) (effects (font (size 1.27 1.27))))
  (property "Value" "RPi_CSI_15" (at 2.54 -27.94 0) (effects (font (size 1.27 1.27))))
  (property "Footprint" "Connector_FFC-FPC:TE_1-84952-5_1x15-1MP_P1.0mm_Horizontal" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (property "Datasheet" "~" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (property "Description" "Raspberry Pi camera connector, 15-pin 1.0 mm FFC, 2-lane CSI-2" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (symbol "RPi_CSI_15_0_1"
    (rectangle (start -2.54 20.32) (end 10.16 -20.32) (stroke (width 0.254) (type default)) (fill (type background))))
  (symbol "RPi_CSI_15_1_1" {' '.join(pins)})
  (embedded_fonts no))'''
    return sexp.parse(txt)[0]


def libsym(lib, name):
    s = sexp.lib_symbol(f'{SYMDIR}/{lib}.kicad_sym', name)
    s = list(s)
    s[1] = q(f'{lib}:{name}')
    return s


def write_local_lib():
    s = ffc_symbol('RPi_CSI_15')
    txt = '(kicad_symbol_lib (version 20241209) (generator "gen_sch.py") (generator_version "1.0")\n\t' + \
        sexp.dump(s, 1) + '\n)\n'
    open(os.path.join(PRJ, 'Local', 'local.kicad_sym'), 'w').write(txt)


# ---------------------------------------------------------------- pins
def pin_table(sym):
    """number -> (x, y, angle) in symbol coordinates"""
    out = {}
    for sub in sexp.find_all(sym, 'symbol'):
        for p in sexp.find_all(sub, 'pin'):
            at = sexp.find(p, 'at')
            out[sexp.find(p, 'number')[1].strip('"')] = (float(at[1]), float(at[2]), int(float(at[3])))
    return out


# ---------------------------------------------------------------- content
items = []      # schematic items (wires, labels, symbols)
lib = {}        # lib_id -> symbol definition
counters = {'#PWR': 0, '#FLG': 0}


def add_lib(lib_id, sym):
    if lib_id not in lib:
        lib[lib_id] = sym


def prop(name, val, x, y, hide=False, angle=0):
    h = ' (hide yes)' if hide else ''
    return f'(property {q(name)} {q(val)} (at {x:.2f} {y:.2f} {angle}) (effects (font (size 1.27 1.27)){h}))'


def place(lib_id, ref, value, x, y, footprint='', rot=0, ref_xy=None, val_xy=None, desc='', extra=None):
    sym = lib[lib_id]
    pins = pin_table(sym)
    rx, ry = ref_xy if ref_xy else (x + 2.54, y - 2.54)
    vx, vy = val_xy if val_xy else (x + 2.54, y + 2.54)
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
    # absolute pin points (rotation 0 only)
    return {n: (x + px, y - py, a) for n, (px, py, a) in pins.items()}


def wire(x1, y1, x2, y2):
    items.append(sexp.parse(f'(wire (pts (xy {x1:.2f} {y1:.2f}) (xy {x2:.2f} {y2:.2f})) '
                            f'(stroke (width 0) (type default)) (uuid {uid("w", x1, y1, x2, y2)}))')[0])


def label(name, x, y, angle):
    """angle = direction the text runs from the connection point (0 right, 90 up, 180 left, 270 down)"""
    just = 'left bottom' if angle in (0, 90) else 'right bottom'
    items.append(sexp.parse(f'(label {q(name)} (at {x:.2f} {y:.2f} {angle}) '
                            f'(effects (font (size 1.27 1.27)) (justify {just})) '
                            f'(uuid {uid("l", name, x, y)}))')[0])


def power(net, x, y, rot=0):
    lid = 'power:GND' if net == 'GND' else 'power:+3V3'
    counters['#PWR'] += 1
    ref = f'#PWR{counters["#PWR"]:02d}'
    vy = y + 5.08 if net == 'GND' else y - 5.08
    place(lid, ref, net, x, y, rot=rot, val_xy=(x, vy))


def flag(x, y, rot=0):
    counters['#FLG'] += 1
    ref = f'#FLG{counters["#FLG"]:02d}'
    place('power:PWR_FLAG', ref, 'PWR_FLAG', x, y, rot=rot, val_xy=(x, y - 3.81 if rot == 0 else y + 3.81))


def noconn(x, y):
    items.append(sexp.parse(f'(no_connect (at {x:.2f} {y:.2f}) (uuid {uid("nc", x, y)}))')[0])


OUT = {0: (-1, 0, 180), 180: (1, 0, 0), 90: (0, 1, 270), 270: (0, -1, 90)}


def connect(pins, num, net, stub=2.54, power_label=False):
    """wire stub outward from a pin, then a label or power symbol"""
    x, y, a = pins[num]
    dx, dy, la = OUT[a]
    ex, ey = x + dx * stub, y + dy * stub
    wire(x, y, ex, ey)
    if net in ('GND', '+3V3') and not power_label:
        if net == 'GND' and dy == 0:
            # sideways pin: short down-stub to the ground symbol
            wire(ex, ey, ex, ey + 2.54)
            power(net, ex, ey + 2.54)
        elif net == '+3V3' and dy == 0:
            wire(ex, ey, ex, ey - 2.54)
            power(net, ex, ey - 2.54)
        else:
            power(net, ex, ey)
    else:
        label(net, ex, ey, la)


def text(s, x, y, size=1.27):
    items.append(sexp.parse(f'(text {q(s)} (exclude_from_sim no) (at {x:.2f} {y:.2f} 0) '
                            f'(effects (font (size {size} {size})) (justify left)) (uuid {uid("t", s)}))')[0])


def build():
    add_lib('Connector_Generic:Conn_02x06_Top_Bottom', libsym('Connector_Generic', 'Conn_02x06_Top_Bottom'))
    ffc = ffc_symbol('local:RPi_CSI_15')
    add_lib('local:RPi_CSI_15', ffc)
    for lid in ('Device:R', 'Device:C', 'Device:Polyfuse', 'power:GND', 'power:+3V3', 'power:PWR_FLAG'):
        add_lib(lid, libsym(*lid.split(':')))

    # J1 Pmod
    j1 = place('Connector_Generic:Conn_02x06_Top_Bottom', 'J1', 'Pmod (host)', 76.2, 88.9,
               footprint='local:Conn_Pmod_Spec_B_Thin', ref_xy=(77.47, 78.74), val_xy=(77.47, 99.06),
               desc='Pmod 2x6 right angle (Digilent Pmod Type 1A / spec B)')
    pmod = {'1': 'CAM_SCL', '2': 'CSI_CLK_P', '3': 'CSI_D1_P', '4': 'CSI_D0_P', '5': 'GND', '6': '+3V3',
            '7': 'CAM_SDA', '8': 'CSI_CLK_N', '9': 'CSI_D1_N', '10': 'CSI_D0_N', '11': 'GND', '12': '+3V3'}
    for n, net in pmod.items():
        connect(j1, n, net, stub=5.08, power_label=True)

    # J2 FFC
    j2 = place('local:RPi_CSI_15', 'J2', 'TE 1-84952-5 (alt. 1-84953-5)', 193.04, 88.9,
               footprint='Connector_FFC-FPC:TE_1-84952-5_1x15-1MP_P1.0mm_Horizontal',
               ref_xy=(193.04, 66.04), val_xy=(195.58, 116.84),
               desc='15-pin 1.0 mm FFC, bottom contact (top-contact 1-84953-5 has the same footprint)')
    ffc_nets = {'1': 'GND', '2': 'CSI_D0_N', '3': 'CSI_D0_P', '4': 'GND', '5': 'CSI_D1_N', '6': 'CSI_D1_P',
                '7': 'GND', '8': 'CSI_CLK_N', '9': 'CSI_CLK_P', '10': 'GND', '11': 'CAM_GPIO',
                '13': 'CAM_SCL', '14': 'CAM_SDA', '15': '+3V3_CAM'}
    for n, net in ffc_nets.items():
        if net == 'GND':
            x, y, a = j2[n]
            wire(x, y, x - 5.08, y)
            label('GND', x - 5.08, y, 180)
        else:
            connect(j2, n, net, stub=5.08)
    x, y, a = j2['12']
    noconn(x, y)
    x, y, a = j2['MP']
    wire(x, y, x, y + 2.54)
    power('GND', x, y + 2.54)
    # GND label nets need a GND symbol somewhere on the same net name: tie label GND to the power net
    wire(170.18, 132.08, 170.18, 134.62)
    label('GND', 170.18, 132.08, 90)
    power('GND', 170.18, 134.62)

    # F1 polyfuse: +3V3 -> +3V3_CAM
    f1 = place('Device:Polyfuse', 'F1', '500mA hold', 127.0, 50.8, footprint='Fuse:Fuse_0805_2012Metric',
               ref_xy=(129.54, 49.53), val_xy=(129.54, 52.07), desc='Resettable fuse, 6 V, I_hold 0.5 A, 0805',
               extra={'MPN': 'PTC 0805, I_hold 0.5 A, >= 6 V (e.g. Littelfuse 0805L050)'})
    connect(f1, '1', '+3V3')
    connect(f1, '2', '+3V3_CAM')
    # C1 bulk at the camera supply
    c1 = place('Device:C', 'C1', '10u', 142.24, 50.8, footprint='Capacitor_SMD:C_0805_2012Metric',
               ref_xy=(144.78, 49.53), val_xy=(144.78, 52.07), desc='10 uF 10 V X5R 0805')
    connect(c1, '1', '+3V3_CAM')
    connect(c1, '2', 'GND')

    # pull-ups (to the Pmod 3.3 V)
    for i, (ref, val, net, x) in enumerate((('R1', '2.2k', 'CAM_SDA', 114.3), ('R2', '2.2k', 'CAM_SCL', 129.54),
                                             ('R3', '10k', 'CAM_GPIO', 144.78))):
        r = place('Device:R', ref, val, x, 139.7, footprint='Resistor_SMD:R_0402_1005Metric',
                  ref_xy=(x + 2.54, 138.43), val_xy=(x + 2.54, 140.97), desc=f'{val} 1% 0402')
        connect(r, '1', '+3V3')
        connect(r, '2', net)

    # the power-net labels used at the connectors, tied to the power symbols
    wire(185.42, 132.08, 185.42, 129.54)
    label('+3V3', 185.42, 132.08, 270)
    power('+3V3', 185.42, 129.54)

    # power flags
    wire(101.6, 45.72, 101.6, 50.8)
    power('+3V3', 101.6, 45.72)
    flag(101.6, 50.8, rot=180)
    wire(101.6, 60.96, 101.6, 66.04)
    flag(101.6, 60.96)
    power('GND', 101.6, 66.04)

    notes = [
        'Pmod RPi Camera: Raspberry Pi camera (15-pin FFC, 2-lane MIPI CSI-2) on one Pmod.',
        'Soft D-PHY receiver: FPGA LVDS inputs with on-chip 100R termination, no LP receivers',
        '(eda/csi_capture, rtl/csi2). Lanes are DC coupled: no series R, no AC coupling, no bias.',
        'CSI pairs: 100 ohm differential, routed on F.Cu over solid B.Cu ground, no vias.',
        'J2: bottom-contact 1-84952-5. If the cable turns out reversed (F1 trips: 3V3 meets camera GND),',
        'fit the top-contact 1-84953-5 instead (same footprint) and insert the cable the other way up.',
        'CAM_GPIO (camera power enable) pulled up: the camera powers with the Pmod. CAM_CLK not used.',
    ]
    for i, s in enumerate(notes):
        text(s, 25.4, 162.56 + i * 3.81)


def write_sch():
    lib_s = '(lib_symbols ' + ' '.join(sexp.dump(s, 2) for s in lib.values()) + ')'
    body = '\n\t'.join(sexp.dump(it, 1) for it in items)
    txt = f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0")
\t(uuid {ROOT})
\t(paper "A4")
\t(title_block (title "Pmod RPi Camera (MIPI CSI-2)") (date "2026-10-12") (rev "A") (company "fpga_samples / eda/csi_capture") (comment 1 "Raspberry Pi Camera v2 (IMX219) and other 15-pin 2-lane CSI-2 cameras"))
\t{lib_s}
\t{body}
\t(sheet_instances (path "/" (page "1")))
\t(embedded_fonts no)
)
'''
    open(os.path.join(PRJ, NAME + '.kicad_sch'), 'w').write(txt)


if __name__ == '__main__':
    write_local_lib()
    build()
    write_sch()
    print('wrote', NAME + '.kicad_sch')
