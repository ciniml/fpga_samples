// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Game Boy cartridge ROM dumper for a ModRetro Chromatic running eda/chromatic_cart_dump.
//!
//! The FPGA only offers single-byte bus reads and MBC register writes (it refuses every write
//! outside a small whitelist, and selects cartridge RAM only for reads in its RAM mode); this
//! tool reads the header, decides the mapper, switches banks and saves the ROM image or the
//! save data (cartridge RAM, read only).

mod header;
mod link;
mod ops;
mod proto;
mod web;

use clap::{Parser, Subcommand};
use header::{Header, Mapper};
use link::{Link, SimLink, UsbLink};
use ops::{DumpOpts, Progress, SaveOpts};
use proto::Reader;
use std::{io::Write, path::PathBuf, time::Instant};

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
    /// read the save data (cartridge RAM), twice and compared; nothing is ever written to it
    Save {
        /// output file (default: <title>.sav)
        #[arg(short, long)]
        output: Option<PathBuf>,
        /// override the mapper from the header (mbc1, mbc2, mbc3, mbc5)
        #[arg(long)]
        mapper: Option<String>,
        /// read even when the header checksum is wrong
        #[arg(long)]
        force: bool,
        /// leave the slot powered afterwards
        #[arg(long)]
        keep_power: bool,
    },
    /// show the flash chip of a flash cartridge (autoselect; nothing is written to the flash array)
    FlashId,
    /// write an image to a flash cartridge (SST39VF1681 / 1682): backup first, erase only the
    /// blocks that need it, program, read back
    FlashWrite {
        /// image to write
        file: PathBuf,
        /// flash address to write at (e.g. 0x1F0000)
        #[arg(long, default_value = "0", value_parser = parse_num)]
        offset: usize,
        /// allow changing blocks that are not blank (the game itself)
        #[arg(long)]
        overwrite: bool,
        /// where the automatic full backup goes (default: ~/chromatic-dumps)
        #[arg(long)]
        backup_dir: Option<PathBuf>,
    },
    /// web UI (status, header, ROM dump, save data, FPGA SRAM load) for the local network
    Serve {
        /// address to listen on
        #[arg(long, default_value = "0.0.0.0:8095")]
        bind: String,
        /// directory for the dumps, listed and downloadable in the UI (default: ~/chromatic-dumps)
        #[arg(long)]
        out: Option<PathBuf>,
        /// bitstream for the "load FPGA" button (SRAM only, never the flash)
        #[arg(long)]
        bitstream: Option<PathBuf>,
    },
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
    if h.mapper() == Mapper::Mbc2 {
        println!("RAM size       : {:02x} (512 x 4 bit inside the MBC2)", h.ram_code());
    } else if h.mapper() == Mapper::Mbc7 {
        println!("RAM size       : {:02x} (serial EEPROM, 93LC56 256 B / 93LC66 512 B)", h.ram_code());
    } else {
        println!("RAM size       : {:02x} ({} KiB)", h.ram_code(), h.ram_size() >> 10);
    }
    println!("battery        : {}", h.battery());
    println!(
        "header checksum: {:02x} ({})",
        h.header_checksum(),
        if h.header_ok() { "OK".to_string() } else { format!("BAD, calculated {:02x}", h.header_checksum_calc()) }
    );
    println!("global checksum: {:04x}", h.global_checksum());
}

/// progress on stderr
struct Term {
    t0: Instant,
    last: String,
}

impl Progress for Term {
    fn step(&mut self, phase: &str, done: usize, total: usize) {
        if phase != self.last {
            if !self.last.is_empty() {
                eprintln!();
            }
            self.last = phase.to_string();
            self.t0 = Instant::now();
        }
        eprint!("\r{phase} {done:3}/{total}");
        let _ = std::io::stderr().flush();
    }
    fn note(&mut self, msg: &str) {
        if !self.last.is_empty() {
            eprintln!();
            self.last.clear();
        }
        eprintln!("note: {msg}");
    }
}

impl Term {
    fn new() -> Term { Term { t0: Instant::now(), last: String::new() } }
    fn end(&mut self) {
        if !self.last.is_empty() {
            eprintln!();
            self.last.clear();
        }
    }
}

fn parse_num(s: &str) -> Result<usize, String> {
    let r = if let Some(h) = s.strip_prefix("0x").or(s.strip_prefix("0X")) { usize::from_str_radix(h, 16) } else { s.parse() };
    r.map_err(|e| format!("{s}: {e}"))
}

fn dumps_dir(d: &Option<PathBuf>) -> PathBuf {
    d.clone().unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join("chromatic-dumps"))
}

fn parse_mapper(s: &Option<String>) -> Result<Option<Mapper>, String> {
    s.as_ref().map(|s| Mapper::parse(s).ok_or(format!("unknown mapper '{s}'"))).transpose()
}

fn finish_note<L: Link>(r: &mut Reader<L>) -> Result<(), String> {
    let s = r.status()?;
    if s.ram_on || s.ram_mode() {
        eprintln!("warning: {}", s.describe());
    }
    if s.reject_cnt != 0 {
        eprintln!("note: the device refused {} write(s)", s.reject_cnt);
    }
    Ok(())
}

fn run<L: Link>(r: &mut Reader<L>, cmd: &Cmd) -> Result<(), String> {
    let s = r.hello()?;
    eprintln!("reader: {}", s.describe());
    match cmd {
        Cmd::Status | Cmd::Serve { .. } => Ok(()),
        Cmd::FlashId => ops::powered(r, false, |r| {
            if !r.flash_mode(true)? {
                return Err("the device refused flash mode".into());
            }
            let id = r.flash_id();
            let off = r.flash_mode(false);
            let id = id?;
            off?;
            println!("identifier     : {id:02x?}");
            match ops::flash_chip(&id) {
                Some(c) => println!("chip           : {} ({} KiB){}", c.name, c.size >> 10, if c.block.is_some() { "" } else { ", writing not supported" }),
                None => println!("chip           : unknown"),
            }
            Ok(())
        }),
        Cmd::FlashWrite { file, offset, overwrite, backup_dir } => {
            let image = std::fs::read(file).map_err(|e| format!("{}: {e}", file.display()))?;
            let res = ops::powered(r, false, |r| {
                let h = ops::read_header(r)?;
                print_header(&h);
                // identify, then a full backup (read twice) before anything is written
                if !r.flash_mode(true)? {
                    return Err("the device refused flash mode".into());
                }
                let id = r.flash_id();
                let off = r.flash_mode(false);
                let id = id?;
                off?;
                let chip = ops::flash_chip(&id).ok_or(format!("unknown flash identifier {id:02x?}: not writing"))?;
                eprintln!("flash: {} ({} KiB)", chip.name, chip.size >> 10);
                let a = ops::flash_read(r, 0, chip.size)?;
                let b = ops::flash_read(r, 0, chip.size)?;
                if a != b {
                    return Err("the backup reads differ: check the contacts (nothing written)".into());
                }
                let dir = dumps_dir(backup_dir);
                std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
                let base = format!("{}-flash-backup", ops::sanitize(&h.title()));
                let mut path = dir.join(format!("{base}.bin"));
                let mut i = 2;
                while path.exists() && std::fs::read(&path).map(|d| d != a).unwrap_or(true) {
                    path = dir.join(format!("{base}-{i}.bin"));
                    i += 1;
                }
                std::fs::write(&path, &a).map_err(|e| format!("{}: {e}", path.display()))?;
                println!("backup         : {} (SHA-1 {})", path.display(), ops::sha1_hex(&a));
                let mut t = Term::new();
                let res = ops::flash_write(r, &image, *offset, *overwrite, &mut t);
                t.end();
                let w = res?;
                println!("written        : {} bytes at {:#x} on {}: {} block(s) erased, {} byte(s) programmed, read back OK ({:.1} s)",
                    image.len(), offset, w.chip, w.erased, w.programmed, w.secs);
                Ok(())
            });
            finish_note(r)?;
            res
        }
        Cmd::Header { keep_power } => ops::powered(r, *keep_power, |r| ops::read_header(r).map(|h| print_header(&h))),
        Cmd::Dump { output, verify, mapper, banks, mbc1m, force, keep_power } => {
            let o = DumpOpts { verify: *verify, mapper: parse_mapper(mapper)?, banks: *banks, mbc1m: *mbc1m, force: *force };
            let res = ops::powered(r, *keep_power, |r| {
                print_header(&ops::read_header(r)?);
                let mut t = Term::new();
                let res = ops::dump_rom(r, &o, &mut t);
                t.end();
                let d = res?;
                if d.verified {
                    eprintln!("verify: identical");
                }
                if d.global_ok() {
                    println!("global checksum: OK ({:04x})", d.global_calc);
                } else {
                    println!("global checksum: MISMATCH (calculated {:04x}, header {:04x}): some cartridges ship with a wrong value, compare the SHA-1 with a known-good list", d.global_calc, d.header.global_checksum());
                }
                println!("size           : {} bytes ({:.1} s)", d.rom.len(), d.secs);
                println!("CRC32          : {:08x}", crc32fast::hash(&d.rom));
                println!("SHA-1          : {}", ops::sha1_hex(&d.rom));
                let path = output.clone().unwrap_or_else(|| {
                    PathBuf::from(format!("{}.{}", ops::sanitize(&d.header.title()), if d.header.is_cgb() { "gbc" } else { "gb" }))
                });
                std::fs::write(&path, &d.rom).map_err(|e| format!("{}: {e}", path.display()))?;
                println!("saved          : {}", path.display());
                Ok(())
            });
            finish_note(r)?;
            res
        }
        Cmd::Save { output, mapper, force, keep_power } => {
            let o = SaveOpts { mapper: parse_mapper(mapper)?, force: *force };
            let res = ops::powered(r, *keep_power, |r| {
                print_header(&ops::read_header(r)?);
                let mut t = Term::new();
                let res = ops::read_save(r, &o, &mut t);
                t.end();
                let d = res?;
                eprintln!("read {} bytes twice ({} x {} bytes), identical, {:.2} s", d.ram.len(), d.banks, d.bank_size, d.secs);
                println!("size           : {} bytes", d.ram.len());
                println!("CRC32          : {:08x}", crc32fast::hash(&d.ram));
                println!("SHA-1          : {}", ops::sha1_hex(&d.ram));
                let path = output.clone().unwrap_or_else(|| PathBuf::from(format!("{}.sav", ops::sanitize(&d.header.title()))));
                std::fs::write(&path, &d.ram).map_err(|e| format!("{}: {e}", path.display()))?;
                println!("saved          : {}", path.display());
                Ok(())
            });
            finish_note(r)?;
            res
        }
    }
}

fn main() {
    let cli = Cli::parse();
    if let Cmd::Serve { bind, out, bitstream } = &cli.cmd {
        let bs = bitstream.clone().unwrap_or_else(web::default_bitstream);
        let out = out.clone().unwrap_or_else(|| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join("chromatic-dumps")
        });
        if let Err(e) = web::serve(bind, &out, &bs, cli.sim.clone()) {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
        return;
    }
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
