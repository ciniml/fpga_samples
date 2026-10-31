# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Single source of truth for the Pmod 100BASE-TX MagJack (integrated magnetics) variant.

Circuit = eda/pmod_100base_tx/README.md section 3 / 4 / 7.
Each part: ref, symbol (lib_id), value, footprint, pin->net map, MPN, Manufacturer, LCSC,
dnp flag, schematic placement (x, y, rot) on an A3 sheet.
"""

R0402 = 'Resistor_SMD:R_0402_1005Metric'
C0402 = 'Capacitor_SMD:C_0402_1005Metric'
C0603 = 'Capacitor_SMD:C_0603_1608Metric'
C1206 = 'Capacitor_SMD:C_1206_3216Metric'

RS = 'Device:R_Small'
CS = 'Device:C_Small'


def R(ref, val, n1, n2, mpn, sch, fp=R0402, mfr='', lcsc='', dnp=False, desc=''):
    return dict(ref=ref, sym=RS, value=val, fp=fp, pins={'1': n1, '2': n2},
                mpn=mpn, mfr=mfr, lcsc=lcsc, dnp=dnp, desc=desc, sch=sch)


def C(ref, val, n1, n2, mpn, sch, fp=C0402, mfr='', lcsc='', dnp=False, desc=''):
    return dict(ref=ref, sym=CS, value=val, fp=fp, pins={'1': n1, '2': n2},
                mpn=mpn, mfr=mfr, lcsc=lcsc, dnp=dnp, desc=desc, sch=sch)


PARTS = [
    # ---------------- Pmod header (peripheral side, male right angle) ----------------
    dict(ref='J1', sym='pmod_100base_tx:Conn_02x06_Top_Bottom', value='Pmod 2x6 R/A male',
         fp='pmod_100base_tx:Pmod_Peripheral_2x06_P2.54mm_Horizontal',
         pins={'1': 'A_P', '2': 'B_P', '3': 'PWM_A', '4': 'TX_P', '5': 'GND', '6': '+3V3',
               '7': 'A_N', '8': 'B_N', '9': 'PWM_B', '10': 'TX_N', '11': 'GND', '12': '+3V3'},
         mpn='TSW-106-08-G-D-RA', mfr='Samtec', lcsc='', dnp=False,  # hand soldered (LCSC alt. C41417354)
         desc='Pmod peripheral plug, 2x6 2.54mm right angle male, Type 1-6 top / 7-12 bottom',
         sch=(63.5, 73.66, 0)),

    # ---------------- TX: Rs / Rp / Cr / CMC (+0R bypass) / series C ----------------
    R('R1', '62', 'TX_P', 'TXP_DRV', 'FRC0402F62R0TS', (45.72, 139.7, 90), mfr='FOJAN', lcsc='C2909376', desc='Rs, tune for 0.95-1.05 V diff'),
    R('R2', '62', 'TX_N', 'TXN_DRV', 'FRC0402F62R0TS', (45.72, 172.72, 90), mfr='FOJAN', lcsc='C2909376', desc='Rs, tune for 0.95-1.05 V diff'),
    R('R3', '120', 'TXP_DRV', 'GND', '0402WGF1200TCE', (60.96, 147.32, 0), mfr='UNI-ROYAL', lcsc='C25079', desc='Rp'),
    R('R4', '120', 'TXN_DRV', 'GND', '0402WGF1200TCE', (60.96, 180.34, 0), mfr='UNI-ROYAL', lcsc='C25079', desc='Rp'),
    C('C1', '47p', 'TXP_DRV', 'GND', '0402CG470J500NT', (71.12, 147.32, 0), mfr='FH', lcsc='C1567', desc='Cr C0G 50V, edge rate tune'),
    C('C2', '47p', 'TXN_DRV', 'GND', '0402CG470J500NT', (71.12, 180.34, 0), mfr='FH', lcsc='C1567', desc='Cr C0G 50V, edge rate tune'),
    C('C3', '0.1u/50V', 'TXP_DRV', 'TD_P', 'CC0603KRX7R9BB104', (119.38, 139.7, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='TX DC block (no DC across the winding)'),
    C('C4', '0.1u/50V', 'TXN_DRV', 'TD_N', 'CC0603KRX7R9BB104', (119.38, 172.72, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='TX DC block (no DC across the winding)'),

    # ---------------- RX: termination + taps ----------------
    R('R7', '49.9', 'RD_P', 'RD_CT', '0402WGF499JTCE', (181.61, 50.8, 0), mfr='UNI-ROYAL', lcsc='C25120', desc='RX termination'),
    R('R8', '49.9', 'RD_CT', 'RD_N', '0402WGF499JTCE', (181.61, 73.66, 0), mfr='UNI-ROYAL', lcsc='C25120', desc='RX termination'),
    C('C5', '10n', 'RD_CT', 'GND', 'CL05B103KB5NNNC', (194.31, 73.66, 0), mfr='Samsung', lcsc='C15195', desc='Ct termination midpoint, X7R 50V'),
    C('C6', '0.1u/50V', 'RD_P', 'A_P', 'CC0603KRX7R9BB104', (163.83, 88.9, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='Ca tap, X7R 50V'),
    C('C7', '0.1u/50V', 'RD_N', 'A_N', 'CC0603KRX7R9BB104', (163.83, 101.6, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='Ca tap, X7R 50V'),
    C('C8', '0.1u/50V', 'RD_P', 'B_P', 'CC0603KRX7R9BB104', (163.83, 114.3, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='Ca tap, X7R 50V'),
    C('C9', '0.1u/50V', 'RD_N', 'B_N', 'CC0603KRX7R9BB104', (163.83, 127.0, 90), mfr='Yageo', lcsc='C14663', fp=C0603, desc='Ca tap, X7R 50V'),
    R('R9', '2.2k', 'A_P', 'VB', '0402WGF2201TCE', (191.77, 88.9, 90), mfr='UNI-ROYAL', lcsc='C25879', desc='Rb'),
    R('R10', '2.2k', 'A_N', 'VTH_A', '0402WGF2201TCE', (191.77, 101.6, 90), mfr='UNI-ROYAL', lcsc='C25879', desc='Rb'),
    R('R11', '2.2k', 'B_P', 'VTH_B', '0402WGF2201TCE', (191.77, 114.3, 90), mfr='UNI-ROYAL', lcsc='C25879', desc='Rb'),
    R('R12', '2.2k', 'B_N', 'VB', '0402WGF2201TCE', (191.77, 127.0, 90), mfr='UNI-ROYAL', lcsc='C25879', desc='Rb'),

    # ---------------- Bias: VB and VTH_A / VTH_B ----------------
    R('R13', '330', '+3V3', 'VB', '0402WGF3300TCE', (162.56, 157.48, 0), mfr='UNI-ROYAL', lcsc='C25104', desc='VB divider (1.32 V)'),
    R('R14', '220', 'VB', 'GND', '0402WGF2200TCE', (162.56, 177.8, 0), mfr='UNI-ROYAL', lcsc='C25091', desc='VB divider'),
    C('C10', '10u', 'VB', 'GND', 'CL10A106KP8NNNC', (175.26, 177.8, 0), mfr='Samsung', lcsc='C19702', fp=C0603, desc='X5R 10V'),
    C('C11', '0.1u', 'VB', 'GND', 'CL05B104KB54PNC', (185.42, 177.8, 0), mfr='Samsung', lcsc='C307331', desc='X7R 50V'),
    R('R15', '3.3k', 'PWM_A', 'VTH_A', '0402WGF3301TCE', (212.09, 154.94, 90), mfr='UNI-ROYAL', lcsc='C25890', desc='PWM filter (2.7k widens range)'),
    R('R16', '1k', 'VTH_A', 'VB', '0402WGF1001TCE', (236.22, 154.94, 90), mfr='UNI-ROYAL', lcsc='C11702', desc='PWM filter'),
    C('C12', '1u', 'VTH_A', 'GND', 'CL05A105KA5NQNC', (222.25, 162.56, 0), mfr='Samsung', lcsc='C52923', desc='X5R 25V'),
    R('R17', '3.3k', 'PWM_B', 'VTH_B', '0402WGF3301TCE', (212.09, 177.8, 90), mfr='UNI-ROYAL', lcsc='C25890', desc='PWM filter (2.7k widens range)'),
    R('R18', '1k', 'VTH_B', 'VB', '0402WGF1001TCE', (236.22, 177.8, 90), mfr='UNI-ROYAL', lcsc='C11702', desc='PWM filter'),
    C('C13', '1u', 'VTH_B', 'GND', 'CL05A105KA5NQNC', (222.25, 185.42, 0), mfr='Samsung', lcsc='C52923', desc='X5R 25V'),

    # ---------------- 3.3 V decoupling ----------------
    C('C14', '10u', '+3V3', 'GND', 'CL10A106KP8NNNC', (50.8, 109.22, 0), mfr='Samsung', lcsc='C19702', fp=C0603, desc='X5R 10V'),
    C('C15', '0.1u', '+3V3', 'GND', 'CL05B104KB54PNC', (60.96, 109.22, 0), mfr='Samsung', lcsc='C307331', desc='X7R 50V'),
    C('C16', '0.1u', '+3V3', 'GND', 'CL05B104KB54PNC', (71.12, 109.22, 0), mfr='Samsung', lcsc='C307331', desc='X7R 50V'),

    # ---------------- MagJack / TVS / centre taps ----------------
    dict(ref='J2', sym='pmod_100base_tx:RJ45_Hanrun_HR911105A_Horizontal', value='HR911105A',
         fp='Connector_RJ:RJ45_Hanrun_HR911105A_Horizontal',
         pins={'1': 'TD_P', '2': 'TD_N', '3': 'RD_P', '4': 'TCT', '5': 'RCT', '6': 'RD_N',
               '7': None, '8': 'GND', '9': None, '10': None, '11': None, '12': None, 'SH': 'GND'},
         mpn='HR911105A', mfr='HanRun', lcsc='C12074', dnp=False,
         desc='RJ45 MagJack 10/100, 1:1 magnetics with CT, Bob Smith 75R+1nF/2kV integrated (pin 8), LEDs unused',
         sch=(345.44, 88.9, 0)),
    dict(ref='U1', sym='pmod_100base_tx:TPD4E02B04DQA', value='TPD4E02B04',
         fp='Package_SON:USON-10_2.5x1.0mm_P0.5mm',
         pins={'1': 'RD_N', '10': 'RD_N', '2': 'RD_P', '9': 'RD_P',
               '4': 'TD_N', '7': 'TD_N', '5': 'TD_P', '6': 'TD_P', '3': 'GND', '8': 'GND'},
         mpn='TPD4E02B04DQAR', mfr='Texas Instruments', lcsc='C106794', dnp=False,
         desc='4ch bidirectional ESD on the PHY side of the magnetics, 0.25 pF, flow-through',
         sch=(289.56, 88.9, 0)),
    C('C17', '0.1u', 'TCT', 'GND', 'CL05B104KB54PNC', (279.4, 147.32, 0), mfr='Samsung', lcsc='C307331', desc='TX centre tap AC ground (NOT to 3.3 V)'),
    C('C18', '0.1u', 'RCT', 'GND', 'CL05B104KB54PNC', (292.1, 147.32, 0), mfr='Samsung', lcsc='C307331', desc='RX centre tap AC ground (NOT to 3.3 V)'),
]

NAME = 'pmod_100base_tx_magjack'
