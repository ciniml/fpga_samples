#!/usr/bin/env python3
"""defines_gen.v for the simulation (same content as project.tcl writes, plus IDX_<ball>)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'host'))
from slogic_probe import load_pins, DRIVABLE

pinset, pull = sys.argv[1], sys.argv[2].lower()
pins = load_pins(pinset)
n = len(pins)
mask = sum(1 << p['index'] for p in pins if p['class'] in DRIVABLE)
n_io = sum(1 for p in pins if p['class'] != 'mipi')
print(f'`define PROBE_N {n}')
print(f'`define PROBE_N_IO {n_io}')
if n_io != n:
    print('`define PROBE_MIPI_DPHY')
print(f"`define PROBE_CAN_DRIVE {n}'h{mask:x}")
print(f"`define PROBE_PULL 2'd{ {'none': 0, 'up': 1, 'down': 2}[pull] }")
print(f"`define PROBE_PINSET 2'd{ {'main': 0, 'cfg': 1, 'la': 2, 'mipi': 3}[pinset] }")
for p in pins:
    print(f'`define IDX_{p["ball"]} {p["index"]}')
