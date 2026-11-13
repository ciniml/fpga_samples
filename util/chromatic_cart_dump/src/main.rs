// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Game Boy cartridge ROM dumper for a ModRetro Chromatic running eda/chromatic_cart_dump.
//!
//! The FPGA only offers single-byte bus reads and MBC register writes (it refuses every write
//! outside a small whitelist and never selects cartridge RAM); this tool reads the header,
//! decides the mapper, switches banks and saves the image.

mod header;
mod link;
mod proto;

use clap::{Parser, Subcommand};
use header::{global_checksum_calc, Header, Mapper};
use link::{Link, SimLink, UsbLink};
use proto::Reader;
use sha1::{Digest, Sha1};
use std::{path::PathBuf, time::{Duration, Instant}};

#[derive(Parser)]
#[command(version, about = "Read the ROM of the cartridge in a ModRetro Chromatic (eda/chromatic_cart_dump)")]
struct Cli {
    /// talk to the Verilator model (rtl/chromatic/test, `make simexe`) instead of the USB device
    #[arg(long, global = true, value_name = "EXE")]
    sim: Option<String>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// show the reader / slot state
    Status,
    /// power the slot and show the cartridge header
    Header {
        /// leave the slot powered afterwards
        #[arg(long)]
        keep_power: bool,
    },
    /// dump the whole ROM
    Dump {
        /// output file (default: <title>.gb / .gbc)
        #[arg(short, long)]
        output: Option<PathBuf>,
        /// read everything twice and compare
        #[arg(long)]
        verify: bool,
        /// override the mapper from the header (none, mbc1, mbc2, mbc3, mbc5, mbc7, camera, huc1, huc3)
        #[arg(long)]
        mapper: Option<String>,
        /// override the number of 16 KiB banks from the header
        #[arg(long)]
        banks: Option<usize>,
        /// MBC1 multicart wiring (detected automatically for 1 MiB MBC1 cartridges)
        #[arg(long)]
        mbc1m: bool,
        /// dump even when the header checksum is wrong / the mapper is unsupported (banks 0-1 only)
        #[arg(long)]
        force: bool,
        /// leave the slot powered afterwards
        #[arg(long)]
        keep_power: bool,
    },
}

const BANK: usize = 0x4000;

struct Banker {
    mapper: Mapper,
    mbc1m: bool,
}

impl Banker {
    /// put the MBC in a known state: cartridge RAM / RTC disabled, banking mode 0
    fn init<L: Link>(&self, r: &mut Reader<L>) -> Result<(), String> {
        match self.mapper {
            Mapper::RomOnly => {}
            Mapper::Mbc1 => {
                r.mbc(0x0000, 0x00)?;
                r.mbc(0x6000, 0x00)?;
                r.mbc(0x4000, 0x00)?;
                r.mbc(0x2000, 0x01)?;
            }
            Mapper::Mbc5 => {
                r.mbc(0x0000, 0x00)?;
                r.mbc(0x4000, 0x00)?; // RAM bank 0, rumble motor off
                r.mbc(0x3000, 0x00)?;
                r.mbc(0x2000, 0x01)?;
            }
            _ => {
                r.mbc(0x0000, 0x00)?;
            }
        }
        Ok(())
    }

    /// 16 KiB of ROM bank `bank`
    fn read_bank<L: Link>(&self, r: &mut Reader<L>, bank: usize) -> Result<Vec<u8>, String> {
        if bank == 0 {
            return r.read(0x0000, BANK);
        }
        match self.mapper {
            Mapper::RomOnly => r.read(0x4000, BANK),
            Mapper::Mbc1 => {
                let (hi_shift, lo_mask) = if self.mbc1m { (4, 0x0F) } else { (5, 0x1F) };
                let hi = (bank >> hi_shift) as u8;
                let lo = (bank & lo_mask) as u8;
                if lo == 0 {
                    // banks 0x20 / 0x40 / 0x60 (0x10 / 0x20 / 0x30 on multicarts) are not reachable
                    // at 0x4000: mode 1 maps them at 0x0000
                    r.mbc(0x4000, hi)?;
                    r.mbc(0x6000, 0x01)?;
                    let d = r.read(0x0000, BANK);
                    r.mbc(0x6000, 0x00)?;
                    d
                } else {
                    r.mbc(0x4000, hi)?;
                    r.mbc(0x2000, lo)?;
                    r.read(0x4000, BANK)
                }
            }
            Mapper::Mbc2 => {
                r.mbc(0x2100, (bank & 0x0F) as u8)?;
                r.read(0x4000, BANK)
            }
            Mapper::Mbc5 => {
                r.mbc(0x3000, (bank >> 8) as u8 & 1)?;
                r.mbc(0x2000, bank as u8)?;
                r.read(0x4000, BANK)
            }
            Mapper::Mbc3 | Mapper::Mbc7 | Mapper::PocketCamera | Mapper::HuC1 | Mapper::HuC3 => {
                r.mbc(0x2000, bank as u8)?;
                r.read(0x4000, BANK)
            }
            m => Err(format!("{} is not supported", m.name())),
        }
    }
}

fn supported(m: Mapper) -> bool {
    matches!(
        m,
        Mapper::RomOnly | Mapper::Mbc1 | Mapper::Mbc2 | Mapper::Mbc3 | Mapper::Mbc5 | Mapper::Mbc7
            | Mapper::PocketCamera | Mapper::HuC1 | Mapper::HuC3
    )
}

/// the header, read until three reads agree
fn read_header<L: Link>(r: &mut Reader<L>) -> Result<Header, String> {
    let a = r.read(0x0100, 0x50)?;
    let b = r.read(0x0100, 0x50)?;
    let c = r.read(0x0100, 0x50)?;
    if a != b || b != c {
        return Err("the header reads differently each time: check the cartridge contacts".into());
    }
    if a.iter().all(|&x| x == 0xFF) || a.iter().all(|&x| x == 0x00) {
        return Err(format!("the header is all {:02x}: no cartridge, or no contact", a[0]));
    }
    Ok(Header::new(a))
}

fn print_header(h: &Header) {
    println!("title          : {}", h.title());
    println!("CGB flag       : {:02x}{}", h.cgb(), if h.is_cgb() { " (CGB)" } else { "" });
    println!("SGB            : {}", h.sgb());
    println!("cartridge type : {:02x} ({})", h.cart_type(), h.mapper().name());
    match h.rom_banks() {
        Some(n) => println!("ROM size       : {:02x} ({} KiB, {} banks)", h.rom_code(), n * 16, n),
        None => println!("ROM size       : {:02x} (invalid)", h.rom_code()),
    }
    println!("RAM size       : {:02x} ({} KiB, not read)", h.ram_code(), h.ram_size() >> 10);
    println!(
        "header checksum: {:02x} ({})",
        h.header_checksum(),
        if h.header_ok() { "OK".to_string() } else { format!("BAD, calculated {:02x}", h.header_checksum_calc()) }
    );
    println!("global checksum: {:04x}", h.global_checksum());
}

/// MBC1 multicart: in mode 1 with the upper register = 1, 0x0000 shows bank 0x10 on multicart
/// wiring (bank 0x20 otherwise); a second copy of the bank-0 logo there means a multicart
fn detect_mbc1m<L: Link>(r: &mut Reader<L>, h: &Header) -> Result<bool, String> {
    r.mbc(0x4000, 0x01)?;
    r.mbc(0x6000, 0x01)?;
    let logo = r.read(0x0104, 0x30);
    r.mbc(0x6000, 0x00)?;
    r.mbc(0x4000, 0x00)?;
    Ok(logo? == h.logo())
}

fn sanitize(s: &str) -> String {
    let t: String = s
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    let t = t.trim_matches('_').to_string();
    if t.is_empty() { "cartridge".into() } else { t }
}

fn dump_all<L: Link>(r: &mut Reader<L>, b: &Banker, banks: usize, pass: &str) -> Result<Vec<u8>, String> {
    let mut rom = Vec::with_capacity(banks * BANK);
    let t0 = Instant::now();
    for bank in 0..banks {
        rom.extend_from_slice(&b.read_bank(r, bank)?);
        eprint!("\r{pass}bank {:3}/{banks}  {:5.0} KiB/s", bank + 1, rom.len() as f64 / 1024.0 / t0.elapsed().as_secs_f64());
    }
    eprintln!();
    Ok(rom)
}

fn run<L: Link>(r: &mut Reader<L>, cmd: &Cmd) -> Result<(), String> {
    let s = r.hello()?;
    eprintln!("reader: {}", s.describe());
    match cmd {
        Cmd::Status => Ok(()),
        Cmd::Header { keep_power } => {
            r.power_up(Duration::from_secs(2))?;
            let res = read_header(r).map(|h| print_header(&h));
            if !keep_power {
                r.power(false)?;
            }
            res
        }
        Cmd::Dump { output, verify, mapper, banks, mbc1m, force, keep_power } => {
            r.power_up(Duration::from_secs(2))?;
            let res = (|| {
                let h = read_header(r)?;
                print_header(&h);
                if !h.header_ok() && !force {
                    return Err("header checksum mismatch: bad contact or not a licensed-format header (--force to dump anyway)".into());
                }
                let mut m = match mapper {
                    Some(s) => Mapper::parse(s).ok_or(format!("unknown mapper '{s}'"))?,
                    None => h.mapper(),
                };
                let mut n = banks.or(h.rom_banks()).ok_or("invalid ROM size code: give --banks")?;
                if !supported(m) {
                    if !force {
                        return Err(format!("{} is not supported (--force dumps banks 0-1 without bank switching)", m.name()));
                    }
                    eprintln!("warning: {} not supported, dumping banks 0-1 only", m.name());
                    m = Mapper::RomOnly;
                    n = 2;
                }
                let mut b = Banker { mapper: m, mbc1m: *mbc1m };
                b.init(r)?;
                if m == Mapper::Mbc1 && !mbc1m && n == 64 && detect_mbc1m(r, &h)? {
                    eprintln!("MBC1 multicart detected");
                    b.mbc1m = true;
                }
                let rom = dump_all(r, &b, n, "")?;
                if *verify {
                    let again = dump_all(r, &b, n, "verify ")?;
                    if let Some(i) = rom.iter().zip(&again).position(|(x, y)| x != y) {
                        return Err(format!("verify: first difference at {i:06x} ({:02x} / {:02x})", rom[i], again[i]));
                    }
                    eprintln!("verify: identical");
                }
                if rom[0x100..0x150] != h.raw[..] {
                    return Err("the header in the dump differs from the first read".into());
                }
                let gc = global_checksum_calc(&rom);
                if gc == h.global_checksum() {
                    println!("global checksum: OK ({gc:04x})");
                } else {
                    println!("global checksum: MISMATCH (calculated {gc:04x}, header {:04x}): some cartridges ship with a wrong value, compare the SHA-1 with a known-good list", h.global_checksum());
                }
                let mut sha = Sha1::new();
                sha.update(&rom);
                println!("size           : {} bytes", rom.len());
                println!("CRC32          : {:08x}", crc32fast::hash(&rom));
                println!("SHA-1          : {:x}", sha.finalize());
                let path = output.clone().unwrap_or_else(|| {
                    PathBuf::from(format!("{}.{}", sanitize(&h.title()), if h.is_cgb() { "gbc" } else { "gb" }))
                });
                std::fs::write(&path, &rom).map_err(|e| format!("{}: {e}", path.display()))?;
                println!("saved          : {}", path.display());
                Ok(())
            })();
            if !keep_power {
                if let Err(e) = r.power(false) {
                    eprintln!("warning: power off: {e}");
                }
            }
            let s = r.status()?;
            if s.reject_cnt != 0 {
                eprintln!("note: the device refused {} write(s)", s.reject_cnt);
            }
            res
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let res = match &cli.sim {
        Some(exe) => SimLink::spawn(exe).and_then(|l| {
            let mut r = Reader::new(l);
            let res = run(&mut r, &cli.cmd);
            let fin = r.link.finish();
            res.and(fin)
        }),
        None => UsbLink::open().and_then(|l| run(&mut Reader::new(l), &cli.cmd)),
    };
    if let Err(e) = res {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}
