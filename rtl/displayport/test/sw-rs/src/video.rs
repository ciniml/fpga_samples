//! Video pipeline configuration helper for the Phase D MSA / TU registers.

use bootrom_pac;

#[derive(Clone, Copy)]
pub struct VideoConfig {
    pub htotal:    u16,
    pub vtotal:    u16,
    pub hstart:    u16,
    pub vstart:    u16,
    pub hwidth:    u16,
    pub vheight:   u16,
    pub hsw:       u16,
    pub hsp:       bool,
    pub vsw:       u16,
    pub vsp:       bool,
    pub mvid:      u32, // 24-bit
    pub nvid:      u32, // 24-bit
    pub misc0:     u8,
    pub misc1:     u8,
    pub tu_active: u8,  // 1..64
}

pub struct Video {
    p: bootrom_pac::VIDEO,
}

impl Video {
    pub fn new(p: bootrom_pac::VIDEO) -> Self {
        Self { p }
    }

    pub fn setup_and_enable(&self, c: &VideoConfig) {
        unsafe {
            self.p.htotal.write(|w| w.bits(c.htotal as u32));
            self.p.vtotal.write(|w| w.bits(c.vtotal as u32));
            self.p.hstart.write(|w| w.bits(c.hstart as u32));
            self.p.vstart.write(|w| w.bits(c.vstart as u32));
            self.p.hwidth.write(|w| w.bits(c.hwidth as u32));
            self.p.vheight.write(|w| w.bits(c.vheight as u32));
            let hsw_hsp: u32 = (c.hsw as u32 & 0x7FFF) | ((c.hsp as u32) << 15);
            let vsw_vsp: u32 = (c.vsw as u32 & 0x7FFF) | ((c.vsp as u32) << 15);
            self.p.hsw_hsp.write(|w| w.bits(hsw_hsp));
            self.p.vsw_vsp.write(|w| w.bits(vsw_vsp));
            self.p.mvid.write(|w| w.bits(c.mvid & 0x00FF_FFFF));
            self.p.nvid.write(|w| w.bits(c.nvid & 0x00FF_FFFF));
            let misc: u32 = (c.misc0 as u32) | ((c.misc1 as u32) << 8);
            self.p.misc.write(|w| w.bits(misc));
            self.p
                .tu_active
                .write(|w| w.value().bits(c.tu_active & 0x7F));
            self.p.ctrl.write(|w| w.enable().set_bit());
        }
    }
}
