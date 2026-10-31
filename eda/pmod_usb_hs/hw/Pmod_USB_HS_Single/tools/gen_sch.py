#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_USB_HS_Single.kicad_sch.

USB 2.0 high-speed device on one Pmod: Gowin USB 2.0 SoftPHY "Single LVDS"
wiring without the D- comparator (7 FPGA pins + VBUS detect), for
rtl/usb/gowin/usb_phy_gowin_sl.v with CMP1=1 (see ../../SINGLE_PMOD.md).
Values are TN710's Arora-V ones (GW5A). The netlist below is the single
source of truth; gen_pcb.py reads the schematic's netlist export.
"""
import os
import uuid
import sexp
from sexp import q

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'Pmod_USB_HS_Single'
SYMDIR = '/usr/share/kicad/symbols'
NS = uuid.UUID('0b5e7c2a-91d4-4f3e-8a6b-6d2f1c9e4b77')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(map(str, k))))


ROOT = uid('root')


def libsym(lib, name):
    s = sexp.lib_symbol(f'{SYMDIR}/{lib}.kicad_sym', name)
    s = list(s)
    s[1] = q(f'{lib}:{name}')
    return s


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


# LCSC / MPN per part (JLC basic parts where there is one; tools/lcsc_order.py buys equivalents
# when LCSC itself is short). J1 (Pmod header) is hand soldered and has none.
PARTS = {
    'J2': ('C165948', 'HRO TYPE-C-31-M-12'),
    'D1': ('C436349', 'TI TPD1E05U06DPYR'), 'D2': ('C436349', 'TI TPD1E05U06DPYR'),
    'R6': ('C25076', 'UNI-ROYAL 0402WGF1000TCE'), 'R7': ('C25076', 'UNI-ROYAL 0402WGF1000TCE'),
    'R2': ('C25105', 'UNI-ROYAL 0402WGF330JTCE'), 'R3': ('C25105', 'UNI-ROYAL 0402WGF330JTCE'),
    'R1': ('C25867', 'UNI-ROYAL 0402WGF1501TCE'),
    'R8': ('C25900', 'UNI-ROYAL 0402WGF4701TCE'),
    'R9': ('C25087', 'UNI-ROYAL 0402WGF2000TCE'),
    'R10': ('C25905', 'UNI-ROYAL 0402WGF5101TCE'), 'R11': ('C25905', 'UNI-ROYAL 0402WGF5101TCE'),
    'R12': ('C25741', 'UNI-ROYAL 0402WGF1003TCE'),
    'R13': ('C25755', 'UNI-ROYAL 0402WGF1503TCE'),
    'C1': ('C52923', 'Samsung CL05A105KA5NQNC'), 'C5': ('C52923', 'Samsung CL05A105KA5NQNC'),
    'C3': ('C19702', 'Samsung CL10A106KP8NNNC'),
    'C4': ('C307331', 'Samsung CL05B104KB54PNC'),
}


def place(lib_id, ref, value, x, y, footprint='', rot=0, ref_xy=None, val_xy=None, desc='', extra=None):
    sym = lib[lib_id]
    pins = pin_table(sym)
    rx, ry = ref_xy if ref_xy else (x + 2.54, y - 2.54)
    vx, vy = val_xy if val_xy else (x + 2.54, y + 2.54)
    power = ref.startswith('#')
    props = [prop('Reference', ref, rx, ry, hide=power), prop('Value', value, vx, vy),
             prop('Footprint', footprint, x, y, hide=True), prop('Datasheet', '~', x, y, hide=True),
             prop('Description', desc, x, y, hide=True)]
    extra = dict(extra or {})
    if ref in PARTS:
        extra['LCSC'], extra['MPN'] = PARTS[ref]
    for k, v in extra.items():
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


R0402 = 'Resistor_SMD:R_0402_1005Metric'
C0402 = 'Capacitor_SMD:C_0402_1005Metric'
C0603 = 'Capacitor_SMD:C_0603_1608Metric'


def resistor(ref, val, x, y, n1, n2, desc, fp=R0402, lib_id='Device:R'):
    """vertical R / C, pin 1 (top) on n1, pin 2 (bottom) on n2"""
    r = place(lib_id, ref, val, x, y, footprint=fp, ref_xy=(x + 2.54, y - 1.27), val_xy=(x + 2.54, y + 1.27),
              desc=desc)
    connect(r, '1', n1)
    connect(r, '2', n2)


def build():
    add_lib('Connector_Generic:Conn_02x06_Top_Bottom', libsym('Connector_Generic', 'Conn_02x06_Top_Bottom'))
    for lid in ('Connector:USB_C_Receptacle_USB2.0_16P', 'Power_Protection:TPD1E05U06DPY', 'Device:R', 'Device:C',
                'power:GND', 'power:+3V3', 'power:PWR_FLAG'):
        add_lib(lid, libsym(*lid.split(':')))

    # ---- J2 USB-C (USB 2.0 only, UFP) ----
    j2 = place('Connector:USB_C_Receptacle_USB2.0_16P', 'J2', 'USB_C_Receptacle_USB2.0_16P', 45.72, 88.9,
               footprint='Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12', ref_xy=(45.72, 60.96),
               val_xy=(45.72, 116.84), desc='USB Type-C receptacle, USB 2.0 (16 pin)',
               extra={'MPN': 'HRO TYPE-C-31-M-12'})
    done = set()
    for n, net in (('A4', 'VBUS'), ('A5', 'CC1'), ('B5', 'CC2'), ('A6', 'USB_DP'), ('B6', 'USB_DP'),
                   ('A7', 'USB_DN'), ('B7', 'USB_DN')):
        if j2[n][:2] in done:
            continue
        done.add(j2[n][:2])
        connect(j2, n, net, stub=7.62)
    for n in ('A8', 'B8'):
        x, y, a = j2[n]
        noconn(x, y)
    connect(j2, 'A1', 'GND')
    connect(j2, 'SH', 'GND')

    # ---- ESD (one 0.42 pF diode per line, at the connector) ----
    for ref, net, x in (('D1', 'USB_DP', 63.5), ('D2', 'USB_DN', 81.28)):
        d = place('Power_Protection:TPD1E05U06DPY', ref, 'TPD1E05U06DPY', x, 134.62,
                  footprint='Package_SON:Texas_DPY0002A_0.6x1mm_P0.65mm', ref_xy=(x - 2.54, 129.54),
                  val_xy=(x - 2.54, 127.0), desc='1-channel ESD protection, 0.42 pF, X1SON-2',
                  extra={'MPN': 'TI TPD1E05U06DPYR'})
        connect(d, '1', net)
        connect(d, '2', 'GND')

    # ---- Single LVDS network (TN710 USB2.0-RC, Arora-V values, no D- comparator) ----
    resistor('R6', '100', 101.6, 50.8, 'USB_DP', 'DX_P', '100R 1% 0402 (dx series, D+)')
    resistor('R7', '100', 114.3, 50.8, 'USB_DN', 'DX_N', '100R 1% 0402 (dx series, D-)')
    resistor('R2', '33', 127.0, 50.8, 'USB_DP', 'TERM_DP', '33R 1% 0402 (HS termination, D+)')
    resistor('R3', '33', 139.7, 50.8, 'USB_DN', 'TERM_DN', '33R 1% 0402 (HS termination, D-)')
    resistor('R1', '1.5k', 152.4, 50.8, 'USB_DP', 'PULLUP', '1.5k 1% 0402 (D+ pull-up, soft connect)')
    # VREF (one comparator) and the 3.3 V decoupling
    resistor('R8', '4.7k', 101.6, 88.9, '+3V3', 'VREF', '4.7k 1% 0402 (VREF ~135 mV)')
    resistor('R9', '200', 114.3, 88.9, 'VREF', 'GND', '200R 1% 0402 (VREF)')
    resistor('C1', '1u', 127.0, 88.9, 'VREF', 'GND', '1 uF 10 V X5R 0402 (VREF)', fp=C0402, lib_id='Device:C')
    resistor('C3', '10u', 139.7, 88.9, '+3V3', 'GND', '10 uF 10 V X5R 0603', fp=C0603, lib_id='Device:C')
    resistor('C4', '100n', 152.4, 88.9, '+3V3', 'GND', '100 nF 16 V X7R 0402', fp=C0402, lib_id='Device:C')
    # CC (Rd, UFP) / VBUS detect
    resistor('R10', '5.1k', 101.6, 127.0, 'CC1', 'GND', '5.1k 1% 0402 (CC1 Rd)')
    resistor('R11', '5.1k', 114.3, 127.0, 'CC2', 'GND', '5.1k 1% 0402 (CC2 Rd)')
    resistor('R12', '100k', 127.0, 127.0, 'VBUS', 'VBUS_DET', '100k 1% 0402 (VBUS divider, 5 V -> 3.0 V)')
    resistor('R13', '150k', 139.7, 127.0, 'VBUS_DET', 'GND', '150k 1% 0402 (VBUS divider)')
    resistor('C5', '1u', 152.4, 127.0, 'VBUS', 'GND', '1 uF 10 V X5R 0402 (VBUS)', fp=C0402, lib_id='Device:C')

    # ---- J1 Pmod ----
    j1 = place('Connector_Generic:Conn_02x06_Top_Bottom', 'J1', 'Pmod (host)', 213.36, 88.9,
               footprint='local:Conn_Pmod_Spec_B_Thin', ref_xy=(214.63, 78.74), val_xy=(214.63, 99.06),
               desc='Pmod 2x6 right angle (Digilent Pmod Type 1A / spec B)')
    pmod = {'1': 'DX_P', '2': 'USB_DP', '3': 'TERM_DP', '4': 'PULLUP', '5': 'GND', '6': '+3V3',
            '7': 'DX_N', '8': 'VREF', '9': 'TERM_DN', '10': 'VBUS_DET', '11': 'GND', '12': '+3V3'}
    for n, net in pmod.items():
        connect(j1, n, net, stub=5.08, power_label=True)
    # the power-net labels at the Pmod, tied to the power symbols
    wire(195.58, 119.38, 195.58, 121.92)
    label('GND', 195.58, 119.38, 90)
    power('GND', 195.58, 121.92)
    wire(208.28, 119.38, 208.28, 116.84)
    label('+3V3', 208.28, 119.38, 270)
    power('+3V3', 208.28, 116.84)

    # power flags
    wire(25.4, 45.72, 25.4, 50.8)
    power('+3V3', 25.4, 45.72)
    flag(25.4, 50.8, rot=180)
    wire(38.1, 45.72, 38.1, 50.8)
    flag(38.1, 45.72)
    power('GND', 38.1, 50.8)

    notes = [
        'Pmod USB HS Single: USB 2.0 HS device on one Pmod (Gowin SoftPHY Single LVDS wiring without the D- comparator).',
        'FPGA side: rtl/usb/gowin/usb_phy_gowin_sl.v with CMP1=1 (eda/pmod_usb_hs/SINGLE_PMOD.md). Arora-V (GW5A) values from TN710.',
        'Pmod 1/7 DX_P/DX_N: LVCMOS33D bidirectional pair (transmit + differential receive), R6/R7 in series.',
        'Pmod 2/8 D+ / VREF: LVDS25 input pair = D+ comparator (squelch). VREF = 3.3 V x 200 / 4900 = 135 mV.',
        'Pmod 3/9 TERM_DP/DN: drive low = 45 ohm HS termination (pin + R2/R3), Hi-Z = FS line state input (LVCMOS33).',
        'Pmod 4 PULLUP: high = 1.5k on D+ (FS attach). Pmod 10 VBUS_DET: VBUS / 1.67 (LVCMOS33 input).',
        'UFP only: Rd 5.1k on CC1/CC2, VBUS is not used as a supply. Shield to GND.',
    ]
    for i, s in enumerate(notes):
        text(s, 25.4, 162.56 + i * 3.81)


def write_sch():
    lib_s = '(lib_symbols ' + ' '.join(sexp.dump(s, 2) for s in lib.values()) + ')'
    body = '\n\t'.join(sexp.dump(it, 1) for it in items)
    txt = f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0")
\t(uuid {ROOT})
\t(paper "A4")
\t(title_block (title "Pmod USB HS Single (USB 2.0 HS device, 7 pins)") (date "2026-10-18") (rev "A") (company "fpga_samples / eda/pmod_usb_hs") (comment 1 "Gowin USB 2.0 SoftPHY Single LVDS wiring, D+ comparator only (usb_phy_gowin_sl CMP1=1)"))
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
