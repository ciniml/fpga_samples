// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Cartridge header (0x0100-0x014F), Pan Docs layout.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mapper {
    RomOnly,
    Mbc1,
    Mbc2,
    Mbc3,
    Mbc5,
    Mbc6,
    Mbc7,
    Mmm01,
    PocketCamera,
    Tama5,
    HuC1,
    HuC3,
    Unknown(u8),
}

impl Mapper {
    pub fn from_type(t: u8) -> Mapper {
        match t {
            0x00 | 0x08 | 0x09 => Mapper::RomOnly,
            0x01..=0x03 => Mapper::Mbc1,
            0x05 | 0x06 => Mapper::Mbc2,
            0x0B..=0x0D => Mapper::Mmm01,
            0x0F..=0x13 => Mapper::Mbc3,
            0x19..=0x1E => Mapper::Mbc5,
            0x20 => Mapper::Mbc6,
            0x22 => Mapper::Mbc7,
            0xFC => Mapper::PocketCamera,
            0xFD => Mapper::Tama5,
            0xFE => Mapper::HuC3,
            0xFF => Mapper::HuC1,
            t => Mapper::Unknown(t),
        }
    }
    pub fn name(&self) -> String {
        match self {
            Mapper::RomOnly => "ROM only".into(),
            Mapper::Mbc1 => "MBC1".into(),
            Mapper::Mbc2 => "MBC2".into(),
            Mapper::Mbc3 => "MBC3".into(),
            Mapper::Mbc5 => "MBC5".into(),
            Mapper::Mbc6 => "MBC6".into(),
            Mapper::Mbc7 => "MBC7".into(),
            Mapper::Mmm01 => "MMM01".into(),
            Mapper::PocketCamera => "Pocket Camera".into(),
            Mapper::Tama5 => "TAMA5".into(),
            Mapper::HuC1 => "HuC1".into(),
            Mapper::HuC3 => "HuC3".into(),
            Mapper::Unknown(t) => format!("unknown type {t:02x}"),
        }
    }
    pub fn parse(s: &str) -> Option<Mapper> {
        Some(match s.to_ascii_lowercase().as_str() {
            "none" | "rom" | "romonly" => Mapper::RomOnly,
            "mbc1" => Mapper::Mbc1,
            "mbc2" => Mapper::Mbc2,
            "mbc3" => Mapper::Mbc3,
            "mbc5" => Mapper::Mbc5,
            "mbc7" => Mapper::Mbc7,
            "camera" => Mapper::PocketCamera,
            "huc1" => Mapper::HuC1,
            "huc3" => Mapper::HuC3,
            _ => return None,
        })
    }
}

pub struct Header {
    pub raw: Vec<u8>, // 0x0100..0x0150
}

impl Header {
    pub fn new(raw: Vec<u8>) -> Header {
        assert_eq!(raw.len(), 0x50);
        Header { raw }
    }
    fn b(&self, a: usize) -> u8 { self.raw[a - 0x100] }
    pub fn title(&self) -> String {
        // 0x134..0x143 (16 bytes on old carts, 11 + manufacturer + CGB flag on newer ones)
        let end = if self.b(0x143) & 0x80 != 0 { 0x143 } else { 0x144 };
        self.raw[0x34..end - 0x100]
            .iter()
            .take_while(|&&c| c != 0)
            .map(|&c| if (0x20..0x7F).contains(&c) { c as char } else { '?' })
            .collect::<String>()
            .trim_end()
            .to_string()
    }
    pub fn cgb(&self) -> u8 { self.b(0x143) }
    pub fn is_cgb(&self) -> bool { self.cgb() & 0x80 != 0 }
    pub fn sgb(&self) -> bool { self.b(0x146) == 0x03 }
    pub fn cart_type(&self) -> u8 { self.b(0x147) }
    pub fn mapper(&self) -> Mapper { Mapper::from_type(self.cart_type()) }
    pub fn rom_code(&self) -> u8 { self.b(0x148) }
    pub fn ram_code(&self) -> u8 { self.b(0x149) }
    /// ROM banks (16 KiB) from 0x148, None for an invalid code
    pub fn rom_banks(&self) -> Option<usize> {
        match self.rom_code() {
            c @ 0x00..=0x08 => Some(2usize << c),
            0x52 => Some(72),
            0x53 => Some(80),
            0x54 => Some(96),
            _ => None,
        }
    }
    pub fn ram_size(&self) -> usize {
        match self.ram_code() {
            0x01 => 2 << 10,
            0x02 => 8 << 10,
            0x03 => 32 << 10,
            0x04 => 128 << 10,
            0x05 => 64 << 10,
            _ => 0,
        }
    }
    /// rumble cartridges (MBC5 0x1C-0x1E): RAM bank bit 3 drives the motor
    pub fn rumble(&self) -> bool { matches!(self.cart_type(), 0x1C..=0x1E) }
    /// battery-backed cartridge types (the RAM / RTC keeps its contents)
    pub fn battery(&self) -> bool {
        matches!(self.cart_type(), 0x03 | 0x06 | 0x09 | 0x0D | 0x0F | 0x10 | 0x13 | 0x1B | 0x1E | 0x22 | 0xFC | 0xFD | 0xFF)
    }
    pub fn header_checksum(&self) -> u8 { self.b(0x14D) }
    pub fn header_checksum_calc(&self) -> u8 {
        let mut x: u8 = 0;
        for a in 0x134..=0x14C {
            x = x.wrapping_sub(self.b(a)).wrapping_sub(1);
        }
        x
    }
    pub fn header_ok(&self) -> bool { self.header_checksum() == self.header_checksum_calc() }
    pub fn global_checksum(&self) -> u16 { (self.b(0x14E) as u16) << 8 | self.b(0x14F) as u16 }
    pub fn logo(&self) -> &[u8] { &self.raw[0x04..0x34] }
}

/// global checksum of a full image: the sum of every byte except 0x14E / 0x14F
pub fn global_checksum_calc(rom: &[u8]) -> u16 {
    let mut s: u16 = 0;
    for (i, &b) in rom.iter().enumerate() {
        if i != 0x14E && i != 0x14F {
            s = s.wrapping_add(b as u16);
        }
    }
    s
}
