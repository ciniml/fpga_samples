"""Single source of truth for the Pmod 100BASE-TX direct-attach board.

Circuit = eda/pmod_100base_tx/README.md section 3 / 4 / 7.
Each part: ref, symbol (lib_id), value, footprint, pin->net map, MPN, Manufacturer,
dnp flag, schematic placement (x, y, rot) on an A3 sheet.
"""

R0402 = 'Resistor_SMD:R_0402_1005Metric'
C0402 = 'Capacitor_SMD:C_0402_1005Metric'
C0603 = 'Capacitor_SMD:C_0603_1608Metric'
C1206 = 'Capacitor_SMD:C_1206_3216Metric'

RS = 'Device:R_Small'
CS = 'Device:C_Small'


def R(ref, val, n1, n2, mpn, sch, fp=R0402, mfr='Yageo', dnp=False, desc=''):
    return dict(ref=ref, sym=RS, value=val, fp=fp, pins={'1': n1, '2': n2},
                mpn=mpn, mfr=mfr, dnp=dnp, desc=desc, sch=sch)


def C(ref, val, n1, n2, mpn, sch, fp=C0402, mfr='Murata', dnp=False, desc=''):
    return dict(ref=ref, sym=CS, value=val, fp=fp, pins={'1': n1, '2': n2},
                mpn=mpn, mfr=mfr, dnp=dnp, desc=desc, sch=sch)


PARTS = [
    # ---------------- Pmod header (peripheral side, male right angle) ----------------
    dict(ref='J1', sym='pmod_100base_tx:Conn_02x06_Top_Bottom', value='Pmod 2x6 R/A male',
         fp='pmod_100base_tx:Pmod_Peripheral_2x06_P2.54mm_Horizontal',
         pins={'1': 'A_P', '2': 'B_P', '3': 'PWM_A', '4': 'TX_P', '5': 'GND', '6': '+3V3',
               '7': 'A_N', '8': 'B_N', '9': 'PWM_B', '10': 'TX_N', '11': 'GND', '12': '+3V3'},
         mpn='TSW-106-08-G-D-RA', mfr='Samtec', dnp=False,
         desc='Pmod peripheral plug, 2x6 2.54mm right angle male, Type 1-6 top / 7-12 bottom',
         sch=(63.5, 73.66, 0)),

    # ---------------- TX: Rs / Rp / Cr / CMC (+0R bypass) / series C ----------------
    R('R1', '62', 'TX_P', 'TXP_DRV', 'RC0402FR-0762RL', (45.72, 139.7, 90), desc='Rs, tune for 0.95-1.05 V diff'),
    R('R2', '62', 'TX_N', 'TXN_DRV', 'RC0402FR-0762RL', (45.72, 172.72, 90), desc='Rs, tune for 0.95-1.05 V diff'),
    R('R3', '120', 'TXP_DRV', 'GND', 'RC0402FR-07120RL', (60.96, 147.32, 0), desc='Rp'),
    R('R4', '120', 'TXN_DRV', 'GND', 'RC0402FR-07120RL', (60.96, 180.34, 0), desc='Rp'),
    C('C1', '47p', 'TXP_DRV', 'GND', 'GRM1555C1H470JA01D', (71.12, 147.32, 0), desc='Cr C0G 50V, edge rate tune'),
    C('C2', '47p', 'TXN_DRV', 'GND', 'GRM1555C1H470JA01D', (71.12, 180.34, 0), desc='Cr C0G 50V, edge rate tune'),
    dict(ref='L1', sym='pmod_100base_tx:Filter_EMI_CommonMode', value='CMC 90R@100MHz',
         fp='pmod_100base_tx:L_CommonModeChoke_2012Metric_FlowThrough',
         pins={'1': 'TXP_DRV', '2': 'TXP_C', '3': 'TXN_DRV', '4': 'TXN_C'},
         mpn='ACM2012-900-2P-T002', mfr='TDK', dnp=True,
         desc='Optional TX CMC (DNP in first build, R5/R6 0R fitted instead)',
         sch=(96.52, 157.48, 0)),
    R('R5', '0', 'TXP_DRV', 'TXP_C', 'RC0402JR-070RL', (96.52, 139.7, 90), desc='CMC bypass (remove when L1 fitted)'),
    R('R6', '0', 'TXN_DRV', 'TXN_C', 'RC0402JR-070RL', (96.52, 172.72, 90), desc='CMC bypass (remove when L1 fitted)'),
    C('C3', '0.1u/100V', 'TXP_C', 'TD_P', 'GRM188R72A104KA35D', (119.38, 139.7, 90), fp=C0603, desc='TX series C, X7R 100V'),
    C('C4', '0.1u/100V', 'TXN_C', 'TD_N', 'GRM188R72A104KA35D', (119.38, 172.72, 90), fp=C0603, desc='TX series C, X7R 100V'),

    # ---------------- RX: termination + taps ----------------
    R('R7', '49.9', 'RD_P', 'RD_CT', 'RC0402FR-0749R9L', (181.61, 50.8, 0), desc='RX termination'),
    R('R8', '49.9', 'RD_CT', 'RD_N', 'RC0402FR-0749R9L', (181.61, 73.66, 0), desc='RX termination'),
    C('C5', '10n/100V', 'RD_CT', 'GND', 'GRM188R72A103KA01D', (194.31, 73.66, 0), fp=C0603, desc='Ct termination midpoint, X7R 100V'),
    C('C6', '0.1u/100V', 'RD_P', 'A_P', 'GRM188R72A104KA35D', (163.83, 88.9, 90), fp=C0603, desc='Ca tap'),
    C('C7', '0.1u/100V', 'RD_N', 'A_N', 'GRM188R72A104KA35D', (163.83, 101.6, 90), fp=C0603, desc='Ca tap'),
    C('C8', '0.1u/100V', 'RD_P', 'B_P', 'GRM188R72A104KA35D', (163.83, 114.3, 90), fp=C0603, desc='Ca tap'),
    C('C9', '0.1u/100V', 'RD_N', 'B_N', 'GRM188R72A104KA35D', (163.83, 127.0, 90), fp=C0603, desc='Ca tap'),
    R('R9', '2.2k', 'A_P', 'VB', 'RC0402FR-072K2L', (191.77, 88.9, 90), desc='Rb'),
    R('R10', '2.2k', 'A_N', 'VTH_A', 'RC0402FR-072K2L', (191.77, 101.6, 90), desc='Rb'),
    R('R11', '2.2k', 'B_P', 'VTH_B', 'RC0402FR-072K2L', (191.77, 114.3, 90), desc='Rb'),
    R('R12', '2.2k', 'B_N', 'VB', 'RC0402FR-072K2L', (191.77, 127.0, 90), desc='Rb'),

    # ---------------- Bias: VB and VTH_A / VTH_B ----------------
    R('R13', '270', '+3V3', 'VB', 'RC0402FR-07270RL', (162.56, 157.48, 0), desc='VB divider (1.32 V)'),
    R('R14', '180', 'VB', 'GND', 'RC0402FR-07180RL', (162.56, 177.8, 0), desc='VB divider'),
    C('C10', '10u', 'VB', 'GND', 'GRM188R61A106KE69D', (175.26, 177.8, 0), fp=C0603, desc='X5R 10V'),
    C('C11', '0.1u', 'VB', 'GND', 'GRM155R71C104KA88D', (185.42, 177.8, 0), desc='X7R 16V'),
    R('R15', '3.3k', 'PWM_A', 'VTH_A', 'RC0402FR-073K3L', (212.09, 154.94, 90), desc='PWM filter (2.7k widens range)'),
    R('R16', '1k', 'VTH_A', 'VB', 'RC0402FR-071KL', (236.22, 154.94, 90), desc='PWM filter'),
    C('C12', '1u', 'VTH_A', 'GND', 'GRM155R61A105KE15D', (222.25, 162.56, 0), desc='X5R 10V'),
    R('R17', '3.3k', 'PWM_B', 'VTH_B', 'RC0402FR-073K3L', (212.09, 177.8, 90), desc='PWM filter (2.7k widens range)'),
    R('R18', '1k', 'VTH_B', 'VB', 'RC0402FR-071KL', (236.22, 177.8, 90), desc='PWM filter'),
    C('C13', '1u', 'VTH_B', 'GND', 'GRM155R61A105KE15D', (222.25, 185.42, 0), desc='X5R 10V'),

    # ---------------- 3.3 V decoupling ----------------
    C('C14', '10u', '+3V3', 'GND', 'GRM188R61A106KE69D', (50.8, 109.22, 0), fp=C0603, desc='X5R 10V'),
    C('C15', '0.1u', '+3V3', 'GND', 'GRM155R71C104KA88D', (60.96, 109.22, 0), desc='X7R 16V'),
    C('C16', '0.1u', '+3V3', 'GND', 'GRM155R71C104KA88D', (71.12, 109.22, 0), desc='X7R 16V'),

    # ---------------- RJ45 / TVS / Bob Smith ----------------
    dict(ref='J2', sym='pmod_100base_tx:RJ45_Shielded', value='RJ45 8P8C no magnetics',
         fp='Connector_RJ:RJ45_Amphenol_RJHSE5380',
         pins={'1': 'TD_P', '2': 'TD_N', '3': 'RD_P', '4': 'BS_4', '5': 'BS_5', '6': 'RD_N',
               '7': 'BS_7', '8': 'BS_8', 'SH': 'GND'},
         mpn='RJHSE-5380', mfr='Amphenol ICC', dnp=False,
         desc='Shielded 8P8C, no magnetics, no LED, THT right angle',
         sch=(340.36, 88.9, 0)),
    dict(ref='U1', sym='pmod_100base_tx:TPD4E02B04DQA', value='TPD4E02B04',
         fp='Package_SON:USON-10_2.5x1.0mm_P0.5mm',
         pins={'1': 'RD_P', '10': 'RD_P', '2': 'RD_N', '9': 'RD_N',
               '4': 'TD_P', '7': 'TD_P', '5': 'TD_N', '6': 'TD_N', '3': 'GND', '8': 'GND'},
         mpn='TPD4E02B04DQAR', mfr='Texas Instruments', dnp=False,
         desc='4ch bidirectional ESD, 0.25 pF, +/-3.6 V, flow-through (NC pads carry the line)',
         sch=(289.56, 88.9, 0)),
    R('R19', '75', 'BS_4', 'BS_MID', 'RC0402FR-0775RL', (299.72, 147.32, 0), desc='Bob Smith (optional)'),
    R('R20', '75', 'BS_5', 'BS_MID', 'RC0402FR-0775RL', (309.88, 147.32, 0), desc='Bob Smith (optional)'),
    R('R21', '75', 'BS_7', 'BS_MID', 'RC0402FR-0775RL', (320.04, 147.32, 0), desc='Bob Smith (optional)'),
    R('R22', '75', 'BS_8', 'BS_MID', 'RC0402FR-0775RL', (330.2, 147.32, 0), desc='Bob Smith (optional)'),
    # line-side discharge resistors (DC reference for the floating line nodes)
    R('R23', '1M', 'TD_P', 'GND', 'RC0402FR-071ML', (127.0, 195.58, 0), desc='Line-side bleed to GND'),
    R('R24', '1M', 'TD_N', 'GND', 'RC0402FR-071ML', (137.16, 195.58, 0), desc='Line-side bleed to GND'),
    R('R25', '1M', 'RD_P', 'GND', 'RC0402FR-071ML', (147.32, 195.58, 0), desc='Line-side bleed to GND'),
    R('R26', '1M', 'RD_N', 'GND', 'RC0402FR-071ML', (157.48, 195.58, 0), desc='Line-side bleed to GND'),
    C('C17', '1n/2kV', 'BS_MID', 'GND', 'C1206C102KGRACTU', (342.9, 160.02, 0), fp=C1206, mfr='KEMET',
      desc='Bob Smith cap, X7R 2kV (optional)'),
]
