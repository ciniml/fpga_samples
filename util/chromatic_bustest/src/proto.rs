// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Commands of rtl/chromatic/bt_cmd.veryl (Master, the Chromatic) and
//! rtl/chromatic/cart_target.veryl (Target, the board on the adapter).
#![allow(dead_code)]

use crate::link::Link;
use std::time::{Duration, Instant};

pub const OP_FILL: u8 = 0;
pub const OP_VERIFY: u8 = 1;
pub const OP_MIX: u8 = 2;

fn u16le(b: &[u8]) -> u16 { u16::from_le_bytes([b[0], b[1]]) }
fn u32le(b: &[u8]) -> u32 { u32::from_le_bytes([b[0], b[1], b[2], b[3]]) }

// ---------------------------------------------------------------- master

#[derive(Clone, Copy, Debug)]
pub struct MStatus {
    pub flags: u8,
    pub rst_high: bool,
    pub cyc: u8,
    pub sample: u8,
    pub wr_on: u8,
    pub wr_off: u8,
    pub d_seen: u8,
}

impl MStatus {
    pub fn cart(&self) -> bool { self.flags & 0x01 != 0 }
    pub fn switch_on(&self) -> bool { self.flags & 0x02 != 0 }
    pub fn ready(&self) -> bool { self.flags & 0x10 != 0 }
    pub fn unlocked(&self) -> bool { self.flags & 0x40 != 0 }
    pub fn describe(&self) -> String {
        format!(
            "slot {} / switch {} / bus {} / {} / /RST {} / timing cyc {} sample {} wr {}-{}",
            if self.cart() { "occupied" } else { "empty" },
            if self.switch_on() { "ON" } else { "OFF" },
            if self.ready() { "ready" } else { "not ready" },
            if self.unlocked() { "unlocked" } else { "locked" },
            if self.rst_high { "high" } else { "low" },
            self.cyc, self.sample, self.wr_on, self.wr_off
        )
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct MResult {
    pub status: u8,
    pub ops: u32,
    pub errors: u32,
    pub f_idx: u32,
    pub f_addr: u16,
    pub f_exp: u8,
    pub f_got: u8,
    pub xor_or: u8,
    pub us: u32,
}

pub struct Master<L: Link> {
    pub link: L,
}

impl<L: Link> Master<L> {
    pub fn status(&mut self) -> Result<MStatus, String> {
        self.link.send(b"S")?;
        let mut b = [0u8; 16];
        self.link.recv(&mut b)?;
        if &b[0..2] != b"BT" || b[2] != 1 {
            return Err(format!("unexpected master status {b:02x?} (is eda/chromatic_cart_bustest loaded?)"));
        }
        Ok(MStatus { flags: b[3], rst_high: b[4] & 1 != 0, cyc: b[5], sample: b[6], wr_on: b[7], wr_off: b[8], d_seen: b[9] })
    }
    pub fn power(&mut self, on: bool) -> Result<u8, String> {
        self.link.send(&[b'P', on as u8])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        Ok(b[1])
    }
    pub fn power_up(&mut self) -> Result<MStatus, String> {
        let s = self.status()?;
        if !s.cart() || !s.switch_on() {
            return Err(format!("cannot power the slot: {}", s.describe()));
        }
        self.power(true)?;
        let t0 = Instant::now();
        loop {
            let s = self.status()?;
            if s.ready() {
                return Ok(s);
            }
            if t0.elapsed() > Duration::from_secs(3) {
                return Err(format!("slot not ready: {}", s.describe()));
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }
    pub fn timing(&mut self, cyc: u8, sample: u8, wr_on: u8, wr_off: u8) -> Result<(), String> {
        self.link.send(&[b'T', cyc, sample, wr_on, wr_off])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        if b[1] != 1 {
            return Err(format!("timing cyc {cyc} sample {sample} wr {wr_on}-{wr_off} refused"));
        }
        Ok(())
    }
    /// handshake with the target (in its ID mode): Ok(unlocked, bytes read)
    pub fn handshake(&mut self) -> Result<(bool, [u8; 4]), String> {
        self.link.send(b"H")?;
        let mut b = [0u8; 6];
        self.link.recv(&mut b)?;
        Ok((b[1] == 1, [b[2], b[3], b[4], b[5]]))
    }
    pub fn read(&mut self, addr: u16, len: usize) -> Result<Vec<u8>, String> {
        let n = if len >= 0x10000 { 0 } else { len };
        self.link.send(&[b'R', addr as u8, (addr >> 8) as u8, n as u8, (n >> 8) as u8])?;
        let mut v = vec![0u8; if n == 0 { 0x10000 } else { n }];
        self.link.recv(&mut v)?;
        Ok(v)
    }
    pub fn write(&mut self, addr: u16, d: u8) -> Result<u8, String> {
        self.link.send(&[b'W', addr as u8, (addr >> 8) as u8, d])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        Ok(b[1])
    }
    /// static mode (ctl: [0] /RD [1] /WR [2] /CS [3] PHI [4] drive D [5] DIR_E): D pins as seen
    pub fn static_pins(&mut self, en: bool, a: u16, ctl: u8, d: u8) -> Result<u8, String> {
        self.link.send(&[b'Z', en as u8, a as u8, (a >> 8) as u8, ctl, d])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        Ok(b[1])
    }
    pub fn rst_force(&mut self, low: bool) -> Result<(), String> {
        self.link.send(&[b'G', low as u8])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)
    }
    pub fn run(&mut self, op: u8, cart: bool, seed: u32, count: u32) -> Result<MResult, String> {
        let mut c = vec![b'X', op, cart as u8];
        c.extend_from_slice(&seed.to_le_bytes());
        c.extend_from_slice(&count.to_le_bytes());
        self.link.send(&c)?;
        let mut b = [0u8; 24];
        self.link.recv(&mut b)?;
        if b[0] != b'X' {
            return Err(format!("unexpected run reply {b:02x?}"));
        }
        Ok(MResult {
            status: b[1], ops: u32le(&b[2..]), errors: u32le(&b[6..]), f_idx: u32le(&b[10..]), f_addr: u16le(&b[14..]),
            f_exp: b[16], f_got: b[17], xor_or: b[18], us: u32le(&b[19..]),
        })
    }
}

// ---------------------------------------------------------------- target

#[derive(Clone, Copy, Debug, Default)]
pub struct TStatus {
    pub mode: u8,
    pub dly: u8,
    pub flags: u8,
    pub a: u16,
    pub ctl: u8, // [0] /RD [1] /WR [2] /CS [3] PHI [4] /RST
    pub d: u8,
    pub rd_cnt: u32,
    pub wr_cnt: u32,
    pub phi_edges: u32,
    pub phi_high: u32,
    pub seen: u32,
    pub errs: u32,
    pub axor: u16,
    pub dxor: u8,
    pub rwerr: u32,
    pub cserr: u32,
    pub extra: u32,
    pub f_idx: u32,
    pub f_oa: u16,
    pub f_ea: u16,
    pub f_od: u8,
    pub f_ed: u8,
    pub f_flags: u8, // [0] observed write [1] expected write [2] observed /CS [3] expected /CS
}

pub struct Target<L: Link> {
    pub link: L,
}

impl<L: Link> Target<L> {
    pub fn status(&mut self) -> Result<TStatus, String> {
        self.link.send(b"S")?;
        let mut b = [0u8; 64];
        self.link.recv(&mut b)?;
        if &b[0..2] != b"TG" || b[2] != 1 {
            return Err(format!("unexpected target status {:02x?} (is eda/cart_target loaded?)", &b[..8]));
        }
        Ok(TStatus {
            mode: b[3], dly: b[4], flags: b[5], a: u16le(&b[6..]), ctl: b[8], d: b[9], rd_cnt: u32le(&b[10..]),
            wr_cnt: u32le(&b[14..]), phi_edges: u32le(&b[18..]), phi_high: u32le(&b[22..]), seen: u32le(&b[26..]),
            errs: u32le(&b[30..]), axor: u16le(&b[34..]), dxor: b[36], rwerr: u32le(&b[38..]), cserr: u32le(&b[42..]),
            extra: u32le(&b[46..]), f_idx: u32le(&b[50..]), f_oa: u16le(&b[54..]), f_ea: u16le(&b[56..]), f_od: b[58],
            f_ed: b[59], f_flags: b[60],
        })
    }
    fn cmd(&mut self, c: &[u8]) -> Result<(), String> {
        self.link.send(c)?;
        let mut b = [0u8; 1];
        self.link.recv(&mut b)?;
        if b[0] != c[0] {
            return Err(format!("unexpected target reply {:02x} to {:02x}", b[0], c[0]));
        }
        Ok(())
    }
    /// 0 ID, 1 RAM (all), 2 RAM (cartridge map), 3 silent
    pub fn mode(&mut self, mode: u8, dly: u8) -> Result<(), String> { self.cmd(&[b'M', mode, dly]) }
    pub fn arm(&mut self, op: u8, cart: bool, seed: u32, count: u32) -> Result<(), String> {
        let mut c = vec![b'C', op, cart as u8];
        c.extend_from_slice(&seed.to_le_bytes());
        c.extend_from_slice(&count.to_le_bytes());
        self.cmd(&c)
    }
    pub fn drive(&mut self, en: bool, d: u8) -> Result<(), String> { self.cmd(&[b'D', en as u8, d]) }
    pub fn rst_drv(&mut self, on: bool) -> Result<(), String> { self.cmd(&[b'R', on as u8]) }
    pub fn aud(&mut self, on: bool) -> Result<(), String> { self.cmd(&[b'A', on as u8]) }
}
