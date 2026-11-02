// Sound for the demos: the board's I2S output (eda/ethernet_hub75 AUDIO=1,
// UDP port 10002, 16-bit stereo 48 kHz little endian, 256 frames a packet).
// A demo starts voices with play(); a thread mixes them and sends while the
// board's level replies {5, level, max} leave room for a packet (like
// util/udpaudiosend). Without replies (a build without audio) it sends at
// the real-time rate. The board plays (L + R) / 2 on one small speaker, so
// both channels get the same mono mix.
use std::net::UdpSocket;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub const RATE: f32 = 48000.0;
const PKT: usize = 256;

/// a sound: one mono sample (about -1..1) per call, None when it is over
pub trait Voice: Send {
    fn next(&mut self) -> Option<f32>;
}

static ON: AtomicBool = AtomicBool::new(false);
static VOICES: Mutex<Vec<Box<dyn Voice>>> = Mutex::new(Vec::new());
static GAIN: Mutex<f32> = Mutex::new(1.0);
// the board's buffer level from its last reply (0xffff: no replies)
static LEVEL: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0xffff);

/// for the status line: the board's audio buffer, or None without replies
pub fn level() -> Option<u32> {
    Some(LEVEL.load(Ordering::Relaxed)).filter(|&l| l != 0xffff)
}

/// starts a voice (ignored when the sound is off)
pub fn play(v: impl Voice + 'static) {
    if ON.load(Ordering::Relaxed) {
        VOICES.lock().unwrap().push(Box::new(v));
    }
}

/// the next n samples of the mix, soft clipped
pub fn render(n: usize) -> Vec<f32> {
    let gain = *GAIN.lock().unwrap();
    let mut out = vec![0.0; n];
    let mut voices = VOICES.lock().unwrap();
    voices.retain_mut(|v| {
        for s in out.iter_mut() {
            match v.next() {
                Some(x) => *s += x,
                None => return false,
            }
        }
        true
    });
    out.iter().map(|s| (s * gain).tanh()).collect()
}

/// mixes without sending (the snapshots write the samples to a file)
pub fn start_offline() {
    ON.store(true, Ordering::Relaxed);
}

/// the sender thread: `bind` the PC's address (any port), `dest` the board
/// 16-bit mono 48 kHz WAV header for `frames` samples
pub fn wav_header(frames: usize) -> Vec<u8> {
    let n = frames as u32 * 2;
    let mut f = Vec::new();
    f.extend_from_slice(b"RIFF");
    f.extend_from_slice(&(36 + n).to_le_bytes());
    f.extend_from_slice(b"WAVEfmt ");
    for v in [16u32, 0x0001_0001, 48000, 96000, 0x0010_0002] {
        f.extend_from_slice(&v.to_le_bytes());
    }
    f.extend_from_slice(b"data");
    f.extend_from_slice(&n.to_le_bytes());
    f
}

/// what is sent, also written to a WAV file (the header is brought up to
/// date every second, so a killed demo leaves a playable file)
struct Recorder {
    f: std::fs::File,
    frames: usize,
}

impl Recorder {
    fn add(&mut self, s: &[f32]) -> std::io::Result<()> {
        use std::io::{Seek, SeekFrom, Write};
        let b: Vec<u8> = s.iter().flat_map(|v| ((v * 32767.0) as i16).to_le_bytes()).collect();
        self.f.write_all(&b)?;
        let before = self.frames;
        self.frames += s.len();
        if self.frames / 48000 != before / 48000 {
            self.f.seek(SeekFrom::Start(0))?;
            self.f.write_all(&wav_header(self.frames))?;
            self.f.seek(SeekFrom::End(0))?;
        }
        Ok(())
    }
}

pub fn start(bind: &str, dest: std::net::IpAddr, gain: f32, record: Option<&std::path::Path>) -> std::io::Result<()> {
    let mut rec = match record {
        Some(p) => {
            let mut f = std::fs::File::create(p)?;
            std::io::Write::write_all(&mut f, &wav_header(0))?;
            Some(Recorder { f, frames: 0 })
        }
        None => None,
    };
    let ip = bind.rsplit_once(':').map_or(bind, |(a, _)| a);
    let sock = UdpSocket::bind((ip, 0))?;
    sock.set_read_timeout(Some(Duration::from_millis(5)))?;
    let dest = std::net::SocketAddr::new(dest, 10002);
    *GAIN.lock().unwrap() = gain;
    ON.store(true, Ordering::Relaxed);
    std::thread::spawn(move || {
        let (mut level, mut max) = (0usize, 2048usize);
        let mut last_reply: Option<Instant> = None;
        let t0 = Instant::now();
        let mut sent = 0usize;
        let mut pkt = Vec::with_capacity(PKT * 4);
        loop {
            let live = last_reply.is_some_and(|t| t.elapsed() < Duration::from_millis(200));
            if !live {
                LEVEL.store(0xffff, Ordering::Relaxed);
            }
            // with replies: fill the board's buffer; without: real time
            // plus a little ahead
            let room = if live {
                max.saturating_sub(level) >= PKT
            } else {
                sent < (t0.elapsed().as_secs_f32() * RATE) as usize + 1024
            };
            if room {
                pkt.clear();
                let mix = render(PKT);
                if let Some(r) = rec.as_mut() {
                    if let Err(e) = r.add(&mix) {
                        eprintln!("\r\nrecording stopped: {}\r", e);
                        rec = None;
                    }
                }
                for s in mix {
                    let v = ((s * 32767.0) as i16).to_le_bytes();
                    pkt.extend_from_slice(&v);
                    pkt.extend_from_slice(&v);
                }
                if sock.send_to(&pkt, dest).is_err() {
                    std::thread::sleep(Duration::from_millis(10));
                }
                sent += PKT;
                level += PKT;
                continue;
            }
            let mut r = [0u8; 16];
            match sock.recv(&mut r) {
                Ok(5) if r[0] == 5 => {
                    level = u16::from_be_bytes([r[1], r[2]]) as usize;
                    max = u16::from_be_bytes([r[3], r[4]]) as usize;
                    last_reply = Some(Instant::now());
                    LEVEL.store(level as u32, Ordering::Relaxed);
                }
                Ok(_) => {}
                Err(_) => {
                    if !live {
                        // keep the real-time pace from here on
                        std::thread::sleep(Duration::from_millis(2));
                    }
                }
            }
        }
    });
    Ok(())
}

/// white noise, -1..1 (xorshift32, cheap enough for many voices)
pub struct Noise(pub u32);
impl Noise {
    pub fn next(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 17;
        self.0 ^= self.0 << 5;
        (self.0 as i32) as f32 / 2147483648.0
    }
}

/// a one-pole low-pass filter at `hz`
pub struct Lp {
    a: f32,
    y: f32,
}
impl Lp {
    pub fn new(hz: f32) -> Lp {
        Lp { a: 1.0 - (-2.0 * std::f32::consts::PI * hz / RATE).exp(), y: 0.0 }
    }
    pub fn run(&mut self, x: f32) -> f32 {
        self.y += self.a * (x - self.y);
        self.y
    }
}
