#!/usr/bin/env python3
# Data-path probe: write/read patterns of several sizes at several LBAs
# over NVMe/TCP and list every mismatch (offset, expected, got).
import struct, sys, random
sys.argv = ["smoke_host.py", "4420", sys.argv[1] if len(sys.argv) > 1 else "192.168.37.2"]
import smoke_host as sh

aq = sh.Queue(qid=0)
sh.fabrics_connect(aq, kato=10000)
sh.prop_set(aq, 0x14, 0x00460001)
ioq = sh.Queue(qid=1)
sh.fabrics_connect(ioq)

def xfer(opc, lba, data=None, nbytes=None):
    n = len(data) if data is not None else nbytes
    cid = ioq.next_cid()
    sqe = sh.sqe_base(opc, cid, nsid=1)
    struct.pack_into("<QI", sqe, 40, lba, n // 512 - 1)
    _, _, status, rdata = ioq.run(sqe, wdata=data)
    return status, rdata

random.seed(1)
patterns = {
    "inc":   lambda n: bytes(i & 0xFF for i in range(n)),
    "smoke": lambda n: bytes((i * 7 + b) & 0xFF for b in range(n // 1024) for i in range(1024)),
    "ff":    lambda n: b"\xff" * n,
    "00":    lambda n: b"\x00" * n,
    "55aa":  lambda n: bytes(0x55 if i & 1 else 0xAA for i in range(n)),
    "rand":  lambda n: bytes(random.getrandbits(8) for _ in range(n)),
}
total = 0
for name, gen in patterns.items():
    for size in (2048, 4096):
        for lba in (5, 0, 1000):
            wd = gen(size)
            st, _ = xfer(0x01, lba, data=wd)
            st2, rd = xfer(0x02, lba, nbytes=size)
            diffs = [i for i in range(min(len(rd), len(wd))) if rd[i] != wd[i]]
            total += len(diffs)
            desc = " ".join(f"{i}:{wd[i]:02x}->{rd[i]:02x}" for i in diffs[:6])
            print(f"{name:5s} {size} lba={lba:4d} wst={st:#x} rst={st2:#x} len={len(rd)} diffs={len(diffs)} {desc}")
            if diffs:
                # stable across re-reads (write-side error) or varying (read-side)?
                again = []
                for _ in range(3):
                    _, rd2 = xfer(0x02, lba, nbytes=size)
                    again.append("same" if rd2 == rd else "differs(%d)" % sum(1 for i in range(len(rd2)) if rd2[i] != wd[i]))
                print(f"      re-reads: {again}")
print("TOTAL diffs:", total)
