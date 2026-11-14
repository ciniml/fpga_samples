// A stand-in for the panel board (eda/ethernet_hub75) that shows the
// picture in a web browser: it takes the same UDP traffic as the board
// (video on port 10004 with the 0xdeadbeef ack, colour tables on 10005,
// sound on 10002 with the {5, level, max} replies) and relays it over a
// WebSocket to the page it serves, which draws the LEDs on a canvas with
// the panels laid out as on the board's connectors and plays the sound.
//
//   hub75emu [--http 0.0.0.0:8075] [--frame 256x256] [--panels 2x3]
//   then a demo with --emu (only here) or --mirror <this host> (the board too)
//   and http://<this host>:8075/ in a browser
//
// Only std: a small HTTP server, the WebSocket handshake (SHA-1, base64)
// and its framing. To the browser (binary messages, the first byte the kind):
//   1 frame: u16 w, u16 h (the panels' area), RGB565 little endian rows
//   2 sound: mono i16 little endian at 48 kHz ((L + R) / 2 of the packet)
//   3 colour tables: 64 R, 64 G, 64 B (8 bit, as loaded on port 10005)
// and text messages (JSON): the layout on connecting, the counters every second.
// From the browser: its keys, text "key <name> <1 | 0>" ("key all 0": the
// page lost the focus), sent on to the host the frames come from (UDP
// 10006, where the demo's input.rs takes them like a controller's).
use clap::Parser;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::sync::mpsc::{sync_channel, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const PAGE: &str = include_str!("../emu/index.html");
use hub75_games::input::KEY_PORT;

#[derive(Parser)]
struct Cli {
    /// the web page and its WebSocket (all interfaces: open it from another PC)
    #[arg(long, default_value = "0.0.0.0:8075")]
    http: String,
    /// the address the board's UDP ports listen on (10004 video, 10005
    /// colour tables, 10002 sound)
    #[arg(long, default_value = "0.0.0.0")]
    udp: String,
    /// the frame the sender sends, WxH: 256x256 (16-panel build) or 128x192 (6-panel build)
    #[arg(long, default_value = "256x256")]
    frame: String,
    /// the panels connected, columns x rows of 64x64 from the top left of
    /// the frame (2x3 = the 6 at the booth, 4x4 = all 16)
    #[arg(long, default_value = "2x3")]
    panels: String,
}

fn wxh(s: &str) -> Option<(usize, usize)> {
    let (a, b) = s.split_once('x')?;
    Some((a.parse().ok()?, b.parse().ok()?))
}

/// the browsers connected: each has a writer thread fed through a bounded
/// channel (a slow one loses messages instead of holding the others up)
#[derive(Default)]
struct Hub {
    clients: Mutex<Vec<SyncSender<Arc<Vec<u8>>>>>,
    lut: Mutex<Vec<u8>>,
    frame: Mutex<Option<Arc<Vec<u8>>>>,
    stat: Mutex<Stat>,
    sender: Mutex<Option<SocketAddr>>, // where the frames come from
    keys: Mutex<Option<UdpSocket>>,    // sends the page's keys there
}

#[derive(Default)]
struct Stat {
    frames: u64,
    packets: u64,
    src: String,
    audio_level: Option<u32>,
    audio_packets: u64,
    lut_loads: u64,
}

impl Hub {
    fn send(&self, m: Arc<Vec<u8>>) {
        self.clients.lock().unwrap().retain(|c| !matches!(c.try_send(m.clone()), Err(TrySendError::Disconnected(_))));
    }

    /// a key from a page, to the demo
    fn key(&self, m: &[u8]) {
        let Some(to) = *self.sender.lock().unwrap() else { return };
        if let Some(s) = &*self.keys.lock().unwrap() {
            let _ = s.send_to(m, SocketAddr::new(to.ip(), KEY_PORT));
        }
    }
}

// ---- WebSocket ----

fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h: [u32; 5] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];
    let mut m = data.to_vec();
    m.push(0x80);
    while m.len() % 64 != 56 {
        m.push(0);
    }
    m.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in m.chunks(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            w[i] = u32::from_be_bytes(chunk[i * 4..i * 4 + 4].try_into().unwrap());
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let [mut a, mut b, mut c, mut d, mut e] = h;
        for (i, wi) in w.iter().enumerate() {
            let (f, k) = match i / 20 {
                0 => ((b & c) | (!b & d), 0x5A827999),
                1 => (b ^ c ^ d, 0x6ED9EBA1),
                2 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDC),
                _ => (b ^ c ^ d, 0xCA62C1D6),
            };
            let t = a.rotate_left(5).wrapping_add(f).wrapping_add(e).wrapping_add(k).wrapping_add(*wi);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = t;
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e]) {
            *x = x.wrapping_add(y);
        }
    }
    let mut out = [0u8; 20];
    for i in 0..5 {
        out[i * 4..i * 4 + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

fn base64(data: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::new();
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            s.push(if i <= c.len() { T[(n >> (18 - 6 * i) & 63) as usize] as char } else { '=' });
        }
    }
    s
}

/// a WebSocket message from the server: binary (0x2) or text (0x1), not masked
fn ws_frame(op: u8, payload: &[u8]) -> Vec<u8> {
    let mut f = vec![0x80 | op];
    match payload.len() {
        n if n < 126 => f.push(n as u8),
        n if n < 65536 => {
            f.push(126);
            f.extend_from_slice(&(n as u16).to_be_bytes());
        }
        n => {
            f.push(127);
            f.extend_from_slice(&(n as u64).to_be_bytes());
        }
    }
    f.extend_from_slice(payload);
    f
}

/// a WebSocket message from the browser (masked, at most 64 KB): (opcode, payload)
fn ws_read(r: &mut impl Read) -> std::io::Result<(u8, Vec<u8>)> {
    let mut h = [0u8; 2];
    r.read_exact(&mut h)?;
    let mut n = (h[1] & 0x7f) as usize;
    if n == 126 {
        let mut l = [0u8; 2];
        r.read_exact(&mut l)?;
        n = u16::from_be_bytes(l) as usize;
    } else if n == 127 {
        return Err(std::io::ErrorKind::InvalidData.into());
    }
    let mut mask = [0u8; 4];
    if h[1] & 0x80 != 0 {
        r.read_exact(&mut mask)?;
    }
    let mut p = vec![0u8; n];
    r.read_exact(&mut p)?;
    for (i, b) in p.iter_mut().enumerate() {
        *b ^= mask[i % 4];
    }
    Ok((h[0] & 0x0f, p))
}

fn text(s: &str) -> Arc<Vec<u8>> {
    Arc::new(ws_frame(1, s.as_bytes()))
}

fn binary(kind: u8, data: &[u8]) -> Arc<Vec<u8>> {
    let mut p = Vec::with_capacity(data.len() + 1);
    p.push(kind);
    p.extend_from_slice(data);
    Arc::new(ws_frame(2, &p))
}

fn http(mut s: TcpStream, hub: Arc<Hub>, config: Arc<String>) -> std::io::Result<()> {
    let mut r = BufReader::new(s.try_clone()?);
    let mut line = String::new();
    r.read_line(&mut line)?;
    let path = line.split_whitespace().nth(1).unwrap_or("/").to_string();
    let mut key = None;
    loop {
        let mut h = String::new();
        if r.read_line(&mut h)? == 0 || h.trim().is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            if k.trim().eq_ignore_ascii_case("sec-websocket-key") {
                key = Some(v.trim().to_string());
            }
        }
    }
    match (path.as_str(), key) {
        ("/ws", Some(k)) => {
            let accept = base64(&sha1(format!("{}258EAFA5-E914-47DA-95CA-C5AB0DC85B11", k).as_bytes()));
            write!(s, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {}\r\n\r\n", accept)?;
            s.set_nodelay(true)?;
            let (tx, rx) = sync_channel::<Arc<Vec<u8>>>(48);
            // the layout, the tables and the last picture first
            tx.send(text(&config)).ok();
            tx.send(binary(3, &hub.lut.lock().unwrap())).ok();
            if let Some(f) = hub.frame.lock().unwrap().clone() {
                tx.send(f).ok();
            }
            hub.clients.lock().unwrap().push(tx);
            let mut w = s.try_clone()?;
            std::thread::spawn(move || {
                for m in rx {
                    if w.write_all(&m).is_err() {
                        break;
                    }
                }
                let _ = w.shutdown(std::net::Shutdown::Both);
            });
            // the page's keys, until it closes
            while let Ok((op, m)) = ws_read(&mut r) {
                if op == 8 {
                    break;
                }
                if op == 1 && m.starts_with(b"key ") {
                    hub.key(&m);
                }
            }
            let _ = s.shutdown(std::net::Shutdown::Both);
        }
        ("/" | "/index.html", _) => {
            write!(s, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-cache\r\n\r\n", PAGE.len())?;
            s.write_all(PAGE.as_bytes())?;
        }
        _ => {
            s.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")?;
        }
    }
    Ok(())
}

// ---- the board's UDP ports ----

/// a frame comes as a burst of 128 packets (256x256), more than the
/// default receive buffer holds on Linux (each packet costs about twice its
/// size there): ask for the most an unprivileged socket gets (rmem_max)
#[cfg(target_os = "linux")]
fn big_rcvbuf(s: &UdpSocket) {
    use std::os::fd::AsRawFd;
    extern "C" {
        fn setsockopt(fd: i32, level: i32, name: i32, val: *const std::ffi::c_void, len: u32) -> i32;
    }
    const SOL_SOCKET: i32 = 1;
    const SO_RCVBUF: i32 = 8;
    let max = std::fs::read_to_string("/proc/sys/net/core/rmem_max").ok().and_then(|v| v.trim().parse::<i32>().ok()).unwrap_or(212992);
    let v: i32 = max.max(4 << 20);
    unsafe {
        setsockopt(s.as_raw_fd(), SOL_SOCKET, SO_RCVBUF, &v as *const i32 as *const _, 4);
    }
}
#[cfg(not(target_os = "linux"))]
fn big_rcvbuf(_: &UdpSocket) {}

/// video: the packets fill the frame; the one that writes its last byte
/// shows it (to the browsers) and is answered with de ad be ef
fn video(sock: UdpSocket, hub: Arc<Hub>, fw: usize, fh: usize, cols: usize, rows: usize) {
    let total = fw * fh * 2;
    let unit = if total > 65536 { 2 } else { 1 };
    let mut fb = vec![0u8; total];
    let mut buf = [0u8; 2048];
    let (w, h) = (cols * 64, rows * 64);
    loop {
        let Ok((n, src)) = sock.recv_from(&mut buf) else { continue };
        if n < 3 {
            continue;
        }
        let off = u16::from_be_bytes([buf[0], buf[1]]) as usize * unit;
        let data = &buf[2..n];
        if off >= total {
            continue;
        }
        let end = (off + data.len()).min(total);
        fb[off..end].copy_from_slice(&data[..end - off]);
        {
            let mut st = hub.stat.lock().unwrap();
            st.packets += 1;
        }
        if end == total {
            let mut m = Vec::with_capacity(4 + w * h * 2);
            m.extend_from_slice(&(w as u16).to_le_bytes());
            m.extend_from_slice(&(h as u16).to_le_bytes());
            for y in 0..h {
                m.extend_from_slice(&fb[y * fw * 2..y * fw * 2 + w * 2]);
            }
            let msg = binary(1, &m);
            *hub.frame.lock().unwrap() = Some(msg.clone());
            hub.send(msg);
            let _ = sock.send_to(&[0xde, 0xad, 0xbe, 0xef], src);
            *hub.sender.lock().unwrap() = Some(src);
            let mut st = hub.stat.lock().unwrap();
            st.frames += 1;
            st.src = src.to_string();
        }
    }
}

/// the colour tables after a reset: the identity (bits copied down)
fn identity_lut() -> Vec<u8> {
    let mut t = Vec::with_capacity(192);
    for n in [32usize, 64, 32] {
        for i in 0..64usize {
            let v = i.min(n - 1);
            t.push(if n == 32 { (v << 3 | v >> 2) as u8 } else { (v << 2 | v >> 4) as u8 });
        }
    }
    t
}

fn lut(sock: UdpSocket, hub: Arc<Hub>) {
    let mut buf = [0u8; 256];
    loop {
        let Ok((n, _)) = sock.recv_from(&mut buf) else { continue };
        if n < 2 {
            continue;
        }
        let mask = buf[0];
        let msg = {
            let mut t = hub.lut.lock().unwrap();
            for ch in 0..3 {
                if mask >> ch & 1 != 0 {
                    for (i, v) in buf[1..n.min(65)].iter().enumerate() {
                        t[ch * 64 + i] = *v;
                    }
                }
            }
            binary(3, &t)
        };
        hub.stat.lock().unwrap().lut_loads += 1;
        hub.send(msg);
    }
}

/// sound: a model of the board's FIFO (2048 frames, plays from 1024 on,
/// at 48 kHz), the level reply every 256 frames played, the samples to the
/// browsers as they come
fn sound(sock: UdpSocket, hub: Arc<Hub>) {
    const MAX: f64 = 2048.0;
    const START: f64 = 1024.0;
    sock.set_read_timeout(Some(Duration::from_millis(2))).ok();
    let mut buf = [0u8; 4096];
    let (mut level, mut playing, mut played) = (0.0f64, false, 0.0f64);
    let mut last = Instant::now();
    let mut src: Option<SocketAddr> = None;
    let mut last_packet = Instant::now();
    loop {
        let got = sock.recv_from(&mut buf);
        let now = Instant::now();
        let dt = now.duration_since(last).as_secs_f64() * 48000.0;
        last = now;
        if playing {
            let p = dt.min(level);
            level -= p;
            let before = played;
            played += p;
            if level <= 0.0 {
                playing = false;
            }
            if (played / 256.0).floor() != (before / 256.0).floor() {
                if let Some(a) = src {
                    let l = level as u16;
                    let r = [5, (l >> 8) as u8, l as u8, (MAX as u16 >> 8) as u8, MAX as u16 as u8];
                    let _ = sock.send_to(&r, a);
                }
            }
        }
        if let Ok((n, a)) = got {
            src = Some(a);
            last_packet = now;
            let frames = n / 4;
            level = (level + frames as f64).min(MAX);
            if !playing && level >= START {
                playing = true;
            }
            let mut m = Vec::with_capacity(frames * 2);
            for f in buf[..frames * 4].chunks_exact(4) {
                let l = i16::from_le_bytes([f[0], f[1]]) as i32;
                let r = i16::from_le_bytes([f[2], f[3]]) as i32;
                m.extend_from_slice(&(((l + r) / 2) as i16).to_le_bytes());
            }
            hub.send(binary(2, &m));
            let mut st = hub.stat.lock().unwrap();
            st.audio_packets += 1;
            st.audio_level = Some(level as u32);
        } else if now.duration_since(last_packet) > Duration::from_secs(1) {
            hub.stat.lock().unwrap().audio_level = None;
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let (fw, fh) = wxh(&cli.frame).ok_or("--frame: WxH")?;
    let (cols, rows) = wxh(&cli.panels).ok_or("--panels: CxR")?;
    if fw % 64 != 0 || fh % 64 != 0 || cols * 64 > fw || rows * 64 > fh || cols == 0 || rows == 0 {
        return Err("--panels must fit in --frame (64x64 panels)".into());
    }
    // the connectors: J4 on, row by row across the frame (J4 J5 / J8 J9 /
    // J12 J13 for 2x3 on the 16-panel build, J4..J9 on the 6-panel one)
    let labels: Vec<String> =
        (0..rows).flat_map(|r| (0..cols).map(move |c| (r, c))).map(|(r, c)| format!("\"J{}\"", 4 + r * (fw / 64) + c)).collect();
    let config = Arc::new(format!(
        "{{\"type\":\"config\",\"fw\":{},\"fh\":{},\"cols\":{},\"rows\":{},\"labels\":[{}]}}",
        fw,
        fh,
        cols,
        rows,
        labels.join(",")
    ));
    let hub = Arc::new(Hub::default());
    *hub.lut.lock().unwrap() = identity_lut();
    *hub.keys.lock().unwrap() = Some(UdpSocket::bind("0.0.0.0:0")?);

    let v = UdpSocket::bind((cli.udp.as_str(), 10004))?;
    big_rcvbuf(&v);
    let l = UdpSocket::bind((cli.udp.as_str(), 10005))?;
    let a = UdpSocket::bind((cli.udp.as_str(), 10002))?;
    let listener = TcpListener::bind(&cli.http)?;
    {
        let hub = hub.clone();
        std::thread::spawn(move || video(v, hub, fw, fh, cols, rows));
    }
    {
        let hub = hub.clone();
        std::thread::spawn(move || lut(l, hub));
    }
    {
        let hub = hub.clone();
        std::thread::spawn(move || sound(a, hub));
    }
    {
        // the counters, every second
        let hub = hub.clone();
        std::thread::spawn(move || {
            let mut last = (0u64, 0u64, 0u64);
            loop {
                std::thread::sleep(Duration::from_secs(1));
                let s = {
                    let st = hub.stat.lock().unwrap();
                    let s = format!(
                        "{{\"type\":\"stat\",\"fps\":{},\"pps\":{},\"src\":\"{}\",\"audio\":{},\"audio_pps\":{},\"lut_loads\":{},\"clients\":{}}}",
                        st.frames - last.0,
                        st.packets - last.1,
                        st.src,
                        st.audio_level.map_or("null".into(), |l| l.to_string()),
                        st.audio_packets - last.2,
                        st.lut_loads,
                        hub.clients.lock().unwrap().len()
                    );
                    last = (st.frames, st.packets, st.audio_packets);
                    s
                };
                hub.send(text(&s));
            }
        });
    }
    let port = listener.local_addr()?.port();
    println!("hub75emu: frame {}x{}, panels {}x{} ({}x{} px)", fw, fh, cols, rows, cols * 64, rows * 64);
    println!("  UDP {}: 10004 video, 10005 colour tables, 10002 sound", cli.udp);
    println!("  open http://<this host>:{}/ (listening on {})", port, cli.http);
    for s in listener.incoming().flatten() {
        let (hub, config) = (hub.clone(), config.clone());
        std::thread::spawn(move || {
            let _ = http(s, hub, config);
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handshake() {
        // RFC 6455 section 1.3
        let k = "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        assert_eq!(base64(&sha1(k.as_bytes())), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
        assert_eq!(base64(b"ab"), "YWI=");
    }
}
