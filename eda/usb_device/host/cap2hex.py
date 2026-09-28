#!/usr/bin/env python3
"""Convert a usb_capture.py dump (6 bytes per word) to a $readmemh file (one 48-bit word per line)."""
import sys
raw = open(sys.argv[1], "rb").read(); n = len(raw) // 6
with open(sys.argv[2], "w") as f:
    for i in range(n):
        w = raw[6*i:6*i+6]; f.write("%012x\n" % int.from_bytes(w, "little"))
print(n, "words")
