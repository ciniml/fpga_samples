#!/usr/bin/env python3
"""Concurrent bulk OUT/IN streaming through the EP1 loopback: usb_stream.py [bytes]"""
import os, sys, time, threading, usb.core
dev = usb.core.find(idVendor=0x1209, idProduct=0x0001)
total = int(sys.argv[1]) if len(sys.argv) > 1 else 8*1024*1024
chunk = 16384
data = os.urandom(total)
err = []
def writer():
    try:
        for i in range(0, total, chunk): dev.write(0x01, data[i:i+chunk], timeout=5000)
    except Exception as e: err.append(f"write: {e}")
t0 = time.time(); th = threading.Thread(target=writer); th.start()
got = bytearray()
try:
    while len(got) < total:
        got += dev.read(0x81, chunk, timeout=5000)
except Exception as e: err.append(f"read: {e}")
th.join(); dt = time.time() - t0
ok = bytes(got) == data
print(f"streamed {len(got)}/{total} bytes in {dt:.2f} s = {len(got)/dt/1e6:.2f} MB/s each way, data {'OK' if ok else 'MISMATCH'}", err)
