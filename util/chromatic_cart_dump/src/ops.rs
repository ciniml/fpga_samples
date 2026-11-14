// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Cartridge operations shared by the command line and the web UI: header, ROM dump, save data.

use crate::header::{global_checksum_calc, Header, Mapper};
use crate::link::Link;
use crate::proto::Reader;
use std::time::{Duration, Instant};

/// progress and messages of a long operation
pub trait Progress {
    /// `phase` (e.g. "ROM", "verify"), `done` of `total` units
    fn step(&mut self, phase: &str, done: usize, total: usize);
    /// a warning / note for the user
    fn note(&mut self, msg: &str);
}

pub const BANK: usize = 0x4000;

pub struct Banker {
    pub mapper: Mapper,
    pub mbc1m: bool,
}

impl Banker {
    /// put the MBC in a known state: cartridge RAM / RTC disabled, banking mode 0
    pub fn init<L: Link>(&self, r: &mut Reader<L>) -> Result<(), String> {
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
    pub fn read_bank<L: Link>(&self, r: &mut Reader<L>, bank: usize) -> Result<Vec<u8>, String> {
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

pub fn supported(m: Mapper) -> bool {
    matches!(
        m,
        Mapper::RomOnly | Mapper::Mbc1 | Mapper::Mbc2 | Mapper::Mbc3 | Mapper::Mbc5 | Mapper::Mbc7
            | Mapper::PocketCamera | Mapper::HuC1 | Mapper::HuC3
    )
}

/// the header, read until three reads agree
pub fn read_header<L: Link>(r: &mut Reader<L>) -> Result<Header, String> {
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

/// MBC1 multicart: in mode 1 with the upper register = 1, 0x0000 shows bank 0x10 on multicart
/// wiring (bank 0x20 otherwise); a second copy of the bank-0 logo there means a multicart
pub fn detect_mbc1m<L: Link>(r: &mut Reader<L>, h: &Header) -> Result<bool, String> {
    r.mbc(0x4000, 0x01)?;
    r.mbc(0x6000, 0x01)?;
    let logo = r.read(0x0104, 0x30);
    r.mbc(0x6000, 0x00)?;
    r.mbc(0x4000, 0x00)?;
    Ok(logo? == h.logo())
}

pub fn sanitize(s: &str) -> String {
    let t: String = s
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    let t = t.trim_matches('_').to_string();
    if t.is_empty() { "cartridge".into() } else { t }
}

/// (banks, bytes per bank) of the cartridge RAM, or why it is not read
pub fn ram_layout(m: Mapper, h: &Header) -> Result<(usize, usize), String> {
    match m {
        Mapper::Mbc2 => Ok((1, 512)),
        // 93LC56 (256 bytes) or 93LC66 (512 bytes): 512 are read, read_ram decides
        Mapper::Mbc7 => Ok((1, 512)),
        Mapper::Mbc1 | Mapper::Mbc3 | Mapper::Mbc5 => {
            let size = h.ram_size();
            if size == 0 {
                return Err(format!("the header declares no cartridge RAM (RAM size code {:02x})", h.ram_code()));
            }
            let bs = size.min(0x2000);
            let nb = size / bs;
            let max = match m {
                // MBC1: the RAM bank is the upper register in mode 1, which also moves ROM banks
                // on cartridges over 512 KiB (those have no banked RAM)
                Mapper::Mbc1 if nb > 1 && h.rom_banks().unwrap_or(0) > 32 => 1,
                Mapper::Mbc1 => 4,
                Mapper::Mbc3 => 8,
                // bit 3 of the RAM bank drives the rumble motor
                Mapper::Mbc5 if h.rumble() => 8,
                _ => 16,
            };
            if nb > max {
                return Err(format!("{} KiB of RAM does not fit the {} RAM banking", size >> 10, m.name()));
            }
            Ok((nb, bs))
        }
        m => Err(format!("reading the RAM of {} is not supported", m.name())),
    }
}

/// the whole cartridge RAM: RAM mode, enable, banks, disable, RAM mode off
pub fn read_ram<L: Link>(r: &mut Reader<L>, m: Mapper, nb: usize, bs: usize) -> Result<Vec<u8>, String> {
    if !r.ram_mode(true)? {
        return Err("the device refused RAM mode".into());
    }
    if m == Mapper::Mbc7 {
        return read_mbc7(r);
    }
    let banked = matches!(m, Mapper::Mbc1 | Mapper::Mbc3 | Mapper::Mbc5);
    let res = (|| {
        if m == Mapper::Mbc1 && nb > 1 {
            r.mbc(0x6000, 0x01)?;
        }
        r.mbc(0x0000, 0x0A)?;
        let mut out = Vec::with_capacity(nb * bs);
        for b in 0..nb {
            if banked {
                r.mbc(0x4000, b as u8)?;
            }
            out.extend_from_slice(&r.read(0xA000, bs)?);
        }
        Ok::<_, String>(out)
    })();
    // disable the RAM ourselves, then leave RAM mode (the device would disable it either way)
    let off = r.mbc(0x0000, 0x00).and_then(|_| r.ram_off());
    if banked {
        let _ = r.mbc(0x4000, 0x00);
    }
    if m == Mapper::Mbc1 {
        let _ = r.mbc(0x6000, 0x00);
    }
    let mut out = res?;
    off?;
    if m == Mapper::Mbc2 {
        // 4-bit RAM: the upper nibble is not driven
        for x in &mut out {
            *x |= 0xF0;
        }
    }
    Ok(out)
}


/// power the slot, run `f`, power it down again (unless `keep`)
/// MBC7: RAM enable 1, the EEPROM through the FPGA's read-only engine (which writes RAM enable 2
/// itself), disable. 256 words are read; a 93LC56 ignores address bit 7, so identical halves mean
/// a 256-byte EEPROM (an empty 93LC66 is then saved as 256 bytes of FF).
fn read_mbc7<L: Link>(r: &mut Reader<L>) -> Result<Vec<u8>, String> {
    let res = (|| {
        r.status()?; // clears the error flags
        r.mbc(0x0000, 0x0A)?;
        let d = r.eeprom(0, 256)?;
        let s = r.status()?;
        if s.err & 0x08 != 0 {
            return Err("the EEPROM read did not complete (refused by the device)".to_string());
        }
        Ok(d)
    })();
    let off = r.mbc(0x0000, 0x00).and_then(|_| r.ram_off());
    let d = res?;
    off?;
    Ok(if d[..256] == d[256..] { d[..256].to_vec() } else { d })
}

pub fn powered<L: Link, T>(
    r: &mut Reader<L>,
    keep: bool,
    f: impl FnOnce(&mut Reader<L>) -> Result<T, String>,
) -> Result<T, String> {
    r.power_up(Duration::from_secs(2))?;
    let res = f(r);
    if !keep {
        if let Err(e) = r.power(false) {
            return res.and(Err(format!("power off: {e}")));
        }
    }
    res
}

pub struct DumpOpts {
    pub verify: bool,
    pub mapper: Option<Mapper>,
    pub banks: Option<usize>,
    pub mbc1m: bool,
    pub force: bool,
}

pub struct RomResult {
    pub header: Header,
    pub rom: Vec<u8>,
    pub mapper: Mapper,
    pub mbc1m: bool,
    pub verified: bool,
    pub global_calc: u16,
    pub secs: f64,
}

impl RomResult {
    pub fn global_ok(&self) -> bool { self.global_calc == self.header.global_checksum() }
}

fn read_banks<L: Link>(r: &mut Reader<L>, b: &Banker, banks: usize, phase: &str, p: &mut dyn Progress) -> Result<Vec<u8>, String> {
    let mut rom = Vec::with_capacity(banks * BANK);
    for bank in 0..banks {
        rom.extend_from_slice(&b.read_bank(r, bank)?);
        p.step(phase, bank + 1, banks);
    }
    Ok(rom)
}

/// the whole ROM (the slot must be powered)
pub fn dump_rom<L: Link>(r: &mut Reader<L>, o: &DumpOpts, p: &mut dyn Progress) -> Result<RomResult, String> {
    let h = read_header(r)?;
    if !h.header_ok() && !o.force {
        return Err("header checksum mismatch: bad contact or not a licensed-format header (force to dump anyway)".into());
    }
    let mut m = o.mapper.unwrap_or(h.mapper());
    let mut n = o.banks.or(h.rom_banks()).ok_or("invalid ROM size code: give the number of banks")?;
    if !supported(m) {
        if !o.force {
            return Err(format!("{} is not supported (force dumps banks 0-1 without bank switching)", m.name()));
        }
        p.note(&format!("{} not supported, dumping banks 0-1 only", m.name()));
        m = Mapper::RomOnly;
        n = 2;
    }
    let mut b = Banker { mapper: m, mbc1m: o.mbc1m };
    b.init(r)?;
    if m == Mapper::Mbc1 && !o.mbc1m && n == 64 && detect_mbc1m(r, &h)? {
        p.note("MBC1 multicart detected");
        b.mbc1m = true;
    }
    let t0 = Instant::now();
    let rom = read_banks(r, &b, n, "ROM", p)?;
    if o.verify {
        let again = read_banks(r, &b, n, "verify", p)?;
        if let Some(i) = rom.iter().zip(&again).position(|(x, y)| x != y) {
            return Err(format!("verify: first difference at {i:06x} ({:02x} / {:02x})", rom[i], again[i]));
        }
    }
    if rom[0x100..0x150] != h.raw[..] {
        return Err("the header in the dump differs from the first read".into());
    }
    let global_calc = global_checksum_calc(&rom);
    Ok(RomResult { header: h, rom, mapper: m, mbc1m: b.mbc1m, verified: o.verify, global_calc, secs: t0.elapsed().as_secs_f64() })
}

pub struct SaveOpts {
    pub mapper: Option<Mapper>,
    pub force: bool,
}

pub struct SaveResult {
    pub header: Header,
    pub ram: Vec<u8>,
    pub banks: usize,
    pub bank_size: usize,
    pub secs: f64,
}

impl SaveResult {
    pub fn all_ff(&self) -> bool { self.ram.iter().all(|&x| x == 0xFF) }
}

/// the save data, read twice and compared (the slot must be powered)
pub fn read_save<L: Link>(r: &mut Reader<L>, o: &SaveOpts, p: &mut dyn Progress) -> Result<SaveResult, String> {
    let h = read_header(r)?;
    if !h.header_ok() && !o.force {
        return Err("header checksum mismatch: bad contact or not a licensed-format header (force to read anyway)".into());
    }
    let m = o.mapper.unwrap_or(h.mapper());
    let (nb, bs) = ram_layout(m, &h)?;
    if !h.battery() {
        p.note(&format!("cartridge type {:02x} has no battery: the RAM holds nothing across power-offs", h.cart_type()));
    }
    Banker { mapper: m, mbc1m: false }.init(r)?;
    let t0 = Instant::now();
    p.step("RAM", 0, 2);
    let ram = read_ram(r, m, nb, bs)?;
    p.step("RAM", 1, 2);
    let again = read_ram(r, m, nb, bs)?;
    p.step("RAM", 2, 2);
    if let Some(i) = ram.iter().zip(&again).position(|(x, y)| x != y) {
        return Err(format!("the two reads differ first at {i:05x} ({:02x} / {:02x}): check the contacts", ram[i], again[i]));
    }
    let _ = bs;
    let bank_size = ram.len() / nb;
    let res = SaveResult { header: h, ram, banks: nb, bank_size, secs: t0.elapsed().as_secs_f64() };
    if res.all_ff() {
        p.note("the RAM reads all FF (empty save, no RAM, or a dead battery)");
    }
    Ok(res)
}

pub fn sha1_hex(d: &[u8]) -> String {
    use sha1::{Digest, Sha1};
    let mut sha = Sha1::new();
    sha.update(d);
    format!("{:x}", sha.finalize())
}

// ---------------------------------------------------------------- flash cartridges

pub struct FlashChip {
    pub name: &'static str,
    pub size: usize,
    /// erase unit of the 0x30 command, uniform over the chip (None: not supported for writing)
    pub block: Option<usize>,
}

/// identify from the autoselect bytes (0x00-0x03, 0x1C-0x1F)
pub fn flash_chip(id: &[u8; 8]) -> Option<FlashChip> {
    match (id[0], id[1], id[2], id[4]) {
        (0xBF, 0xC8, _, _) => Some(FlashChip { name: "SST39VF1681", size: 0x200000, block: Some(0x10000) }),
        (0xBF, 0xC9, _, _) => Some(FlashChip { name: "SST39VF1682", size: 0x200000, block: Some(0x10000) }),
        // boot-sector parts: the 0x30 erase unit differs at one end (needs the CFI sector map)
        (0x01 | 0x9D, _, 0x7E, 0x1A | 0x1C | 0x1D) => Some(FlashChip { name: "S29GL032 / IS29GL032", size: 0x400000, block: None }),
        _ => None,
    }
}

/// (bank, cartridge address) of flash address `fa` (MBC5 wiring: bank 0 at 0x0000, others in the window)
fn flash_cart_addr(fa: usize) -> (u16, u16) {
    let bank = (fa / BANK) as u16;
    if bank == 0 { (1, fa as u16) } else { (bank, 0x4000 | (fa % BANK) as u16) }
}

/// `len` bytes of the flash from flash address `fa` (ordinary reads, bank by bank)
pub fn flash_read<L: Link>(r: &mut Reader<L>, fa: usize, len: usize) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(len);
    let mut a = fa;
    while out.len() < len {
        let n = (len - out.len()).min(BANK - a % BANK);
        let (bank, ca) = flash_cart_addr(a);
        if a >= BANK {
            r.mbc(0x3000, (bank >> 8) as u8 & 1)?;
            r.mbc(0x2000, bank as u8)?;
        }
        out.extend_from_slice(&r.read(ca, n)?);
        a += n;
    }
    Ok(out)
}

pub struct FlashWriteResult {
    pub chip: &'static str,
    pub erased: usize,
    pub programmed: usize,
    pub secs: f64,
}

/// write `image` at flash address `offset`: blocks that need a 0 -> 1 change are erased, only the
/// differing bytes are programmed, everything is read back. Blocks that are not blank are changed
/// only with `overwrite`. The caller keeps the slot powered and has taken a backup.
pub fn flash_write<L: Link>(
    r: &mut Reader<L>,
    image: &[u8],
    offset: usize,
    overwrite: bool,
    p: &mut dyn Progress,
) -> Result<FlashWriteResult, String> {
    if !r.flash_mode(true)? {
        return Err("the device refused flash mode".into());
    }
    let res = (|| {
        let id = r.flash_id()?;
        let chip = flash_chip(&id).ok_or(format!("unknown flash identifier {id:02x?}"))?;
        let block = chip.block.ok_or(format!("{}: writing is not supported (its erase sectors are not uniform)", chip.name))?;
        if image.is_empty() || offset + image.len() > chip.size {
            return Err(format!("{} bytes at {offset:#x} do not fit the {} KiB {}", image.len(), chip.size >> 10, chip.name));
        }
        let b0 = offset / block;
        let b1 = (offset + image.len() - 1) / block;
        let t0 = Instant::now();
        // plan
        let mut plan = Vec::new();
        for b in b0..=b1 {
            let base = b * block;
            let cur = flash_read(r, base, block)?;
            let mut new = cur.clone();
            let lo = offset.max(base);
            let hi = (offset + image.len()).min(base + block);
            new[lo - base..hi - base].copy_from_slice(&image[lo - offset..hi - offset]);
            if new == cur {
                continue;
            }
            if !overwrite && cur.iter().any(|&x| x != 0xFF) {
                return Err(format!("block {base:#08x} is not blank: refusing to change it without overwrite"));
            }
            let erase = cur.iter().zip(&new).any(|(&c, &n)| c & n != n);
            plan.push((base, cur, new, erase));
        }
        let total: usize = plan.len();
        let (mut erased, mut programmed) = (0, 0);
        for (i, (base, cur, new, erase)) in plan.iter().enumerate() {
            let have = if *erase {
                let (bank, ca) = flash_cart_addr(*base);
                match r.flash_erase(bank, ca)? {
                    0 => {}
                    1 => return Err(format!("erase of block {base:#08x} timed out")),
                    s => return Err(format!("erase of block {base:#08x} refused ({s})")),
                }
                erased += 1;
                let chk = flash_read(r, *base, block)?;
                if let Some(j) = chk.iter().position(|&x| x != 0xFF) {
                    return Err(format!("block {base:#08x} not blank after erase ({:#08x} = {:02x})", base + j, chk[j]));
                }
                vec![0xFFu8; block]
            } else {
                cur.clone()
            };
            // program runs of differing bytes, within one 16 KiB bank window, up to 4 KiB each
            let mut j = 0;
            while j < block {
                if have[j] == new[j] {
                    j += 1;
                    continue;
                }
                let start = j;
                let lim = (start - start % BANK + BANK).min(block).min(start + 4096);
                while j < lim && have[j] != new[j] {
                    j += 1;
                }
                let (bank, ca) = flash_cart_addr(base + start);
                let (st, n) = r.flash_program(bank, ca, &new[start..j])?;
                if st != 0 || n != j - start {
                    return Err(format!("program at {:#08x}: status {st}, {n} of {} bytes", base + start, j - start));
                }
                programmed += n;
            }
            p.step("flash", i + 1, total);
        }
        // read back
        for (base, _, new, _) in &plan {
            let chk = flash_read(r, *base, block)?;
            if let Some(j) = chk.iter().zip(new).position(|(a, b)| a != b) {
                return Err(format!("verify: {:#08x} reads {:02x}, expected {:02x}", base + j, chk[j], new[j]));
            }
        }
        Ok(FlashWriteResult { chip: chip.name, erased, programmed, secs: t0.elapsed().as_secs_f64() })
    })();
    let off = r.flash_mode(false);
    let res = res?;
    off?;
    Ok(res)
}
