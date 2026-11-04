#!/usr/bin/env python3
# Read the status of ethernet_hub75 (UDP 10006, see the DK_LED-RXCARD top).
#   fbstat.py [board ip] [local ip]
import socket, sys


def query(board="192.168.10.2", local="192.168.10.1", timeout=1.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((local, 0))
    s.settimeout(timeout)
    s.sendto(b"\0", (board, 10006))
    d, _ = s.recvfrom(128)
    if len(d) < 48 or d[0] != 0xD2:
        raise ValueError("unexpected reply: " + d.hex())
    be = lambda a, b: int.from_bytes(d[a:b], "big")
    return {
        "lock": d[1] & 1, "init": d[1] >> 1 & 1, "cal_ok": d[1] >> 2 & 1, "cal_fail": d[1] >> 3 & 1,
        "ready": d[1] >> 4 & 1, "ddr": d[1] >> 5 & 1, "ovr": d[1] >> 6 & 1,
        "lat": d[2], "sel": d[3] & 15, "sel_odd": d[3] >> 4,
        "errors": be(4, 6), "first": be(6, 9), "speed": d[9] & 3, "lost": be(10, 12), "flips": be(12, 16),
        "pass": [be(16, 18), be(18, 20), be(20, 22)],
        "ovr_sel": d[22] & 15, "ovr_sel_odd": d[22] >> 4, "ovr_lat": d[23] & 15,
        "mask": be(24, 40), "runs": be(40, 44),
    }


def mask_text(m):
    # beat b = bits 16b +: 16 (DQ15..0)
    return " ".join("b%d:%04x" % (b, m >> (16 * b) & 0xFFFF) for b in range(8))


if __name__ == "__main__":
    board = sys.argv[1] if len(sys.argv) > 1 else "192.168.10.2"
    local = sys.argv[2] if len(sys.argv) > 2 else "192.168.10.1"
    try:
        st = query(board, local)
    except socket.timeout:
        sys.exit("no reply")
    yn = lambda v: "yes" if v else "no"
    print("PLL locked        ", yn(st["lock"]))
    print("DDR2 build        ", yn(st["ddr"]))
    print("DDR2 initialised  ", yn(st["init"]))
    print("calibrated        ", yn(st["cal_ok"]), "(failed)" if st["cal_fail"] else "")
    print("frame buffer ready", yn(st["ready"]))
    print("RD_LAT / RD_SEL   ", st["lat"], "/", st["sel"], "(odd", st["sel_odd"], ")")
    if st["ovr"]:
        print("override          ", st["ovr_lat"], "/", st["ovr_sel"], "(odd", st["ovr_sel_odd"], ")")
    print("memory test errors", st["errors"], "first at burst 0x%06x" % st["first"] if st["errors"] else "")
    print("  per pass R0 R1 R2", *st["pass"])
    if st["mask"]:
        print("  wrong bits      ", mask_text(st["mask"]))
    print("memory test runs  ", st["runs"])
    print("link              ", ["10M", "100M", "1000M", "?"][st["speed"]])
    print("video words lost  ", st["lost"])
    print("frames shown      ", st["flips"])
