#!/usr/bin/env python3
# Read the status of ethernet_hub75 (UDP 10006, see the DK_LED-RXCARD top).
#   fbstat.py [board ip] [local ip]
import socket, sys

BOARD = sys.argv[1] if len(sys.argv) > 1 else "192.168.10.2"
LOCAL = sys.argv[2] if len(sys.argv) > 2 else "192.168.10.1"

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((LOCAL, 0))
s.settimeout(1.0)
s.sendto(b"\0", (BOARD, 10006))
try:
    d, _ = s.recvfrom(64)
except socket.timeout:
    sys.exit("no reply")
if len(d) < 16 or d[0] != 0xD2:
    sys.exit("unexpected reply: " + d.hex())

f = d[1]
flag = lambda b: "yes" if f >> b & 1 else "no"
print("PLL locked        ", flag(0))
print("DDR2 build        ", flag(5))
print("DDR2 initialised  ", flag(1))
print("calibrated        ", flag(2), "(failed)" if f >> 3 & 1 else "")
print("frame buffer ready", flag(4))
print("RD_LAT / RD_SEL   ", d[2], "/", d[3] & 15, "(odd", d[3] >> 4, ")")
print("memory test errors", int.from_bytes(d[4:6], "big"),
      "first at burst 0x%06x" % int.from_bytes(d[6:9], "big") if int.from_bytes(d[4:6], "big") else "")
print("link              ", ["10M", "100M", "1000M", "?"][d[9] & 3])
print("video words lost  ", int.from_bytes(d[10:12], "big"))
print("frames shown      ", int.from_bytes(d[12:16], "big"))
