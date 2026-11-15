// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Byte-stream links to the cartridge: the Dock's USB-UART, or USB 2.0 (EP1 OUT / IN of
//! eda/cart_game with a Pmod USB HS Single; the same command stream).

use nusb::{
    io::{EndpointRead, EndpointWrite},
    transfer::{Bulk, ControlIn, ControlType, In, Out, Recipient},
    MaybeFuture,
};
use std::{
    io::{Read, Write},
    time::Duration,
};

pub const VID: u16 = 0x1209;
pub const PID: u16 = 0x0001;

pub trait Link {
    fn send(&mut self, data: &[u8]) -> Result<(), String>;
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String>;
}

pub struct UartLink(pub Box<dyn serialport::SerialPort>);

impl Link for UartLink {
    fn send(&mut self, data: &[u8]) -> Result<(), String> {
        self.0.write_all(data).map_err(|e| format!("UART write: {e}"))
    }
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String> {
        self.0.read_exact(buf).map_err(|e| format!("UART read: {e}"))
    }
}

pub struct UsbLink {
    _dev: nusb::Device,
    _iface: nusb::Interface,
    out: EndpointWrite<Bulk>,
    inp: EndpointRead<Bulk>,
    pub high_speed: bool,
}

impl UsbLink {
    /// The first 1209:0001 device whose vendor request 0x01 answers "GC" in the upper half
    /// (eda/cart_game; other test devices share the IDs).
    pub fn open() -> Result<UsbLink, String> {
        let list = nusb::list_devices().wait().map_err(|e| e.to_string())?;
        let mut last = format!("no {VID:04x}:{PID:04x} device (is eda/cart_game loaded and the Pmod USB HS Single connected?)");
        for di in list.filter(|d| d.vendor_id() == VID && d.product_id() == PID) {
            let r = (|| {
                let dev = di.open().wait().map_err(|e| format!("open: {e}"))?;
                let iface = dev.claim_interface(0).wait().map_err(|e| format!("claim: {e}"))?;
                let id = iface
                    .control_in(
                        ControlIn {
                            control_type: ControlType::Vendor,
                            recipient: Recipient::Device,
                            request: 0x01,
                            value: 0,
                            index: 0,
                            length: 4,
                        },
                        Duration::from_millis(1000),
                    )
                    .wait()
                    .map_err(|e| format!("id request: {e}"))?;
                if id.len() != 4 || id[2] != b'C' || id[3] != b'G' {
                    return Err(format!("{VID:04x}:{PID:04x} is not eda/cart_game (id {id:02x?})"));
                }
                let out = iface
                    .endpoint::<Bulk, Out>(0x01)
                    .map_err(|e| format!("EP1 OUT: {e}"))?
                    .writer(16384)
                    .with_write_timeout(Duration::from_secs(3));
                let inp = iface
                    .endpoint::<Bulk, In>(0x81)
                    .map_err(|e| format!("EP1 IN: {e}"))?
                    .reader(16384)
                    .with_read_timeout(Duration::from_secs(3));
                Ok(UsbLink { _dev: dev, _iface: iface, out, inp, high_speed: id[0] & 1 != 0 })
            })();
            match r {
                Ok(mut l) => {
                    if !l.high_speed {
                        eprintln!("note: USB link at full speed");
                    }
                    l.drain();
                    return Ok(l);
                }
                Err(e) => last = e,
            }
        }
        Err(last)
    }

    /// Throw away what an interrupted earlier run left in the IN direction.
    fn drain(&mut self) {
        self.inp.set_read_timeout(Duration::from_millis(50));
        let mut b = [0u8; 4096];
        while matches!(self.inp.read(&mut b), Ok(n) if n > 0) {}
        self.inp.set_read_timeout(Duration::from_secs(3));
    }
}

impl Link for UsbLink {
    fn send(&mut self, data: &[u8]) -> Result<(), String> {
        self.out.write_all(data).map_err(|e| format!("USB write: {e}"))?;
        self.out.flush().map_err(|e| format!("USB write: {e}"))
    }
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String> {
        self.inp.read_exact(buf).map_err(|e| format!("USB read: {e}"))
    }
}
