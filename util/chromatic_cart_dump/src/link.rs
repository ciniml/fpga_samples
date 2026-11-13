// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Byte-stream links to the cartridge reader: the USB device (EP1 OUT / IN) or the
//! Verilator model of rtl/chromatic/test (stdin / stdout of a child process).

use nusb::{
    io::{EndpointRead, EndpointWrite},
    transfer::{Bulk, ControlIn, ControlType, In, Out, Recipient},
    MaybeFuture,
};
use std::{
    io::{Read, Write},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    time::Duration,
};

pub const VID: u16 = 0x1209;
pub const PID: u16 = 0x0001;
/// vendor request 0x01 (i_vendor_status of UsbDevice) of eda/chromatic_cart_dump: "GBCR"
pub const DEVICE_ID: u32 = u32::from_le_bytes(*b"GBCR");

pub trait Link {
    fn send(&mut self, data: &[u8]) -> Result<(), String>;
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String>;
}

pub struct UsbLink {
    _dev: nusb::Device,
    _iface: nusb::Interface,
    out: EndpointWrite<Bulk>,
    inp: EndpointRead<Bulk>,
}

impl UsbLink {
    pub fn open() -> Result<UsbLink, String> {
        let list = nusb::list_devices().wait().map_err(|e| e.to_string())?;
        let mut last = format!(
            "no {VID:04x}:{PID:04x} device (is eda/chromatic_cart_dump loaded and the console on?)"
        );
        for di in list.filter(|d| d.vendor_id() == VID && d.product_id() == PID) {
            let r = (|| {
                let dev = di.open().wait().map_err(|e| format!("open: {e}"))?;
                let iface = dev
                    .claim_interface(0)
                    .wait()
                    .map_err(|e| format!("claim: {e}"))?;
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
                if id.len() != 4 || u32::from_le_bytes([id[0], id[1], id[2], id[3]]) != DEVICE_ID {
                    return Err(format!("{VID:04x}:{PID:04x} is not the cartridge reader (id {id:02x?})"));
                }
                let out = iface
                    .endpoint::<Bulk, Out>(0x01)
                    .map_err(|e| format!("EP1 OUT: {e}"))?
                    .writer(4096)
                    .with_write_timeout(Duration::from_secs(2));
                let inp = iface
                    .endpoint::<Bulk, In>(0x81)
                    .map_err(|e| format!("EP1 IN: {e}"))?
                    .reader(16384)
                    .with_read_timeout(Duration::from_secs(3));
                Ok(UsbLink { _dev: dev, _iface: iface, out, inp })
            })();
            match r {
                Ok(l) => return Ok(l),
                Err(e) => last = e,
            }
        }
        Err(last)
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

/// rtl/chromatic/test: `make simexe` builds obj_sim_*/cart_sim
pub struct SimLink {
    child: Child,
    stdin: Option<ChildStdin>,
    stdout: ChildStdout,
}

impl SimLink {
    pub fn spawn(exe: &str) -> Result<SimLink, String> {
        let mut child = Command::new(exe)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("{exe}: {e}"))?;
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().ok_or("no stdout")?;
        Ok(SimLink { child, stdin, stdout })
    }
    /// close the model's input and wait for it: Ok(()) unless it reported a rule violation
    pub fn finish(mut self) -> Result<(), String> {
        drop(self.stdin.take());
        let st = self.child.wait().map_err(|e| e.to_string())?;
        if st.success() {
            Ok(())
        } else {
            Err(format!("cartridge model: {st} (3 = rule violation)"))
        }
    }
}

impl Link for SimLink {
    fn send(&mut self, data: &[u8]) -> Result<(), String> {
        let w = self.stdin.as_mut().ok_or("closed")?;
        w.write_all(data).and_then(|_| w.flush()).map_err(|e| format!("sim write: {e}"))
    }
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String> {
        self.stdout.read_exact(buf).map_err(|e| format!("sim read: {e}"))
    }
}
