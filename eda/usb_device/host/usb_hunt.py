#!/usr/bin/env python3
"""Hunt for silent data corruption: stream the EP1 loopback (one 32 MB random
buffer per iteration, writer thread, reader accumulating), compare every
16 KB as soon as it is back, and on the first mismatch immediately stop the
device's packet log (armed all along, 'L' / 'D'), quiesce both directions and
compare the host's byte sums with the device's FIFO checksums (vendor
request) to tell on which side the data changed.

  usb_hunt.py [-p /dev/ttyUSB1] [--minutes 30] [--out hunt.bin]
  usb_log.py --decode hunt.bin      # transactions around the event
"""
import argparse, os, sys, time, threading, serial, usb.core

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1"); ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--out", default="hunt.bin"); ap.add_argument("--total", type=int, default=32 * 1024 * 1024)
    ap.add_argument("--no-sums", action="store_true", help="skip the vendor checksum requests (experiment)")
    ap.add_argument("--no-log", action="store_true", help="do not use the UART packet log (debugger port unavailable)")
    a = ap.parse_args(); chunk = 16384
    dev = usb.core.find(idVendor=0x1209, idProduct=0x0001)
    while True:                                                    # leftovers of an aborted run
        try: dev.read(0x81, chunk, timeout=200)
        except usb.core.USBError: break
    def vs(sel):                                                   # device FIFO checksums (16-bit sums of committed bytes)
        dev.ctrl_transfer(0x40, 0x02, sel, 0, b""); st = bytes(dev.ctrl_transfer(0xC0, 0x01, 0, 0, 4)); return st[0] | st[1] << 8
    class NoSerial:
        def write(self, *_): pass
        def read(self, *_): return b""
        def close(self): pass
    s = NoSerial() if a.no_log else serial.Serial(a.port, 115200, timeout=0.05)
    if not a.no_log:
        while s.read(4096): pass
        for attempt in range(3):                                   # arm the packet log; a leading 0 completes a half-received command
            s.write(b"\x00L"); time.sleep(0.3)
            buf = s.read(64); i = buf.find(b"U")
            if i >= 0 and len(buf) >= i + 10 and (buf[i+9] & 3) == 1: break
        else:
            raise SystemExit("could not arm the packet log")
    w0, r0 = (0, 0) if a.no_sums else (vs(2), vs(1)); sum_sent = sum_got = 0; sum_got_bytes = 0
    t_end = time.time() + a.minutes * 60; it = 0; tot = 0; t0 = time.time(); event = None
    while time.time() < t_end and event is None:
        data = os.urandom(a.total); err = []; wdone = [0]
        def writer():
            try:
                for i in range(0, a.total, chunk):
                    if event is not None: break
                    dev.write(0x01, data[i:i+chunk], timeout=5000); wdone[0] = i + chunk
            except Exception as e: err.append(f"write: {e}")
        th = threading.Thread(target=writer); th.start(); got = bytearray(); checked = 0
        try:
            while len(got) < a.total:
                got += dev.read(0x81, chunk, timeout=5000)
                while checked + chunk <= len(got):
                    if got[checked:checked+chunk] != data[checked:checked+chunk]:
                        s.write(b"D"); event = ("mismatch", checked); break
                    checked += chunk
                if event: break
        except Exception as e:
            s.write(b"D"); event = ("error", str(e)); err.append(f"read: {e}")
        if event is None:
            th.join(); it += 1; tot += a.total; sum_sent = (sum_sent + sum(data)) & 0xffff; sum_got = (sum_got + sum(got)) & 0xffff; sum_got_bytes += len(got)
            if err: s.write(b"D"); event = ("error", err); break
            if it % 10 == 0: print(f"{tot/1e6:.0f} MB ok ({tot/(time.time()-t0)/1e6:.1f} MB/s)", flush=True)
    if event is None:
        print(f"no event in {tot/1e6:.0f} MB"); s.write(b"D"); s.close(); return
    # ---- report ----
    kind, info = event
    if kind == "mismatch":
        diffs = [i for i in range(info, info + chunk) if got[i] != data[i]]
        sh = [512*k for k in range(-8, 9) if k and 0 <= diffs[0]+512*k and data[diffs[0]+512*k:diffs[0]+512*k+256] == bytes(got[diffs[0]:diffs[0]+256])]
        print(f"MISMATCH after {tot/1e6:.0f} MB + {info/1e6:.1f} MB: {len(diffs)} bytes differ in the 16 KB chunk, first at {diffs[0]} "
              f"(packet {diffs[0]//512}, byte {diffs[0]%512}): data {data[diffs[0]]:02x} got {got[diffs[0]]:02x}; shift candidates {sh}")
        open(a.out + ".data", "wb").write(data[info:info+chunk] + bytes(got[info:info+chunk]))   # 16 KB sent + 16 KB received
    else:
        print(f"ERROR after {tot/1e6:.0f} MB: {info}")
    # the packet log: it streams right after the 'D' that stopped it, so read it before anything else touches the port
    if not a.no_log: s.timeout = 3
    raw = b""
    while len(raw) < 8192 * 6:
        c = s.read(8192 * 6 - len(raw))
        if not c: break
        raw += c
    s.close(); open(a.out, "wb").write(raw)
    print(f"log dumped to {a.out} ({len(raw)//6} words); decode with: usb_log.py --decode {a.out}")
    # quiesce: keep draining while the writer finishes its chunk, then drain the rest
    tail = bytearray()
    while th.is_alive():
        try: tail += dev.read(0x81, chunk, timeout=300)
        except usb.core.USBError: pass
    while True:
        try: tail += dev.read(0x81, chunk, timeout=300)
        except usb.core.USBError: break
    try:
        if a.no_sums: raise RuntimeError("sums disabled")
        dw, dr = vs(2), vs(1); ac, ra = vs(4), vs(8); ac2, ra2 = vs(4), vs(8)
        if (ac, ra) != (ac2, ra2): print(f"  (counters still moving: {ac:04x}/{ra:04x} -> {ac2:04x}/{ra2:04x})")
        hs = (sum_sent + sum(data[:wdone[0]]) + w0) & 0xffff; hg = (sum_got + sum(got) + sum(tail) + r0) & 0xffff
        print(f"sums after quiescing ({wdone[0]/1e6:.2f} MB written, {len(got)+len(tail)} B received this iteration): "
              f"host sent {hs:04x} | device committed {dw:04x} | device sent&ACKed {dr:04x} | host received {hg:04x}")
        print("  OUT side (host sent vs device committed):", "OK" if hs == dw else "DIFFERS")
        print("  FIFO (committed vs sent&ACKed):", "OK" if dw == dr else "DIFFERS")
        print("  IN side (device sent&ACKed vs host received):", "OK" if dr == hg else "DIFFERS")
        rx_bytes = sum_got_bytes + len(got) + len(tail)
        print(f"  device: {ac} ACKs taken, rd_ptr advanced {ra} B (mod 64K); host received {rx_bytes} B = {rx_bytes//512} packets "
              f"({rx_bytes & 0xffff:04x} mod 64K) -> {'device skipped data' if (ra - rx_bytes) & 0xffff and (ac - rx_bytes//512) & 0xffff == 0 else 'host dropped ACKed packets' if (ac - rx_bytes//512) & 0xffff else 'consistent'}")
    except Exception as e: print("checksum read failed:", e)

if __name__ == "__main__":
    main()
