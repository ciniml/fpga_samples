// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Byte-stream links: the Chromatic (USB EP1, eda/chromatic_cart_bustest), the test target (UART),
//! or both ends in the Verilator model (rtl/chromatic/test/bt: stdin/stdout and two FIFOs).

use nusb::{
    io::{EndpointRead, EndpointWrite},
    transfer::{Bulk, ControlIn, ControlType, In, Out, Recipient},
    MaybeFuture,
};
use std::{
    fs::File,
    io::{Read, Write},
    path::PathBuf,
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    time::Duration,
};

pub trait Link {
    fn send(&mut self, data: &[u8]) -> Result<(), String>;
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String>;
}

impl Link for Box<dyn Link> {
    fn send(&mut self, d: &[u8]) -> Result<(), String> { (**self).send(d) }
    fn recv(&mut self, b: &mut [u8]) -> Result<(), String> { (**self).recv(b) }
}

pub const VID: u16 = 0x1209;
pub const PID: u16 = 0x0001;
/// vendor request 0x01 of eda/chromatic_cart_bustest
pub const DEVICE_ID: u32 = u32::from_le_bytes(*b"GBBT");

pub struct UsbLink {
    _dev: nusb::Device,
    _iface: nusb::Interface,
    out: EndpointWrite<Bulk>,
    inp: EndpointRead<Bulk>,
}

impl UsbLink {
    pub fn open() -> Result<UsbLink, String> {
        let list = nusb::list_devices().wait().map_err(|e| e.to_string())?;
        let mut last = format!("no {VID:04x}:{PID:04x} device (is eda/chromatic_cart_bustest loaded and the console on?)");
        for di in list.filter(|d| d.vendor_id() == VID && d.product_id() == PID) {
            let r = (|| {
                let dev = di.open().wait().map_err(|e| format!("open: {e}"))?;
                let iface = dev.claim_interface(0).wait().map_err(|e| format!("claim: {e}"))?;
                let id = iface
                    .control_in(
                        ControlIn { control_type: ControlType::Vendor, recipient: Recipient::Device, request: 0x01, value: 0, index: 0, length: 4 },
                        Duration::from_millis(1000),
                    )
                    .wait()
                    .map_err(|e| format!("id request: {e}"))?;
                if id.len() != 4 || u32::from_le_bytes([id[0], id[1], id[2], id[3]]) != DEVICE_ID {
                    return Err(format!("{VID:04x}:{PID:04x} is not the bus test design (id {id:02x?})"));
                }
                let out = iface.endpoint::<Bulk, Out>(0x01).map_err(|e| format!("EP1 OUT: {e}"))?.writer(4096).with_write_timeout(Duration::from_secs(2));
                let inp = iface.endpoint::<Bulk, In>(0x81).map_err(|e| format!("EP1 IN: {e}"))?.reader(16384).with_read_timeout(Duration::from_secs(60));
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
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String> { self.inp.read_exact(buf).map_err(|e| format!("USB read: {e}")) }
}

pub struct SerialLink {
    port: Box<dyn serialport::SerialPort>,
}

impl SerialLink {
    pub fn open(path: &str, baud: u32) -> Result<SerialLink, String> {
        let port = serialport::new(path, baud).timeout(Duration::from_secs(3)).open().map_err(|e| format!("{path}: {e}"))?;
        let _ = port.clear(serialport::ClearBuffer::All);
        Ok(SerialLink { port })
    }
}

impl Link for SerialLink {
    fn send(&mut self, data: &[u8]) -> Result<(), String> { self.port.write_all(data).map_err(|e| format!("UART write: {e}")) }
    fn recv(&mut self, buf: &mut [u8]) -> Result<(), String> { self.port.read_exact(buf).map_err(|e| format!("UART read: {e}")) }
}

/// the Verilator model: Chromatic stream on stdin / stdout, target stream on two FIFOs
pub struct Sim {
    child: Child,
    dir: PathBuf,
}

pub struct SimChromatic {
    stdin: Option<ChildStdin>,
    stdout: ChildStdout,
}
pub struct SimTarget {
    to: File,
    from: File,
}

impl Sim {
    pub fn spawn(exe: &str) -> Result<(Sim, SimChromatic, SimTarget), String> {
        let dir = std::env::temp_dir().join(format!("chromatic_bustest_{}", std::process::id()));
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let (fin, fout) = (dir.join("uart_in"), dir.join("uart_out"));
        for f in [&fin, &fout] {
            let st = Command::new("mkfifo").arg(f).status().map_err(|e| format!("mkfifo: {e}"))?;
            if !st.success() {
                return Err("mkfifo failed".into());
            }
        }
        let mut child = Command::new(exe)
            .env("BT_SIM_UART_IN", &fin)
            .env("BT_SIM_UART_OUT", &fout)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("{exe}: {e}"))?;
        // same order as the model: its write end (our read end) first
        let from = File::open(&fout).map_err(|e| format!("fifo: {e}"))?;
        let to = std::fs::OpenOptions::new().write(true).open(&fin).map_err(|e| format!("fifo: {e}"))?;
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().ok_or("no stdout")?;
        Ok((Sim { child, dir }, SimChromatic { stdin, stdout }, SimTarget { to, from }))
    }
    /// wait for the model (after the links are dropped): Err when it saw contention
    pub fn finish(mut self) -> Result<(), String> {
        let st = self.child.wait().map_err(|e| e.to_string())?;
        let _ = std::fs::remove_dir_all(&self.dir);
        if st.success() { Ok(()) } else { Err(format!("model: {st} (3 = data bus contention)")) }
    }
}

impl Link for SimChromatic {
    fn send(&mut self, d: &[u8]) -> Result<(), String> {
        let w = self.stdin.as_mut().ok_or("closed")?;
        w.write_all(d).and_then(|_| w.flush()).map_err(|e| format!("sim write: {e}"))
    }
    fn recv(&mut self, b: &mut [u8]) -> Result<(), String> { self.stdout.read_exact(b).map_err(|e| format!("sim read: {e}")) }
}

impl Link for SimTarget {
    fn send(&mut self, d: &[u8]) -> Result<(), String> { self.to.write_all(d).and_then(|_| self.to.flush()).map_err(|e| format!("sim uart write: {e}")) }
    fn recv(&mut self, b: &mut [u8]) -> Result<(), String> { self.from.read_exact(b).map_err(|e| format!("sim uart read: {e}")) }
}
