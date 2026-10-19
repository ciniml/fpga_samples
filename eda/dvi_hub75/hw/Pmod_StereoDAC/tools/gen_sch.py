#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_StereoDAC.kicad_sch.

Pmod (12-pin, right angle) pins 1 / 2 = the two 1-bit delta-sigma DAC
outputs of eda/dvi_hub75 (rtl/hdmi_rx) -> per channel the RC low-pass of
eda/dvi_hub75/README.md (1k / 3.3n, 10k / 330p), 1 uF DC block, 100k
bleeder -> 3.5 mm stereo jack (tip = L, ring = R, sleeve = GND).
gen_pcb.py reads the schematic's netlist export.
"""
import os
import uuid
import sexp
from sexp import q

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'Pmod_StereoDAC'
SYMDIR = '/usr/share/kicad/symbols'
NS = uuid.UUID('2c71e0b4-9a35-4f6e-bd18-7e0a4c5d9f31')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(map(str, k))))


ROOT = uid('root')

# ---------------------------------------------------------------- symbols
FFC_PINS = ['GND', 'D0_N', 'D0_P', 'GND', 'D1_N', 'D1_P', 'GND', 'CLK_N', 'CLK_P', 'GND',
            'CAM_GPIO', 'CAM_CLK', 'SCL', 'SDA', '3V3']



def libsym(lib, name):
    s = sexp.lib_symbol(f'{SYMDIR}/{lib}.kicad_sym', name)
    s = list(s)
    s[1] = q(f'{lib}:{name}')
    return s



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


def place(lib_id, ref, value, x, y, footprint='', rot=0, ref_xy=None, val_xy=None, desc='', extra=None, datasheet='~'):
    sym = lib[lib_id]
    pins = pin_table(sym)
    rx, ry = ref_xy if ref_xy else (x + 2.54, y - 2.54)
    vx, vy = val_xy if val_xy else (x + 2.54, y + 2.54)
    power = ref.startswith('#')
    props = [prop('Reference', ref, rx, ry, hide=power), prop('Value', value, vx, vy),
             prop('Footprint', footprint, x, y, hide=True), prop('Datasheet', datasheet, x, y, hide=True),
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



PARTS = {   # value, footprint, LCSC, MPN, description
    '1k':   ('Resistor_SMD:R_0603_1608Metric', 'C21190', 'UNI-ROYAL 0603WAF1001T5E', '1 kOhm 1% 0603'),
    '10k':  ('Resistor_SMD:R_0603_1608Metric', 'C25804', 'UNI-ROYAL 0603WAF1002T5E', '10 kOhm 1% 0603'),
    '100k': ('Resistor_SMD:R_0603_1608Metric', 'C25803', 'UNI-ROYAL 0603WAF1003T5E', '100 kOhm 1% 0603'),
    '3.3n': ('Capacitor_SMD:C_0603_1608Metric', 'C107048', 'YAGEO CC0603JRNPO9BN332', '3.3 nF 50 V C0G 5% 0603'),
    '330p': ('Capacitor_SMD:C_0603_1608Metric', 'C1664', 'Samsung CL10C331JB8NNNC', '330 pF 50 V C0G 5% 0603'),
    '1u':   ('Capacitor_SMD:C_0805_2012Metric', 'C28323', 'Samsung CL21B105KBFNNNE', '1 uF 50 V X7R 10% 0805 (DC block)'),
}


def part(lib_id, ref, value, x, y):
    fp, lcsc, mpn, desc = PARTS[value]
    return place(lib_id, ref, value, x, y, footprint=fp, ref_xy=(x + 2.54, y - 1.27), val_xy=(x + 2.54, y + 1.27),
                 desc=desc, extra={'LCSC': lcsc, 'MPN': mpn})


def chain(ch, y, refs):
    """one channel: DSM in -> R 1k -> C 3.3n -> R 10k -> C 330p -> C 1u -> R 100k -> jack"""
    a, f1, f2, out = f'AUDIO_{ch}', f'{ch}_F1', f'{ch}_F2', f'{ch}_OUT'
    r1, c1, r2, c2, c3, r3 = refs
    for i, (lib, ref, val, n1, n2) in enumerate((
            ('Device:R', r1, '1k', a, f1), ('Device:C', c1, '3.3n', f1, 'GND'),
            ('Device:R', r2, '10k', f1, f2), ('Device:C', c2, '330p', f2, 'GND'),
            ('Device:C', c3, '1u', f2, out), ('Device:R', r3, '100k', out, 'GND'))):
        p = part(lib, ref, val, 50.8 + 20.32 * i, y)
        for num, net in (('1', n1), ('2', n2)):
            if net == 'GND':
                connect(p, num, net)
            else:
                connect(p, num, net)


def build():
    add_lib('Connector_Generic:Conn_02x06_Top_Bottom', libsym('Connector_Generic', 'Conn_02x06_Top_Bottom'))
    add_lib('Connector_Audio:AudioJack3', libsym('Connector_Audio', 'AudioJack3'))
    add_lib('Connector_Generic:Conn_01x03', libsym('Connector_Generic', 'Conn_01x03'))
    for lid in ('Device:R', 'Device:C', 'power:GND', 'power:PWR_FLAG'):
        add_lib(lid, libsym(*lid.split(':')))

    j1 = place('Connector_Generic:Conn_02x06_Top_Bottom', 'J1', 'Pmod (host)', 76.2, 127.0,
               footprint='local:Conn_Pmod_Spec_B_Thin', ref_xy=(77.47, 116.84), val_xy=(77.47, 137.16),
               desc='Pmod 2x6 right angle (Digilent Pmod Type 1A / spec B)',
               extra={'MPN': '2x6 2.54 mm right-angle pin header (hand soldered)'})
    for n, net in (('1', 'AUDIO_L'), ('2', 'AUDIO_R'), ('5', 'GND'), ('11', 'GND')):
        connect(j1, n, net, stub=5.08, power_label=True)
    for n in ('3', '4', '6', '7', '8', '9', '10', '12'):
        x, y, a = j1[n]
        noconn(x, y)

    chain('L', 63.5, ('R1', 'C1', 'R2', 'C2', 'C3', 'R3'))
    chain('R', 101.6, ('R11', 'C11', 'R12', 'C12', 'C13', 'R13'))

    j2 = place('Connector_Audio:AudioJack3', 'J2', 'PJ-313D', 165.1, 127.0,
               footprint='local:Jack_3.5mm_SHOUHAN_PJ-313D_Horizontal', ref_xy=(162.56, 119.38), val_xy=(162.56, 134.62),
               desc='3.5 mm stereo jack, SMD (SHOU HAN PJ-313D): tip = L, ring = R, sleeve = GND',
               extra={'LCSC': 'C668608', 'MPN': 'SHOU HAN PJ-313D'},
               datasheet='https://datasheet.lcsc.com/datasheet/pdf/4db06f4710100142f95009097243e291.pdf')
    connect(j2, 'T', 'L_OUT')
    connect(j2, 'R', 'R_OUT')
    connect(j2, 'S', 'GND', power_label=True)

    # the same outputs on a 3-pin header, GND in the middle (a reversed plug never shorts L to R)
    j3 = place('Connector_Generic:Conn_01x03', 'J3', 'L / GND / R', 165.1, 154.94,
               footprint='Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical', ref_xy=(165.1, 149.86),
               val_xy=(165.1, 160.02), desc='1x03 2.54 mm pin header, vertical: 1 = L, 2 = GND, 3 = R (line out, after the DC block)',
               extra={'LCSC': 'C49257', 'MPN': 'BOOMELE 2.54-1*3P'})
    connect(j3, '1', 'L_OUT')
    connect(j3, '2', 'GND', power_label=True)
    connect(j3, '3', 'R_OUT')

    # the GND label is the power net
    wire(190.5, 129.54, 190.5, 132.08)
    label('GND', 190.5, 129.54, 90)
    power('GND', 190.5, 132.08)
    wire(203.2, 124.46, 203.2, 129.54)
    flag(203.2, 124.46)
    power('GND', 203.2, 129.54)

    notes = [
        'Pmod Stereo DAC: the two 1-bit delta-sigma outputs of eda/dvi_hub75 (rtl/hdmi_rx, 6.19 MHz) to a 3.5 mm stereo jack.',
        'Per channel (eda/dvi_hub75/README.md): 1k / 3.3n and 10k / 330p RC (both ~48 kHz), 1 uF DC block, 100k bleeder.',
        '-3 dB ~28.5 kHz, 20 kHz -1.6 dB, 6.19 MHz -85 dB (with ~30 ohm pin impedance). Flatter: C1 / C11 2.2n, C2 / C12 220p.',
        'Line level (~1.1 Vrms full scale, ~10 kohm source): headphones need an amplifier. Pmod 3.3 V is not used.',
        'J3 carries the same outputs as the jack (after the DC block): 1 = L, 2 = GND, 3 = R.',
    ]
    for i, s in enumerate(notes):
        text(s, 25.4, 162.56 + i * 3.81)


def write_sch():
    lib_s = '(lib_symbols ' + ' '.join(sexp.dump(s, 2) for s in lib.values()) + ')'
    body = '\n\t'.join(sexp.dump(it, 1) for it in items)
    txt = f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0")
\t(uuid {ROOT})
\t(paper "A4")
\t(title_block (title "Pmod Stereo DAC") (date "2026-10-20") (rev "A") (company "fpga_samples / eda/dvi_hub75") (comment 1 "Line output for the delta-sigma DAC of eda/dvi_hub75 (HDMI audio)"))
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
