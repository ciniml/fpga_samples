// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! The L4 test ROM (MBC5, 64 KiB ROM, 8 KiB RAM), hand-assembled for the SM83.
//!
//! The CPU checks the cartridge over and over and leaves its results in the cartridge RAM, which
//! the host reads over the UART while it runs:
//!   - the sum of each ROM bank through 0x4000-0x7FFF for the bank numbers 0, 1, 2, 3, 0x100
//!     and 0x102 (bank 0 and 0x100 against the sum of 0x0000-0x3FFF read at start, the others
//!     against the sums of the image)
//!   - 0xA100-0xBFFF filled once with (lo ^ hi ^ 0x5A) of the address, then read back
//!   - a pass or fail count per round, and the background colour (green / red)
//!
//! RAM results (offsets from 0xA000): 0 "L4GO" after the start, 4 A and B at boot, 6 KEY1,
//! 0x10 rounds passed (u32), 0x14 rounds failed (u32), 0x18 the last failed check (1-6),
//! 0x19 RAM mismatches (u8, wraps), 0x20 the last sum of each check (u16 x 6).

use std::collections::HashMap;

pub const ROM_SIZE: usize = 0x10000;
pub const RAM_PATTERN_START: usize = 0x100;
/// (bank number, 0: compare with the bank-0 sum / 1-3: the image's bank)
pub const CHECKS: [(u16, usize); 6] = [(0, 0), (1, 1), (2, 2), (3, 3), (0x100, 0), (0x102, 2)];

pub fn ram_pattern(off: usize) -> u8 {
    let a = 0xA000 + off;
    (a as u8) ^ ((a >> 8) as u8) ^ 0x5A
}

pub fn bank_sum(rom: &[u8], bank: usize) -> u16 {
    rom[bank * 0x4000..(bank + 1) * 0x4000].iter().fold(0u16, |s, &b| s.wrapping_add(b as u16))
}

enum Fix {
    Rel(String),
    Abs(String),
}

struct Asm {
    rom: Vec<u8>,
    pc: usize,
    labels: HashMap<String, usize>,
    fixes: Vec<(usize, Fix)>,
}

impl Asm {
    fn b(&mut self, bytes: &[u8]) {
        for &x in bytes {
            self.rom[self.pc] = x;
            self.pc += 1;
        }
    }
    fn label(&mut self, l: &str) {
        assert!(self.labels.insert(l.to_string(), self.pc).is_none(), "label {l}");
    }
    /// jr / jr cc (opcode 18, 20, 28, 30, 38)
    fn jr(&mut self, op: u8, l: &str) {
        self.b(&[op, 0]);
        self.fixes.push((self.pc - 1, Fix::Rel(l.into())));
    }
    /// jp / call (C3, CD)
    fn jp(&mut self, op: u8, l: &str) {
        self.b(&[op, 0, 0]);
        self.fixes.push((self.pc - 2, Fix::Abs(l.into())));
    }
    fn ld_a(&mut self, n: u8) { self.b(&[0x3E, n]) }
    fn st(&mut self, addr: u16) { self.b(&[0xEA, addr as u8, (addr >> 8) as u8]) } // ld [nn],a
    fn ld_hl(&mut self, n: u16) { self.b(&[0x21, n as u8, (n >> 8) as u8]) }
    fn resolve(&mut self) {
        for (pos, f) in std::mem::take(&mut self.fixes) {
            match f {
                Fix::Rel(l) => {
                    let t = self.labels[&l] as isize;
                    let d = t - (pos as isize + 1);
                    assert!((-128..=127).contains(&d), "jr {l} out of range");
                    self.rom[pos] = d as i8 as u8;
                }
                Fix::Abs(l) => {
                    let t = self.labels[&l];
                    self.rom[pos] = t as u8;
                    self.rom[pos + 1] = (t >> 8) as u8;
                }
            }
        }
    }
}

fn xs(mut x: u32) -> u32 {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    x
}

/// `logo`: the 48 bytes at 0x0104 of any cartridge (the boot ROM compares them)
pub fn build(logo: &[u8], double_speed: bool) -> Vec<u8> {
    let mut a = Asm { rom: vec![0xFF; ROM_SIZE], pc: 0, labels: HashMap::new(), fixes: vec![] };
    // banks 1-3: the bank number, then pseudo-random bytes
    let mut x = 0x1234_5678u32;
    for bank in 1..4 {
        a.rom[bank * 0x4000] = bank as u8;
        for i in 1..0x4000 {
            x = xs(x);
            a.rom[bank * 0x4000 + i] = (x >> 24) as u8;
        }
    }
    let sums: Vec<u16> = (0..4).map(|k| bank_sum(&a.rom, k)).collect();

    // header
    a.pc = 0x100;
    a.b(&[0x00, 0xC3, 0x50, 0x01]);
    a.rom[0x104..0x134].copy_from_slice(logo);
    let title = if double_speed { b"L4 BUS 2X" as &[u8] } else { b"L4 BUS 1X" };
    a.rom[0x134..0x143].fill(0);
    a.rom[0x134..0x134 + title.len()].copy_from_slice(title);
    a.rom[0x143] = 0x80; // CGB compatible
    a.rom[0x144] = b'0';
    a.rom[0x145] = b'0';
    a.rom[0x146] = 0;
    a.rom[0x147] = 0x1B; // MBC5 + RAM + battery
    a.rom[0x148] = 0x01; // 64 KiB
    a.rom[0x149] = 0x02; // 8 KiB
    a.rom[0x14A] = 0x01;
    a.rom[0x14B] = 0x33;
    a.rom[0x14C] = 0;

    // code
    a.pc = 0x150;
    a.b(&[0xF3]); // di
    a.b(&[0x31, 0xF0, 0xDF]); // ld sp,$DFF0
    a.b(&[0xE0, 0x80]); // ldh [$80],a
    a.b(&[0x78, 0xE0, 0x81]); // ld a,b ; ldh [$81],a
    if double_speed {
        a.ld_a(0x30);
        a.b(&[0xE0, 0x00]); // ldh [$00],a (P1: no key lines)
        a.ld_a(0x01);
        a.b(&[0xE0, 0x4D]); // ldh [$4D],a (KEY1: prepare)
        a.b(&[0x10, 0x00]); // stop
    }
    a.ld_a(0x0A);
    a.st(0x0000); // RAM on
    a.b(&[0xAF]); // xor a
    a.st(0x4000); // RAM bank 0
    a.ld_hl(0x0000);
    a.b(&[0x0E, 0x40]); // ld c,$40
    a.jp(0xCD, "sum_range");
    a.b(&[0x7B, 0xE0, 0x83, 0x7A, 0xE0, 0x84]); // bank-0 sum -> $83/$84
    a.b(&[0xF0, 0x80]);
    a.st(0xA004);
    a.b(&[0xF0, 0x81]);
    a.st(0xA005);
    a.b(&[0xF0, 0x4D]);
    a.st(0xA006);
    // clear A010-A02F
    a.ld_hl(0xA010);
    a.b(&[0x06, 0x20, 0xAF]); // ld b,$20 ; xor a
    a.label("clr");
    a.b(&[0x22, 0x05]); // ld [hl+],a ; dec b
    a.jr(0x20, "clr");
    // pattern A100-BFFF
    a.ld_hl(0xA000 + RAM_PATTERN_START as u16);
    a.label("fill");
    a.b(&[0x7D, 0xAC, 0xEE, 0x5A, 0x22]); // ld a,l ; xor h ; xor $5A ; ld [hl+],a
    a.b(&[0x7C, 0xFE, 0xC0]); // ld a,h ; cp $C0
    a.jr(0x20, "fill");
    for (i, &c) in b"L4GO".iter().enumerate() {
        a.ld_a(c);
        a.st(0xA000 + i as u16);
    }

    a.label("main");
    a.b(&[0xAF, 0xE0, 0x82]); // fail flag = 0
    for (k, &(bank, exp)) in CHECKS.iter().enumerate() {
        a.ld_a(bank as u8);
        a.st(0x2000);
        a.ld_a((bank >> 8) as u8);
        a.st(0x3000);
        a.ld_hl(0x4000);
        a.b(&[0x0E, 0x80]);
        a.jp(0xCD, "sum_range");
        a.b(&[0x7B]);
        a.st(0xA020 + 2 * k as u16);
        a.b(&[0x7A]);
        a.st(0xA021 + 2 * k as u16);
        let (bad, ok) = (format!("bad{k}"), format!("ok{k}"));
        if exp == 0 {
            a.b(&[0xF0, 0x83, 0xBB]); // ldh a,[$83] ; cp e
            a.jr(0x20, &bad);
            a.b(&[0xF0, 0x84, 0xBA]); // ldh a,[$84] ; cp d
            a.jr(0x20, &bad);
        } else {
            a.b(&[0x7B, 0xFE, sums[exp] as u8]); // ld a,e ; cp n
            a.jr(0x20, &bad);
            a.b(&[0x7A, 0xFE, (sums[exp] >> 8) as u8]); // ld a,d ; cp n
            a.jr(0x20, &bad);
        }
        a.jr(0x18, &ok);
        a.label(&bad);
        a.ld_a(k as u8 + 1);
        a.st(0xA018);
        a.ld_a(1);
        a.b(&[0xE0, 0x82]);
        a.label(&ok);
    }
    a.b(&[0xAF]);
    a.st(0x3000);
    // RAM read back
    a.ld_hl(0xA000 + RAM_PATTERN_START as u16);
    a.label("vfy");
    a.b(&[0x7D, 0xAC, 0xEE, 0x5A, 0xBE]); // ... ; cp [hl]
    a.jr(0x28, "vok");
    a.b(&[0xE5]); // push hl
    a.ld_hl(0xA019);
    a.b(&[0x34, 0xE1]); // inc [hl] ; pop hl
    a.ld_a(1);
    a.b(&[0xE0, 0x82]);
    a.label("vok");
    a.b(&[0x23, 0x7C, 0xFE, 0xC0]); // inc hl ; ld a,h ; cp $C0
    a.jr(0x20, "vfy");
    // tally
    a.b(&[0xF0, 0x82, 0xA7]); // ldh a,[$82] ; and a
    a.jr(0x20, "fail");
    a.ld_hl(0xA010);
    a.b(&[0x11, 0xE0, 0x03]); // ld de,$03E0 (green)
    a.jr(0x18, "inc");
    a.label("fail");
    a.ld_hl(0xA014);
    a.b(&[0x11, 0x1F, 0x00]); // ld de,$001F (red)
    a.label("inc");
    for i in 0..4 {
        a.b(&[0x34]); // inc [hl]
        if i < 3 {
            a.jr(0x20, "pal");
            a.b(&[0x23]);
        }
    }
    a.label("pal");
    a.b(&[0xF0, 0x40, 0xCB, 0x7F]); // ldh a,[$40] ; bit 7,a
    a.jr(0x28, "nopal");
    a.label("vbl");
    a.b(&[0xF0, 0x44, 0xFE, 144]); // ldh a,[$44] ; cp 144
    a.jr(0x38, "vbl");
    a.ld_a(0x80);
    a.b(&[0xE0, 0x68, 0x7B, 0xE0, 0x69, 0x7A, 0xE0, 0x69]); // BCPS, BCPD lo, hi
    a.label("nopal");
    a.jp(0xC3, "main");

    // DE = sum of [HL, C:00)
    a.label("sum_range");
    a.b(&[0x11, 0x00, 0x00]);
    a.label("sl");
    a.b(&[0x2A, 0x83, 0x5F]); // ld a,[hl+] ; add a,e ; ld e,a
    a.jr(0x30, "ss");
    a.b(&[0x14]); // inc d
    a.label("ss");
    a.b(&[0x7C, 0xB9]); // ld a,h ; cp c
    a.jr(0x20, "sl");
    a.b(&[0xC9]);
    assert!(a.pc < 0x4000);
    a.resolve();

    let mut rom = a.rom;
    let mut c = 0u8;
    for &x in &rom[0x134..0x14D] {
        c = c.wrapping_sub(x).wrapping_sub(1);
    }
    rom[0x14D] = c;
    let g = rom.iter().enumerate().filter(|(i, _)| *i != 0x14E && *i != 0x14F).fold(0u16, |s, (_, &b)| s.wrapping_add(b as u16));
    rom[0x14E] = (g >> 8) as u8;
    rom[0x14F] = g as u8;
    rom
}
