//! Thin HAL over the minimal I2C master peripheral (see i2c_master.veryl).
//! Primitive-per-command model: the FW sequences START / WRITE / READ /
//! STOP explicitly.

use bootrom_pac;

const CMD_START: u32 = 1 << 0;
const CMD_STOP: u32 = 1 << 1;
const CMD_WRITE: u32 = 1 << 2;
const CMD_READ: u32 = 1 << 3;
const CMD_READ_NACK: u32 = (1 << 3) | (1 << 4);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum I2cError {
    /// Slave did not ACK an address or data byte.
    Nack,
}

pub struct I2c {
    p: bootrom_pac::I2C,
}

impl I2c {
    pub fn new(p: bootrom_pac::I2C) -> Self {
        Self { p }
    }

    fn cmd(&self, c: u32) {
        unsafe {
            self.p.cmd.write(|w| w.bits(c));
        }
        while self.p.cmd.read().busy().bit_is_set() {}
    }

    fn ack_error(&self) -> bool {
        self.p.cmd.read().ack_error().bit_is_set()
    }

    fn write_byte(&self, b: u8) -> Result<(), I2cError> {
        unsafe {
            self.p.data.write(|w| w.bits(b as u32));
        }
        self.cmd(CMD_WRITE);
        if self.ack_error() {
            Err(I2cError::Nack)
        } else {
            Ok(())
        }
    }

    fn read_byte(&self, last: bool) -> u8 {
        self.cmd(if last { CMD_READ_NACK } else { CMD_READ });
        (self.p.data.read().bits() & 0xFF) as u8
    }

    /// Register write: S, addr+W, reg, data..., P
    pub fn write_regs(&self, dev7: u8, reg: u8, data: &[u8]) -> Result<(), I2cError> {
        self.cmd(CMD_START);
        let r = (|| {
            self.write_byte(dev7 << 1)?;
            self.write_byte(reg)?;
            for &b in data {
                self.write_byte(b)?;
            }
            Ok(())
        })();
        self.cmd(CMD_STOP);
        r
    }

    pub fn write_reg(&self, dev7: u8, reg: u8, val: u8) -> Result<(), I2cError> {
        self.write_regs(dev7, reg, &[val])
    }

    /// Register read: S, addr+W, reg, Sr, addr+R, data..., P
    pub fn read_regs(&self, dev7: u8, reg: u8, out: &mut [u8]) -> Result<(), I2cError> {
        self.cmd(CMD_START);
        let r = (|| {
            self.write_byte(dev7 << 1)?;
            self.write_byte(reg)?;
            self.cmd(CMD_START); // repeated START
            self.write_byte((dev7 << 1) | 1)?;
            let n = out.len();
            for (i, slot) in out.iter_mut().enumerate() {
                *slot = self.read_byte(i + 1 == n);
            }
            Ok(())
        })();
        self.cmd(CMD_STOP);
        r
    }

    pub fn read_reg(&self, dev7: u8, reg: u8) -> Result<u8, I2cError> {
        let mut b = [0u8; 1];
        self.read_regs(dev7, reg, &mut b)?;
        Ok(b[0])
    }
}
