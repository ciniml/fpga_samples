#!/usr/bin/env python3
# Sweep the DDR2 read capture of ethernet_hub75 (DK_LED-RXCARD, HUB75_IMPL=ddr):
# for every RD_LAT / RD_SEL the read capture is overridden (UDP 10007) and
# the 32 MB memory test run again; the words wrong per pass are printed.
#   ddr2sweep.py [lat_min lat_max]
# By default RD_SEL_ODD = RD_SEL + 2 (the usual relation); the memory test
# also clears the frame buffer, so the panels go black. At the end the
# override is switched off again (calibrated values, one more test run).
import socket, sys, time
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from fbstat import query, mask_text

BOARD, LOCAL = "192.168.10.2", "192.168.10.1"
args = sys.argv[1:]
lat_min = int(args[0]) if len(args) > 0 else 9
lat_max = int(args[1]) if len(args) > 1 else 13

ctl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
ctl.bind((LOCAL, 0))


def run(cmd):
    before = query(BOARD, LOCAL)["runs"]
    ctl.sendto(bytes(cmd), (BOARD, 10007))
    t0 = time.time()
    while time.time() - t0 < 5:
        time.sleep(0.1)
        try:
            st = query(BOARD, LOCAL)
        except socket.timeout:
            continue
        if st["runs"] != before and st["ready"]:
            return st
    raise RuntimeError("memory test did not finish")


st = query(BOARD, LOCAL)
print("calibrated: RD_LAT %d RD_SEL %d / %d" % (st["lat"], st["sel"], st["sel_odd"]))
print("lat sel odd   R0     R1     R2")
for lat in range(lat_min, lat_max + 1):
    for sel in range(0, 10):
        odd = min(sel + 2, 9)
        st = run([1, sel, odd, lat])
        p = st["pass"]
        line = "%3d %3d %3d %6d %6d %6d" % (lat, sel, odd, *p)
        if 0 < sum(p) < 65535 * 3:
            line += "   " + mask_text(st["mask"])
        print(line, flush=True)
st = run([2])
print("override off: errors per pass", *st["pass"])
