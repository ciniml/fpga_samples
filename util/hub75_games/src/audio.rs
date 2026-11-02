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
// showcase: the fade of the current demo, and a count of demo switches
static FADE: Mutex<f32> = Mutex::new(1.0);
static SCENE: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
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

/// showcase: a new demo is on; the sounds of the last one stop (its
/// background sounds start again when it comes back, see Keep)
pub fn new_scene() {
    SCENE.fetch_add(1, Ordering::Relaxed);
    VOICES.lock().unwrap().clear();
}

/// showcase: the volume follows the picture's fade (0..1)
pub fn set_fade(f: f32) {
    *FADE.lock().unwrap() = f;
}

/// a demo's background sound (rain, water, ...): start() is true when it
/// has to be started, at first and again after the showcase came back
#[derive(Default)]
pub struct Keep(Option<u32>);
impl Keep {
    pub fn start(&mut self) -> bool {
        let s = SCENE.load(Ordering::Relaxed);
        let first = self.0 != Some(s);
        self.0 = Some(s);
        first
    }
}

/// the next n samples of the mix, soft clipped
pub fn render(n: usize) -> Vec<f32> {
    let gain = *GAIN.lock().unwrap() * *FADE.lock().unwrap();
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

/// a one-pole high-pass filter at `hz`
pub struct Hp(Lp);
impl Hp {
    pub fn new(hz: f32) -> Hp {
        Hp(Lp::new(hz))
    }
    pub fn run(&mut self, x: f32) -> f32 {
        x - self.0.run(x)
    }
}

/// a two-pole resonant band-pass (state variable filter) at `hz`, q 0.5..20
pub struct Bp {
    f: f32,
    q: f32,
    lo: f32,
    band: f32,
}
impl Bp {
    pub fn new(hz: f32, q: f32) -> Bp {
        let mut b = Bp { f: 0.0, q: 1.0 / q, lo: 0.0, band: 0.0 };
        b.tune(hz);
        b
    }
    pub fn tune(&mut self, hz: f32) {
        self.f = 2.0 * (std::f32::consts::PI * hz.min(RATE / 6.0) / RATE).sin();
    }
    pub fn run(&mut self, x: f32) -> f32 {
        self.lo += self.f * self.band;
        let hi = x - self.lo - self.q * self.band;
        self.band += self.f * hi;
        self.band
    }
}

/// seconds to samples
pub fn secs(s: f32) -> usize {
    (s * RATE) as usize
}

/// a tone: sine (plus `harm` of its octave and twelfth for a brighter sound
/// on a small speaker) gliding from f0 to f1 over its length, with a linear
/// attack and an exponential decay (time constant `decay` s)
pub struct Tone {
    t: usize,
    len: usize,
    delay: usize,
    ph: f32,
    f0: f32,
    f1: f32,
    amp: f32,
    attack: f32,
    decay: f32,
    harm: f32,
    sq: bool,
}
impl Tone {
    pub fn new(f: f32, amp: f32, decay: f32) -> Tone {
        Tone { t: 0, len: secs(decay * 6.0), delay: 0, ph: 0.0, f0: f, f1: f, amp, attack: 0.004, decay, harm: 0.0, sq: false }
    }
    pub fn glide(mut self, f1: f32) -> Tone {
        self.f1 = f1;
        self
    }
    pub fn attack(mut self, s: f32) -> Tone {
        self.attack = s;
        self
    }
    pub fn harm(mut self, h: f32) -> Tone {
        self.harm = h;
        self
    }
    /// a square wave (odd harmonics up to the 7th: the old game sound)
    pub fn square(mut self) -> Tone {
        self.sq = true;
        self
    }
    pub fn len(mut self, s: f32) -> Tone {
        self.len = secs(s);
        self
    }
    pub fn after(mut self, s: f32) -> Tone {
        self.delay = secs(s);
        self
    }
}
impl Voice for Tone {
    fn next(&mut self) -> Option<f32> {
        if self.delay > 0 {
            self.delay -= 1;
            return Some(0.0);
        }
        if self.t >= self.len {
            return None;
        }
        let s = self.t as f32 / RATE;
        let u = self.t as f32 / self.len as f32;
        let f = self.f0 * (self.f1 / self.f0).powf(u);
        self.ph = (self.ph + f / RATE).fract();
        self.t += 1;
        let env = (s / self.attack).min(1.0) * (-s / self.decay).exp() * (1.0 - u).min(20.0 * (1.0 - u)).min(1.0);
        let tau = std::f32::consts::TAU;
        let x = if self.sq {
            let p = tau * self.ph;
            p.sin() + (3.0 * p).sin() / 3.0 + (5.0 * p).sin() / 5.0 + (7.0 * p).sin() / 7.0
        } else {
            (tau * self.ph).sin() + self.harm * (0.5 * (2.0 * tau * self.ph).sin() + 0.25 * (3.0 * tau * self.ph).sin())
        };
        Some(self.amp * env * x)
    }
}

/// a bell: inharmonic partials, the high ones dying first
pub struct Bell {
    t: usize,
    len: usize,
    delay: usize,
    f: f32,
    amp: f32,
    decay: f32,
}
const BELL: [(f32, f32, f32); 5] = [(1.0, 1.0, 1.0), (2.0, 0.6, 0.6), (2.76, 0.45, 0.45), (5.4, 0.3, 0.25), (8.93, 0.2, 0.15)];
impl Bell {
    pub fn new(f: f32, amp: f32, decay: f32) -> Bell {
        Bell { t: 0, len: secs(decay * 5.0), delay: 0, f, amp, decay }
    }
    pub fn after(mut self, s: f32) -> Bell {
        self.delay = secs(s);
        self
    }
}
impl Voice for Bell {
    fn next(&mut self) -> Option<f32> {
        if self.delay > 0 {
            self.delay -= 1;
            return Some(0.0);
        }
        if self.t >= self.len {
            return None;
        }
        let s = self.t as f32 / RATE;
        self.t += 1;
        let tau = std::f32::consts::TAU;
        let mut x = 0.0;
        for (r, a, d) in BELL {
            let f = self.f * r;
            if f < RATE / 2.5 {
                x += a * (tau * f * s).sin() * (-s / (self.decay * d)).exp();
            }
        }
        Some(self.amp * x * (s / 0.002).min(1.0))
    }
}

/// a burst of noise through a band-pass, attack then exponential decay
/// (thumps, pops, splashes, clicks); amp 1 is about 0.5 rms at the peak
pub struct Burst {
    t: usize,
    len: usize,
    delay: usize,
    noise: Noise,
    bp: Bp,
    f0: f32,
    f1: f32,
    amp: f32,
    attack: f32,
    decay: f32,
}
impl Burst {
    pub fn new(seed: u32, hz: f32, q: f32, amp: f32, decay: f32) -> Burst {
        // the band-pass passes about 0.0048 sqrt(hz q) rms of this noise
        let amp = amp * 0.5 / (0.0048 * (hz * q).sqrt());
        Burst { t: 0, len: secs(decay * 6.0), delay: 0, noise: Noise(seed | 1), bp: Bp::new(hz, q), f0: hz, f1: hz, amp, attack: 0.001, decay }
    }
    /// the band moves from hz to f1 over the sound
    pub fn sweep(mut self, f1: f32) -> Burst {
        self.f1 = f1;
        self
    }
    pub fn attack(mut self, s: f32) -> Burst {
        self.attack = s;
        self.len += secs(s);
        self
    }
    pub fn after(mut self, s: f32) -> Burst {
        self.delay = secs(s);
        self
    }
}
impl Voice for Burst {
    fn next(&mut self) -> Option<f32> {
        if self.delay > 0 {
            self.delay -= 1;
            return Some(0.0);
        }
        if self.t >= self.len {
            return None;
        }
        let s = self.t as f32 / RATE;
        let u = self.t as f32 / self.len as f32;
        if self.f1 != self.f0 && self.t % 32 == 0 {
            self.bp.tune(self.f0 * (self.f1 / self.f0).powf(u));
        }
        self.t += 1;
        let env = if s < self.attack { s / self.attack } else { (-(s - self.attack) / self.decay).exp() };
        Some(self.amp * env * self.bp.run(self.noise.next()))
    }
}

/// crackling: random short clicks, `rate` a second, for `len` s fading out
/// (`len` 0: forever, for a fire)
pub struct Crackle {
    t: usize,
    len: usize,
    delay: usize,
    noise: Noise,
    hp: Hp,
    rate: f32,
    amp: f32,
    click: f32,
    fall: f32,
}
impl Crackle {
    pub fn new(seed: u32, rate: f32, amp: f32, len: f32) -> Crackle {
        Crackle { t: 0, len: secs(len), delay: 0, noise: Noise(seed | 1), hp: Hp::new(1500.0), rate, amp, click: 0.0, fall: 0.992 }
    }
    /// clicks of about `ms` (longer: duller pops)
    pub fn click_ms(mut self, ms: f32) -> Crackle {
        self.fall = (-1.0 / (ms * 0.001 * RATE)).exp();
        self
    }
    pub fn after(mut self, s: f32) -> Crackle {
        self.delay = secs(s);
        self
    }
}
impl Voice for Crackle {
    fn next(&mut self) -> Option<f32> {
        if self.delay > 0 {
            self.delay -= 1;
            return Some(0.0);
        }
        if self.len > 0 && self.t >= self.len {
            return None;
        }
        let env = if self.len > 0 { 1.0 - self.t as f32 / self.len as f32 } else { 1.0 };
        self.t += 1;
        if (self.noise.next() * 0.5 + 0.5) < self.rate / RATE {
            self.click = self.amp * env * (0.3 + 0.7 * self.noise.next().abs());
        }
        self.click *= self.fall;
        Some(self.hp.run(self.click * self.noise.next()))
    }
}

/// a value a demo sets every tick and its background sound follows
#[derive(Clone, Default)]
pub struct Param(std::sync::Arc<std::sync::atomic::AtomicU32>);
impl Param {
    pub fn set(&self, v: f32) {
        self.0.store(v.to_bits(), Ordering::Relaxed);
    }
    pub fn get(&self) -> f32 {
        f32::from_bits(self.0.load(Ordering::Relaxed))
    }
}

/// a Param smoothed for the samples (no zipper noise at the tick steps)
pub struct Smooth {
    p: Param,
    v: f32,
}
impl Smooth {
    pub fn new(p: &Param) -> Smooth {
        Smooth { p: p.clone(), v: p.get() }
    }
    /// call once a sample
    pub fn next(&mut self) -> f32 {
        self.v += (self.p.get() - self.v) * 0.0008;
        self.v
    }
}

/// running water: band-limited noise that surges slowly, with drops that
/// plip (short rising chirps) now and then; `level` scales it
pub struct Water {
    noise: Noise,
    lp: Lp,
    lp2: Lp,
    hp: Hp,
    amp: f32,
    level: Option<Smooth>,
    plip_rate: f32,
    plips: Vec<(usize, usize, f32, f32, f32, f32)>, // t, len, phase, f0, f1, amp
    t: u32,
    seed: u32,
}
impl Water {
    /// `bright`: the upper end of the band (Hz), `amp`: about the rms
    pub fn new(seed: u32, bright: f32, amp: f32, plip_rate: f32) -> Water {
        Water {
            noise: Noise(seed | 1),
            lp: Lp::new(bright),
            lp2: Lp::new(bright * 1.5),
            hp: Hp::new(250.0),
            // the filters keep about sqrt(hz) / 320 rms of this noise
            amp: amp * 320.0 / bright.sqrt(),
            level: None,
            plip_rate,
            plips: Vec::new(),
            t: 0,
            seed,
        }
    }
    pub fn level(mut self, p: &Param) -> Water {
        self.level = Some(Smooth::new(p));
        self
    }
}
impl Voice for Water {
    fn next(&mut self) -> Option<f32> {
        self.t = self.t.wrapping_add(1);
        let lvl = self.level.as_mut().map_or(1.0, |l| l.next());
        let w = self.noise.next();
        let s = self.t as f32 / RATE;
        let surge = 1.0 + 0.25 * crate::fx::noise(s * 0.7, self.seed) + 0.15 * crate::fx::noise(s * 3.0, self.seed + 1);
        let mut out = self.hp.run(self.lp2.run(self.lp.run(w))) * self.amp * surge;
        if (self.noise.next() * 0.5 + 0.5) < self.plip_rate * lvl / RATE {
            let f0 = 600.0 + 1400.0 * (self.noise.next() * 0.5 + 0.5);
            let len = secs(0.02 + 0.03 * self.noise.next().abs());
            let a = 0.03 + 0.05 * self.noise.next().abs();
            self.plips.push((0, len, 0.0, f0, f0 * 1.8, a));
        }
        for p in self.plips.iter_mut() {
            let u = p.0 as f32 / p.1 as f32;
            p.2 = (p.2 + p.3 * (p.4 / p.3).powf(u) / RATE).fract();
            out += p.5 * (std::f32::consts::TAU * p.2).sin() * (1.0 - u) * (u * 20.0).min(1.0);
            p.0 += 1;
        }
        self.plips.retain(|p| p.0 < p.1);
        Some(out * lvl)
    }
}

/// a soft pad: slightly detuned sines that move through `chords` (Hz),
/// `hold` s each, the notes fading in and out slowly; `shine` (a Param,
/// 0..1) adds the octave above for a brighter sound
pub struct Pad {
    notes: Vec<f32>,
    chords: Vec<Vec<usize>>,
    hold: usize,
    t: usize,
    ph: Vec<[f32; 3]>,
    gain: Vec<f32>,
    amp: f32,
    shine: Option<Smooth>,
}
impl Pad {
    pub fn new(chords: &[&[f32]], hold: f32, amp: f32) -> Pad {
        let mut notes: Vec<f32> = Vec::new();
        for c in chords {
            for &f in c.iter() {
                if !notes.iter().any(|&n| (n - f).abs() < 0.01) {
                    notes.push(f);
                }
            }
        }
        let chords = chords.iter().map(|c| c.iter().map(|&f| notes.iter().position(|&n| (n - f).abs() < 0.01).unwrap()).collect()).collect();
        let n = notes.len();
        Pad { notes, chords, hold: secs(hold), t: 0, ph: vec![[0.0; 3]; n], gain: vec![0.0; n], amp, shine: None }
    }
    pub fn shine(mut self, p: &Param) -> Pad {
        self.shine = Some(Smooth::new(p));
        self
    }
}
impl Voice for Pad {
    fn next(&mut self) -> Option<f32> {
        let chord = &self.chords[(self.t / self.hold) % self.chords.len()];
        self.t += 1;
        let shine = self.shine.as_mut().map_or(0.0, |s| s.next());
        let tau = std::f32::consts::TAU;
        let mut out = 0.0;
        let k = chord.len() as f32;
        for (i, &f) in self.notes.iter().enumerate() {
            let target = if chord.contains(&i) { 1.0 / k.sqrt() } else { 0.0 };
            self.gain[i] += (target - self.gain[i]) * (1.0 / (1.5 * RATE));
            if self.gain[i] < 1e-4 {
                continue;
            }
            let p = &mut self.ph[i];
            for (j, d) in [0.998f32, 1.002, 2.0].iter().enumerate() {
                p[j] = (p[j] + f * d / RATE).fract();
            }
            out += self.gain[i] * (0.5 * (tau * p[0]).sin() + 0.5 * (tau * p[1]).sin() + 0.35 * shine * (tau * p[2]).sin());
        }
        Some(self.amp * out)
    }
}

/// wind: noise through a resonant band-pass whose pitch (Hz) and level
/// follow two Params
pub struct Wind {
    noise: Noise,
    bp: Bp,
    q: f32,
    hz: Smooth,
    level: Smooth,
    amp: f32,
    t: u32,
}
impl Wind {
    pub fn new(seed: u32, hz: &Param, level: &Param, q: f32, amp: f32) -> Wind {
        let hz = Smooth::new(hz);
        let f = hz.v.max(50.0);
        Wind { noise: Noise(seed | 1), bp: Bp::new(f, q), q, hz, level: Smooth::new(level), amp, t: 0 }
    }
}
impl Voice for Wind {
    fn next(&mut self) -> Option<f32> {
        let f = self.hz.next().max(50.0);
        if self.t % 32 == 0 {
            self.bp.tune(f);
        }
        self.t = self.t.wrapping_add(1);
        let norm = 0.5 / (0.0048 * (f * self.q).sqrt());
        Some(self.amp * norm * self.level.next() * self.bp.run(self.noise.next()))
    }
}

/// sound effects for the games (short, in the style of old game machines)
pub mod sfx {
    use super::{play, Burst, Crackle, Tone};

    fn seed() -> u32 {
        static S: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(12345);
        S.fetch_add(0x9e37_79b9, std::sync::atomic::Ordering::Relaxed)
    }

    /// notes one after another, `step` s apart: (Hz, amp)
    pub fn notes(list: &[(f32, f32)], step: f32, len: f32) {
        for (i, &(f, a)) in list.iter().enumerate() {
            if f > 0.0 {
                play(Tone::new(f, a, 10.0).square().len(len).after(i as f32 * step));
            }
        }
    }
    /// the player's shot (often: soft)
    pub fn shot() {
        play(Tone::new(1400.0, 0.025, 10.0).glide(700.0).square().len(0.04));
    }
    /// something takes a hit but survives
    pub fn hit() {
        play(Burst::new(seed(), 2200.0, 3.0, 0.08, 0.004));
    }
    /// an explosion, size 0 (small) .. 1 (big)
    pub fn explode(size: f32) {
        let s = seed();
        play(Burst::new(s, 900.0, 0.7, 0.2 + 0.3 * size, 0.06 + 0.25 * size).sweep(150.0));
        if size > 0.5 {
            play(Crackle::new(s ^ 5, 60.0, 0.4 * size, 0.4 + 0.6 * size).click_ms(3.0));
        }
    }
    /// a bomb going off
    pub fn bomb() {
        play(Burst::new(seed(), 300.0, 0.7, 0.35, 0.25).sweep(2500.0).attack(0.15));
        explode(1.0);
    }
    /// an item picked up
    pub fn pickup() {
        notes(&[(1046.5, 0.05), (1318.5, 0.05), (1568.0, 0.05), (2093.0, 0.05)], 0.05, 0.05);
    }
    /// an extra life
    pub fn extend() {
        notes(&[(1174.7, 0.05), (1568.0, 0.05), (1396.9, 0.05), (1975.5, 0.05), (2349.3, 0.06)], 0.07, 0.09);
    }
    /// the player is lost
    pub fn die() {
        play(Tone::new(900.0, 0.07, 10.0).glide(90.0).square().len(0.7));
        explode(0.8);
    }
    /// a boss is coming
    pub fn warning() {
        for k in 0..4 {
            play(Tone::new(660.0, 0.06, 10.0).glide(990.0).square().len(0.25).after(k as f32 * 0.6));
            play(Tone::new(990.0, 0.06, 10.0).glide(660.0).square().len(0.25).after(k as f32 * 0.6 + 0.3));
        }
    }
    /// a game starts
    pub fn start() {
        notes(&[(523.3, 0.06), (659.3, 0.06), (784.0, 0.06), (1046.5, 0.07)], 0.07, 0.1);
    }
    /// a stage cleared
    pub fn clear() {
        notes(&[(659.3, 0.06), (784.0, 0.06), (880.0, 0.06), (784.0, 0.06), (1046.5, 0.06), (1318.5, 0.07)], 0.1, 0.12);
    }
    /// the game is over
    pub fn game_over() {
        notes(&[(784.0, 0.06), (659.3, 0.06), (523.3, 0.06), (392.0, 0.07)], 0.25, 0.3);
    }
    /// all cleared: a longer fanfare
    pub fn fanfare() {
        notes(
            &[(523.3, 0.06), (392.0, 0.06), (523.3, 0.06), (659.3, 0.06), (587.3, 0.06), (698.5, 0.06), (659.3, 0.06), (784.0, 0.06), (0.0, 0.0), (1046.5, 0.08)],
            0.13,
            0.15,
        );
    }
    /// a bounce or a blip at f Hz
    pub fn blip(f: f32, amp: f32) {
        play(Tone::new(f, amp, 10.0).square().len(0.035));
    }
}
