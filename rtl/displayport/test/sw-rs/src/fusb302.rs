//! FUSB302B USB PD PHY driver (I2C, polling — INT_N not required).
//!
//! Covers what the Type-C DP alt-mode SOURCE needs:
//!   - device reset / power-up / ID check
//!   - Rp presentation on both CC pins and attach detection by CC
//!     comparator measurement (no TOGGLE engine: we poll)
//!   - orientation detection (which CC shows Rd)
//!   - VCONN to the unused CC pin
//!   - BMC TX with auto-CRC/auto-retry, RX via the 80-byte FIFO
//!
//! Register map per the FUSB302B datasheet (onsemi, Rev.5).

use crate::i2c::{I2c, I2cError};

pub const FUSB302_ADDR: u8 = 0x22; // 7-bit

// Registers
const REG_DEVICE_ID: u8 = 0x01;
const REG_SWITCHES0: u8 = 0x02;
const REG_SWITCHES1: u8 = 0x03;
const REG_MEASURE: u8 = 0x04;
const REG_CONTROL0: u8 = 0x06;
const REG_CONTROL1: u8 = 0x07;
const REG_CONTROL2: u8 = 0x08;
const REG_CONTROL3: u8 = 0x09;
const REG_MASK: u8 = 0x0A;
const REG_POWER: u8 = 0x0B;
const REG_RESET: u8 = 0x0C;
const REG_MASKA: u8 = 0x0E;
const REG_MASKB: u8 = 0x0F;
const REG_STATUS0: u8 = 0x40;
const REG_STATUS1: u8 = 0x41;
const REG_INTERRUPT: u8 = 0x42;
const REG_FIFOS: u8 = 0x43;

// SWITCHES0 bits
const SW0_PU_EN2: u8 = 1 << 7;
const SW0_PU_EN1: u8 = 1 << 6;
const SW0_VCONN_CC2: u8 = 1 << 5;
const SW0_VCONN_CC1: u8 = 1 << 4;
const SW0_MEAS_CC2: u8 = 1 << 3;
const SW0_MEAS_CC1: u8 = 1 << 2;

// SWITCHES1 bits
const SW1_POWERROLE: u8 = 1 << 7; // 1 = source in the PD header
const SW1_DATAROLE: u8 = 1 << 4; // 1 = DFP in the PD header
const SW1_AUTO_CRC: u8 = 1 << 2;
const SW1_TXCC2: u8 = 1 << 1;
const SW1_TXCC1: u8 = 1 << 0;
const SW1_SPECREV_2_0: u8 = 0b01 << 5;

// CONTROL0
const CTL0_TX_FLUSH: u8 = 1 << 6;
const CTL0_HOST_CUR_DEF: u8 = 0b01 << 2; // default USB current Rp
const CTL0_MASK_ALL: u8 = 1 << 5;

// CONTROL1
const CTL1_RX_FLUSH: u8 = 1 << 2;

// CONTROL3
const CTL3_AUTO_RETRY: u8 = 1 << 0;
const CTL3_N_RETRIES_3: u8 = 0b11 << 1;

// RESET
const RESET_SW_RES: u8 = 1 << 0;
const RESET_PD_RESET: u8 = 1 << 1;

// POWER
const POWER_ALL: u8 = 0x0F;

// STATUS0 bits
const ST0_ACTIVITY: u8 = 1 << 6;
const ST0_COMP: u8 = 1 << 5;
const ST0_CRC_CHK: u8 = 1 << 4;
pub const ST0_BC_LVL_MASK: u8 = 0x03;

// STATUS1 bits
const ST1_RX_EMPTY: u8 = 1 << 5;

// TX FIFO tokens
const TKN_TXON: u8 = 0xA1;
const TKN_SOP1: u8 = 0x12;
const TKN_SOP2: u8 = 0x13;
const TKN_PACKSYM: u8 = 0x80;
const TKN_JAM_CRC: u8 = 0xFF;
const TKN_EOP: u8 = 0x14;
const TKN_TXOFF: u8 = 0xFE;
// RX FIFO tokens (upper 3 bits)
const RXTKN_SOP: u8 = 0b111 << 5;
const RXTKN_MASK: u8 = 0b111 << 5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cc {
    Cc1,
    Cc2,
}

pub struct Fusb302<'a> {
    i2c: &'a I2c,
}

impl<'a> Fusb302<'a> {
    pub fn new(i2c: &'a I2c) -> Self {
        Self { i2c }
    }

    fn wr(&self, reg: u8, v: u8) -> Result<(), I2cError> {
        self.i2c.write_reg(FUSB302_ADDR, reg, v)
    }
    fn rd(&self, reg: u8) -> Result<u8, I2cError> {
        self.i2c.read_reg(FUSB302_ADDR, reg)
    }

    pub fn device_id(&self) -> Result<u8, I2cError> {
        self.rd(REG_DEVICE_ID)
    }

    /// Full init for a polling source: SW reset, power up all blocks,
    /// mask interrupts (we poll status registers), auto retry on.
    pub fn init_source(&self) -> Result<(), I2cError> {
        self.wr(REG_RESET, RESET_SW_RES)?;
        self.wr(REG_POWER, POWER_ALL)?;
        // Polling operation: mask all INT_N causes.
        self.wr(REG_MASK, 0xFF)?;
        self.wr(REG_MASKA, 0xFF)?;
        self.wr(REG_MASKB, 0xFF)?;
        self.wr(REG_CONTROL0, CTL0_HOST_CUR_DEF | CTL0_MASK_ALL)?;
        self.wr(REG_CONTROL3, CTL3_AUTO_RETRY | CTL3_N_RETRIES_3)?;
        // Present Rp on both CC pins (manual attach polling, no TOGGLE).
        self.wr(REG_SWITCHES0, SW0_PU_EN1 | SW0_PU_EN2)?;
        Ok(())
    }

    /// Measure one CC pin: returns the 2-bit BC_LVL (00 = <200mV i.e.
    /// open/Ra-ish, >0 = Rd present under default-current Rp).
    pub fn measure_cc(&self, cc: Cc) -> Result<u8, I2cError> {
        let meas = match cc {
            Cc::Cc1 => SW0_MEAS_CC1,
            Cc::Cc2 => SW0_MEAS_CC2,
        };
        self.wr(REG_SWITCHES0, SW0_PU_EN1 | SW0_PU_EN2 | meas)?;
        // Settle: a few hundred microseconds is ample at 27 MHz.
        for _ in 0..5_000 {
            unsafe { core::arch::asm!("nop") };
        }
        Ok(self.rd(REG_STATUS0)? & ST0_BC_LVL_MASK)
    }

    /// After attach: route BMC to the chosen CC, enable auto-GoodCRC,
    /// header roles = source/DFP, spec rev 2.0, VCONN to the other pin.
    pub fn configure_attached(&self, cc: Cc) -> Result<(), I2cError> {
        let (meas, txcc, vconn) = match cc {
            Cc::Cc1 => (SW0_MEAS_CC1, SW1_TXCC1, SW0_VCONN_CC2),
            Cc::Cc2 => (SW0_MEAS_CC2, SW1_TXCC2, SW0_VCONN_CC1),
        };
        self.wr(REG_SWITCHES0, SW0_PU_EN1 | SW0_PU_EN2 | meas | vconn)?;
        self.wr(
            REG_SWITCHES1,
            SW1_POWERROLE | SW1_DATAROLE | SW1_SPECREV_2_0 | SW1_AUTO_CRC | txcc,
        )?;
        // Reset the PD logic for a clean message counter state.
        self.wr(REG_RESET, RESET_PD_RESET)?;
        self.flush_rx()?;
        Ok(())
    }

    /// Measure VBUS via the MDAC comparator (420 mV steps, binary
    /// search). Restores the MEASURE register afterwards.
    pub fn measure_vbus_mv(&self) -> Result<u32, I2cError> {
        let mut lo = 0u8;
        let mut hi = 63u8;
        while lo < hi {
            let mid = (lo + hi + 1) / 2;
            self.wr(REG_MEASURE, 0x40 | mid)?; // MEAS_VBUS | MDAC
            for _ in 0..3_000 {
                unsafe { core::arch::asm!("nop") };
            }
            if (self.rd(REG_STATUS0)? & ST0_COMP) != 0 {
                lo = mid; // VBUS above threshold
            } else {
                hi = mid - 1;
            }
        }
        self.wr(REG_MEASURE, 0x31)?; // default CC threshold
        Ok((lo as u32 + 1) * 420)
    }

    pub fn flush_rx(&self) -> Result<(), I2cError> {
        self.wr(REG_CONTROL1, CTL1_RX_FLUSH)
    }

    /// Transmit one SOP PD message (header + 32-bit objects).
    pub fn send_sop(&self, header: u16, objects: &[u32]) -> Result<(), I2cError> {
        let nbytes = 2 + 4 * objects.len();
        self.wr(REG_CONTROL0, CTL0_HOST_CUR_DEF | CTL0_MASK_ALL | CTL0_TX_FLUSH)?;
        let mut buf = [0u8; 40];
        let mut n = 0usize;
        for t in [TKN_SOP1, TKN_SOP1, TKN_SOP1, TKN_SOP2] {
            buf[n] = t;
            n += 1;
        }
        buf[n] = TKN_PACKSYM | (nbytes as u8);
        n += 1;
        buf[n] = (header & 0xFF) as u8;
        buf[n + 1] = (header >> 8) as u8;
        n += 2;
        for o in objects {
            buf[n] = (*o & 0xFF) as u8;
            buf[n + 1] = ((*o >> 8) & 0xFF) as u8;
            buf[n + 2] = ((*o >> 16) & 0xFF) as u8;
            buf[n + 3] = ((*o >> 24) & 0xFF) as u8;
            n += 4;
        }
        buf[n] = TKN_JAM_CRC;
        buf[n + 1] = TKN_EOP;
        buf[n + 2] = TKN_TXOFF;
        buf[n + 3] = TKN_TXON;
        n += 4;
        self.i2c.write_regs(FUSB302_ADDR, REG_FIFOS, &buf[..n])
    }

    /// Poll for a received SOP message. Returns Ok(None) when the RX
    /// FIFO is empty. On success fills `objs` and returns
    /// (header, object_count).
    pub fn recv_sop(&self, objs: &mut [u32; 7]) -> Result<Option<(u16, usize)>, I2cError> {
        if (self.rd(REG_STATUS1)? & ST1_RX_EMPTY) != 0 {
            return Ok(None);
        }
        let token = self.rd(REG_FIFOS)?;
        if (token & RXTKN_MASK) != RXTKN_SOP {
            // Not SOP (SOP'/SOP'' or noise): drain this frame and drop.
            let mut hdr = [0u8; 2];
            self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut hdr)?;
            let h = u16::from_le_bytes(hdr);
            let cnt = ((h >> 12) & 0x7) as usize;
            let mut sink = [0u8; 4];
            for _ in 0..cnt {
                self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut sink)?;
            }
            self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut sink)?; // CRC
            return Ok(None);
        }
        let mut hdr = [0u8; 2];
        self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut hdr)?;
        let header = u16::from_le_bytes(hdr);
        let count = ((header >> 12) & 0x7) as usize;
        for i in 0..count {
            let mut ob = [0u8; 4];
            self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut ob)?;
            objs[i] = u32::from_le_bytes(ob);
        }
        // Discard the trailing CRC32.
        let mut crc = [0u8; 4];
        self.i2c.read_regs(FUSB302_ADDR, REG_FIFOS, &mut crc)?;
        Ok(Some((header, count)))
    }
}
