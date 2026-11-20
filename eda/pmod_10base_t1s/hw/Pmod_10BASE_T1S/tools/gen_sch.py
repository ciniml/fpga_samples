#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Generate Pmod_10BASE_T1S.kicad_sch (and Local/local.kicad_sym, the CMC footprint).

10BASE-T1S (IEEE 802.3cg, Clause 147) on one Pmod without a PHY chip: the
FPGA implements PCS / PMA / PLCA, the board only carries passives, one analog
switch, the CMC and an ESD array. Design study: ../../README.md.

- J1 = Pmod plug (Digilent numbering: 1-6 upper row, 7-12 lower row, 5/11
  GND, 6/12 VCC = 3.3 V). Upper-row pins are the true (P) side of the
  FPGA's LVDS pairs (Tang Primer 25K pmod0 = J6: F5/G5, G7/G8). Same order
  as eda/pmod_100base_tx except pin 9 (TX_EN instead of a second PWM).
  1 / 7 CMP_HP / CMP_HN (comparator H, LVDS25 input), 2 / 8 CMP_LP / CMP_LN
  (comparator L), 3 PWM_TH, 9 TX_EN, 4 / 10 TX_P / TX_N (LVCMOS33).
- TX, two paths selected per side by a 3-pad solder jumper (JP2 = +, JP3 = -;
  centre pad = TXx_RC after the 100R):
  1-2 (default, bridged by a copper strip): switch path. 220 pF to GND (edge
  rate, ~10 ns 20-80 %) -> TMUX1511 (switch 1 / 2, SEL = TX_EN, 10k
  pull-down: off while the FPGA is unconfigured; isolated when unpowered) ->
  22R -> TRX_P / TRX_N. ~145R per side incl. the pin and Ron: ~1.0 Vpp into
  the 50R of the two 100R end terminations.
  2-3 (cut the 1-2 strip, bridge 2-3): series-L path. 1 uH (L2 / L3) straight
  to TRX_P / TRX_N, the 220 pF is disconnected: 100R + 1 uH give ~1.0-1.1 Vpp
  and 10.5-12 ns 20-80 % (ngspice, 50R || 15 pF). The FPGA keeps TX_EN low
  (U1 open; U1 may also be left off) and releases the TX pins while idle
  (T1sBringup command 'd'). No Extended part on this path.
- RX: comparator H = (VB + v+) vs (VTH + v-) -> v > +th, comparator L =
  (VTH + v+) vs (VB + v-) -> v > -th, th = VTH - VB set by PWM_TH
  (5.1k / 1k to VB, 1 uF): -204 ... +337 mV. TRX_P / TRX_N are biased to VB
  (20k each); the VTH taps are AC coupled (100 nF) and biased to VTH (20k).
  1k in series with every FPGA pin (hides the pin capacitance from the
  bus, limits ESD current).
- Line: TRX -> ESD (TPD4E02B04, transceiver side) -> CMC 200 uH (TDK
  ACT1210L-201) -> 100 nF 50 V DC block -> J2 (5.0 mm screw terminal) and
  J3 (2.54 mm probe header). End termination 2 x 49.9R with a centre
  100 nF + 100k to GND, switched by JP1 (fit the shunt at the two ends of a
  mixing segment). Common-mode termination 2 x 1.5k (drop node, OPEN
  Alliance option) not fitted. No PoDL.

The netlist below is the single source of truth; gen_pcb.py reads the
schematic's netlist export.
"""
import os
import uuid
import sexp
from sexp import q

HERE = os.path.dirname(os.path.abspath(__file__))
PRJ = os.path.dirname(HERE)
NAME = 'Pmod_10BASE_T1S'
SYMDIR = '/usr/share/kicad/symbols'
NS = uuid.UUID('3c1e9f52-8a47-4d0b-b6e1-2f7a9c4d5e81')


def uid(*k):
    return str(uuid.uuid5(NS, '/'.join(map(str, k))))


ROOT = uid('root')

# ---------------------------------------------------------------- local symbols
# name -> (reference, body width, footprint, description, left pins, right pins); pin = (num, name, type) or None
CUSTOM = {
    'TMUX1511': ('U', 15.24, 'Package_SO:TSSOP-14_4.4x5mm_P0.65mm',
                 'TI TMUX1511 4-channel SPST switch, 2 Ohm, 3.3 pF, powered-off protected, 1.8 V logic, TSSOP-14', [
        ('14', 'VDD', 'power_in'), None,
        ('2', 'S1', 'passive'), ('5', 'S2', 'passive'), ('9', 'S3', 'passive'), ('12', 'S4', 'passive'), None,
        ('1', 'SEL1', 'input'), ('4', 'SEL2', 'input'), ('10', 'SEL3', 'input'), ('13', 'SEL4', 'input'), None,
        ('7', 'GND', 'power_in'),
    ], [
        None, None, ('3', 'D1', 'passive'), ('6', 'D2', 'passive'), ('8', 'D3', 'passive'), ('11', 'D4', 'passive'),
    ]),
    'ACT1210L-201': ('L', 10.16, 'local:L_CommonModeChoke_TDK_ACT1210',
                     'TDK ACT1210L-201-2P-TL00 common mode choke, 200 uH, 2 lines, 3.2x2.5 mm (windings 1-4, 2-3)', [
        ('1', '1', 'passive'), ('2', '2', 'passive'),
    ], [
        ('4', '4', 'passive'), ('3', '3', 'passive'),
    ]),
}


def write_cmc_footprint():
    """TDK ACT1210 recommended land: pads 1.05 x 0.4 mm, 2.0 mm inner gap / 4.1 mm overall, rows 1.6 mm overall"""
    pads = []
    for num, x, y in (('1', -1.525, -0.6), ('2', -1.525, 0.6), ('3', 1.525, 0.6), ('4', 1.525, -0.6)):
        pads.append(f'(pad "{num}" smd roundrect (at {x} {y}) (size 1.05 0.4) (layers "F.Cu" "F.Paste" "F.Mask") '
                    f'(roundrect_rratio 0.25))')
    txt = f'''(footprint "L_CommonModeChoke_TDK_ACT1210" (version 20241229) (generator "gen_sch.py")
  (layer "F.Cu")
  (descr "TDK ACT1210 common mode choke 3.2x2.5 mm, recommended land pattern (ACT1210L-201 data sheet)")
  (attr smd)
  (property "Reference" "REF**" (at 0 -2.2 0) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))))
  (property "Value" "ACT1210L-201" (at 0 2.2 0) (layer "F.Fab") (effects (font (size 0.8 0.8) (thickness 0.12))))
  (fp_line (start -0.8 -1.35) (end 0.8 -1.35) (stroke (width 0.12) (type solid)) (layer "F.SilkS"))
  (fp_line (start -0.8 1.35) (end 0.8 1.35) (stroke (width 0.12) (type solid)) (layer "F.SilkS"))
  (fp_circle (center -2.45 -0.6) (end -2.35 -0.6) (stroke (width 0.2) (type solid)) (fill yes) (layer "F.SilkS"))
  (fp_rect (start -1.6 -1.25) (end 1.6 1.25) (stroke (width 0.1) (type solid)) (fill no) (layer "F.Fab"))
  (fp_rect (start -2.3 -1.5) (end 2.3 1.5) (stroke (width 0.05) (type solid)) (fill no) (layer "F.CrtYd"))
  {' '.join(pads)}
  (embedded_fonts no)
)
'''
    open(os.path.join(PRJ, 'Local', 'local.pretty', 'L_CommonModeChoke_TDK_ACT1210.kicad_mod'), 'w').write(txt)


def ic_symbol(name):
    ref, w, fp, desc, left, right = CUSTOM[name]
    rows = max(len(left), len(right))
    top = round((rows - 1) * 2.54 / 2 / 2.54) * 2.54
    pins = []
    for side, lst in ((-1, left), (1, right)):
        for i, p in enumerate(lst):
            if p is None:
                continue
            num, pn, typ = p
            x = side * (w / 2 + 2.54)
            y = top - i * 2.54
            pins.append(f'(pin {typ} line (at {x:.2f} {y:.2f} {0 if side < 0 else 180}) (length 2.54) '
                        f'(name {q(pn)} (effects (font (size 1.27 1.27)))) '
                        f'(number {q(num)} (effects (font (size 1.27 1.27)))))')
    y1, y2 = top + 2.54, top - rows * 2.54
    txt = f'''(symbol {q(name)} (pin_names (offset 1.016)) (exclude_from_sim no) (in_bom yes) (on_board yes)
  (property "Reference" {q(ref)} (at 0 {y1 + 1.27:.2f} 0) (effects (font (size 1.27 1.27))))
  (property "Value" {q(name)} (at 0 {y2 - 1.27:.2f} 0) (effects (font (size 1.27 1.27))))
  (property "Footprint" {q(fp)} (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (property "Datasheet" "~" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (property "Description" {q(desc)} (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
  (symbol {q(name + '_0_1')}
    (rectangle (start {-w / 2:.2f} {y1:.2f}) (end {w / 2:.2f} {y2:.2f}) (stroke (width 0.254) (type default)) (fill (type background))))
  (symbol {q(name + '_1_1')} {' '.join(pins)})
  (embedded_fonts no))'''
    return sexp.parse(txt)[0]


def write_local_lib():
    body = '\n\t'.join(sexp.dump(ic_symbol(n), 1) for n in CUSTOM)
    txt = '(kicad_symbol_lib (version 20241209) (generator "gen_sch.py") (generator_version "1.0")\n\t' + body + '\n)\n'
    open(os.path.join(PRJ, 'Local', 'local.kicad_sym'), 'w').write(txt)


def local_sym(name):
    s = list(ic_symbol(name))
    s[1] = q(f'local:{name}')
    return s


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


# LCSC / MPN per part (JLC basic parts where there is one). J1 (Pmod plug), J3 (probe header) and JP1
# are hand soldered and have none; J2 (screw terminal, through hole) is hand soldered by default
# (jlc_files.py leaves it out of the CPL).
C100N = ('C1525', 'Samsung CL05B104KO5NNNC')
C100N50 = ('C14663', 'YAGEO CC0603KRX7R9BB104')
C1U = ('C52923', 'Samsung CL05A105KA5NQNC')
C10U = ('C19702', 'Samsung CL10A106KP8NNNC')
C220P = ('C1530', 'FH 0402B221K500NT')
R22R = ('C25092', 'UNI-ROYAL 0402WGF220JTCE')
R49 = ('C25120', 'UNI-ROYAL 0402WGF499JTCE')
R100 = ('C25076', 'UNI-ROYAL 0402WGF1000TCE')
R1K = ('C11702', 'UNI-ROYAL 0402WGF1001TCE')
R2K = ('C4109', 'UNI-ROYAL 0402WGF2001TCE')
R1K5 = ('C22843', 'UNI-ROYAL 0603WAF1501T5E')
R3K3 = ('C25890', 'UNI-ROYAL 0402WGF3301TCE')
R5K1 = ('C25905', 'UNI-ROYAL 0402WGF5101TCE')
L1U = ('C1042', 'Sunlord SDFL2012Q1R0KTF')
R10K = ('C25744', 'UNI-ROYAL 0402WGF1002TCE')
R20K = ('C25765', 'UNI-ROYAL 0402WGF2002TCE')
R100K = ('C25741', 'UNI-ROYAL 0402WGF1003TCE')
# not fitted: common-mode termination (drop node option), probe header
DNP = {'R23', 'R24', 'J3'}
# copper solder jumpers (the footprints exclude themselves from the BOM / placement)
NO_BOM = {'JP2', 'JP3'}
PARTS = {
    'U1': ('C2866750', 'TI TMUX1511PWR'),
    'U2': ('C106794', 'TI TPD4E02B04DQAR'),
    'L1': ('C131444', 'TDK ACT1210L-201-2P-TL00'),
    'J2': ('C474881', 'Cixi Kefa KF301-5.0-2P'),
    'R1': R100, 'R2': R100, 'L2': L1U, 'L3': L1U, 'R5': R22R, 'R6': R22R, 'R7': R10K,
    'R8': R20K, 'R9': R20K, 'R10': R1K, 'R11': R1K, 'R12': R20K, 'R13': R1K, 'R14': R20K, 'R15': R1K,
    'R16': R3K3, 'R17': R2K, 'R18': R5K1, 'R19': R1K,
    'R20': R49, 'R21': R49, 'R22': R100K, 'R23': R1K5, 'R24': R1K5,
    'C1': C220P, 'C2': C220P, 'C3': C100N, 'C4': C100N, 'C5': C100N, 'C6': C10U, 'C7': C100N, 'C8': C1U,
    'C9': C100N50, 'C10': C100N50, 'C11': C100N50, 'C12': C10U, 'C13': C100N,
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
           f'(in_bom {"no" if power or ref in NO_BOM else "yes"}) (on_board {"no" if power else "yes"}) (dnp {"yes" if ref in DNP else "no"}) (uuid {uid(ref)}) '
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
    """wire stub outward from a pin, then a label or power symbol (net None: no-connect flag)"""
    x, y, a = pins[num]
    if net is None:
        noconn(x, y)
        return
    dx, dy, la = OUT[a]
    ex, ey = x + dx * stub, y + dy * stub
    wire(x, y, ex, ey)
    if net in ('GND', '+3V3') and not power_label:
        if net == 'GND' and dy == 0:
            wire(ex, ey, ex, ey + 2.54)
            power(net, ex, ey + 2.54)
        elif net == '+3V3' and dy == 0:
            wire(ex, ey, ex, ey - 2.54)
            power(net, ex, ey - 2.54)
        elif (net == 'GND' and dy < 0) or (net == '+3V3' and dy > 0):
            label(net, ex, ey, la)
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
L0603 = 'Inductor_SMD:L_0603_1608Metric'


def two(ref, val, x, y, n1, n2, desc, fp=R0402, lib_id='Device:R'):
    """vertical two-terminal part, pin 1 (top) on n1, pin 2 (bottom) on n2"""
    r = place(lib_id, ref, val, x, y, footprint=fp, ref_xy=(x + 2.54, y - 1.27), val_xy=(x + 2.54, y + 1.27),
              desc=desc)
    connect(r, '1', n1)
    connect(r, '2', n2)


def cap(ref, val, x, y, n1, desc, fp=C0402):
    two(ref, val, x, y, n1, 'GND', desc, fp=fp, lib_id='Device:C')


def build():
    write_local_lib()
    write_cmc_footprint()
    add_lib('Connector_Generic:Conn_02x06_Top_Bottom', libsym('Connector_Generic', 'Conn_02x06_Top_Bottom'))
    for n in CUSTOM:
        add_lib(f'local:{n}', local_sym(n))
    for lid in ('Power_Protection:TPD4E02B04DQA', 'Device:R', 'Device:C', 'Device:L', 'Jumper:SolderJumper_3_Bridged12', 'Connector_Generic:Conn_01x02',
                'Connector_Generic:Conn_01x03', 'power:GND', 'power:+3V3', 'power:PWR_FLAG'):
        add_lib(lid, libsym(*lid.split(':')))

    # ---- Pmod plug ----
    y = 63.5
    j = place('Connector_Generic:Conn_02x06_Top_Bottom', 'J1', 'Pmod', 33.02, y,
              footprint='local:Conn_Pmod_Spec_B_Thin', ref_xy=(34.29, y - 12.7), val_xy=(34.29, y + 12.7),
              desc='Pmod 2x6 right angle (Digilent Pmod Type 1A / spec B)')
    pins = {'5': 'GND', '11': 'GND', '6': '+3V3', '12': '+3V3',
            '1': 'CMP_HP', '7': 'CMP_HN', '2': 'CMP_LP', '8': 'CMP_LN', '3': 'PWM_TH', '9': 'TX_EN',
            '4': 'TX_P', '10': 'TX_N'}
    for n, net in pins.items():
        connect(j, n, net, stub=5.08, power_label=True)
    # tie the GND / +3V3 labels to the power symbols
    wire(15.24, y + 7.62, 15.24, y + 10.16)
    label('GND', 15.24, y + 7.62, 90)
    power('GND', 15.24, y + 10.16)
    wire(10.16, y - 7.62, 10.16, y - 10.16)
    label('+3V3', 10.16, y - 7.62, 270)
    power('+3V3', 10.16, y - 10.16)

    # ---- TX: series R, edge-rate C, switch, series R ----
    two('R1', '100', 76.2, 45.72, 'TX_P', 'TXP_RC', '100R 1% 0402 (TX+ series; tune R1 / R2 for 1.0 Vpp)')
    two('R2', '100', 86.36, 45.72, 'TX_N', 'TXN_RC', '100R 1% 0402 (TX- series)')
    cap('C1', '220p', 96.52, 45.72, 'TXP_C', '220 pF 50 V X7R 0402 (TX+ edge rate ~10 ns 20-80 %, hidden by U1 when idle; JP2 1-2)')
    cap('C2', '220p', 106.68, 45.72, 'TXN_C', '220 pF 50 V X7R 0402 (TX- edge rate; JP3 1-2)')
    for ref, x, c, rc, l, sign in (('JP2', 116.84, 'TXP_C', 'TXP_RC', 'TXP_L', '+'), ('JP3', 139.7, 'TXN_C', 'TXN_RC', 'TXN_L', '-')):
        jp = place('Jumper:SolderJumper_3_Bridged12', ref, 'SW/L', x, 33.02,
                   footprint='Jumper:SolderJumper-3_P1.3mm_Bridged12_RoundedPad1.0x1.5mm_NumberLabels',
                   ref_xy=(x, 26.67), val_xy=(x, 38.1),
                   desc=f'TX{sign} path: 1-2 (bridged) = C + TMUX1511 switch, 2-3 = series 1 uH (cut 1-2 first)')
        connect(jp, '1', c)
        connect(jp, '2', rc)
        connect(jp, '3', l)
    two('L2', '1u', 162.56, 33.02, 'TXP_L', 'TRX_P', '1 uH 0805 multilayer, 50 mA (TX+ series-L path, edge rate with R1)',
        fp='Inductor_SMD:L_0805_2012Metric', lib_id='Device:L')
    two('L3', '1u', 172.72, 33.02, 'TXN_L', 'TRX_N', '1 uH 0805 multilayer (TX- series-L path)',
        fp='Inductor_SMD:L_0805_2012Metric', lib_id='Device:L')
    two('R5', '22', 137.16, 45.72, 'TXP_SW', 'TRX_P', '22R 1% 0402 (TX+ series, line side of the switch)')
    two('R6', '22', 147.32, 45.72, 'TXN_SW', 'TRX_N', '22R 1% 0402 (TX- series)')
    two('R7', '10k', 157.48, 45.72, 'TX_EN', 'GND', '10k 1% 0402 (TX_EN pull-down: switch off while the FPGA is unconfigured)')
    u1 = place('local:TMUX1511', 'U1', 'TMUX1511', 101.6, 88.9, footprint=CUSTOM['TMUX1511'][2],
               ref_xy=(101.6, 73.66), val_xy=(101.6, 104.14), desc=CUSTOM['TMUX1511'][3])
    for n, net in (('2', 'TXP_RC'), ('3', 'TXP_SW'), ('5', 'TXN_RC'), ('6', 'TXN_SW'), ('1', 'TX_EN'), ('4', 'TX_EN'),
                   ('9', 'GND'), ('8', 'GND'), ('12', 'GND'), ('11', 'GND'), ('10', 'GND'), ('13', 'GND'),
                   ('14', '+3V3'), ('7', 'GND')):
        connect(u1, n, net)
    cap('C3', '100n', 127.0, 88.9, '+3V3', '100 nF 16 V X7R 0402 (U1 VDD)')

    # ---- RX: bias, taps, series R to the FPGA pins ----
    two('R8', '20k', 76.2, 127.0, 'TRX_P', 'VB', '20k 1% 0402 (TRX+ bias to VB)')
    two('R9', '20k', 86.36, 127.0, 'TRX_N', 'VB', '20k 1% 0402 (TRX- bias to VB)')
    two('R10', '1k', 96.52, 127.0, 'TRX_P', 'CMP_HP', '1k 1% 0402 (comparator H +: VB + v+)')
    two('R11', '1k', 106.68, 127.0, 'TRX_N', 'CMP_LN', '1k 1% 0402 (comparator L -: VB + v-)')
    two('C4', '100n', 116.84, 127.0, 'TRX_N', 'TAP_HN', '100 nF 16 V X7R 0402 (comparator H - tap, AC coupled)',
        fp=C0402, lib_id='Device:C')
    two('R12', '20k', 127.0, 127.0, 'TAP_HN', 'VTH', '20k 1% 0402 (comparator H - tap bias to VTH)')
    two('R13', '1k', 137.16, 127.0, 'TAP_HN', 'CMP_HN', '1k 1% 0402 (comparator H -: VTH + v-)')
    two('C5', '100n', 147.32, 127.0, 'TRX_P', 'TAP_LP', '100 nF 16 V X7R 0402 (comparator L + tap, AC coupled)',
        fp=C0402, lib_id='Device:C')
    two('R14', '20k', 157.48, 127.0, 'TAP_LP', 'VTH', '20k 1% 0402 (comparator L + tap bias to VTH)')
    two('R15', '1k', 167.64, 127.0, 'TAP_LP', 'CMP_LP', '1k 1% 0402 (comparator L +: VTH + v+)')

    # ---- VB and VTH ----
    two('R16', '3.3k', 76.2, 162.56, '+3V3', 'VB', '3.3k 1% 0402 (VB = 1.245 V with R17)')
    two('R17', '2k', 86.36, 162.56, 'VB', 'GND', '2k 1% 0402 (VB divider)')
    cap('C6', '10u', 96.52, 162.56, 'VB', '10 uF 10 V X5R 0603 (VB)', fp=C0603)
    cap('C7', '100n', 106.68, 162.56, 'VB', '100 nF 16 V X7R 0402 (VB)')
    two('R18', '5.1k', 116.84, 162.56, 'PWM_TH', 'VTH', '5.1k 1% 0402 (PWM filter: th = (D x 3.3 V - VB) x 0.164)')
    two('R19', '1k', 127.0, 162.56, 'VTH', 'VB', '1k 1% 0402 (PWM filter to VB)')
    cap('C8', '1u', 137.16, 162.56, 'VTH', '1 uF 25 V X5R 0402 (VTH, tau 0.85 ms)')

    # ---- ESD (transceiver side), CMC, DC block ----
    u2 = place('Power_Protection:TPD4E02B04DQA', 'U2', 'TPD4E02B04', 210.82, 63.5,
               footprint='Package_SON:USON-10_2.5x1.0mm_P0.5mm', ref_xy=(205.74, 48.26),
               val_xy=(205.74, 83.82), desc='4-channel ESD protection, 0.25 pF, USON-10 flow-through (2 channels used)')
    for (p, q_), net in ((('1', '10'), 'TRX_P'), (('2', '9'), 'TRX_N'), (('4', '7'), None), (('5', '6'), None)):
        connect(u2, p, net)
        connect(u2, q_, net)
    connect(u2, '3', 'GND')
    connect(u2, '8', 'GND')
    l1 = place('local:ACT1210L-201', 'L1', 'ACT1210L-201', 251.46, 63.5, footprint=CUSTOM['ACT1210L-201'][2],
               ref_xy=(251.46, 55.88), val_xy=(251.46, 71.12), desc=CUSTOM['ACT1210L-201'][3])
    for n, net in (('1', 'TRX_P'), ('2', 'TRX_N'), ('4', 'CM_P'), ('3', 'CM_N')):
        connect(l1, n, net)
    two('C9', '100n/50V', 279.4, 50.8, 'CM_P', 'LINE_P', '100 nF 50 V X7R 0603 (DC block +)', fp=C0603, lib_id='Device:C')
    two('C10', '100n/50V', 289.56, 50.8, 'CM_N', 'LINE_N', '100 nF 50 V X7R 0603 (DC block -)', fp=C0603, lib_id='Device:C')

    # ---- end termination (JP1), common-mode termination (not fitted), static discharge ----
    jp = place('Connector_Generic:Conn_01x02', 'JP1', 'TERM', 213.36, 127.0,
               footprint='Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical',
               ref_xy=(213.36, 121.92), val_xy=(213.36, 134.62),
               desc='2-pin header + shunt: fit to terminate (100R) at the ends of a mixing segment')
    connect(jp, '1', 'LINE_P')
    connect(jp, '2', 'TERM_A')
    two('R20', '49.9', 228.6, 127.0, 'TERM_A', 'TERM_CT', '49.9R 1% 0402 (end termination half)')
    two('R21', '49.9', 238.76, 127.0, 'TERM_CT', 'LINE_N', '49.9R 1% 0402 (end termination half)')
    cap('C11', '100n/50V', 248.92, 127.0, 'TERM_CT', '100 nF 50 V X7R 0603 (termination centre, OPEN Alliance C3)', fp=C0603)
    two('R22', '100k', 259.08, 127.0, 'TERM_CT', 'GND', '100k 1% 0402 (static discharge, OPEN Alliance R3)')
    two('R23', '1.5k', 269.24, 127.0, 'LINE_P', 'TERM_CT', '1.5k 1% 0603 (common-mode termination, NOT FITTED: drop node option)',
        fp='Resistor_SMD:R_0603_1608Metric')
    two('R24', '1.5k', 279.4, 127.0, 'LINE_N', 'TERM_CT', '1.5k 1% 0603 (common-mode termination, NOT FITTED)',
        fp='Resistor_SMD:R_0603_1608Metric')

    # ---- connectors ----
    j2 = place('Connector_Generic:Conn_01x02', 'J2', 'T1S', 320.04, 63.5,
               footprint='TerminalBlock:TerminalBlock_MaiXu_MX126-5.0-02P_1x02_P5.00mm',
               ref_xy=(320.04, 58.42), val_xy=(320.04, 71.12),
               desc='5.0 mm 2-pin screw terminal (KF301-5.0-2P): 1 = BI_DA+, 2 = BI_DA-')
    connect(j2, '1', 'LINE_P')
    connect(j2, '2', 'LINE_N')
    j3 = place('Connector_Generic:Conn_01x03', 'J3', 'PROBE', 320.04, 101.6,
               footprint='Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical',
               ref_xy=(320.04, 93.98), val_xy=(320.04, 109.22),
               desc='2.54 mm 3-pin header (NOT FITTED): line +, line -, GND for probes / jumper wires')
    connect(j3, '1', 'LINE_P')
    connect(j3, '2', 'LINE_N')
    connect(j3, '3', 'GND')

    # ---- 3.3 V decoupling ----
    cap('C12', '10u', 76.2, 198.12, '+3V3', '10 uF 10 V X5R 0603 (Pmod VCC)', fp=C0603)
    cap('C13', '100n', 86.36, 198.12, '+3V3', '100 nF 16 V X7R 0402 (Pmod VCC)')

    # power flags
    for net, x in (('+3V3', 25.4), ('GND', 38.1)):
        wire(x, 22.86, x, 27.94)
        if net == '+3V3':
            power('+3V3', x, 22.86)
            flag(x, 27.94, rot=180)
        else:
            flag(x, 22.86)
            power('GND', x, 27.94)

    notes = [
        'Pmod 10BASE-T1S: IEEE 802.3cg 10BASE-T1S without a PHY chip (PCS / PMA / PLCA in the FPGA). '
        'Tang Primer 25K pmod0 (J6, bank 1) or Tang Nano 9K Pmod base Rev.C pmod0.',
        'TX: LVCMOS33 x2 -> 100R -> JP2 / JP3. 1-2 (default): 220p (edge rate) -> TMUX1511 (TX_EN) -> 22R, high-Z when idle '
        'and when unpowered. 2-3: series 1 uH (L2 / L3) -> TRX, FPGA tristate when idle, TX_EN low. ~1.0 Vpp into 50R, ~10 ns.',
        'RX: comparator H (1/7) = v > +th, L (2/8) = v > -th, th = VTH - VB from PWM_TH (-204 ... +337 mV). '
        'Hysteresis (SR latch) and DME decoding in the FPGA.',
        'Line: ESD (transceiver side) -> 200 uH CMC -> 100 nF DC block -> J2. JP1: 100R end termination '
        '(fit at both ends of the segment). R23 / R24: common-mode termination (option). No PoDL.',
    ]
    for i, s in enumerate(notes):
        text(s, 25.4, 233.68 + i * 3.81)


def write_sch():
    lib_s = '(lib_symbols ' + ' '.join(sexp.dump(s, 2) for s in lib.values()) + ')'
    body = '\n\t'.join(sexp.dump(it, 1) for it in items)
    txt = f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0")
\t(uuid {ROOT})
\t(paper "A3")
\t(title_block (title "Pmod 10BASE-T1S (PHY-less, IEEE 802.3cg)") (date "2026-11-21") (rev "A") (company "fpga_samples / eda/pmod_10base_t1s") (comment 1 "TX: LVCMOS + RC + TMUX1511 or series 1 uH (JP2/JP3); RX: two LVDS-input comparators; 200 uH CMC, 100 nF DC block, switchable 100R end termination"))
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
