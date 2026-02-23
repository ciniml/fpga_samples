use core::cell::RefCell;

use bootrom_pac;
use embedded_hal_nb::serial::*;

pub struct SerialOut<SerialOut> {
    serial_out: SerialOut,
}
impl SerialOut<bootrom_pac::SYSTEM_SERIALOUT> {
    pub fn init(serial_out: bootrom_pac::SYSTEM_SERIALOUT) -> Self {
        Self {
            serial_out,
        }
    }
}
impl embedded_hal::serial::ErrorType for SerialOut<bootrom_pac::SYSTEM_SERIALOUT> {
    type Error = embedded_hal::serial::ErrorKind;
}
impl embedded_hal_nb::serial::Write<u8> for SerialOut<bootrom_pac::SYSTEM_SERIALOUT> {
    fn write(&mut self, word: u8) -> embedded_hal_nb::nb::Result<(), Self::Error> {
        if self.serial_out.serial_out.read().txbusy().bit_is_set() {
            Err(embedded_hal_nb::nb::Error::WouldBlock)
        } else {
            self.serial_out.serial_out.write(|w| w.data().bits(word));
            Ok(())
        }
    }
    fn flush(&mut self) -> embedded_hal_nb::nb::Result<(), Self::Error> {
        if self.serial_out.serial_out.read().txbusy().bit_is_clear() {
            Ok(())
        } else {
            Err(embedded_hal_nb::nb::Error::WouldBlock)
        }
    }
}

impl core::fmt::Write for SerialOut<bootrom_pac::SYSTEM_SERIALOUT> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for byte in s.as_bytes().into_iter() {
            embedded_hal_nb::nb::block!(self.write(*byte)).map_err(|_| core::fmt::Error)?
        }
        Ok(())
    }
}
