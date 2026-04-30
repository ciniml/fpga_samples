//! MAIN_LINK peripheral wrapper.

use bootrom_pac;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pattern {
    Idle = 0,
    Tps1 = 1,
    Tps2 = 2,
}

pub struct MainLink {
    p: bootrom_pac::MAIN_LINK,
}

impl MainLink {
    pub fn new(p: bootrom_pac::MAIN_LINK) -> Self {
        Self { p }
    }

    pub fn set_lane_count(&self, n: u8) {
        unsafe {
            self.p.lane_count.write(|w| w.value().bits(n & 0x7));
        }
    }

    /// Set the active pattern. If `rd_reset` is true, also pulse the
    /// encoder RD-reset request so the next byte starts at RD = -.
    pub fn set_pattern(&self, pat: Pattern, rd_reset: bool) {
        // CTRL: PATTERN_SELECT[1:0] | ENABLE[4] | RD_RESET[5]
        let bits: u32 = (pat as u32) | (1 << 4) | (if rd_reset { 1 << 5 } else { 0 });
        unsafe {
            self.p.ctrl.write(|w| w.bits(bits));
        }
    }

    pub fn disable(&self) {
        unsafe {
            self.p.ctrl.write(|w| w.bits(0));
        }
    }

    pub fn set_lane0_drive(&self, swing: u8, pre_emphasis: u8) {
        let max_swing = (swing == 3) as u32;
        let max_preemph = (pre_emphasis == 3) as u32;
        let bits: u32 = (swing as u32 & 0x3)
            | (max_swing << 2)
            | ((pre_emphasis as u32 & 0x3) << 3)
            | (max_preemph << 5);
        unsafe {
            self.p.lane0_drive.write(|w| w.bits(bits));
        }
    }
}
