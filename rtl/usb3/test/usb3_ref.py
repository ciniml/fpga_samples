#!/usr/bin/env python3
"""Bit-exact reference models for the USB 3.2 Gen1 link layer primitives.

Used to generate/check test vectors for the Veryl implementation.
Definitions: USB 3.2 Rev 1.1 sections 6.3.1.3 (+Appendix B), 7.2.1.1.2,
7.2.1.1.3, 7.2.1.2.2.
"""
import zlib

# ---------------------------------------------------------------- scrambler
def lfsr_adv8(l):
    """Advance the x^16+x^5+x^4+x^3+1 LFSR by 8 serial shifts (Appendix B)."""
    b = [(l >> i) & 1 for i in range(16)]
    o = [0] * 16
    o[0] = b[8]; o[1] = b[9]; o[2] = b[10]
    o[3] = b[11] ^ b[8]
    o[4] = b[12] ^ b[9] ^ b[8]
    o[5] = b[13] ^ b[10] ^ b[9] ^ b[8]
    o[6] = b[14] ^ b[11] ^ b[10] ^ b[9]
    o[7] = b[15] ^ b[12] ^ b[11] ^ b[10]
    o[8] = b[0] ^ b[13] ^ b[12] ^ b[11]
    o[9] = b[1] ^ b[14] ^ b[13] ^ b[12]
    o[10] = b[2] ^ b[15] ^ b[14] ^ b[13]
    o[11] = b[3] ^ b[15] ^ b[14]
    o[12] = b[4] ^ b[15]
    o[13] = b[5]; o[14] = b[6]; o[15] = b[7]
    return sum(v << i for i, v in enumerate(o))

def lfsr_serial8(l):
    """Same thing, 8 single-bit shifts, as an independent cross-check."""
    for _ in range(8):
        fb = (l >> 15) & 1
        l = ((l << 1) & 0xFFFF) ^ (0x0039 if fb else 0)  # taps x^5,x^4,x^3,1 -> bits 5,4,3,0
    return l

COM, SKP = 0xBC, 0x3C

class Scrambler:
    def __init__(self):
        self.lfsr = 0xFFFF
    def step(self, byte, k):
        """Process one symbol (byte, k flag). Returns the (de)scrambled byte."""
        if k and byte == SKP:
            return byte                      # no XOR, no advance
        if k and byte == COM:
            self.lfsr = 0xFFFF               # reset, no advance
            return byte
        out = byte
        if not k:
            mask = sum(((self.lfsr >> (15 - i)) & 1) << i for i in range(8))
            out = byte ^ mask
        self.lfsr = lfsr_adv8(self.lfsr)
        return out

# ---------------------------------------------------------------- CRCs
def crc_lsbfirst(data_bits, poly, width, init):
    """Non-reflected register, bits fed in the given order."""
    reg = init
    top = 1 << (width - 1)
    for bit in data_bits:
        fb = ((reg & top) != 0) ^ bit
        reg = ((reg << 1) & ((1 << width) - 1)) ^ (poly if fb else 0)
    return reg

def bits_of_bytes(bs):
    for b in bs:
        for i in range(8):
            yield (b >> i) & 1

def bitrev(v, w):
    return sum(((v >> i) & 1) << (w - 1 - i) for i in range(w))

def crc16_field(hdr12):
    """CRC-16 field value (bits [15:0]; byte 0 of the field = bits [7:0])."""
    reg = crc_lsbfirst(bits_of_bytes(hdr12), 0x100B, 16, 0xFFFF)
    return (~bitrev(reg, 16)) & 0xFFFF

def crc16_residual_ok(hdr12_plus_crc):
    return crc_lsbfirst(bits_of_bytes(hdr12_plus_crc), 0x100B, 16, 0xFFFF) == 0xF6AA

def crc32_field(data):
    reg = crc_lsbfirst(bits_of_bytes(data), 0x04C11DB7, 32, 0xFFFFFFFF)
    return (~bitrev(reg, 32)) & 0xFFFFFFFF

def crc32_residual_ok(data_plus_crc):
    return crc_lsbfirst(bits_of_bytes(data_plus_crc), 0x04C11DB7, 32, 0xFFFFFFFF) == 0xC704DD7B

def crc5_field(lcw11):
    """CRC-5 over the 11 LSBs of the link control word; returns bits [15:11]
    as a 5-bit value where bit 0 of the result goes to LCW bit 11."""
    bits = [(lcw11 >> i) & 1 for i in range(11)]
    reg = crc_lsbfirst(bits, 0x05, 5, 0x1F)
    # MSb of the complemented remainder -> bit 11 ... LSb -> bit 15
    return (~bitrev(reg, 5)) & 0x1F

def lcw(seq_or_11bits):
    v = seq_or_11bits & 0x7FF
    return v | (crc5_field(v) << 11)

def crc5_residual_ok(lcw16):
    bits = [(lcw16 >> i) & 1 for i in range(11)] + [(lcw16 >> (11 + i)) & 1 for i in range(5)]
    # bits 11..15 carry MSb..LSb of the remainder: feed them in that order? The spec says
    # residual is computed over the whole word; we verify by reconstruction instead.
    return crc5_field(lcw16 & 0x7FF) == (lcw16 >> 11)

if __name__ == "__main__":
    import random
    # LFSR tables from Appendix B
    l = 0xFFFF; seq = []
    for _ in range(16):
        l = lfsr_adv8(l); seq.append(l)
    exp = [0xE817,0x0328,0x284B,0x4DE8,0xE755,0x404F,0x4140,0x4E79,0x761E,0x1466,0x6574,0x7DBD,0xB6E5,0xFDA6,0xB165]
    assert seq[:15] == exp, [hex(x) for x in seq]
    for _ in range(1000):
        x = random.randrange(1 << 16); assert lfsr_adv8(x) == lfsr_serial8(x)
    s = Scrambler(); s.step(COM, 1)
    z = bytes(s.step(0, 0) for _ in range(15))
    assert z == bytes.fromhex("FF17C014B2E7028272 6E28A6BE6DBF".replace(" ", "")), z.hex()
    # CRC-32 equals zlib's (reflected, init/final all ones) as a little-endian field
    for n in (0, 1, 3, 4, 17, 1024):
        d = bytes(random.randrange(256) for _ in range(n))
        f = crc32_field(d)
        assert f == zlib.crc32(d), (f, zlib.crc32(d))
        assert crc32_residual_ok(d + f.to_bytes(4, "little"))
    for _ in range(20):
        h = bytes(random.randrange(256) for _ in range(12))
        f = crc16_field(h)
        assert crc16_residual_ok(h + f.to_bytes(2, "little"))
    # CRC-16 should match the reflected form: poly 0xD008, init 0xFFFF, xorout 0xFFFF
    def crc16_refl(bs):
        r = 0xFFFF
        for b in bs:
            r ^= b
            for _ in range(8):
                r = (r >> 1) ^ (0xD008 if r & 1 else 0)
        return r ^ 0xFFFF
    for _ in range(20):
        h = bytes(random.randrange(256) for _ in range(12))
        assert crc16_field(h) == crc16_refl(h)
    # CRC-5 reflected form: poly 0x14, init 0x1F, complement
    def crc5_refl(v):
        r = 0x1F
        for i in range(11):
            fb = (r & 1) ^ ((v >> i) & 1)
            r = (r >> 1) ^ (0x14 if fb else 0)
        return (~r) & 0x1F
    for v in range(1 << 11):
        assert crc5_field(v) == crc5_refl(v)
    print("ref model self-check OK")
    print("LCW examples: seq0 %04x seq1 %04x seq7 %04x" % (lcw(0), lcw(1), lcw(7)))
