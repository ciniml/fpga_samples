#!/usr/bin/env python3
"""Long-run bulk soak: repeats concurrent EP1 OUT/IN streams and records
throughput, data mismatches, USB errors, the device's rxerr/reset counters
(UART status frame) and kernel USB messages.

  usb_soak.py [--minutes 30] [--bytes 33554432] [-p /dev/ttyUSB1] [--log soak.log]
"""
import argparse, os, subprocess, threading, time, serial, usb.core

def status(port):
    try:
        with serial.Serial(port, 115200, timeout=0.05) as s:
            while s.read(4096): pass
            s.timeout = 0.5; buf = s.read(64)
        i = buf.find(b"U")
        if i < 0 or len(buf) < i + 10: return None
        f = buf[i:i+10]
        return dict(hs=(f[1] >> 2) & 1, cfg=(f[1] >> 3) & 1, addr=f[2], resets=f[5], rxerr=f[6], sofs=f[7] | f[8] << 8)
    except Exception as e:
        return None

def stream(dev, total, chunk=16384):
    data = os.urandom(total); err = []
    def writer():
        try:
            for i in range(0, total, chunk): dev.write(0x01, data[i:i+chunk], timeout=5000)
        except Exception as e: err.append(f"write: {e}")
    th = threading.Thread(target=writer); th.start(); got = bytearray(); t0 = time.time()
    try:
        while len(got) < total: got += dev.read(0x81, chunk, timeout=5000)
    except Exception as e: err.append(f"read: {e}")
    th.join(); dt = time.time() - t0
    return len(got), dt, bytes(got) == data, err

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=30); ap.add_argument("--bytes", type=int, default=32 * 1024 * 1024)
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1"); ap.add_argument("--log", default="soak.log")
    a = ap.parse_args()
    log = open(a.log, "a")
    def out(msg):
        line = f"{time.strftime('%H:%M:%S')} {msg}"; print(line, flush=True); log.write(line + "\n"); log.flush()
    t_end = time.time() + a.minutes * 60; it = 0; total_bytes = 0; mismatches = 0; usb_errors = 0
    st0 = status(a.port); out(f"start: status={st0}")
    dev = None
    while time.time() < t_end:
        if dev is None:
            dev = usb.core.find(idVendor=0x1209, idProduct=0x0001)
            if dev is None: out("device not found; waiting"); time.sleep(2); usb_errors += 1; continue
        n, dt, ok, err = stream(dev, a.bytes); it += 1; total_bytes += n
        if err:                       # drop the handle so a re-enumerated device is picked up again
            usb.util.dispose_resources(dev); dev = None; time.sleep(1)
        if not ok: mismatches += 1
        if err: usb_errors += 1
        st = status(a.port)
        out(f"iter {it}: {n/1e6:.1f} MB in {dt:.2f} s ({n/dt/1e6:.1f} MB/s each way) data={'OK' if ok else 'MISMATCH'} err={err} "
            f"total={total_bytes/1e6:.0f} MB mismatches={mismatches} usb_errors={usb_errors} status={st}")
    k = subprocess.run("journalctl -k --since '-%d min' --no-pager 2>/dev/null | grep -ci 'usb 1-1.4'" % int(a.minutes + 1), shell=True, capture_output=True, text=True)
    out(f"done: {it} iterations, {total_bytes/1e6:.0f} MB each way, mismatches={mismatches}, usb_errors={usb_errors}, kernel usb 1-1.4 lines={k.stdout.strip()}")

if __name__ == "__main__":
    main()
