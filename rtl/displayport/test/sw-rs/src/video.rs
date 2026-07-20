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

impl VideoConfig {
    /// Active pixel bytes per lane per line.
    fn active_bytes_per_lane(&self, lanes: u16) -> u32 {
        (self.hwidth as u32) * 3 / (lanes as u32)
    }
    /// Link symbols per line per lane. `num`/`den` is LS_clk / pixel_clk
    /// (e.g. 6/1 for 27 Mpix on RBR, 12/11 for 148.5 Mpix on RBR x4);
    /// htotal * num must be divisible by den.
    pub fn line_symbols(&self, num: u32, den: u32) -> u16 {
        ((self.htotal as u32) * num / den) as u16
    }
    /// TU-region symbols per line per lane:
    /// floor(B / tu_active) * 64 + (B % tu_active).
    pub fn active_window(&self, lanes: u16) -> u16 {
        let b = self.active_bytes_per_lane(lanes);
        let ac = self.tu_active as u32;
        (b / ac * 64 + b % ac) as u16
    }
}

pub struct Video {
    p: bootrom_pac::VIDEO,
    /// LS_clk / pixel_clk ratio numerator/denominator and lane count,
    /// used to derive the line accounting registers.
    ls_num: u32,
    ls_den: u32,
    lanes: u16,
}

impl Video {
    pub fn new(p: bootrom_pac::VIDEO) -> Self {
        Self { p, ls_num: 6, ls_den: 1, lanes: 1 }
    }
    #[allow(dead_code)]
    pub fn set_rate(&mut self, ls_num: u32, ls_den: u32, lanes: u16) {
        self.ls_num = ls_num;
        self.ls_den = ls_den;
        self.lanes = lanes;
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
            self.p
                .line_symbols
                .write(|w| w.value().bits(c.line_symbols(self.ls_num, self.ls_den)));
            self.p
                .active_window
                .write(|w| w.value().bits(c.active_window(self.lanes)));
            self.p.ctrl.write(|w| w.enable().set_bit());
        }
    }
}
