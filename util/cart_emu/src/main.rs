// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Host tool of eda/cart_emu: a Tang Primer 25K on the FPGA cartridge adapter (gb_fpga_cart_de0)
//! as an MBC5 cartridge that a console boots (L4 of the adapter test). Builds the test ROM,
//! loads it over the Dock's UART and reads the counters, the trace and the CPU's results.

mod rom;

use clap::{Parser, Subcommand};
use std::{io::{Read, Write}, time::Duration};

#[derive(Parser)]
#[command(version, about = "MBC5 cartridge on the FPGA cartridge adapter (eda/cart_emu) and the L4 test ROM")]
struct Cli {
    #[arg(long, global = true, default_value = "/dev/ttyUSB1")]
    tty: String,
    #[arg(long, global = true, default_value_t = 1_000_000)]
    baud: u32,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// build the L4 test ROM
    Rom {
        /// a cartridge image to take the 48 logo bytes (0x0104-0x0133) from
        #[arg(long)]
        logo_from: String,
        /// switch the CGB to double speed first
        #[arg(long)]
        double: bool,
        #[arg(short, long)]
        out: String,
    },
    /// load a ROM (up to 64 KiB), clear the RAM, arm the trace for the next /RST rise, answer
    Load {
        rom: String,
        /// RAM fill byte
        #[arg(long, default_value_t = 0xFF)]
        fill: u8,
    },
    /// counters and, for the L4 ROM, the CPU's results
    Status {
        /// the ROM that was loaded (for the expected sums)
        #[arg(long)]
        rom: Option<String>,
    },
    /// status every few seconds
    Watch {
        #[arg(long)]
        rom: Option<String>,
        #[arg(long, default_value_t = 5)]
        every: u64,
        #[arg(long, default_value_t = 0)]
        count: u32,
    },
    /// print the trace
    Trace {
        #[arg(short, default_value_t = 2048)]
        n: usize,
    },
    /// re-arm the trace: now, or at the next /RST rise
    Arm {
        #[arg(long)]
        at_reset: bool,
        /// every cycle (not only the cartridge's)
        #[arg(long)]
        all: bool,
    },
    /// save the cartridge RAM
    Ram {
        #[arg(short, long)]
        out: String,
    },
    /// answer the bus (1) or not (0)
    Enable { on: u8 },
    /// clear the counters (and re-arm the trace for the next boot)
    Clear,
}

struct Emu {
    port: Box<dyn serialport::SerialPort>,
    en: bool,
}

struct Status {
    raw: [u8; 64],
}

impl Status {
    fn u32(&self, o: usize) -> u32 { u32::from_le_bytes(self.raw[o..o + 4].try_into().unwrap()) }
    fn u16(&self, o: usize) -> u16 { u16::from_le_bytes(self.raw[o..o + 2].try_into().unwrap()) }
}

impl Emu {
    fn open(tty: &str, baud: u32) -> Result<Emu, String> {
        let port = serialport::new(tty, baud).timeout(Duration::from_secs(3)).open().map_err(|e| format!("{tty}: {e}"))?;
        let _ = port.clear(serialport::ClearBuffer::All);
        let mut e = Emu { port, en: false };
        let st = e.status()?;
        if &st.raw[0..2] != b"CE" {
            return Err(format!("{tty}: not eda/cart_emu (status {:02x?})", &st.raw[0..3]));
        }
        e.en = st.raw[3] & 1 != 0;
        Ok(e)
    }
    fn send(&mut self, d: &[u8]) -> Result<(), String> { self.port.write_all(d).map_err(|e| format!("UART write: {e}")) }
    fn recv(&mut self, n: usize) -> Result<Vec<u8>, String> {
        let mut b = vec![0; n];
        self.port.read_exact(&mut b).map_err(|e| format!("UART read: {e}"))?;
        Ok(b)
    }
    fn ack(&mut self, c: u8) -> Result<(), String> {
        let r = self.recv(1)?;
        if r[0] != c { Err(format!("reply {:02x} to '{}'", r[0], c as char)) } else { Ok(()) }
    }
    fn status(&mut self) -> Result<Status, String> {
        self.send(b"S")?;
        let r = self.recv(64)?;
        Ok(Status { raw: r.try_into().unwrap() })
    }
    fn enable(&mut self, en: bool) -> Result<(), String> {
        self.send(&[b'E', en as u8])?;
        self.ack(b'E')?;
        self.en = en;
        Ok(())
    }
    fn hdr(op: u8, reg: u8, addr: u32, len: u16) -> [u8; 7] {
        [op, reg, addr as u8, (addr >> 8) as u8, (addr >> 16) as u8, len as u8, (len >> 8) as u8]
    }
    fn write(&mut self, reg: u8, addr: u32, data: &[u8]) -> Result<(), String> {
        for (i, ch) in data.chunks(4096).enumerate() {
            let mut m = Self::hdr(b'W', reg, addr + (i * 4096) as u32, ch.len() as u16).to_vec();
            m.extend_from_slice(ch);
            self.send(&m)?;
            self.ack(b'W')?;
        }
        Ok(())
    }
    fn read(&mut self, reg: u8, addr: u32, len: usize) -> Result<Vec<u8>, String> {
        let mut out = Vec::with_capacity(len);
        while out.len() < len {
            let n = (len - out.len()).min(4096);
            self.send(&Self::hdr(b'Q', reg, addr + out.len() as u32, n as u16))?;
            out.extend(self.recv(n)?);
        }
        Ok(out)
    }
    fn arm(&mut self, now: bool, at_reset: bool, cart_only: bool) -> Result<(), String> {
        self.send(&[b'T', now as u8 | (at_reset as u8) << 1 | (cart_only as u8) << 2])?;
        self.ack(b'T')
    }
}

fn print_status(e: &mut Emu, exp: Option<&[u8]>) -> Result<bool, String> {
    let s = e.status()?;
    let f = s.raw[3];
    let rbank = s.raw[4] as u16 | (s.raw[5] as u16) << 8;
    let ph = s.u32(43);
    let duty = if ph > 0 { s.u32(47) as f64 / 1e6 } else { 0.0 };
    println!(
        "cart: {} | /RST {} | RAM {} | ROM bank {rbank:#x} RAM bank {} | PHI {:.3} MHz ({:.1} %) | resets {} | trace {} entries{}",
        if f & 1 != 0 { "answering" } else { "silent" },
        if f & 8 != 0 { "high" } else { "LOW" },
        if f & 4 != 0 { "on" } else { "off" },
        s.raw[6],
        ph as f64 / 1e6,
        duty,
        s.u16(51),
        s.u16(53),
        if f & 16 != 0 { " (on)" } else if f & 32 != 0 { " (waiting for /RST)" } else { "" },
    );
    println!(
        "reads: ROM0 {} ROMX {} RAM {} | writes: MBC {} RAM {} | RAM while off {} | other: rd {} wr {}",
        s.u32(11),
        s.u32(15),
        s.u32(19),
        s.u32(27),
        s.u32(23),
        s.u32(31),
        s.u32(35),
        s.u32(39)
    );
    // the L4 ROM's results
    let r = e.read(1, 0, 0x40)?;
    if &r[0..4] != b"L4GO" {
        println!("CPU: not started (RAM {:02x?})", &r[0..8]);
        return Ok(false);
    }
    let pass = u32::from_le_bytes(r[0x10..0x14].try_into().unwrap());
    let fail = u32::from_le_bytes(r[0x14..0x18].try_into().unwrap());
    let mut line = format!(
        "CPU: boot A={:#04x} B={:#04x} KEY1={:#04x} | rounds passed {pass} failed {fail} | last failed check {} | RAM mismatches {}",
        r[4], r[5], r[6], r[0x18], r[0x19]
    );
    let sums: Vec<u16> = (0..rom::CHECKS.len()).map(|k| u16::from_le_bytes([r[0x20 + 2 * k], r[0x21 + 2 * k]])).collect();
    let mut ok = fail == 0 && r[0x19] == 0;
    if let Some(img) = exp {
        let want: Vec<u16> = rom::CHECKS.iter().map(|&(b, _)| rom::bank_sum(img, (b as usize) & 3)).collect();
        let bad: Vec<String> =
            rom::CHECKS.iter().zip(sums.iter().zip(&want)).filter(|(_, (g, w))| g != w).map(|(c, (g, w))| format!("bank {:#x}: {g:#06x} != {w:#06x}", c.0)).collect();
        if bad.is_empty() {
            line += " | sums = image";
        } else {
            line += &format!(" | {}", bad.join(", "));
            ok = false;
        }
    }
    println!("{line}");
    Ok(ok && pass > 0)
}

fn run(cli: &Cli) -> Result<bool, String> {
    if let Cmd::Rom { logo_from, double, out } = &cli.cmd {
        let src = std::fs::read(logo_from).map_err(|e| format!("{logo_from}: {e}"))?;
        if src.len() < 0x150 {
            return Err(format!("{logo_from}: too short"));
        }
        let img = rom::build(&src[0x104..0x134], *double);
        std::fs::write(out, &img).map_err(|e| format!("{out}: {e}"))?;
        let sums: Vec<String> = (0..4).map(|k| format!("{:#06x}", rom::bank_sum(&img, k))).collect();
        println!("{out}: {} bytes, header checksum {:#04x}, bank sums {}", img.len(), img[0x14D], sums.join(" "));
        return Ok(true);
    }
    let mut e = Emu::open(&cli.tty, cli.baud)?;
    let load = |p: &Option<String>| -> Result<Option<Vec<u8>>, String> { p.as_ref().map(|p| std::fs::read(p).map_err(|e| format!("{p}: {e}"))).transpose() };
    match &cli.cmd {
        Cmd::Rom { .. } => unreachable!(),
        Cmd::Load { rom, fill } => {
            let img = std::fs::read(rom).map_err(|e| format!("{rom}: {e}"))?;
            if img.is_empty() || img.len() > rom::ROM_SIZE {
                return Err(format!("{rom}: {} bytes (1 to 64 KiB)", img.len()));
            }
            e.enable(false)?;
            e.write(0, 0, &img)?;
            e.write(1, 0, &vec![*fill; 8192])?;
            let back = e.read(0, 0, img.len())?;
            if back != img {
                let i = back.iter().zip(&img).position(|(a, b)| a != b).unwrap_or(0);
                return Err(format!("ROM read back differs at {i:#x}: {:#04x} != {:#04x}", back[i], img[i]));
            }
            if e.read(1, 0, 8192)?.iter().any(|&b| b != *fill) {
                return Err("RAM read back differs".into());
            }
            e.send(b"C")?;
            e.ack(b'C')?;
            e.arm(false, true, true)?;
            e.enable(true)?;
            println!("{rom}: {} bytes loaded and verified, RAM filled with {fill:#04x}; answering, trace waits for /RST", img.len());
            Ok(true)
        }
        Cmd::Status { rom } => print_status(&mut e, load(rom)?.as_deref()),
        Cmd::Watch { rom, every, count } => {
            let img = load(rom)?;
            let mut i = 0;
            let mut ok;
            loop {
                println!("--- {}", i);
                ok = print_status(&mut e, img.as_deref())?;
                i += 1;
                if *count != 0 && i >= *count {
                    break;
                }
                std::thread::sleep(Duration::from_secs(*every));
            }
            Ok(ok)
        }
        Cmd::Trace { n } => {
            let s = e.status()?;
            let have = (s.u16(53) as usize).min(*n);
            let t = e.read(2, 0, have * 8)?;
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
                    if fl & 8 != 0 { "" } else { " /RST" },
                );
                last = time;
            }
            Ok(true)
        }
        Cmd::Arm { at_reset, all } => {
            e.arm(!at_reset, *at_reset, !all)?;
            Ok(true)
        }
        Cmd::Ram { out } => {
            let r = e.read(1, 0, 8192)?;
            std::fs::write(out, &r).map_err(|e| format!("{out}: {e}"))?;
            if &r[0..4] == b"L4GO" {
                let bad = (rom::RAM_PATTERN_START..8192).filter(|&i| r[i] != rom::ram_pattern(i)).count();
                println!("{out}: 8192 bytes, L4 pattern 0xA100-0xBFFF: {bad} bytes differ");
            } else {
                println!("{out}: 8192 bytes");
            }
            Ok(true)
        }
        Cmd::Clear => {
            e.send(b"C")?;
            e.ack(b'C')?;
            e.arm(false, true, true)?;
            Ok(true)
        }
        Cmd::Enable { on } => {
            e.enable(*on != 0)?;
            Ok(true)
        }
    }
}

fn main() {
    let cli = Cli::parse();
    match run(&cli) {
        Ok(true) => {}
        Ok(false) => std::process::exit(1),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(2);
        }
    }
}
