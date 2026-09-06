#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Root-less full-chain simulation host.

Talks raw Ethernet frames to eth_tap_bridge over a SOCK_SEQPACKET Unix
socket ("unix:<path>") and implements just enough ARP/IPv4/TCP (client
side: handshake, in-order receive with ACKs, segmentation to the MSS,
peer window, go-back-N retransmission after a timeout, FIN) to run
smoke_host.py against the RMII RTL without a TAP device.

    ./obj_ethnvme/eth_tap_bridge unix:/tmp/nvme_frames.sock &
    python3 sim_host.py /tmp/nvme_frames.sock
"""
import socket, struct, sys, time, threading, random, os

HOST_MAC = bytes.fromhex("0200deadbeef")
HOST_IP = bytes([192, 168, 37, 1])
DUT_IP = bytes([192, 168, 37, 2])
MSS = 1460


def csum(data):
    if len(data) & 1:
        data += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


class Link:
    """Frame transport + ARP + demux to TCP connections."""

    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        for _ in range(100):
            try:
                self.sock.connect(path)
                break
            except OSError:
                time.sleep(0.1)
        self.sock.settimeout(0.05)
        self.dut_mac = None
        self.conns = {}          # local port -> Tcp
        self.opened = []         # every Tcp created (closed after each run)
        self.lock = threading.Lock()
        self.running = True
        self.th = threading.Thread(target=self.pump, daemon=True)
        self.th.start()

    def send_frame(self, f):
        if len(f) < 60:
            f += b"\x00" * (60 - len(f))
        self.sock.send(f)

    def arp_request(self):
        f = b"\xff" * 6 + HOST_MAC + b"\x08\x06"
        f += struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1) + HOST_MAC + HOST_IP + b"\x00" * 6 + DUT_IP
        self.send_frame(f)

    def resolve(self):
        for _ in range(50):
            if self.dut_mac:
                return
            self.arp_request()
            time.sleep(0.2)
        raise RuntimeError("no ARP reply from the RTL")

    def send_ip(self, proto, payload):
        ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), random.randint(0, 0xFFFF), 0x4000, 64, proto, 0, HOST_IP, DUT_IP)
        ip = ip[:10] + struct.pack("!H", csum(ip)) + ip[12:]
        self.send_frame(self.dut_mac + HOST_MAC + b"\x08\x00" + ip + payload)

    def pump(self):
        while self.running:
            try:
                f = self.sock.recv(4096)
            except socket.timeout:
                self.tick()
                continue
            except OSError:
                return
            if len(f) < 14:
                continue
            et = struct.unpack("!H", f[12:14])[0]
            if et == 0x0806:
                op = struct.unpack("!H", f[20:22])[0]
                sha, spa, tpa = f[22:28], f[28:32], f[38:42]
                if op == 1 and tpa == HOST_IP:   # request for us -> reply
                    r = sha + HOST_MAC + b"\x08\x06" + struct.pack("!HHBBH", 1, 0x0800, 6, 4, 2) + HOST_MAC + HOST_IP + sha + spa
                    self.send_frame(r)
                    self.dut_mac = sha
                elif op == 2 and spa == DUT_IP:
                    self.dut_mac = sha
            elif et == 0x0800:
                ihl = (f[14] & 0xF) * 4
                proto = f[23]
                tot = struct.unpack("!H", f[16:18])[0]
                if proto == 6:
                    seg = f[14 + ihl:14 + tot]
                    dport = struct.unpack("!H", seg[2:4])[0]
                    with self.lock:
                        c = self.conns.get(dport)
                    if c:
                        c.on_segment(seg)
            self.tick()

    def tick(self):
        with self.lock:
            conns = list(self.conns.values())
        for c in conns:
            c.timer()


class Tcp:
    """Minimal client TCP; exposes sendall/recv/close like a socket."""

    def __init__(self, link, dport):
        self.link = link
        self.lport = random.randint(20000, 60000)
        self.dport = dport
        self.iss = random.randint(0, 0x7FFFFFFF)
        self.snd_una = self.iss
        self.snd_nxt = self.iss
        self.rcv_nxt = 0
        self.peer_win = 0
        self.state = "CLOSED"
        self.rxbuf = bytearray()
        self.txq = bytearray()     # unacknowledged + unsent data, from snd_una
        self.sent = 0              # bytes of txq already transmitted
        self.cv = threading.Condition()
        self.last_tx = time.time()
        self.retx = 0
        with link.lock:
            link.conns[self.lport] = self
            link.opened.append(self)
        self.connect()

    def seg(self, flags, payload=b"", seq=None):
        seq = self.snd_nxt if seq is None else seq
        hdr = struct.pack("!HHIIBBHHH", self.lport, self.dport, seq & 0xFFFFFFFF, self.rcv_nxt & 0xFFFFFFFF, 5 << 4, flags, 65535, 0, 0)
        pseudo = HOST_IP + DUT_IP + struct.pack("!BBH", 0, 6, len(hdr) + len(payload))
        ck = csum(pseudo + hdr + payload)
        hdr = hdr[:16] + struct.pack("!H", ck) + hdr[18:]
        self.link.send_ip(6, hdr + payload)
        self.last_tx = time.time()

    def connect(self):
        self.state = "SYN_SENT"
        self.seg(0x02)                      # SYN
        self.snd_nxt = self.iss + 1
        with self.cv:
            if not self.cv.wait_for(lambda: self.state == "ESTAB", timeout=5.0):
                raise RuntimeError("TCP connect timeout")

    def on_segment(self, s):
        sport, dport, seq, ack, off, flags, win = struct.unpack("!HHIIBBH", s[:16])
        hl = (off >> 4) * 4
        payload = s[hl:]
        with self.cv:
            self.peer_win = win
            if self.state == "SYN_SENT":
                if flags & 0x12 == 0x12:
                    self.rcv_nxt = seq + 1
                    self.snd_una = ack
                    self.state = "ESTAB"
                    self.seg(0x10)          # ACK
                    self.cv.notify_all()
                return
            if flags & 0x10:
                # ACK: drop acknowledged bytes from txq
                acked = (ack - self.snd_una) & 0xFFFFFFFF
                if 0 < acked <= len(self.txq):
                    del self.txq[:acked]
                    self.sent = max(0, self.sent - acked)
                    self.snd_una = ack
                    self.retx = 0
                    self.cv.notify_all()
            if payload:
                if seq == self.rcv_nxt:
                    self.rxbuf += payload
                    self.rcv_nxt = (self.rcv_nxt + len(payload)) & 0xFFFFFFFF
                    self.cv.notify_all()
                # ACK (also duplicate ACK for out-of-order data)
                self.seg(0x10)
            if flags & 0x01 and seq == self.rcv_nxt:   # FIN
                self.rcv_nxt = (self.rcv_nxt + 1) & 0xFFFFFFFF
                self.seg(0x10)
                self.state = "CLOSE_WAIT"
                self.cv.notify_all()
        self.push()

    def push(self):
        """Transmit queued data within the peer window, MSS at a time."""
        with self.cv:
            while self.sent < len(self.txq):
                inflight = self.sent
                room = self.peer_win - inflight
                if room <= 0:
                    break
                n = min(MSS, len(self.txq) - self.sent, room)
                chunk = bytes(self.txq[self.sent:self.sent + n])
                self.seg(0x18, chunk, seq=self.snd_una + self.sent)
                self.sent += n
                self.snd_nxt = (self.snd_una + self.sent) & 0xFFFFFFFF

    def timer(self):
        with self.cv:
            if self.sent and time.time() - self.last_tx > 0.5:
                # go-back-N: resend everything from snd_una
                self.sent = 0
                self.retx += 1
                if self.retx > 20:
                    raise RuntimeError("TCP retransmission limit")
        self.push()

    # ---- socket-like API ----
    def sendall(self, data):
        with self.cv:
            self.txq += data
        self.push()
        with self.cv:
            if not self.cv.wait_for(lambda: len(self.txq) == 0, timeout=30.0):
                raise RuntimeError("TCP send timeout (%d bytes unacked)" % len(self.txq))

    def recv(self, n):
        with self.cv:
            if not self.cv.wait_for(lambda: len(self.rxbuf) > 0 or self.state != "ESTAB", timeout=60.0):
                raise RuntimeError("TCP recv timeout")
            d = bytes(self.rxbuf[:n])
            del self.rxbuf[:n]
            return d

    def close(self):
        with self.cv:
            if self.state == "ESTAB" or self.state == "CLOSE_WAIT":
                self.seg(0x11)              # FIN|ACK
                self.snd_nxt += 1
                self.state = "FIN_WAIT"
        time.sleep(0.2)
        with self.link.lock:
            self.link.conns.pop(self.lport, None)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/nvme_frames.sock"
    link = Link(path)
    link.resolve()
    print("[sim_host] RTL MAC %s" % link.dut_mac.hex(":"))

    # run smoke_host with its sockets replaced by our TCP
    runs = int(os.environ.get("SIM_RUNS", "1"))
    sys.argv = ["smoke_host.py", "4420", "192.168.37.2"]
    import smoke_host
    smoke_host.socket.create_connection = lambda addr, *a, **k: Tcp(link, addr[1])
    try:
        for r in range(runs):
            print(f"[sim_host] run {r + 1}/{runs}")
            smoke_host.main()
            # close what the run opened (smoke_host relies on process exit)
            with link.lock:
                conns = list(link.opened); link.opened.clear()
            for c in conns:
                c.close()
            time.sleep(1.0)
    finally:
        link.running = False


if __name__ == "__main__":
    main()
