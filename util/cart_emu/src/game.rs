// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! eda/cart_game: a game cartridge on the FPGA cartridge adapter. The ROM image lives in the Tang
//! Primer 25K's W25Q64 at 4 MiB (written here over single-line SPI through the FPGA, which only
//! lets erase and program through at 4 MiB and above), bank 0 and the cartridge RAM in block RAM.

use crate::{Emu, Status};
use clap::Subcommand;
use std::time::{Duration, Instant};

pub const FLASH_BASE: u32 = 0x40_0000;
pub const FLASH_END: u32 = 0x80_0000;
const BLOCK: u32 = 0x1_0000;

fn num(s: &str) -> Result<u32, String> {
    let r = if let Some(h) = s.strip_prefix("0x") { u32::from_str_radix(h, 16) } else { s.parse() };
    r.map_err(|e| format!("{s}: {e}"))
}

#[derive(Subcommand)]
pub enum GameCmd {
    /// the flash's JEDEC ID and status registers
    FlashId,
    /// read the flash (single line)
    FlashRead {
        #[arg(long, value_parser = num, default_value = "0x400000")]
        offset: u32,
        #[arg(long, value_parser = num, default_value = "0x400000")]
        len: u32,
        #[arg(short, long)]
        out: String,
    },
    /// write a ROM (up to 4 MiB) to the flash at 4 MiB: only the 64 KiB blocks that differ, then verify
    Write { rom: String },
    /// set the cartridge up for a ROM already written (mapper from its header), and answer
    Start {
        rom: String,
        /// cartridge RAM to start with (else 0xFF)
        #[arg(long)]
        sav: Option<String>,
        /// flash capture tick (else calibrated)
        #[arg(long)]
        cap: Option<u8>,
        /// SPI-Quad reads (22 SCLK) instead of QPI (16 SCLK)
        #[arg(long)]
        spiq: bool,
        /// SPI-Quad in continuous read mode (14 SCLK after the first read)
        #[arg(long)]
        cont: bool,
    },
    /// counters
    Status,
    /// clear the counters (and start the trace again at the next boot)
    Clear,
    /// status every few seconds
    Watch {
        #[arg(long, default_value_t = 5)]
        every: u64,
        #[arg(long, default_value_t = 0)]
        count: u32,
    },
    /// save the cartridge RAM (the size of the ROM header's)
    Save {
        rom: String,
        #[arg(short, long)]
        out: String,
    },
    /// print the trace
    Trace {
        #[arg(short, default_value_t = 2048)]
        n: usize,
    },
    /// answer reads only after the address is stable N clocks (10 ns), to measure the margin
    Delay { n: u8 },
    /// count switchable-bank reads whose data came after N clocks (10 ns) as late
    Late { n: u8 },
    /// stop answering and leave QPI mode
    Stop,
    /// (debug) bytes through the quad engine for each capture tick, then the status registers
    #[command(hide = true)]
    Qdump {
        #[arg(long, value_parser = num, default_value = "0x400000")]
        addr: u32,
        #[arg(long, default_value_t = 16)]
        len: usize,
    },
}

struct Game {
    e: Emu,
    /// SPI-Quad reads (EBh on one line) instead of QPI
    spiq: bool,
    /// ... in continuous read mode
    cont: bool,
}

/// what the cartridge needs from the ROM header
struct Header {
    title: String,
    mapper: u8,
    mapper_name: &'static str,
    rmask: u16,
    ram: usize,
}

fn header(img: &[u8]) -> Result<Header, String> {
    if img.len() < 0x8000 || img.len() % 0x4000 != 0 {
        return Err(format!("{} bytes: not a ROM image (a multiple of 16 KiB, 32 KiB or more)", img.len()));
    }
    if img.len() > (FLASH_END - FLASH_BASE) as usize {
        return Err(format!("{} bytes: more than the 4 MiB of flash for it", img.len()));
    }
    let t = img[0x147];
    let (mapper, mapper_name) = match t {
        0x00 | 0x08 | 0x09 => (0, "none"),
        0x01..=0x03 => (1, "MBC1"),
        0x0F..=0x13 => (3, "MBC3"),
        0x19..=0x1E => (5, "MBC5"),
        _ => return Err(format!("cartridge type {t:#04x} is not supported (MBC1 / MBC3 / MBC5)")),
    };
    let banks = (img.len() / 0x4000).next_power_of_two();
    let ram = match img[0x149] {
        0 => 0,
        1 => 2048,
        2 => 8192,
        3 => 32768,
        r => return Err(format!("RAM size code {r:#04x}: more than the 32 KiB here")),
    };
    let title: String = img[0x134..0x143].iter().take_while(|&&c| c != 0).map(|&c| if (0x20..0x7F).contains(&c) { c as char } else { '.' }).collect();
    Ok(Header { title, mapper, mapper_name, rmask: (banks - 1) as u16, ram })
}

impl Game {
    fn open(tty: &str, baud: u32) -> Result<Game, String> { Ok(Game { e: Emu::open(tty, baud, b"GC")?, spiq: false, cont: false }) }
    fn status(&mut self) -> Result<Status, String> { self.e.status() }
    /// one single-line SPI transfer
    fn spi(&mut self, out: &[u8], nin: usize) -> Result<Vec<u8>, String> {
        let mut m = vec![b'F', out.len() as u8, (out.len() >> 8) as u8, nin as u8, (nin >> 8) as u8];
        m.extend_from_slice(out);
        self.e.send(&m)?;
        let r = self.e.recv(nin)?;
        match self.e.recv(1)?[0] {
            b'F' => Ok(r),
            b'f' => Err(format!("SPI transfer {:02x?} refused (quad mode on, or not allowed)", &out[..out.len().min(4)])),
            c => Err(format!("reply {c:02x} to 'F'")),
        }
    }
    fn quad(&mut self, on: bool, cap: u8) -> Result<(), String> {
        self.e.send(&[b'K', on as u8 | (cap & 3) << 1 | (self.spiq as u8) << 3 | (self.cont as u8) << 4])?;
        self.e.ack(b'K')?;
        let t0 = Instant::now();
        loop {
            let ready = self.status()?.raw[8] & 8 != 0;
            if ready == on {
                return Ok(());
            }
            if t0.elapsed() > Duration::from_secs(1) {
                return Err(format!("flash quad mode did not turn {}", if on { "on" } else { "off" }));
            }
        }
    }
    fn wait_busy(&mut self, limit: Duration) -> Result<(), String> {
        let t0 = Instant::now();
        while self.spi(&[0x05], 1)?[0] & 1 != 0 {
            if t0.elapsed() > limit {
                return Err("flash busy for too long".into());
            }
        }
        Ok(())
    }
    fn read(&mut self, addr: u32, len: usize) -> Result<Vec<u8>, String> {
        let mut out = Vec::with_capacity(len);
        while out.len() < len {
            let a = addr + out.len() as u32;
            let n = (len - out.len()).min(4096);
            out.extend(self.spi(&[0x03, (a >> 16) as u8, (a >> 8) as u8, a as u8], n)?);
        }
        Ok(out)
    }
    fn erase_block(&mut self, addr: u32) -> Result<(), String> {
        assert!(addr >= FLASH_BASE && addr % BLOCK == 0);
        self.spi(&[0x06], 0)?;
        self.spi(&[0xD8, (addr >> 16) as u8, (addr >> 8) as u8, addr as u8], 0)?;
        self.wait_busy(Duration::from_secs(3))
    }
    fn program(&mut self, addr: u32, data: &[u8]) -> Result<(), String> {
        assert!(addr >= FLASH_BASE && data.len() <= 256 && (addr & 0xFF) as usize + data.len() <= 256);
        self.spi(&[0x06], 0)?;
        let mut m = vec![0x02, (addr >> 16) as u8, (addr >> 8) as u8, addr as u8];
        m.extend_from_slice(data);
        self.spi(&m, 0)?;
        self.wait_busy(Duration::from_millis(100))
    }
    /// bytes through the quad engine (not while answering)
    fn qread(&mut self, addr: u32, len: usize) -> Result<Vec<u8>, String> { self.e.read(3, addr, len) }
}

fn print_status(g: &mut Game) -> Result<(), String> {
    let s = g.status()?;
    let f = s.raw[3];
    let bank = s.raw[4] as u16 | (s.raw[5] as u16) << 8;
    let ph = s.u32(50);
    println!(
        "cart: {} (delay {} ns) | /RST {} | {} ROM bank {bank:#x} RAM {} bank {} | flash {} cap {} | PHI {:.3} MHz | resets {} | trace {}",
        if f & 1 != 0 { "answering" } else { "silent" },
        s.raw[9] as u32 * 10,
        if f & 8 != 0 { "high" } else { "LOW" },
        ["none", "MBC1", "?", "MBC3", "?", "MBC5", "?", "?"][s.raw[7] as usize & 7],
        if f & 4 != 0 { "on" } else { "off" },
        s.raw[6],
        if s.raw[8] & 8 != 0 { if s.raw[8] & 32 != 0 { "continuous" } else if s.raw[8] & 16 != 0 { "SPI-Quad" } else { "QPI" } } else if s.raw[8] & 4 != 0 { "starting" } else { "single" },
        s.raw[8] & 3,
        ph as f64 / 1e6,
        s.u16(58),
        s.u16(62),
    );
    println!(
        "reads: ROM0 {} ROMX {} (late {}, no data {}, slowest {} ns) RAM {} | writes: MBC {} RAM {} | RAM while off {} | other rd {}",
        s.u32(14),
        s.u32(18),
        s.u32(42),
        s.u32(46),
        s.raw[60] as u32 * 10,
        s.u32(22),
        s.u32(30),
        s.u32(26),
        s.u32(34),
        s.u32(38),
    );
    Ok(())
}

pub fn run(tty: &str, baud: u32, cmd: &GameCmd) -> Result<bool, String> {
    let mut g = Game::open(tty, baud)?;
    let readf = |p: &str| std::fs::read(p).map_err(|e| format!("{p}: {e}"));
    match cmd {
        GameCmd::FlashId => {
            g.e.enable(false)?;
            g.quad(false, 0)?;
            let id = g.spi(&[0x9F], 3)?;
            let sr: Vec<u8> = [0x05, 0x35, 0x15].iter().map(|&c| g.spi(&[c], 1).map(|r| r[0])).collect::<Result<_, _>>()?;
            let uid = g.spi(&[0x4B, 0, 0, 0, 0], 8)?;
            println!("JEDEC ID {:02x} {:02x} {:02x} | SR1 {:#04x} SR2 {:#04x} SR3 {:#04x} | unique ID {:02x?}", id[0], id[1], id[2], sr[0], sr[1], sr[2], uid);
            Ok(true)
        }
        GameCmd::FlashRead { offset, len, out } => {
            g.e.enable(false)?;
            g.quad(false, 0)?;
            let t0 = Instant::now();
            let mut data = Vec::with_capacity(*len as usize);
            while data.len() < *len as usize {
                let n = (*len as usize - data.len()).min(0x10000);
                data.extend(g.read(offset + data.len() as u32, n)?);
                eprint!("\r{} / {} KiB", data.len() / 1024, len / 1024);
            }
            eprintln!();
            std::fs::write(out, &data).map_err(|e| format!("{out}: {e}"))?;
            let ff = data.iter().filter(|&&b| b == 0xFF).count();
            println!("{out}: {} bytes from {offset:#x} in {:.1} s ({ff} bytes are FF)", data.len(), t0.elapsed().as_secs_f64());
            Ok(true)
        }
        GameCmd::Write { rom } => {
            let img = readf(rom)?;
            let h = header(&img)?;
            g.e.enable(false)?;
            g.quad(false, 0)?;
            let id = g.spi(&[0x9F], 3)?;
            // Winbond W25Q64 or the XTX part on later boards (0B 40 17): same commands
            if !matches!(id[0], 0xEF | 0x0B) || id[2] != 0x17 {
                return Err(format!("flash JEDEC ID {id:02x?} is not a 64 Mbit W25Q-compatible part"));
            }
            let t0 = Instant::now();
            let (mut erased, mut pages) = (0, 0);
            for (bi, blk) in img.chunks(BLOCK as usize).enumerate() {
                let addr = FLASH_BASE + bi as u32 * BLOCK;
                let mut cur = g.read(addr, blk.len())?;
                if cur != blk {
                    if cur.iter().zip(blk).any(|(&c, &n)| c & n != n) {
                        g.erase_block(addr)?;
                        erased += 1;
                        cur = vec![0xFF; blk.len()];
                    }
                    for (pi, page) in blk.chunks(256).enumerate() {
                        let o = pi * 256;
                        if &cur[o..o + page.len()] != page {
                            g.program(addr + o as u32, page)?;
                            pages += 1;
                        }
                    }
                    if g.read(addr, blk.len())? != blk {
                        return Err(format!("verify failed in the block at {addr:#x}"));
                    }
                }
                eprint!("\r{} / {} KiB", (bi + 1) * 64, img.len() / 1024);
            }
            eprintln!();
            println!(
                "{rom}: \"{}\" {} {} KiB at flash {FLASH_BASE:#x}: {erased} blocks erased, {pages} pages programmed, verified ({:.1} s)",
                h.title,
                h.mapper_name,
                img.len() / 1024,
                t0.elapsed().as_secs_f64()
            );
            Ok(true)
        }
        GameCmd::Start { rom, sav, cap, spiq, cont } => {
            g.spiq = *spiq || *cont;
            g.cont = *cont;
            let img = readf(rom)?;
            let h = header(&img)?;
            g.e.enable(false)?;
            g.quad(false, 0)?;
            // the image must be in the flash already: compare the start of every bank
            for b in 0..img.len() / 0x4000 {
                let a = b * 0x4000;
                if g.read(FLASH_BASE + a as u32, 64)? != img[a..a + 64] {
                    return Err(format!("the flash does not hold {rom} (bank {b:#x} differs): run `game write` first"));
                }
            }
            let mut ram = vec![0xFF; 32768];
            if let Some(p) = sav {
                let s = readf(p)?;
                let n = s.len().min(32768);
                ram[..n].copy_from_slice(&s[..n]);
            }
            let xmask: u8 = if h.ram >= 32768 { 3 } else { 0 } | if h.ram > 0 { 0x80 } else { 0 };
            g.e.send(&[b'M', h.mapper, h.rmask as u8, (h.rmask >> 8) as u8, xmask])?;
            g.e.ack(b'M')?;
            g.e.write(0, 0, &img[..0x4000])?;
            g.e.write(1, 0, &ram)?;
            if g.e.read(0, 0, 0x4000)? != img[..0x4000] {
                return Err("bank 0 read back differs".into());
            }
            // quad mode, and the capture tick
            let spots: Vec<u32> = (0..img.len() / 0x4000).step_by((img.len() / 0x4000 / 8).max(1)).map(|b| (b * 0x4000 + 0x1F0) as u32).collect();
            let mut good = vec![];
            for c in 0..4u8 {
                if cap.is_some_and(|k| k != c) {
                    continue;
                }
                g.quad(true, c)?;
                let mut ok = true;
                for &o in &spots {
                    if g.qread(FLASH_BASE + o, 256)? != img[o as usize..o as usize + 256] {
                        ok = false;
                        break;
                    }
                }
                println!("capture tick {c}: {}", if ok { "reads match" } else { "differs" });
                if ok {
                    good.push(c);
                }
            }
            if good.is_empty() {
                return Err("no capture tick reads the flash right in quad mode".into());
            }
            let c = good[good.len() / 2];
            g.quad(true, c)?;
            g.e.send(b"C")?;
            g.e.ack(b'C')?;
            g.e.arm(false, true, true)?;
            g.e.enable(true)?;
            println!(
                "\"{}\" {} {} KiB, RAM {} KiB{}: answering (capture tick {c}); boot the console now",
                h.title,
                h.mapper_name,
                img.len() / 1024,
                h.ram / 1024,
                if sav.is_some() { " (from the save)" } else { "" }
            );
            Ok(true)
        }
        GameCmd::Clear => {
            g.e.send(b"C")?;
            g.e.ack(b'C')?;
            g.e.arm(false, true, true)?;
            Ok(true)
        }
        GameCmd::Status => {
            print_status(&mut g)?;
            Ok(true)
        }
        GameCmd::Watch { every, count } => {
            let mut i = 0;
            loop {
                println!("--- {i}");
                print_status(&mut g)?;
                i += 1;
                if *count != 0 && i >= *count {
                    return Ok(true);
                }
                std::thread::sleep(Duration::from_secs(*every));
            }
        }
        GameCmd::Save { rom, out } => {
            let h = header(&readf(rom)?)?;
            if h.ram == 0 {
                return Err(format!("{rom} has no cartridge RAM"));
            }
            let r = g.e.read(1, 0, h.ram)?;
            std::fs::write(out, &r).map_err(|e| format!("{out}: {e}"))?;
            println!("{out}: {} bytes", r.len());
            Ok(true)
        }
        GameCmd::Trace { n } => {
            let s = g.status()?;
            let have = (s.u16(62) as usize).min(*n);
            let t = g.e.read(2, 0, have * 8)?;
            let mut last = 0u32;
            for (i, en) in t.chunks(8).enumerate() {
                let a = u16::from_le_bytes([en[0], en[1]]);
                let (d, fl) = (en[2], en[3]);
                let time = u32::from_le_bytes(en[4..8].try_into().unwrap());
                println!(
                    "{i:5} {:12.2} us (+{:8.2}) {} {a:04x} {d:02x}{}{}{}",
                    time as f64 / 100.0,
                    time.wrapping_sub(last) as f64 / 100.0,
                    if fl & 1 != 0 { "W" } else { "R" },
                    if fl & 2 != 0 { " /CS" } else { "" },
                    if fl & 4 != 0 { " ram_on" } else { "" },
                    if fl & 16 != 0 { " NO-DATA" } else { "" },
                );
                last = time;
            }
            Ok(true)
        }
        GameCmd::Late { n } => {
            g.e.send(&[b'L', *n])?;
            g.e.ack(b'L')?;
            Ok(true)
        }
        GameCmd::Delay { n } => {
            g.e.send(&[b'D', *n])?;
            g.e.ack(b'D')?;
            Ok(true)
        }
        GameCmd::Qdump { addr, len } => {
            g.e.enable(false)?;
            g.quad(false, 0)?;
            println!("single: {:02x?}", g.read(*addr, *len)?);
            for (sp, co) in [(false, false), (true, false), (true, true)] {
                g.spiq = sp;
                g.cont = co;
                for c in 0..4 {
                    g.quad(true, c)?;
                    println!("{} cap {c}: {:02x?}", if co { "continuous" } else if sp { "SPI-Quad" } else { "QPI" }, g.qread(*addr, *len)?);
                }
                g.quad(false, 0)?;
            }
            let sr: Vec<u8> = [0x05, 0x35, 0x15].iter().map(|&c| g.spi(&[c], 1).map(|r| r[0])).collect::<Result<_, _>>()?;
            println!("after exit: SR1 {:#04x} SR2 {:#04x} SR3 {:#04x}, single: {:02x?}", sr[0], sr[1], sr[2], g.read(*addr, 4)?);
            Ok(true)
        }
        GameCmd::Stop => {
            g.e.enable(false)?;
            g.quad(false, 0)?;
            println!("silent, flash back in single-line mode");
            Ok(true)
        }
    }
}
