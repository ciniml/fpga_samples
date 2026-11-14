// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Command protocol of rtl/chromatic/cart_cmd.veryl.

use crate::link::Link;
use std::time::{Duration, Instant};

pub const PROTO: u8 = 3;

#[derive(Clone, Copy, Debug)]
pub struct Status {
    pub flags: u8,
    pub rst_high: bool,
    pub reject_cnt: u8,
    pub err: u8,
    /// the cartridge RAM is enabled (the device disables it itself when RAM mode ends)
    pub ram_on: bool,
}

impl Status {
    pub fn cart(&self) -> bool { self.flags & 0x01 != 0 }
    pub fn switch_on(&self) -> bool { self.flags & 0x02 != 0 }
    pub fn power_req(&self) -> bool { self.flags & 0x04 != 0 }
    pub fn pwr_en(&self) -> bool { self.flags & 0x08 != 0 }
    pub fn ready(&self) -> bool { self.flags & 0x10 != 0 }
    pub fn legacy(&self) -> bool { self.flags & 0x20 != 0 }
    pub fn ram_mode(&self) -> bool { self.flags & 0x80 != 0 }
    pub fn describe(&self) -> String {
        format!(
            "cartridge {} / switch {} / power request {} / slot power {} / bus {} / /RST {} / board {}{}{}{}",
            if self.cart() { "inserted" } else { "none" },
            if self.switch_on() { "ON" } else { "OFF" },
            self.power_req() as u8,
            if self.legacy() { "n/a" } else if self.pwr_en() { "on" } else { "off" },
            if self.ready() { "ready" } else { "not ready" },
            if self.rst_high { "high" } else { "low" },
            if self.legacy() { "legacy" } else { "new" },
            if self.reject_cnt != 0 { format!(" / refused writes {}", self.reject_cnt) } else { String::new() },
            if self.err != 0 { format!(" / err {:03b}", self.err) } else { String::new() },
            match (self.ram_mode(), self.ram_on) {
                (false, false) => "",
                (true, false) => " / RAM mode",
                (true, true) => " / RAM mode, RAM enabled",
                (false, true) => " / RAM enabled (being disabled)",
            },
        )
    }
}

pub struct Reader<L: Link> {
    pub link: L,
}

#[derive(Debug, PartialEq, Eq)]
pub enum WriteResult {
    Done,
    Refused,
    NotReady,
}

impl<L: Link> Reader<L> {
    pub fn new(link: L) -> Self { Reader { link } }

    /// resynchronise the stream and check the protocol
    pub fn hello(&mut self) -> Result<Status, String> {
        let s = self.status()?;
        Ok(s)
    }

    pub fn status(&mut self) -> Result<Status, String> {
        self.link.send(b"S")?;
        let mut b = [0u8; 8];
        self.link.recv(&mut b)?;
        if &b[0..2] != b"CR" {
            return Err(format!("unexpected status reply {b:02x?} (wrong design, or the stream is out of step: reload the FPGA)"));
        }
        if b[2] != PROTO {
            return Err(format!("protocol {} (this tool speaks {PROTO})", b[2]));
        }
        Ok(Status { flags: b[3], rst_high: b[4] & 1 != 0, reject_cnt: b[5], err: b[6], ram_on: b[7] & 1 != 0 })
    }

    pub fn power(&mut self, on: bool) -> Result<u8, String> {
        self.link.send(&[b'P', on as u8])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        if b[0] != b'P' {
            return Err(format!("unexpected power reply {b:02x?}"));
        }
        Ok(b[1])
    }

    /// RAM mode on / off ('A'): Ok(granted)
    pub fn ram_mode(&mut self, on: bool) -> Result<bool, String> {
        self.link.send(&[b'A', on as u8])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        if b[0] != b'A' {
            return Err(format!("unexpected RAM mode reply {b:02x?}"));
        }
        Ok(b[1] & 0x80 != 0)
    }

    /// leave RAM mode and wait until the device has disabled the cartridge RAM
    pub fn ram_off(&mut self) -> Result<(), String> {
        self.ram_mode(false)?;
        let t0 = Instant::now();
        loop {
            let s = self.status()?;
            if !s.ram_on && !s.ram_mode() {
                return Ok(());
            }
            if t0.elapsed() > Duration::from_secs(2) {
                return Err(format!("the cartridge RAM is still enabled: {}", s.describe()));
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    /// power the slot and wait until the bus is ready and the cartridge released /RST
    pub fn power_up(&mut self, timeout: Duration) -> Result<Status, String> {
        let s = self.status()?;
        if !s.cart() {
            return Err(format!("no cartridge detected ({})", s.describe()));
        }
        if !s.switch_on() {
            return Err("the power switch is OFF".into());
        }
        let flags = self.power(true)?;
        if flags & 0x04 == 0 {
            return Err(format!("power request refused (flags {flags:02x})"));
        }
        let t0 = Instant::now();
        loop {
            let s = self.status()?;
            if s.ready() && s.rst_high {
                return Ok(s);
            }
            if t0.elapsed() > timeout {
                if s.ready() {
                    eprintln!("warning: the cartridge keeps /RST low, reading anyway");
                    return Ok(s);
                }
                return Err(format!("slot not ready: {}", s.describe()));
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    /// `len` bytes from `addr` (one bus read each)
    pub fn read(&mut self, addr: u16, len: usize) -> Result<Vec<u8>, String> {
        let mut out = Vec::with_capacity(len);
        let mut a = addr as usize;
        while out.len() < len {
            let n = (len - out.len()).min(0x4000);
            let cmd = [b'R', a as u8, (a >> 8) as u8, n as u8, (n >> 8) as u8];
            self.link.send(&cmd)?;
            let mut buf = vec![0u8; n];
            self.link.recv(&mut buf)?;
            out.extend_from_slice(&buf);
            a = (a + n) & 0xFFFF;
        }
        Ok(out)
    }

    /// MBC7 EEPROM words from `addr` ('E', read-only engine in the FPGA), high byte first.
    /// Needs RAM mode and 0x0000 <- 0x0A; otherwise the words read FFFF and err bit 3 is set.
    pub fn eeprom(&mut self, addr: u8, words: usize) -> Result<Vec<u8>, String> {
        let n = words.clamp(1, 256);
        let c = if n == 256 { 0 } else { n };
        self.link.send(&[b'E', addr, c as u8, (c >> 8) as u8])?;
        let mut buf = vec![0u8; n * 2];
        self.link.recv(&mut buf)?;
        Ok(buf)
    }

    /// MBC register write (the device refuses anything outside its whitelist)
    pub fn write(&mut self, addr: u16, data: u8) -> Result<WriteResult, String> {
        self.link.send(&[b'W', addr as u8, (addr >> 8) as u8, data])?;
        let mut b = [0u8; 2];
        self.link.recv(&mut b)?;
        match (b[0], b[1]) {
            (b'W', 0) => Ok(WriteResult::Done),
            (b'W', 1) => Ok(WriteResult::Refused),
            (b'W', 2) => Ok(WriteResult::NotReady),
            _ => Err(format!("unexpected write reply {b:02x?}")),
        }
    }

    /// write that must succeed
    pub fn mbc(&mut self, addr: u16, data: u8) -> Result<(), String> {
        match self.write(addr, data)? {
            WriteResult::Done => Ok(()),
            r => Err(format!("MBC write {addr:04x} <- {data:02x}: {r:?}")),
        }
    }
}
