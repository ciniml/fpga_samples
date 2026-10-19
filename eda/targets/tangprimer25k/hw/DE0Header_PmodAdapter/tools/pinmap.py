# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Tang Primer 25K Dock 40-pin header (J3, DE0 compatible) -> Pmod map.

Verified from the Dock schematic (Tang_Primer_25K_Dock_60033) and the
GW5A-25 MBGA121N pin data: pin 11 = +5V, 12 = GND, the other 38 are I/O.
Pins (2k-1, 2k) are true LVDS pairs (even = IOxxA = P, odd = IOxxB = N)
except 17/18 (A1/E1) and 19/20 (D1/E3).
"""
HDR = {1: 'K2', 2: 'K1', 3: 'L1', 4: 'L2', 5: 'K4', 6: 'J4', 7: 'G1', 8: 'G2', 9: 'L3', 10: 'L4',
       13: 'C2', 14: 'B2', 15: 'F1', 16: 'F2', 17: 'A1', 18: 'E1', 19: 'D1', 20: 'E3',
       21: 'J2', 22: 'J1', 23: 'H4', 24: 'G4', 25: 'H2', 26: 'H1', 27: 'J7', 28: 'K7', 29: 'L8', 30: 'L7',
       31: 'K10', 32: 'L10', 33: 'K9', 34: 'L9', 35: 'K8', 36: 'J8', 37: 'F6', 38: 'F7', 39: 'J10', 40: 'J11'}
BANK = {'K2': 2, 'K1': 2, 'L1': 2, 'L2': 2, 'K4': 2, 'J4': 2, 'G1': 2, 'G2': 2, 'L3': 2, 'L4': 2, 'C2': 5, 'B2': 5,
        'F1': 5, 'F2': 5, 'A1': 5, 'E1': 5, 'D1': 5, 'E3': 4, 'J2': 2, 'J1': 2, 'H4': 3, 'G4': 3, 'H2': 3, 'H1': 3,
        'J7': 7, 'K7': 7, 'L8': 7, 'L7': 7, 'K10': 7, 'L10': 7, 'K9': 0, 'L9': 0, 'K8': 0, 'J8': 0, 'F6': 0, 'F7': 0,
        'J10': 7, 'J11': 7}

# (slot, column, header pin -> upper/P position, header pin -> lower/N position, kind)
# The column's "P" goes to Pmod pin col (top row), "N" to pin col+6 (bottom row).
ROUTES = [
    ('A', 1, 2, 1, 'pair'), ('A', 2, 4, 3, 'pair'), ('A', 3, 6, 5, 'pair'), ('A', 4, 8, 7, 'pair'),
    ('B', 1, 10, 9, 'pair'), ('B', 2, 14, 13, 'pair'), ('B', 3, 16, 15, 'pair'), ('B', 4, 18, 17, 'se'),
    ('C', 1, 22, 21, 'pair'), ('C', 2, 24, 23, 'pair'), ('C', 3, 26, 25, 'pair'), ('C', 4, 28, 27, 'pair'),
    ('D', 1, 30, 29, 'pair'), ('D', 2, 32, 31, 'pair'), ('D', 3, 34, 33, 'pair'), ('D', 4, 36, 35, 'pair'),
    ('X1', 1, 20, 19, 'se'),
    ('X2', 1, 38, 37, 'pair'), ('X2', 2, 40, 39, 'pair'),
]
PMODS = ['A', 'B', 'C', 'D']
SLOT_NAME = {'A': 'pmod3', 'B': 'pmod4', 'C': 'pmod5', 'D': 'pmod6'}   # Dock's own Pmods are pmod0..2


def net(slot, col, which, pin):
    """pairs: LVDS_<slot><col>_<ballP>_<ballN>_P / _N (one base name, so KiCad sees the pair);
    single-ended: IO_<slot><col><P|N>_<ball>"""
    r = [r for r in ROUTES if r[0] == slot and r[1] == col][0]
    if r[4] == 'pair':
        return f'LVDS_{slot}{col}_{HDR[r[2]]}_{HDR[r[3]]}_{which}'
    return f'IO_{slot}{col}{which}_{HDR[pin]}'


def pmod_socket_pin(pmod_pin):
    """Pmod pin (1..12) -> pin number of the 2x06 right-angle socket (KiCad Odd_Even numbering,
    as the Dock's own Pmod sockets: odd row = Pmod 1..6 (top), pin 1/2 = 3.3 V)"""
    if pmod_pin <= 6:
        return 13 - 2 * pmod_pin
    return 14 - 2 * (pmod_pin - 6)


def pmod_nets(slot):
    """Pmod pin -> net"""
    out = {5: 'GND', 11: 'GND', 6: '+3V3', 12: '+3V3'}
    for s, col, pp, pn, kind in ROUTES:
        if s == slot:
            out[col] = net(s, col, 'P', pp)
            out[col + 6] = net(s, col, 'N', pn)
    return out


def header_nets():
    out = {11: '+5V', 12: 'GND'}
    for s, col, pp, pn, kind in ROUTES:
        out[pp] = net(s, col, 'P', pp)
        out[pn] = net(s, col, 'N', pn)
    return out


# EXT1 2x2 (pin numbers of PinHeader_2x02 as placed): 1 D1, 2 +3V3, 3 E3, 4 GND
EXT1 = {1: net('X1', 1, 'N', 19), 2: '+3V3', 3: net('X1', 1, 'P', 20), 4: 'GND'}
# EXT2 2x3 rotated 90 deg: lower row 1/3/5, upper row 2/4/6
EXT2 = {1: net('X2', 1, 'P', 38), 2: net('X2', 1, 'N', 37), 3: net('X2', 2, 'P', 40), 4: net('X2', 2, 'N', 39),
        5: 'GND', 6: '+3V3'}
