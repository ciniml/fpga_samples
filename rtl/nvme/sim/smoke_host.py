#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
#
# Minimal user-space NVMe/TCP host used as a smoke test for the
# nvme_tcp_bridge before pointing SPDK at it. Speaks just enough of the
# protocol (no digests, single in-flight command per queue) to run:
# ICReq/ICResp, Fabrics Connect / Property Get/Set, Identify, and a
# Write/Read round trip over the I/O queue with the R2T flow.

import socket
import struct
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4420
SUBNQN = "nqn.2026-09.org.fugafuga:nvme:veryl-sim"
HOSTNQN = "nqn.2026-09.org.fugafuga:host:smoke"

errors = 0


def check(what, cond, detail=""):
    global errors
    if cond:
        print(f"  ok: {what}")
    else:
        print(f"  ERROR: {what} {detail}")
        errors += 1


class Queue:
    def __init__(self, qid, sqsize=31):
        self.qid = qid
        self.sqsize = sqsize
        self.cid = 0
        self.sock = socket.create_connection(("127.0.0.1", PORT))
        self.buf = b""
        # ICReq: pfv=0, hpda=0, no digests, maxr2t=0
        icreq = struct.pack("<BBBBIHBBI", 0x00, 0, 128, 0, 128, 0, 0, 0, 0)
        icreq += b"\x00" * (128 - len(icreq))
        self.sock.sendall(icreq)
        pdu = self.recv_pdu()
        assert pdu[0] == 0x01, "expected ICResp"

    def recv_pdu(self):
        while True:
            if len(self.buf) >= 8:
                plen = struct.unpack("<I", self.buf[4:8])[0]
                if len(self.buf) >= plen:
                    pdu, self.buf = self.buf[:plen], self.buf[plen:]
                    return pdu
            d = self.sock.recv(65536)
            if not d:
                raise RuntimeError("connection closed")
            self.buf += d

    def send_capsule(self, sqe):
        assert len(sqe) == 64
        hdr = struct.pack("<BBBBI", 0x04, 0, 72, 0, 72)
        self.sock.sendall(hdr + sqe)

    def send_h2c_data(self, cccid, ttag, data):
        hdr = struct.pack("<BBBBIHHII4x", 0x06, 0x04, 24, 24, 24 + len(data),
                          cccid, ttag, 0, len(data))
        self.sock.sendall(hdr + data)

    # Run one command to completion. Returns (cqe_dw0, cqe_dw1, status, c2h_data).
    def run(self, sqe, wdata=None):
        cid = struct.unpack("<H", sqe[2:4])[0]
        self.send_capsule(sqe)
        c2h = b""
        while True:
            pdu = self.recv_pdu()
            ptype = pdu[0]
            if ptype == 0x09:  # R2T
                cccid, ttag, r2to, r2tl = struct.unpack("<HHII", pdu[8:20])
                assert wdata is not None and cccid == cid
                self.send_h2c_data(cccid, ttag, wdata[r2to:r2to + r2tl])
            elif ptype == 0x07:  # C2HData
                datao, datal = struct.unpack("<II", pdu[12:20])
                pdo = pdu[3]
                c2h += pdu[pdo:pdo + datal]
            elif ptype == 0x05:  # CapsuleResp
                dw0, dw1, sqhd, _, rcid, status = struct.unpack("<IIHHHH", pdu[8:24])
                assert rcid == cid, f"cid mismatch {rcid:#x} != {cid:#x}"
                return dw0, dw1, status >> 1, c2h
            else:
                raise RuntimeError(f"unexpected PDU type {ptype:#x}")

    def next_cid(self):
        self.cid = (self.cid + 1) & 0xFFFF
        return self.cid


def sqe_base(opc, cid, nsid=0):
    sqe = bytearray(64)
    sqe[0] = opc
    struct.pack_into("<H", sqe, 2, cid)
    struct.pack_into("<I", sqe, 4, nsid)
    return sqe


def fabrics_connect(q, kato=0):
    cid = q.next_cid()
    sqe = sqe_base(0x7F, cid)
    sqe[4] = 0x01  # Connect
    struct.pack_into("<HHH", sqe, 40, 0, q.qid, q.sqsize)  # recfmt, qid, sqsize
    struct.pack_into("<I", sqe, 48, kato)
    dw0, _, status, _ = q.run(sqe)
    check(f"connect qid={q.qid}", status == 0, f"status={status:#x}")
    return dw0 & 0xFFFF  # cntlid


def prop_get(q, ofst, size8=False):
    cid = q.next_cid()
    sqe = sqe_base(0x7F, cid)
    sqe[4] = 0x04
    sqe[40] = 1 if size8 else 0
    struct.pack_into("<I", sqe, 44, ofst)
    dw0, dw1, status, _ = q.run(sqe)
    check(f"property get {ofst:#x}", status == 0, f"status={status:#x}")
    return dw0 | (dw1 << 32)


def prop_set(q, ofst, value):
    cid = q.next_cid()
    sqe = sqe_base(0x7F, cid)
    sqe[4] = 0x00
    struct.pack_into("<I", sqe, 44, ofst)
    struct.pack_into("<Q", sqe, 48, value)
    _, _, status, _ = q.run(sqe)
    check(f"property set {ofst:#x}", status == 0, f"status={status:#x}")


def main():
    print("== admin queue ==")
    aq = Queue(qid=0)
    cntlid = fabrics_connect(aq, kato=10000)
    check("cntlid", cntlid == 1, f"got {cntlid}")

    cap = prop_get(aq, 0x0, size8=True)
    check("CAP.MQES", (cap & 0xFFFF) == 255, f"cap={cap:#x}")
    check("CAP.CSS=NVM", (cap >> 37) & 0xFF == 1, f"cap={cap:#x}")
    vs = prop_get(aq, 0x8)
    check("VS=1.4", vs == 0x00010400, f"vs={vs:#x}")

    prop_set(aq, 0x14, 0x00460001)  # CC: IOSQES=6, IOCQES=4, EN
    csts = prop_get(aq, 0x1C)
    check("CSTS.RDY", csts & 1, f"csts={csts:#x}")

    print("== identify ==")
    cid = aq.next_cid()
    sqe = sqe_base(0x06, cid)
    struct.pack_into("<I", sqe, 40, 0x01)  # CNS=controller
    _, _, status, data = aq.run(sqe)
    check("identify ctrl status", status == 0, f"{status:#x}")
    check("identify ctrl length", len(data) == 4096, f"{len(data)}")
    sn = data[4:24].decode().strip()
    mn = data[24:64].decode().strip()
    check("SN", sn == "VERYL-NVME-0001", f"got '{sn}'")
    check("MN", mn == "Veryl NVMe Sample Controller", f"got '{mn}'")
    subnqn = data[768:1024].split(b"\x00")[0].decode()
    check("SUBNQN", subnqn == SUBNQN, f"got '{subnqn}'")
    check("SGLS", struct.unpack("<I", data[536:540])[0] == 0x00300001)
    check("IOCCSZ", struct.unpack("<I", data[1792:1796])[0] == 4)

    cid = aq.next_cid()
    sqe = sqe_base(0x06, cid, nsid=1)
    struct.pack_into("<I", sqe, 40, 0x00)  # CNS=namespace
    _, _, status, data = aq.run(sqe)
    check("identify ns status", status == 0, f"{status:#x}")
    nsze = struct.unpack("<Q", data[0:8])[0]
    print(f"  namespace size: {nsze} blocks ({nsze * 512 // 1024} KiB)")
    check("NSZE nonzero", nsze > 0)
    check("LBADS=9", data[130] == 9, f"got {data[130]}")

    print("== I/O queue ==")
    ioq = Queue(qid=1)
    fabrics_connect(ioq)

    wdata = bytes((i * 7 + b) & 0xFF for b in range(2) for i in range(1024))  # 2KiB
    nlb = len(wdata) // 512 - 1
    cid = ioq.next_cid()
    sqe = sqe_base(0x01, cid, nsid=1)  # Write, SLBA=5
    struct.pack_into("<QI", sqe, 40, 5, nlb)
    _, _, status, _ = ioq.run(sqe, wdata=wdata)
    check("write status", status == 0, f"{status:#x}")

    cid = ioq.next_cid()
    sqe = sqe_base(0x02, cid, nsid=1)  # Read, SLBA=5
    struct.pack_into("<QI", sqe, 40, 5, nlb)
    _, _, status, rdata = ioq.run(sqe)
    check("read status", status == 0, f"{status:#x}")
    check("read data", rdata == wdata, f"len={len(rdata)}")

    cid = ioq.next_cid()
    sqe = sqe_base(0x02, cid, nsid=1)  # Read out of range
    struct.pack_into("<QI", sqe, 40, nsze - 1, 1)
    _, _, status, _ = ioq.run(sqe)
    check("out-of-range status", status == 0x4080, f"{status:#x}")

    cid = ioq.next_cid()
    _, _, status, _ = ioq.run(sqe_base(0x00, cid, nsid=1))  # Flush
    check("flush status", status == 0, f"{status:#x}")

    if errors:
        print(f"FAIL: {errors} errors")
        sys.exit(1)
    print("PASS: smoke_host")


if __name__ == "__main__":
    main()
