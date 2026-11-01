// The panel link: the screen goes into the top-left corner of a frame of
// the display's size (256x256 for the 16-panel build, 128x192 for 6
// panels), RGB565 little endian, 1024-byte packets with a 2-byte big-endian
// offset (in 2-byte units for frames over 64 KB), like util/udpvideosend.
// After each frame the board answers 0xdeadbeef once it shows it; data
// sent before that would be dropped, so send() waits for the ack (a few ms).
use crate::gfx::{Canvas, H, W};
use std::io;
use std::net::{SocketAddr, UdpSocket};
use std::time::Duration;

pub struct Panel {
    sock: UdpSocket,
    dest: SocketAddr,
    fw: usize,
    buf: Vec<u8>,
    pkt: Vec<u8>,
    pub acks: u64,
}

impl Panel {
    pub fn new(bind: &str, dest: &str, fw: usize, fh: usize) -> io::Result<Panel> {
        assert!(fw >= W && fh >= H, "the frame must hold the 128x192 screen");
        let sock = UdpSocket::bind(bind)?;
        sock.set_read_timeout(Some(Duration::from_millis(6)))?;
        let dest = dest
            .parse()
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
        Ok(Panel { sock, dest, fw, buf: vec![0; fw * fh * 2], pkt: Vec::with_capacity(1026), acks: 0 })
    }

    pub fn send(&mut self, c: &Canvas) -> io::Result<()> {
        for y in 0..H {
            for x in 0..W {
                let [r, g, b] = c.px[y * W + x];
                let v = ((r as u16 >> 3) << 11) | ((g as u16 >> 2) << 5) | (b as u16 >> 3);
                let o = (y * self.fw + x) * 2;
                self.buf[o..o + 2].copy_from_slice(&v.to_le_bytes());
            }
        }
        let unit = if self.buf.len() > 65536 { 2 } else { 1 };
        for off in (0..self.buf.len()).step_by(1024) {
            let end = (off + 1024).min(self.buf.len());
            self.pkt.clear();
            self.pkt.extend_from_slice(&((off / unit) as u16).to_be_bytes());
            self.pkt.extend_from_slice(&self.buf[off..end]);
            self.sock.send_to(&self.pkt, self.dest)?;
        }
        let mut ack = [0u8; 16];
        if self.sock.recv_from(&mut ack).is_ok() {
            self.acks += 1;
        }
        Ok(())
    }
}
