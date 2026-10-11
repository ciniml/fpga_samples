#!/usr/bin/env python3
"""SLogic16U3 pin investigation over JTAG (CMSIS-DAP v2 or FT2232 probe, pyusb only).

Method 1 -- IEEE 1149.1 SAMPLE on the running factory firmware (non-intrusive):
    detect                      IDCODE / USERCODE / status register
    status-watch                print USERCODE / STATUS on every change (MODE button, reloads)
    bsr-len                     length of the boundary-scan register under SAMPLE
    sample -n 64 -o a.json      snapshots; reports toggling / constant cells
    watch                       live list of cells that changed since start
    diff a.json b.json          cells that differ between two conditions
Method 2 -- soft boundary scan through ER1 of ../src/slogic16u3/top.v (needs SRAM load):
    load FILE.fs                gowin-prog sram (--cable dap) / openFPGALoader --write-sram
    ubs-read [--watch]          pin levels / activity / modes
    ubs-set BALL MODE           MODE = hiz | low | high | blink  (--fast, --od, --force)
    ubs-clear                   clear activity flags
    classify                    load pull-up and pull-down builds, classify every pin
    blink-scan                  blink drivable pins one by one (find LEDs / test pads)
Method 3 -- tie SAMPLE cells to balls:
    map-bsr -o bsrmap.json      drive pins via ER1 and find the BSR cells that follow
    (and sample/diff with signals applied to the LA / CK header for the input-only pins)

Only SAMPLE (0x01), IDCODE, USERCODE, STATUS, ER1/ER2 and BYPASS are ever loaded into
the IR. EXTEST and Gowin configuration opcodes are deliberately not available.
"""
import argparse, csv, json, os, random, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
PINS_CSV = os.path.join(HERE, '..', 'src', 'slogic16u3', 'pins.csv')
BUILD_DIR = os.path.join(HERE, '..', 'build')

GW5AT_15_IDCODE = 0x0001681B
IR_LEN = 8
SAFE_IR = {0x01: 'SAMPLE', 0x11: 'IDCODE', 0x13: 'USERCODE', 0x41: 'STATUS',
           0x42: 'ER1', 0x43: 'ER2', 0xFF: 'BYPASS'}

ER1_MAGIC = 0x534C5031
MODES = {'hiz': 0, 'low': 1, 'high': 2, 'blink': 3}
MODE_NAMES = {v: k for k, v in MODES.items()}
PINSETS = {0: 'main', 1: 'cfg', 2: 'la', 3: 'mipi'}
PINSET_SKIP = {'main': ('cfg', 'mipi'), 'cfg': ('la', 'mipi'), 'la': ('probe', 'mipi'), 'mipi': ('probe',)}
DRIVABLE = ('probe', 'uart_tx', 'cfg', 'mipi')

# GW5A status register bit names (from openFPGALoader src/gowin.cpp)
GW5A_STATUS = [
    "CRC Error", "Bad Command", "ID Verify Failed", "Timeout",
    "auto_boot_2nd_fail", "Memory Erase", "Preamble", "System Edit Mode",
    "Program SPI FLASH directly", "auto_boot_1st_fail",
    "Non-JTAG configuration is active", "Bypass", "i2c_sram_f",
    "Done Final", "Security Final", "encrypted_format",
    "key_right", "sspi_mode", "CRC Comparison Done", "CRC Error (2)",
    "ECC Error", "ECC Error Uncorrectable", "CMSER IDLE",
    "CPU Bus Width[0]", "CPU Bus Width[1]", "Retry sync[0]", "Retry sync[1]",
    "Decompression Failed", "OTP Reading Done", "Init Done",
    "Wakeup Done", "Auto Erase",
]


# ---------------------------------------------------------------------------- backends
# A backend executes a list of ops and returns the TDO words of the read shifts:
#   ('tms', [bits])                       clock TMS bits with TDI=0
#   ('shift', n, tdi_int, read, last_tms) clock n bits LSB first, TMS=0 except the last
#                                         bit which carries last_tms

class MpsseBackend:
    """FT2232 channel A in MPSSE mode through pyusb (no libftdi / pyftdi needed)."""

    def __init__(self, vid=0x0403, pid=0x6010, serial=None, iface=0, freq=1e6):
        import usb.core, usb.util
        self.usb, self.util = usb, usb.util
        devs = list(usb.core.find(find_all=True, idVendor=vid, idProduct=pid))
        if serial:
            devs = [d for d in devs if usb.util.get_string(d, d.iSerialNumber) == serial]
        if not devs:
            raise SystemExit(f'no {vid:04x}:{pid:04x} probe found' + (f' with serial {serial}' if serial else ''))
        if len(devs) > 1:
            raise SystemExit('several probes found; pick one with --serial')
        d = self.dev = devs[0]
        self.iface, self.index = iface, iface + 1
        self.reattach = False
        try:
            if d.is_kernel_driver_active(iface):
                d.detach_kernel_driver(iface)
                self.reattach = True
        except (NotImplementedError, usb.core.USBError):
            pass
        try:
            cfg = d.get_active_configuration()
        except usb.core.USBError:
            d.set_configuration()
            cfg = d.get_active_configuration()
        intf = cfg[(iface, 0)]
        usb.util.claim_interface(d, iface)
        is_out = lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT
        self.ep_out = usb.util.find_descriptor(intf, custom_match=is_out)
        self.ep_in = usb.util.find_descriptor(intf, custom_match=lambda e: not is_out(e))
        self.mps = self.ep_in.wMaxPacketSize
        self.rxbuf = bytearray()

        self._ctrl(0x00, 0)        # SIO reset
        self._ctrl(0x09, 2)        # latency timer 2 ms
        self._ctrl(0x0B, 0x0000)   # bitmode reset
        self._ctrl(0x0B, 0x0200)   # MPSSE
        self._ctrl(0x00, 1)        # purge RX
        self._ctrl(0x00, 2)        # purge TX
        time.sleep(0.05)
        self._drain()
        self._sync()
        is_h = d.bcdDevice >= 0x0700
        base = 30e6 if is_h else 6e6
        div = max(0, min(0xFFFF, int(round(base / freq)) - 1))
        self.freq = base / (div + 1)
        init = bytearray([0x85])                      # loopback off
        if is_h:
            init += bytes([0x8A, 0x97, 0x8D])         # /5 off, adaptive off, 3-phase off
        init += bytes([0x86, div & 0xFF, div >> 8])
        init += bytes([0x80, 0x08, 0x0B])             # TCK=0 TDI=0 TMS=1; TCK/TDI/TMS out
        self._write(init)

    def _ctrl(self, req, value):
        self.dev.ctrl_transfer(0x40, req, value, self.index, None, 1000)

    def _write(self, data):
        for i in range(0, len(data), 4096):
            self.ep_out.write(bytes(data[i:i + 4096]), 2000)

    def _read_chunk(self, timeout_ms):
        try:
            raw = bytes(self.ep_in.read(max(self.mps, 4096), timeout_ms))
        except self.usb.core.USBTimeoutError:
            return False
        for i in range(0, len(raw), self.mps):
            self.rxbuf += raw[i + 2:i + self.mps]     # each packet starts with 2 status bytes
        return True

    def _drain(self):
        while self._read_chunk(20) and self.rxbuf:
            self.rxbuf.clear()
        self.rxbuf.clear()

    def _read(self, n, timeout=3.0):
        t_end = time.time() + timeout
        while len(self.rxbuf) < n:
            if time.time() > t_end:
                raise IOError(f'MPSSE read timeout ({len(self.rxbuf)}/{n} bytes)')
            self._read_chunk(100)
        out = bytes(self.rxbuf[:n])
        del self.rxbuf[:n]
        return out

    def _sync(self):
        self._write(bytes([0xAA, 0x87]))
        try:
            r = self._read(2, 1.0)
        except IOError:
            r = b''
        if r != b'\xfa\xaa':
            print(f'warning: MPSSE bad-command echo was {r.hex() or "empty"} (expected faaa)', file=sys.stderr)
        self._drain()

    @staticmethod
    def _tms_cmds(bits, tdi=0, read=False):
        out = bytearray()
        for i in range(0, len(bits), 7):
            ch = bits[i:i + 7]
            v = sum(b << j for j, b in enumerate(ch)) | (tdi << 7)
            out += bytes([0x6B if read else 0x4B, len(ch) - 1, v])
        return out

    def execute(self, ops):
        cmd, plan = bytearray(), []      # plan: per read shift, list of (kind, nbits)
        for op in ops:
            if op[0] == 'tms':
                cmd += self._tms_cmds(op[1])
                continue
            _, n, tdi, read, last_tms = op
            parts, pos = [], 0
            body = n - 1 if last_tms else n
            nbytes = body // 8
            while nbytes:
                c = min(nbytes, 65536)
                data = ((tdi >> pos) & ((1 << (8 * c)) - 1)).to_bytes(c, 'little')
                cmd += bytes([0x39 if read else 0x19, (c - 1) & 0xFF, (c - 1) >> 8]) + data
                parts.append(('B', c))
                pos += 8 * c
                nbytes -= c
            rem = body - pos
            if rem:
                cmd += bytes([0x3B if read else 0x1B, rem - 1, (tdi >> pos) & ((1 << rem) - 1)])
                parts.append(('b', rem))
                pos += rem
            if last_tms:
                cmd += self._tms_cmds([1], (tdi >> pos) & 1, read)
                parts.append(('b', 1))
            if read:
                plan.append(parts)
        nresp = sum(c if k == 'B' else 1 for parts in plan for k, c in parts)
        if nresp:
            cmd.append(0x87)                               # send immediate
        self._write(cmd)
        resp = self._read(nresp) if nresp else b''
        results, r = [], 0
        for parts in plan:
            val, pos = 0, 0
            for k, c in parts:
                if k == 'B':
                    val |= int.from_bytes(resp[r:r + c], 'little') << pos
                    r += c
                    pos += 8 * c
                else:
                    val |= (resp[r] >> (8 - c)) << pos     # bits arrive at the MSB end
                    r += 1
                    pos += c
            results.append(val)
        return results

    def close(self):
        try:
            self._write(bytes([0x80, 0x08, 0x0B]))
            self._ctrl(0x0B, 0x0000)
            self.util.release_interface(self.dev, self.iface)
            if self.reattach:
                self.dev.attach_kernel_driver(self.iface)
        except Exception:
            pass
        self.util.dispose_resources(self.dev)


class CmsisDapBackend:
    """CMSIS-DAP v2 (bulk) probe in JTAG mode through pyusb, e.g. rust-dap (6666:4444).
    Uses DAP_JTAG_Sequence only: up to 64 TCKs per sequence, fixed TMS, optional TDO."""

    def __init__(self, serial=None, freq=1e6):
        import usb.core, usb.util
        self.usb, self.util = usb, usb.util
        found = []
        for d in usb.core.find(find_all=True):
            try:
                cfg = d.get_active_configuration()
            except usb.core.USBError:
                continue
            for intf in cfg:
                if intf.bInterfaceClass != 0xFF:
                    continue
                try:
                    name = usb.util.get_string(d, intf.iInterface) or ''
                except (usb.core.USBError, ValueError):
                    name = ''
                if 'CMSIS-DAP' in name:
                    found.append((d, intf))
        if serial:
            found = [(d, i) for d, i in found if usb.util.get_string(d, d.iSerialNumber) == serial]
        if not found:
            raise SystemExit('no CMSIS-DAP v2 probe found' + (f' with serial {serial}' if serial else ''))
        if len(found) > 1:
            raise SystemExit('several CMSIS-DAP probes found; pick one with --serial')
        self.dev, intf = found[0]
        self.iface = intf.bInterfaceNumber
        usb.util.claim_interface(self.dev, self.iface)
        bulk = [e for e in intf if usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK]
        is_out = lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT
        self.ep_out = next(e for e in bulk if is_out(e))
        self.ep_in = next(e for e in bulk if not is_out(e))   # first IN; a second one is SWO
        self.pkt = self.ep_in.wMaxPacketSize
        info = self._xfer(bytes([0x00, 0xFF]))                # DAP_Info: packet size
        if info[1] == 2:
            self.pkt = int.from_bytes(info[2:4], 'little')
        if self._xfer(bytes([0x02, 0x02]))[1] != 0x02:        # DAP_Connect JTAG
            raise SystemExit('CMSIS-DAP probe has no JTAG port')
        self.freq = int(freq)
        self._xfer(bytes([0x11]) + self.freq.to_bytes(4, 'little'))   # DAP_SWJ_Clock

    def _xfer(self, req):
        self.ep_out.write(req, timeout=2000)
        resp = bytes(self.ep_in.read(max(self.pkt, self.ep_in.wMaxPacketSize), timeout=2000))
        if resp[0] != req[0]:
            raise IOError(f'CMSIS-DAP: response 0x{resp[0]:02x} to command 0x{req[0]:02x}')
        return resp

    def execute(self, ops):
        seqs = []                     # (tms, nbits <= 64, tdi, read_index or None, bit offset)
        nreads = 0
        for op in ops:
            if op[0] == 'tms':
                bits, i = op[1], 0
                while i < len(bits):
                    k = i
                    while k < len(bits) and bits[k] == bits[i] and k - i < 64:
                        k += 1
                    seqs.append((bits[i], k - i, 0, None, 0))
                    i = k
                continue
            _, n, tdi, read, last_tms = op
            ri = nreads if read else None
            nreads += bool(read)
            body = n - 1 if last_tms else n
            pos = 0
            while pos < body:
                c = min(64, body - pos)
                seqs.append((0, c, (tdi >> pos) & ((1 << c) - 1), ri, pos))
                pos += c
            if last_tms:
                seqs.append((1, 1, (tdi >> pos) & 1, ri, pos))
        results = [0] * nreads
        i = 0
        while i < len(seqs):
            req, cnt, rlen, batch = bytearray([0x14, 0]), 0, 2, []
            while i < len(seqs) and cnt < 255:
                tms, c, tdi, ri, off = seqs[i]
                nb = (c + 7) // 8
                if len(req) + 1 + nb > self.pkt or (ri is not None and rlen + nb > self.pkt):
                    break
                req.append((c & 63) | (tms << 6) | ((ri is not None) << 7))
                req += tdi.to_bytes(nb, 'little')
                if ri is not None:
                    rlen += nb
                    batch.append((ri, off, c))
                cnt += 1
                i += 1
            req[1] = cnt
            resp = self._xfer(bytes(req))
            if resp[1] != 0:
                raise IOError(f'DAP_JTAG_Sequence failed (status 0x{resp[1]:02x})')
            r = 2
            for ri, off, c in batch:
                nb = (c + 7) // 8
                results[ri] |= (int.from_bytes(resp[r:r + nb], 'little') & ((1 << c) - 1)) << off
                r += nb
        return results

    def close(self):
        try:
            self._xfer(bytes([0x03]))                         # DAP_Disconnect
            self.util.release_interface(self.dev, self.iface)
        except Exception:
            pass
        self.util.dispose_resources(self.dev)


class SimBackend:
    """Drives ../sim/tb.v (iverilog) through a pipe: one line of 'tms tdi' pairs per
    transaction, one line of TDO bits back."""

    def __init__(self, vvp_cmd):
        self.p = subprocess.Popen(vvp_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True, bufsize=1)
        self.freq = 0

    def execute(self, ops):
        tms, tdi, reads = [], [], []
        for op in ops:
            if op[0] == 'tms':
                tms += op[1]
                tdi += [0] * len(op[1])
                continue
            _, n, v, read, last_tms = op
            start = len(tms)
            tms += [0] * n
            if last_tms:
                tms[-1] = 1
            tdi += [(v >> i) & 1 for i in range(n)]
            if read:
                reads.append((start, n))
        self.p.stdin.write(f'{len(tms)} ' + ''.join(f'{a}{b}' for a, b in zip(tms, tdi)) + '\n')
        self.p.stdin.flush()
        line = self.p.stdout.readline().strip()
        while line.startswith('#') or line.startswith('VCD') or not line:
            if self.p.poll() is not None:
                raise IOError('simulator exited')
            line = self.p.stdout.readline().strip()
        tdo = [1 if c == '1' else 0 for c in line]
        if len(tdo) != len(tms):
            raise IOError(f'simulator returned {len(tdo)} bits for {len(tms)}')
        return [sum(tdo[s + i] << i for i in range(n)) for s, n in reads]

    def close(self):
        try:
            self.p.stdin.write('0 q\n')
            self.p.stdin.flush()
            self.p.wait(5)
        except Exception:
            self.p.kill()


# ---------------------------------------------------------------------------- TAP layer
class Jtag:
    """Always parks in Run-Test/Idle between operations."""
    TO_SHIFT_DR = [1, 0, 0]
    TO_SHIFT_IR = [1, 1, 0, 0]
    EXIT_TO_IDLE = [1, 0, 0, 0, 0, 0]       # Exit1 -> Update -> RTI, + 4 idle clocks

    def __init__(self, backend):
        self.b = backend
        self.cur_ir = None

    def reset(self):
        self.b.execute([('tms', [1] * 6 + [0])])
        self.cur_ir = None

    def ir(self, op):
        if op not in SAFE_IR:
            raise ValueError(f'IR 0x{op:02x} is not in the safe list')
        r = self.b.execute([('tms', self.TO_SHIFT_IR), ('shift', IR_LEN, op, True, 1),
                            ('tms', self.EXIT_TO_IDLE)])[0]
        self.cur_ir = op
        return r

    def dr(self, n, tdi=0, read=True):
        r = self.b.execute([('tms', self.TO_SHIFT_DR), ('shift', n, tdi, read, 1),
                            ('tms', self.EXIT_TO_IDLE)])
        return r[0] if read else None

    def idcode(self):
        self.reset()                         # IDCODE is the reset instruction
        return self.dr(32)

    def read_reg(self, op, n=32):
        self.ir(op)
        return self.dr(n)

    def dr_length(self, op, maxlen=4096):
        """Shift maxlen zeros then maxlen ones; the first 1 out after maxlen bits gives the length."""
        self.ir(op)
        out = self.dr(2 * maxlen, ((1 << maxlen) - 1) << maxlen)
        for i in range(maxlen, 2 * maxlen):
            if (out >> i) & 1:
                return i - maxlen, out & ((1 << (i - maxlen)) - 1)
        return None, None


# ---------------------------------------------------------------------------- pins / ER1
def load_pins(pinset):
    rows = []
    with open(PINS_CSV) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            rows.append(line)
    # probe pins tagged '@la' in the note are kept in the 'la' set (pins the factory app drives)
    pins = [r for r in csv.DictReader(rows)
            if r['class'] not in PINSET_SKIP[pinset] or (pinset in ('la', 'mipi') and '@la' in r['note'])]
    for i, p in enumerate(pins):
        p['index'] = i
    return pins


class Er1:
    """Soft boundary scan register of top.v."""

    def __init__(self, jtag):
        self.j = jtag
        self.off = None
        self.n = None

    def _probe(self):
        self.j.ir(0x42)
        raw = self.j.dr(64 + 8)
        for off in range(8):
            if (raw >> off) & 0xFFFFFFFF == ER1_MAGIC:
                self.off = off
                self.n = (raw >> (off + 32)) & 0xFF
                flags = (raw >> (off + 40)) & 0xFF
                self.pull = ['none', 'up', 'down', '?'][flags & 3]
                self.pinset = PINSETS.get((flags >> 2) & 3, '?')
                self.version = (raw >> (off + 48)) & 0xFF
                self.L = (72 if self.version >= 4 else 64) + 4 * self.n
                self.gw = 15 if self.version >= 4 else 7    # global field width without commit
                self.pins = load_pins(self.pinset)
                if len(self.pins) != self.n:
                    raise SystemExit(f'bitstream reports {self.n} pins, pins.csv ({self.pinset}) has {len(self.pins)}')
                return
        raise SystemExit(f'ER1 magic not found (got 0x{raw & ((1 << 72) - 1):018x}); '
                         'is the probe bitstream loaded?')

    def scan(self, mode=None, glob=None):
        """One ER1 scan; with mode/glob given they are committed and a second scan reads
        the new state back (a scan returns what was captured before its own update)."""
        if self.off is None:
            self._probe()
        if self.j.cur_ir != 0x42:
            self.j.ir(0x42)
        n, L = self.n, self.L
        v = 0
        if mode is not None:
            for i, m in enumerate(mode):
                v |= (m & 3) << (56 + 2 * n + 2 * i)
            gm = (1 << self.gw) - 1
            v |= ((glob & gm) | (gm + 1)) << (56 + 4 * n)
        raw = self.j.dr(L + self.off, v << self.off) >> self.off
        if raw & 0xFFFFFFFF != ER1_MAGIC:
            raise IOError(f'ER1 magic lost (0x{raw & 0xFFFFFFFF:08x})')
        st = {
            'level': [(raw >> (56 + i)) & 1 for i in range(n)],
            'act': [(raw >> (56 + n + i)) & 1 for i in range(n)],
            'mode': [(raw >> (56 + 2 * n + 2 * i)) & 3 for i in range(n)],
            'glob': (raw >> (56 + 4 * n)) & ((1 << self.gw) - 1),
        }
        if mode is not None:
            st = self.scan()
            if st['mode'] != [m & 3 for m in mode] or st['glob'] != glob & ((1 << self.gw) - 1):
                raise IOError('ER1 write did not read back')
        return st

    def find(self, ball):
        if self.off is None:
            self._probe()
        for p in self.pins:
            if p['ball'].upper() == ball.upper() or p['name'].upper() == ball.upper():
                return p
        raise SystemExit(f'{ball} is not in pin set {self.pinset}')


# ---------------------------------------------------------------------------- helpers
def bits_set(v):
    i, out = 0, []
    while v:
        if v & 1:
            out.append(i)
        v >>= 1
        i += 1
    return out


def ranges(idx):
    out, s = [], None
    for k, i in enumerate(idx):
        if s is None:
            s = p = i
        elif i == p + 1:
            p = i
        else:
            out.append(f'{s}' if s == p else f'{s}-{p}')
            s = p = i
        if k == len(idx) - 1:
            out.append(f'{s}' if s == p else f'{s}-{p}')
    return ','.join(out) or '-'


def jitter(j):
    """A random number of idle clocks, so periodic signals do not alias onto the scan rate."""
    j.b.execute([('tms', [0] * random.randint(1, 31))])


def sample_snapshots(j, n, length, interval):
    j.ir(0x01)
    snaps = []
    for _ in range(n):
        jitter(j)
        snaps.append(j.dr(length))
        if interval:
            time.sleep(interval)
    return snaps


def summarize(snaps, length):
    full = (1 << length) - 1
    and_ = full
    or_ = 0
    for s in snaps:
        and_ &= s
        or_ |= s
    toggling = and_ ^ or_
    return {'ones': and_, 'zeros': full & ~or_, 'toggling': toggling}


GOWIN_PROG = os.path.expanduser('~/repos/rust-dap/fpga-config/target/release/gowin-prog')


def loader(args, fs):
    if args.loader:
        cmd = [args.loader] + args.loader_args.split() + [fs]
    elif args.cable == 'dap':
        prog = GOWIN_PROG if os.path.exists(GOWIN_PROG) else 'gowin-prog'
        cmd = [prog, '--cable', 'dap', 'sram', fs]
    else:
        cmd = ['openFPGALoader', '-c', 'ft2232', '--write-sram', fs]
    print('$', ' '.join(cmd))
    subprocess.run(cmd, check=True)


def open_jtag(args, pull=None):
    if args.sim:
        cmd = args.sim if pull is None else args.sim.replace('_up', f'_{pull}')
        b = SimBackend(cmd.split())
    else:
        if args.cable == 'dap':
            b = CmsisDapBackend(serial=args.serial, freq=args.freq)
        else:
            b = MpsseBackend(serial=args.serial, freq=args.freq)
    j = Jtag(b)
    j.reset()
    if not args.any_device and not args.sim:
        idc = j.idcode()
        if idc != GW5AT_15_IDCODE:
            b.close()
            raise SystemExit(f'IDCODE 0x{idc:08x} is not GW5AT-15 (0x{GW5AT_15_IDCODE:08x}); '
                             'check wiring / power, or pass --any-device')
    return j


def get_bsr_len(j, args):
    if args.bsr_len:
        return args.bsr_len
    n, _ = j.dr_length(0x01, args.maxlen)
    if not n:
        raise SystemExit('could not measure the SAMPLE register length')
    return n


# ---------------------------------------------------------------------------- commands
def cmd_detect(j, args):
    idc = j.idcode()
    print(f'IDCODE   0x{idc:08x}' + ('  (GW5AT-15)' if idc == GW5AT_15_IDCODE else ''))
    irc = j.ir(0x13)
    print(f'IR capture 0b{irc:08b}')
    print(f'USERCODE 0x{j.dr(32):08x}')
    st = j.read_reg(0x41)
    print(f'STATUS   0x{st:08x}')
    for i, name in enumerate(GW5A_STATUS):
        if (st >> i) & 1:
            print(f'  [{i:2d}] {name}')
    j.ir(0xFF)
    n, _ = j.dr_length(0xFF, 64)
    print(f'BYPASS length {n} (expect 1)')


def cmd_bsr_len(j, args):
    n, cap = j.dr_length(0x01, args.maxlen)
    if n is None:
        print(f'no 1 came out within {args.maxlen} bits -- not a normal SAMPLE register?')
        return
    print(f'SAMPLE (IR 0x01) register length: {n} bits')
    print(f'captured: {cap:0{(n + 3) // 4}x}')


def cmd_sample(j, args):
    length = get_bsr_len(j, args)
    snaps = sample_snapshots(j, args.n, length, args.interval)
    s = summarize(snaps, length)
    tog = bits_set(s['toggling'])
    print(f'length {length}, {len(snaps)} snapshots')
    print(f'toggling cells ({len(tog)}): {ranges(tog)}')
    print(f'ones: {ranges(bits_set(s["ones"]))}')
    if args.o:
        with open(args.o, 'w') as f:
            json.dump({'length': length, 'label': args.label, 'time': time.time(),
                       'snapshots': [f'{x:x}' for x in snaps]}, f, indent=1)
        print(f'saved {args.o}')


def cmd_watch(j, args):
    length = get_bsr_len(j, args)
    j.ir(0x01)
    base = j.dr(length)
    changed = {}
    print(f'length {length}; watching (Ctrl-C to stop) ...')
    try:
        while True:
            v = j.dr(length)
            for i in bits_set(v ^ base):
                changed[i] = changed.get(i, 0) + 1
            base = v
            line = ' '.join(f'{i}:{changed[i]}' for i in sorted(changed))
            print(f'\rchanged cells (index:count) {line or "-"}'[:240], end='', flush=True)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print()


def cmd_diff(j, args):
    def load(p):
        d = json.load(open(p))
        snaps = [int(x, 16) for x in d['snapshots']]
        return d, summarize(snaps, d['length'])
    da, a = load(args.a)
    db, b = load(args.b)
    if da['length'] != db['length']:
        raise SystemExit('different lengths')
    to_one = a['zeros'] & b['ones']
    to_zero = a['ones'] & b['zeros']
    print(f'{args.a} [{da.get("label")}] -> {args.b} [{db.get("label")}]')
    print(f'0 -> 1 : {ranges(bits_set(to_one))}')
    print(f'1 -> 0 : {ranges(bits_set(to_zero))}')
    print(f'toggling only in A: {ranges(bits_set(a["toggling"] & ~b["toggling"]))}')
    print(f'toggling only in B: {ranges(bits_set(b["toggling"] & ~a["toggling"]))}')


def print_ubs(e, st, prev=None):
    print(f'pin set {e.pinset}, pull {e.pull}, glob 0x{st["glob"]:02x}')
    print(' idx ball  name        class    lvl act mode')
    for p in e.pins:
        i = p['index']
        mark = ''
        if prev and prev['level'][i] != st['level'][i]:
            mark = ' <'
        print(f' {i:3d} {p["ball"]:5s} {p["name"]:11s} {p["class"]:8s} {st["level"][i]:3d} '
              f'{"*" if st["act"][i] else " ":>3s} {MODE_NAMES[st["mode"][i]]}{mark}')


def cmd_ubs_read(j, args):
    e = Er1(j)
    st = e.scan()
    print_ubs(e, st)
    if not args.watch:
        return
    try:
        while True:
            time.sleep(args.interval)
            try:
                st2 = e.scan()
            except IOError as ex:
                # the probe design is gone: the FPGA reconfigured (e.g. from flash)
                us, stat = j.read_reg(0x13), j.read_reg(0x41)
                names = ', '.join(GW5A_STATUS[b] for b in range(32) if stat >> b & 1)
                print(f'{time.strftime("%H:%M:%S")} {ex}: FPGA reconfigured? '
                      f'USERCODE 0x{us:08x} STATUS 0x{stat:08x} ({names})')
                return
            if st2['level'] != st['level'] or st2['act'] != st['act']:
                print(time.strftime('%H:%M:%S'))
                print_ubs(e, st2, st)
            st = st2
    except KeyboardInterrupt:
        pass


def cmd_status_watch(j, args):
    """Print USERCODE / STATUS whenever they change (e.g. while pressing MODE)."""
    prev = None
    try:
        while True:
            cur = (j.read_reg(0x13), j.read_reg(0x41))
            if cur != prev:
                names = ', '.join(GW5A_STATUS[b] for b in range(32) if cur[1] >> b & 1)
                print(f'{time.strftime("%H:%M:%S")} USERCODE 0x{cur[0]:08x} STATUS 0x{cur[1]:08x} ({names})',
                      flush=True)
                prev = cur
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass


def load_classes(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return {}


def check_drive(e, p, args):
    if p['class'] not in DRIVABLE:
        raise SystemExit(f'{p["ball"]} is class {p["class"]}: never driven (RTL CAN_DRIVE=0)')
    c = load_classes(args.classes).get(p['ball'], {}).get('class')
    if c == 'floating':
        return True
    if not args.force:
        print(f'skip {p["ball"]}: classification is {c or "missing"} (run classify, or --force)')
        return False
    if c == 'active':
        print(f'WARNING {p["ball"]}: something drives this pin -- driving it may fight that driver')
    return True


def cmd_ubs_set(j, args):
    e = Er1(j)
    p = e.find(args.ball)
    want = MODES[args.mode]
    if want and not check_drive(e, p, args):
        return
    st = e.scan()
    mode = list(st['mode'])
    mode[p['index']] = want
    glob = (st['glob'] & ~0x05) | (1 if args.fast else 0) | (4 if args.od else 0)
    if args.div is not None:
        glob = (glob & ~0x78) | ((args.div & 15) << 3)
    if args.duty is not None:
        glob = (glob & ~0x7f00) | ((args.duty & 7) << 8)
    if args.duty128 is not None:
        d = args.duty128 & 127
        glob = (glob & ~0x7f00) | ((d >> 4) << 8) | ((d & 15) << 11)
    st = e.scan(mode, glob)
    print_ubs(e, st)


def cmd_ubs_clear(j, args):
    e = Er1(j)
    st = e.scan()
    e.scan(st['mode'], st['glob'] | 2)
    print_ubs(e, e.scan(st['mode'], st['glob'] & ~2))


def find_fs(pinset, pull):
    return os.path.join(BUILD_DIR, f'slogic16u3_{pinset}_{pull}', 'impl', 'pnr', 'slogic16u3_probe.fs')


def classify_once(j, args, nreads=8):
    e = Er1(j)
    st = e.scan()
    e.scan([0] * e.n, (st['glob'] | 2) & ~5)      # all Hi-Z, clear activity
    e.scan([0] * e.n, 0)
    time.sleep(args.settle)
    reads = [e.scan() for _ in range(nreads)]
    return e, reads


def cmd_classify(j, args):
    j.b.close()
    out = load_classes(args.classes)
    res = {}
    for pull in ('up', 'down'):
        fs = find_fs(args.pinset, pull)
        if not args.sim:
            loader(args, fs)
        j2 = open_jtag(args, pull)
        e, reads = classify_once(j2, args)
        if e.pull != pull:
            raise SystemExit(f'loaded build reports pull {e.pull}, expected {pull}')
        res[pull] = (e, reads)
        j2.b.close()
    e = res['up'][0]
    print(' ball  name        class    up dn act -> result')
    for p in e.pins:
        i = p['index']
        lv = {k: {r['level'][i] for r in res[k][1]} for k in res}
        act = any(r['act'][i] for k in res for r in res[k][1])
        if act or len(lv['up']) > 1 or len(lv['down']) > 1:
            c = 'active'
        elif lv['up'] == {1} and lv['down'] == {0}:
            c = 'floating'
        elif lv['up'] == {1} and lv['down'] == {1}:
            c = 'high'
        elif lv['up'] == {0} and lv['down'] == {0}:
            c = 'low'
        else:
            c = 'odd'
        out[p['ball']] = {'name': p['name'], 'pin_class': p['class'], 'class': c,
                          'up': sorted(lv['up']), 'down': sorted(lv['down']), 'act': act}
        print(f' {p["ball"]:5s} {p["name"]:11s} {p["class"]:8s} {"".join(map(str, sorted(lv["up"]))):>2s} '
              f'{"".join(map(str, sorted(lv["down"]))):>2s} {"*" if act else " ":>3s} -> {c}')
    with open(args.classes, 'w') as f:
        json.dump(out, f, indent=1)
    print(f'saved {args.classes}')
    print('floating = follows the internal pull (nothing strong attached): safe to drive.')
    print('high/low = pulled or driven externally (LED to VCC, strap, or an output); active = toggling.')


def cmd_blink_scan(j, args):
    e = Er1(j)
    st = e.scan()
    notes = load_classes(args.notes)
    glob = (1 if args.fast else 0) | (4 if args.od else 0)
    try:
        for p in e.pins:
            if p['class'] not in DRIVABLE or not check_drive(e, p, args):
                continue
            mode = [0] * e.n
            mode[p['index']] = MODES['blink']
            e.scan(mode, glob)
            ans = input(f'{p["ball"]:5s} {p["name"]:11s} blinking -- note (Enter: nothing seen, q: quit): ')
            if ans.strip().lower() == 'q':
                break
            if ans.strip():
                notes[p['ball']] = ans.strip()
    finally:
        e.scan([0] * e.n, 0)
        with open(args.notes, 'w') as f:
            json.dump(notes, f, indent=1)
        print(f'all Hi-Z; notes in {args.notes}')


def cmd_map_bsr(j, args):
    length = get_bsr_len(j, args)
    e = Er1(j)
    e.scan()
    result = load_classes(args.o)

    def snap(mode):
        e.scan(mode, 0)
        s = summarize(sample_snapshots(j, 4, length, 0), length)
        j.ir(0x42)
        return s

    full = (1 << length) - 1
    try:
        for p in e.pins:
            if p['class'] not in DRIVABLE or not check_drive(e, p, args):
                continue
            i = p['index']
            # several Hi-Z / low / high rounds; a cell counts only if it behaves the same in
            # every round and never toggles while the pin is held (rejects unrelated clocks)
            follow, inv, oe, noisy = full, full, full, 0
            for _ in range(args.rounds):
                m = [0] * e.n
                hz = snap(m)
                m[i] = MODES['low']
                lo = snap(m)
                m[i] = MODES['high']
                hi = snap(m)
                noisy |= hz['toggling'] | lo['toggling'] | hi['toggling']
                f = lo['zeros'] & hi['ones']
                follow &= f
                inv &= lo['ones'] & hi['zeros']
                oe &= (hz['ones'] & lo['zeros'] | hz['zeros'] & lo['ones']) & ~f
            data = bits_set(follow & ~noisy)
            inv = bits_set(inv & ~noisy)
            oe = bits_set(oe & ~noisy)
            result[p['ball']] = {'name': p['name'], 'follow': data, 'inverted': inv, 'oe_like': oe}
            print(f'{p["ball"]:5s} {p["name"]:11s} follow {ranges(data):14s} inverted {ranges(inv):10s} oe {ranges(oe)}')
    finally:
        e.scan([0] * e.n, 0)
    with open(args.o, 'w') as f:
        json.dump(result, f, indent=1)
    print(f'saved {args.o}')


def cmd_load(j, args):
    loader(args, args.fs)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--serial', help='USB serial number of the probe')
    ap.add_argument('--freq', type=float, default=1e6, help='TCK frequency (default 1 MHz)')
    ap.add_argument('--any-device', action='store_true', help='skip the GW5AT-15 IDCODE check')
    ap.add_argument('--sim', help='simulation command instead of hardware (e.g. "vvp -n sim/tb.vvp")')
    ap.add_argument('--cable', choices=['dap', 'ftdi'], default='dap',
                    help='dap = CMSIS-DAP v2 (rust-dap), ftdi = FT2232 MPSSE (default dap)')
    ap.add_argument('--loader', help='SRAM loader command (default: gowin-prog sram for dap, '
                    'openFPGALoader -c ft2232 --write-sram for ftdi)')
    ap.add_argument('--loader-args', default='', help='arguments placed before the .fs file')
    ap.add_argument('--bsr-len', type=int, help='skip measuring the SAMPLE length')
    ap.add_argument('--maxlen', type=int, default=4096)
    ap.add_argument('--classes', default='classify.json', help='classification file (classify writes it)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('detect')
    sub.add_parser('bsr-len')
    s = sub.add_parser('sample')
    s.add_argument('-n', type=int, default=32)
    s.add_argument('--interval', type=float, default=0.0)
    s.add_argument('-o')
    s.add_argument('--label', default='')
    s = sub.add_parser('watch')
    s.add_argument('--interval', type=float, default=0.05)
    s = sub.add_parser('status-watch')
    s.add_argument('--interval', type=float, default=0.01)
    s = sub.add_parser('diff')
    s.add_argument('a')
    s.add_argument('b')
    s = sub.add_parser('load')
    s.add_argument('fs')
    s = sub.add_parser('ubs-read')
    s.add_argument('--watch', action='store_true')
    s.add_argument('--interval', type=float, default=0.1)
    s = sub.add_parser('ubs-set')
    s.add_argument('ball')
    s.add_argument('mode', choices=list(MODES))
    s.add_argument('--fast', action='store_true', help='blink at ~100 kHz instead of ~1.5 Hz')
    s.add_argument('--od', action='store_true', help='blink as open-drain (sink only)')
    s.add_argument('--div', type=int, help='blink at osc/2^DIV (1..15, ~26 MHz .. ~1.6 kHz; '
                   'v3 bitstreams), 0 = back to --fast / slow; applies to all blinking pins')
    s.add_argument('--duty128', type=int, help='PWM duty in 1/128 (1..127) with --div >= 7 (v5 bitstreams)')
    s.add_argument('--duty', type=int, help='PWM duty in eighths (1..7) with --div >= 4; 0 = 50 %% '
                   '(v4 bitstreams); applies to all blinking pins')
    s.add_argument('--force', action='store_true')
    sub.add_parser('ubs-clear')
    s = sub.add_parser('classify')
    s.add_argument('--pinset', choices=['main', 'cfg', 'la', 'mipi'], default='main')
    s.add_argument('--settle', type=float, default=0.3)
    s = sub.add_parser('blink-scan')
    s.add_argument('--fast', action='store_true')
    s.add_argument('--od', action='store_true')
    s.add_argument('--force', action='store_true')
    s.add_argument('--notes', default='blink_notes.json')
    s = sub.add_parser('map-bsr')
    s.add_argument('-o', default='bsrmap.json')
    s.add_argument('--rounds', type=int, default=3)
    s.add_argument('--force', action='store_true')
    args = ap.parse_args()

    if args.cmd in ('diff',):
        return cmd_diff(None, args)
    if args.cmd == 'load':
        return cmd_load(None, args)
    j = open_jtag(args)
    try:
        globals()['cmd_' + args.cmd.replace('-', '_')](j, args)
    finally:
        j.b.close()


if __name__ == '__main__':
    main()
