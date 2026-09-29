#!/usr/bin/env python3
"""Host transports for the trace capture command stream (S/T/A/D/?/X/... bytes in, replies out).

  UsbTransport    the USB_HOST build: EP1 OUT = commands, EP1 IN = replies (pyusb, VID 0x1209 PID 0x0001).
                  A reply "message" ends with a short packet / ZLP (the device flushes after ~1 ms idle).
  SerialTransport pyserial on the BL616 UART bridge (/dev/ttyUSB1, 115200).
  HttpTransport   util/serial_bridge (/api/xfer, /api/flush).

All three offer the serial_bridge shape: xfer({"write": [u8], "read": n, "timeout_ms": t}) ->
{"data": [u8], "timeout": bool} and flush().  Scripts call add_args(parser) / from_args(args).
"""
import time

class HttpTransport:
    def __init__(self, url):
        import json, urllib.request
        self.url, self.json, self.urllib = url, json, urllib.request
    def xfer(self, body, to=8000):
        body = dict(body); body.setdefault("timeout_ms", to)
        req = self.urllib.Request(self.url + "/api/xfer", data=self.json.dumps(body).encode(),
                                  headers={"content-type": "application/json"}, method="POST")
        return self.json.load(self.urllib.urlopen(req, timeout=body["timeout_ms"] / 1000 + 5))
    def flush(self):
        self.urllib.urlopen(self.urllib.Request(self.url + "/api/flush", data=b"{}",
                            headers={"content-type": "application/json"}, method="POST"), timeout=5).read()

class SerialTransport:
    def __init__(self, port, baud=115200):
        import serial
        self.ser = serial.Serial(port, baud, timeout=0.1)
    def xfer(self, body, to=8000):
        to = body.get("timeout_ms", to)
        if body.get("write"): self.ser.write(bytes(body["write"]))
        want, data, t0 = body.get("read", 0), b"", time.time()
        while len(data) < want and (time.time() - t0) * 1000 < to:
            data += self.ser.read(want - len(data))
        return {"data": list(data), "timeout": len(data) < want}
    def flush(self):
        self.ser.reset_input_buffer()

class UsbTransport:
    VID, PID = 0x1209, 0x0001
    def __init__(self, serial_number=None):
        import usb.core, usb.util
        self.usb = usb.core
        dev = usb.core.find(idVendor=self.VID, idProduct=self.PID, serial_number=serial_number) if serial_number \
              else usb.core.find(idVendor=self.VID, idProduct=self.PID)
        if dev is None: raise SystemExit("USB device 1209:0001 not found (USB_HOST build enumerated? udev rule?)")
        dev.set_configuration()
        self.dev, self.buf = dev, b""
        self.speed = {2: "full", 3: "high"}.get(dev.speed, str(dev.speed))
        self.flush()
    def _read_some(self, to_ms):
        try:
            return bytes(self.dev.read(0x81, 65536, timeout=max(1, int(to_ms))))
        except self.usb.USBTimeoutError:
            return b""
        except self.usb.USBError as e:   # (pyusb < 1.1 raises USBError errno 110 on timeout)
            if getattr(e, "errno", None) == 110: return b""
            raise
    def xfer(self, body, to=8000):
        to = body.get("timeout_ms", to)
        if body.get("write"): self.dev.write(0x01, bytes(body["write"]), timeout=2000)
        want, t0 = body.get("read", 0), time.time()
        while len(self.buf) < want:
            left = to - (time.time() - t0) * 1000
            if left <= 0: break
            self.buf += self._read_some(min(left, 1000))
        data, self.buf = self.buf[:want], self.buf[want:]
        return {"data": list(data), "timeout": len(data) < want}
    def flush(self):
        self.buf = b""
        for _ in range(4):
            if not self._read_some(20): break

def add_args(ap, default="http"):
    ap.add_argument("--usb", action="store_true", help="talk to the USB_HOST build over USB (pyusb)")
    ap.add_argument("--usb-serial", help="USB device serial number (several boards)")
    ap.add_argument("--url", default="http://127.0.0.1:8081", help="serial_bridge URL")
    ap.add_argument("-p", "--port", default=None, help="serial port (pyserial) instead of serial_bridge")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.set_defaults(transport_default=default)

def from_args(args):
    if getattr(args, "usb", False): return UsbTransport(getattr(args, "usb_serial", None))
    if getattr(args, "port", None): return SerialTransport(args.port, args.baud)
    if getattr(args, "transport_default", "http") == "serial": return SerialTransport("/dev/ttyUSB1", args.baud)
    return HttpTransport(args.url)
