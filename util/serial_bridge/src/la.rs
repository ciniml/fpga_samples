//! SLogic16U3 logic analyzer (eda/slogic16u3_la) capture server.
//!
//! The capture runs on a thread of its own: USB 3.0 bulk IN through nusb
//! (8 transfers of 1 MiB in flight), the stream of rtl/la/la_pkg.veryl parsed
//! in place into a ring of 64-bit words per group, a software trigger on one
//! group, and the stop once every group has its samples. The capture is then
//! kept in memory with min/max (OR/AND) summaries per 256 samples and their
//! pyramid, so that the browser asks only for what one screen shows:
//!
//!   GET  /api/la/device          {ok, id, status} or {error}
//!   POST /api/la/capture         CaptureReq (JSON) -> starts
//!   POST /api/la/stop            ends a capture (a waiting trigger: keeps what is there)
//!   GET  /api/la/status          state, bytes, MB/s, samples per group, trigger
//!   GET  /api/la/meta            the capture: per group W, sample count, x = s * scale - offset
//!   GET  /api/la/view?g&x0&x1&n  binary: per pixel (OR, AND) of the group's channels, or the
//!                                samples themselves when a pixel holds fewer than 2
//!   GET  /api/la/find?g&from&dir&cond   next / previous sample matching cond
//!   GET  /api/la/vcd?x0&x1       VCD of a range (both groups)
//!
//! Positions: sample s of a group (0 = its first sample of the capture) is at
//! x = s * scale - offset; scale = the sample period in ns for the internal
//! clock (both groups start on the same 1.25 ns sample, so their x agree), 1
//! (unit: samples) for an external clock. offset puts x = 0 at the trigger.
//!
//! A trigger condition is one character per channel, CH0 first: X (any),
//! 0, 1, R (rising), F (falling), E (changes). All the non-X channels must
//! hold at the same sample; they must be in one group (a software trigger
//! looks at one group's samples).

use nusb::{
    transfer::{Bulk, ControlIn, ControlOut, ControlType, In, Recipient},
    MaybeFuture,
};
use serde::{Deserialize, Serialize};
use std::{
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, RwLock,
    },
    time::{Duration, Instant},
};

const VID: u16 = 0x1209;
const PID: u16 = 0x0001;
const LA_ID: u32 = 0x0100_4C41;
const XFER: usize = 1 << 20;
const QUEUE: usize = 8; // (usbfs allows 16 MiB per process by default)
const T_NS: f64 = 1.25; // one 800 MS/s sample
const B0: u64 = 256; // samples per level-0 summary
/// ring words beyond the capture: the groups' data arrive a little apart
const MARGIN: u64 = 1 << 16;

// ---------------------------------------------------------------- device

pub struct Dev {
    iface: nusb::Interface,
    _dev: nusb::Device,
}

impl Dev {
    fn open() -> Result<Dev, String> {
        let list = nusb::list_devices().wait().map_err(|e| e.to_string())?;
        let mut last = format!("no {VID:04x}:{PID:04x} device");
        for di in list.filter(|d| d.vendor_id() == VID && d.product_id() == PID) {
            let r = (|| {
                let dev = di.open().wait().map_err(|e| format!("open: {e}"))?;
                let iface = dev
                    .claim_interface(0)
                    .wait()
                    .map_err(|e| format!("claim: {e}"))?;
                let d = Dev { iface, _dev: dev };
                let id = d.reg_rd(0)?;
                if id != LA_ID {
                    return Err(format!("not the LA design (reg 0 = {id:08x})"));
                }
                Ok(d)
            })();
            match r {
                Ok(d) => return Ok(d),
                Err(e) => last = e,
            }
        }
        Err(last)
    }
    fn reg_wr(&self, a: u16, v: u16) -> Result<(), String> {
        self.iface
            .control_out(
                ControlOut {
                    control_type: ControlType::Vendor,
                    recipient: Recipient::Device,
                    request: 0x03,
                    value: v,
                    index: a,
                    data: &[],
                },
                Duration::from_millis(1000),
            )
            .wait()
            .map_err(|e| format!("reg write {a:02x}: {e}"))
    }
    fn reg_rd(&self, a: u16) -> Result<u32, String> {
        let b = self
            .iface
            .control_in(
                ControlIn {
                    control_type: ControlType::Vendor,
                    recipient: Recipient::Device,
                    request: 0x04,
                    value: 0,
                    index: a,
                    length: 4,
                },
                Duration::from_millis(1000),
            )
            .wait()
            .map_err(|e| format!("reg read {a:02x}: {e}"))?;
        if b.len() != 4 {
            return Err(format!("reg read {a:02x}: {} bytes", b.len()));
        }
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
}

// ---------------------------------------------------------------- configuration

#[derive(Deserialize, Serialize, Clone, Default, Debug)]
#[serde(default)]
pub struct GroupReq {
    /// channels 1 / 2 / 4 / 8 (the group's lowest), 0 = off
    pub ch: u32,
    /// "int" (or empty) / "rise" / "fall" / "both"
    pub clk: String,
    /// internal clock: samples per second (800 MHz / div, div 1, 2, 4 or >= 8)
    pub rate: f64,
    pub skew: u32,
    /// use the other group's clock input
    pub other_clk: bool,
    pub test: bool,
    pub thalf: u32,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct CaptureReq {
    #[serde(default)]
    pub a: GroupReq,
    #[serde(default)]
    pub b: GroupReq,
    /// the capture's length (internal clocks), seconds
    #[serde(default = "d_len")]
    pub length_s: f64,
    /// samples to keep of an external-clock group (0: its share of mem_mb)
    #[serde(default)]
    pub ext_samples: u64,
    #[serde(default)]
    pub threshold_v: Option<f64>,
    /// 16 characters X 0 1 R F E, CH0 first (empty / all X: no trigger)
    #[serde(default)]
    pub trigger: String,
    /// with a trigger: the part of the length before it (0..1)
    #[serde(default = "d_pre")]
    pub pre: f64,
    #[serde(default = "d_mem")]
    pub mem_mb: u64,
}
fn d_len() -> f64 {
    0.01
}
fn d_pre() -> f64 {
    0.1
}
fn d_mem() -> u64 {
    8192
}

#[derive(Clone, Copy, Default, Debug, Serialize)]
struct GCfg {
    en: bool,
    wlog: u32,
    cmode: u32,
    test: bool,
    skew: u32,
    cksel: bool,
    div: u32,
    thalf: u32,
}

fn gcfg(r: &GroupReq) -> Result<GCfg, String> {
    if r.ch == 0 {
        return Ok(GCfg::default());
    }
    let wlog = match r.ch {
        1 => 0,
        2 => 1,
        4 => 2,
        8 => 3,
        n => return Err(format!("channels {n}: 1, 2, 4 or 8")),
    };
    let cmode = match r.clk.as_str() {
        "" | "int" => 0,
        "rise" => 1,
        "fall" => 2,
        "both" => 3,
        c => return Err(format!("clock {c}: int, rise, fall or both")),
    };
    let mut div = 1;
    if cmode == 0 {
        if !(r.rate > 0.0) {
            return Err("rate missing".into());
        }
        div = (800e6 / r.rate).round().max(1.0) as u64;
        if !(div == 1 || div == 2 || div == 4 || (8..1 << 24).contains(&div)) {
            return Err(format!(
                "rate {} S/s: 800 MHz / div with div 1, 2, 4 or 8..2^24 (not {div})",
                r.rate
            ));
        }
    }
    let thalf = if r.thalf == 0 { 4 } else { r.thalf };
    if !thalf.is_power_of_two() {
        return Err("thalf: a power of two".into());
    }
    if r.skew > 7 {
        return Err("skew 0..7".into());
    }
    Ok(GCfg {
        en: true,
        wlog,
        cmode,
        test: r.test,
        skew: r.skew,
        cksel: r.other_clk,
        div: div as u32,
        thalf,
    })
}

fn group_regs(d: &Dev, g: usize, c: &GCfg) -> Result<(), String> {
    let b = if g == 1 { 0x0A } else { 0x02 };
    d.reg_wr(
        b,
        (c.cksel as u16) << 8
            | (c.skew as u16 & 7) << 5
            | (c.test as u16) << 4
            | (c.cmode as u16 & 3) << 2
            | (c.wlog as u16 & 3),
    )?;
    d.reg_wr(b + 1, (c.div & 0xFFFF) as u16)?;
    d.reg_wr(b + 2, ((c.div >> 16) & 0xFF) as u16)?;
    d.reg_wr(b + 3, c.thalf as u16)
}

// ---------------------------------------------------------------- trigger / search conditions

/// A condition on one group, replicated into every W-bit lane of a word.
#[derive(Clone, Copy, Default, Debug)]
pub struct Cond {
    mc: u64, // current sample: bits that must equal vc
    vc: u64,
    mp: u64, // previous sample: bits that must equal vp
    vp: u64,
    e: u64, // bits that must change
    edge: bool,
}

fn lane_lsb(w: u32) -> u64 {
    let mut m = 0u64;
    let mut i = 0;
    while i < 64 {
        m |= 1 << i;
        i += w;
    }
    m
}

/// codes: one per channel of the group (X 0 1 R F E)
fn make_cond(codes: &[u8], w: u32) -> Result<Cond, String> {
    let (mut mc, mut vc, mut mp, mut vp, mut e) = (0u64, 0u64, 0u64, 0u64, 0u64);
    for (i, &c) in codes.iter().enumerate() {
        let b = 1u64 << i;
        let c = c.to_ascii_uppercase();
        if c != b'X' && i as u32 >= w {
            return Err(format!("channel {i} of the group is not captured"));
        }
        match c {
            b'X' => {}
            b'0' => mc |= b,
            b'1' => {
                mc |= b;
                vc |= b
            }
            b'R' => {
                mc |= b;
                vc |= b;
                mp |= b
            }
            b'F' => {
                mc |= b;
                mp |= b;
                vp |= b
            }
            b'E' => e |= b,
            _ => return Err(format!("condition character {}", c as char)),
        }
    }
    let rep = |v: u64| {
        let mut r = 0u64;
        let mut i = 0;
        while i < 64 {
            r |= v << i;
            i += w;
        }
        r
    };
    Ok(Cond {
        mc: rep(mc),
        vc: rep(vc),
        mp: rep(mp),
        vp: rep(vp),
        e: rep(e),
        edge: (mp | e) != 0,
    })
}

/// lane LSBs of the samples of `cur` that match (prev_word: the word before)
#[inline]
fn hits(cur: u64, prev_word: u64, w: u32, c: &Cond, lsb: u64) -> u64 {
    let prev = if w == 64 { prev_word } else { (cur << w) | (prev_word >> (64 - w)) };
    let z = ((cur ^ c.vc) & c.mc) | ((prev ^ c.vp) & c.mp) | (!(cur ^ prev) & c.e);
    let mut t = z;
    let mut s = 1;
    while s < w {
        t |= t >> s;
        s <<= 1;
    }
    !t & lsb
}

/// the trigger string -> (group, condition) or None
fn parse_trigger(t: &str, cfg: &[GCfg; 2]) -> Result<Option<(usize, Cond)>, String> {
    let t = t.trim().as_bytes();
    if t.is_empty() || t.iter().all(|&c| c == b'X' || c == b'x') {
        return Ok(None);
    }
    if t.len() != 16 {
        return Err("trigger: 16 characters (CH0 first)".into());
    }
    let used = |g: usize| t[g * 8..g * 8 + 8].iter().any(|&c| c != b'X' && c != b'x');
    if used(0) && used(1) {
        return Err("trigger: the channels of one group only (CH0..7 or CH8..15)".into());
    }
    let g = if used(0) { 0 } else { 1 };
    if !cfg[g].en {
        return Err(format!("trigger: group {} is off", if g == 0 { 'A' } else { 'B' }));
    }
    Ok(Some((g, make_cond(&t[g * 8..g * 8 + 8], 1 << cfg[g].wlog)?)))
}

// ---------------------------------------------------------------- captured data

pub struct GroupData {
    cfg: GCfg,
    w: u32,
    spw: u64,
    words: Vec<u64>,
    /// sample index (since the start) of words[0] lane 0
    first: u64,
    /// valid samples from `first`
    n: u64,
    levels: Vec<Vec<u16>>, // (OR << 8 | AND) per B0 << level samples
    flags: u32,
    scale: f64,
    offset: f64,
    total: u64,
}

impl GroupData {
    #[inline]
    fn sample(&self, rel: u64) -> u8 {
        let wi = (rel / self.spw) as usize;
        let lane = rel % self.spw;
        ((self.words[wi] >> (self.w as u64 * lane)) & ((1u64 << self.w) - 1)) as u8
    }
    fn build_levels(&mut self) {
        let wpb = (B0 / self.spw) as usize; // words per level-0 entry
        let nb = ((self.n + B0 - 1) / B0) as usize;
        let mut l0 = Vec::with_capacity(nb);
        let w = self.w;
        let mask = ((1u32 << w) - 1) as u64;
        for b in 0..nb {
            let lo = b * wpb;
            let hi = ((b + 1) * wpb).min(self.words.len());
            let (mut o, mut a) = (0u64, !0u64);
            for wi in lo..hi {
                let mut x = self.words[wi];
                // pad lanes past the end: neutral for AND
                let first_s = wi as u64 * self.spw;
                if first_s + self.spw > self.n {
                    let valid = self.n.saturating_sub(first_s);
                    let vm = if valid * w as u64 >= 64 { !0 } else { (1u64 << (valid * w as u64)) - 1 };
                    o |= x & vm;
                    x |= !vm;
                    a &= x;
                    continue;
                }
                o |= x;
                a &= x;
            }
            let mut s = 32;
            while s >= w {
                o |= o >> s;
                a &= a >> s;
                s /= 2;
            }
            l0.push((((o & mask) as u16) << 8) | (a & mask) as u16);
        }
        let mut levels = vec![l0];
        while levels.last().unwrap().len() > 1 {
            let p = levels.last().unwrap();
            let q: Vec<u16> = p
                .chunks(2)
                .map(|c| if c.len() == 2 { comb(c[0], c[1]) } else { c[0] })
                .collect();
            levels.push(q);
        }
        self.levels = levels;
    }
    /// (OR, AND) of samples [a, b) (relative, a < b <= n)
    fn summary(&self, a: u64, b: u64) -> u16 {
        let mut acc = 0x00FFu16; // OR 0, AND all ones
        let scan = |acc: &mut u16, x: u64, y: u64| {
            for s in x..y {
                let v = self.sample(s) as u16;
                *acc = comb(*acc, (v << 8) | v);
            }
        };
        if b - a <= 2 * B0 {
            scan(&mut acc, a, b);
            return acc;
        }
        let ia = (a + B0 - 1) / B0;
        let ib = b / B0;
        scan(&mut acc, a, ia * B0);
        scan(&mut acc, ib * B0, b);
        let (mut i, mut j, mut l) = (ia as usize, ib as usize, 0usize);
        while i < j {
            let lv = &self.levels[l];
            if i & 1 == 1 {
                acc = comb(acc, lv[i]);
                i += 1;
            }
            if j & 1 == 1 {
                j -= 1;
                acc = comb(acc, lv[j]);
            }
            i >>= 1;
            j >>= 1;
            l += 1;
        }
        acc
    }
    /// the first (dir > 0: after `from`) or last (dir < 0: before `from`) matching sample, relative
    fn find(&self, from: i64, dir: i32, c: &Cond) -> Option<u64> {
        let lsb = lane_lsb(self.w);
        let nw = self.words.len() as i64;
        let check = |wi: i64| -> u64 {
            let prev = if wi > 0 { self.words[wi as usize - 1] } else { 0 };
            let mut h = hits(self.words[wi as usize], prev, self.w, c, lsb);
            if wi == 0 && c.edge {
                h &= !1; // (no sample before the first)
            }
            let first_s = wi as u64 * self.spw;
            if first_s + self.spw > self.n {
                let valid = self.n.saturating_sub(first_s);
                if valid * (self.w as u64) < 64 {
                    h &= (1u64 << (valid * self.w as u64)) - 1;
                }
            }
            h
        };
        let lane_of = |bit: u32| (bit / self.w) as u64;
        if dir >= 0 {
            let s0 = (from + 1).max(0) as u64;
            if s0 >= self.n {
                return None;
            }
            let mut wi = (s0 / self.spw) as i64;
            let mut h = check(wi) & !((1u64 << (self.w as u64 * (s0 % self.spw))) - 1);
            loop {
                if h != 0 {
                    return Some(wi as u64 * self.spw + lane_of(h.trailing_zeros()));
                }
                wi += 1;
                if wi >= nw {
                    return None;
                }
                h = check(wi);
            }
        } else {
            if from <= 0 {
                return None;
            }
            let s0 = (from as u64 - 1).min(self.n - 1);
            let mut wi = (s0 / self.spw) as i64;
            let keep = self.w as u64 * (s0 % self.spw + 1);
            let mut h = check(wi) & if keep >= 64 { !0 } else { (1u64 << keep) - 1 };
            loop {
                if h != 0 {
                    return Some(wi as u64 * self.spw + lane_of(63 - h.leading_zeros()));
                }
                wi -= 1;
                if wi < 0 {
                    return None;
                }
                h = check(wi);
            }
        }
    }
}

#[inline]
fn comb(x: u16, y: u16) -> u16 {
    ((x | y) & 0xFF00) | (x & y & 0x00FF)
}

pub struct Capture {
    pub id: u64,
    groups: [Option<GroupData>; 2],
    trig: Option<(usize, u64)>, // group, sample (since the start)
    unit: &'static str,
    note: String,
}

// ---------------------------------------------------------------- capture thread

struct GRun {
    cfg: GCfg,
    w: u32,
    spw: u64,
    ring: Vec<u64>,
    cap: u64,
    words: u64,  // data words received
    stored: u64, // data words stored (frozen: no more)
    frozen: bool,
    freeze_at: u64, // samples (u64::MAX: not yet known)
    started: u32,
    ended: u32,
    nseq: u32,
    seqerr: u32,
    end_count: u64,
    flags: u32,
    pre: u64,
    post: u64,
    prev: u64,
}

#[derive(Default, Clone, Serialize)]
pub struct Status {
    pub state: String, // idle / waiting (trigger) / capturing / stopping / processing / done / error
    pub msg: String,
    pub bytes: u64,
    pub mbps: f64,
    pub elapsed: f64,
    pub samples: [u64; 2],
    pub trig: Option<(usize, u64)>,
    pub id: u64,
}

pub struct La {
    dev: Mutex<Option<Dev>>,
    status: Mutex<Status>,
    stop: AtomicBool,
    bytes: AtomicU64,
    busy: AtomicBool,
    next_id: AtomicU64,
    pub cap: RwLock<Option<Arc<Capture>>>,
}

pub type LaShared = Arc<La>;

pub fn new() -> LaShared {
    Arc::new(La {
        dev: Mutex::new(None),
        status: Mutex::new(Status { state: "idle".into(), ..Default::default() }),
        stop: AtomicBool::new(false),
        bytes: AtomicU64::new(0),
        busy: AtomicBool::new(false),
        next_id: AtomicU64::new(1),
        cap: RwLock::new(None),
    })
}

impl La {
    fn set(&self, f: impl FnOnce(&mut Status)) {
        f(&mut self.status.lock().unwrap());
    }
    pub fn status(&self) -> Status {
        self.status.lock().unwrap().clone()
    }
    /// device presence: opens it when needed (not while a capture runs)
    pub fn device(&self) -> serde_json::Value {
        if self.busy.load(Ordering::SeqCst) {
            return serde_json::json!({"ok": true, "busy": true});
        }
        let mut g = self.dev.lock().unwrap();
        let mut r = Err(String::new());
        for _ in 0..2 {
            if g.is_none() {
                match Dev::open() {
                    Ok(d) => *g = Some(d),
                    Err(e) => return serde_json::json!({"ok": false, "error": e}),
                }
            }
            let d = g.as_ref().unwrap();
            r = d.reg_rd(0).and_then(|id| Ok((id, d.reg_rd(1)?)));
            if r.is_ok() {
                break;
            }
            *g = None; // (unplugged / reloaded: open again)
        }
        match r {
            Ok((id, st)) => serde_json::json!({"ok": true, "id": format!("{id:08x}"), "status": st}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        }
    }
    pub fn request_stop(&self) {
        self.stop.store(true, Ordering::SeqCst);
    }
    pub fn start(self: &Arc<Self>, req: CaptureReq) -> Result<u64, String> {
        let cfg = [gcfg(&req.a)?, gcfg(&req.b)?];
        if !cfg[0].en && !cfg[1].en {
            return Err("no group enabled".into());
        }
        let trig = parse_trigger(&req.trigger, &cfg)?;
        if !(req.length_s > 0.0) {
            return Err("length_s".into());
        }
        if self.busy.swap(true, Ordering::SeqCst) {
            return Err("a capture is running".into());
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        self.stop.store(false, Ordering::SeqCst);
        self.bytes.store(0, Ordering::SeqCst);
        self.set(|s| *s = Status { state: "starting".into(), id, ..Default::default() });
        let me = self.clone();
        std::thread::spawn(move || {
            let r = me.run(id, &req, cfg, trig);
            match r {
                Ok(c) => {
                    let msg = c.note.clone();
                    *me.cap.write().unwrap() = Some(Arc::new(c));
                    me.set(|s| {
                        s.state = "done".into();
                        s.msg = msg;
                    });
                }
                Err(e) => me.set(|s| {
                    s.state = "error".into();
                    s.msg = e;
                }),
            }
            me.busy.store(false, Ordering::SeqCst);
        });
        Ok(id)
    }

    fn run(&self, id: u64, req: &CaptureReq, cfg: [GCfg; 2], trig: Option<(usize, Cond)>) -> Result<Capture, String> {
        let mut dg = self.dev.lock().unwrap();
        if dg.is_none() {
            *dg = Some(Dev::open()?);
        }
        let d = dg.as_ref().unwrap();
        if d.reg_rd(0).is_err() {
            *dg = Some(Dev::open()?);
        }
        let d = dg.as_ref().unwrap();
        let r = self.run_dev(d, id, req, cfg, trig);
        if r.is_err() {
            let _ = d.reg_wr(0, 0);
        }
        r
    }

    fn run_dev(&self, d: &Dev, id: u64, req: &CaptureReq, cfg: [GCfg; 2], trig: Option<(usize, Cond)>) -> Result<Capture, String> {
        // ---- sizes: samples per group and rings
        let mem_words = req.mem_mb * (1 << 20) / 8;
        let mut g: Vec<GRun> = Vec::new();
        let mut need = [0u64; 2];
        let n_ext = cfg.iter().filter(|c| c.en && c.cmode != 0).count() as u64;
        let n_int = cfg.iter().filter(|c| c.en && c.cmode == 0).count() as u64;
        let mut used = 0u64;
        for (k, c) in cfg.iter().enumerate() {
            let w = 1u32 << c.wlog;
            let spw = 64 / w as u64;
            if c.en && c.cmode == 0 {
                let rate = 800e6 / c.div as f64;
                need[k] = (req.length_s * rate).ceil() as u64;
                used += need[k] / spw + 2 + MARGIN;
            }
        }
        if used > mem_words {
            return Err(format!("{} MiB needed > mem_mb {}", used * 8 >> 20, req.mem_mb));
        }
        for (k, c) in cfg.iter().enumerate() {
            let w = 1u32 << c.wlog;
            let spw = 64 / w as u64;
            if c.en && c.cmode != 0 {
                need[k] = if req.ext_samples > 0 {
                    req.ext_samples
                } else {
                    ((mem_words - used) / n_ext).saturating_sub(2 + MARGIN) * spw
                };
            }
            let pre = if trig.is_some() { (need[k] as f64 * req.pre.clamp(0.0, 1.0)) as u64 } else { 0 };
            let cap = if c.en { need[k] / spw + 2 + MARGIN } else { 0 };
            if c.en && (cap == 0 || cap > mem_words) {
                return Err("capture too long for mem_mb".into());
            }
            g.push(GRun {
                cfg: *c,
                w,
                spw,
                ring: Vec::new(),
                cap,
                words: 0,
                stored: 0,
                frozen: !c.en,
                freeze_at: if trig.is_none() && c.en && (c.cmode == 0 || n_int == 0) {
                    need[k]
                } else {
                    u64::MAX
                },
                started: 0,
                ended: 0,
                nseq: 0,
                seqerr: 0,
                end_count: 0,
                flags: 0,
                pre,
                post: need[k] - pre,
                prev: 0,
            });
        }
        // rings, touched now (faulting them in during the capture stalls it)
        self.set(|s| s.msg = "allocating".into());
        for r in g.iter_mut() {
            if r.cfg.en {
                r.ring = vec![0u64; r.cap as usize];
                for i in (0..r.ring.len()).step_by(512) {
                    unsafe { std::ptr::write_volatile(&mut r.ring[i], 0) };
                }
            }
        }

        // ---- device: stop, drain, configure
        d.reg_wr(0, 0)?;
        if let Some(v) = req.threshold_v {
            d.reg_wr(0x10, ((v / 6.7 * 1024.0).round().clamp(0.0, 1023.0)) as u16)?;
        }
        let mut ep = d
            .iface
            .endpoint::<Bulk, In>(0x81)
            .map_err(|e| format!("endpoint: {e}"))?;
        for _ in 0..QUEUE {
            let b = ep.allocate(XFER);
            ep.submit(b);
        }
        loop {
            match ep.wait_next_complete(Duration::from_millis(100)) {
                Some(c) => {
                    let mut b = c.buffer;
                    b.clear();
                    ep.submit(b);
                }
                None => break,
            }
        }
        for (k, c) in cfg.iter().enumerate() {
            group_regs(d, k, c)?;
        }
        d.reg_wr(1, (cfg[0].en as u16) | (cfg[1].en as u16) << 1)?;
        let capid = (id & 0xFF) as u32;

        let mut p = Parser::default();
        let mut trig_pos: Option<u64> = None;
        let tg = trig.map(|t| t.0);
        let tc = trig.map(|t| t.1).unwrap_or_default();
        let lsb = trig.map(|t| lane_lsb(1 << cfg[t.0].wlog)).unwrap_or(0);

        d.reg_wr(0, (capid << 8 | 1) as u16)?;
        let t0 = Instant::now();
        self.set(|s| {
            s.state = if trig.is_some() { "waiting" } else { "capturing" }.into();
            s.msg.clear();
        });
        let mut stop_sent: Option<Instant> = None;
        let mut user_stop = false;
        let mut err: Option<String> = None;
        let mut last_status = Instant::now();
        loop {
            if let Some(c) = ep.wait_next_complete(Duration::from_millis(50)) {
                if let Err(e) = c.status {
                    err = Some(format!("transfer: {e}"));
                    break;
                }
                let buf = &c.buffer[..c.actual_len];
                self.bytes.fetch_add(buf.len() as u64, Ordering::Relaxed);
                p.parse(buf, &mut g, capid, |g, k, ws| {
                    store_block(g, k, ws, tg, &tc, lsb, &mut trig_pos, &cfg)
                });
                let mut b = c.buffer;
                b.clear();
                ep.submit(b);
            }
            if self.stop.load(Ordering::SeqCst) && !user_stop {
                user_stop = true;
                for r in g.iter_mut() {
                    r.frozen = true;
                }
            }
            // ext groups next to internal ones: frozen with the last internal one
            if g.iter().any(|r| r.cfg.en && r.cfg.cmode == 0)
                && g.iter().filter(|r| r.cfg.en && r.cfg.cmode == 0).all(|r| r.frozen)
            {
                for r in g.iter_mut() {
                    r.frozen = true;
                }
            }
            let all_frozen = g.iter().all(|r| r.frozen || r.ended > 0);
            if all_frozen && stop_sent.is_none() {
                d.reg_wr(0, (capid << 8) as u16)?;
                stop_sent = Some(Instant::now());
                self.set(|s| s.state = "stopping".into());
            }
            let all_ended = g.iter().all(|r| !r.cfg.en || r.ended > 0);
            if all_ended && stop_sent.is_none() {
                // (the device ended on its own: an overflow or an unsupported clock)
                stop_sent = Some(Instant::now());
            }
            if all_ended {
                break;
            }
            if let Some(t) = stop_sent {
                if t.elapsed() > Duration::from_secs(3) {
                    err = Some("no END from the device".into());
                    break;
                }
            }
            if last_status.elapsed() > Duration::from_millis(100) {
                last_status = Instant::now();
                let el = t0.elapsed().as_secs_f64();
                let by = self.bytes.load(Ordering::Relaxed);
                let tp = trig_pos.map(|t| (tg.unwrap(), t));
                let sm = [g[0].words * g[0].spw, g[1].words * g[1].spw];
                self.set(|s| {
                    s.bytes = by;
                    s.elapsed = el;
                    s.mbps = by as f64 / el / 1e6;
                    s.samples = sm;
                    s.trig = tp;
                    if tp.is_some() && s.state == "waiting" {
                        s.state = "capturing".into();
                    }
                });
            }
        }
        ep.cancel_all();
        while ep.pending() > 0 {
            if ep.wait_next_complete(Duration::from_millis(500)).is_none() {
                break;
            }
        }
        let _ = d.reg_wr(0, (capid << 8) as u16);
        let el = t0.elapsed().as_secs_f64();
        let by = self.bytes.load(Ordering::Relaxed);
        self.set(|s| {
            s.state = "processing".into();
            s.bytes = by;
            s.elapsed = el;
            s.mbps = by as f64 / el / 1e6;
        });
        if let Some(e) = err {
            return Err(e);
        }
        if p.err > 0 {
            return Err(format!("{} stream format errors", p.err));
        }

        // ---- the kept range of each group
        let mut note = Vec::new();
        let tpos = trig_pos.map(|t| (tg.unwrap(), t));
        if tg.is_some() && tpos.is_none() {
            note.push("no trigger (stopped while waiting): the latest samples".to_string());
        }
        let period = |c: &GCfg| c.div as f64 * T_NS;
        let mut groups: [Option<GroupData>; 2] = [None, None];
        for (k, r) in g.iter_mut().enumerate() {
            if !r.cfg.en {
                continue;
            }
            if r.started != 1 || r.ended != 1 {
                return Err(format!("group {k}: START {} END {}", r.started, r.ended));
            }
            if r.seqerr > 0 {
                note.push(format!("{}: {} block sequence errors", gname(k), r.seqerr));
            }
            if r.flags & 1 != 0 {
                note.push(format!("{}: OVERFLOW (the data is complete up to it)", gname(k)));
            }
            if r.flags & 2 != 0 {
                note.push(format!("{}: clock too fast / unsupported timing", gname(k)));
            }
            let valid = r.end_count.min(r.stored * r.spw);
            let avail_lo = r.stored.saturating_sub(r.cap) * r.spw;
            let th = match tpos {
                Some((tgk, t)) if tgk == k => Some(t),
                Some((tgk, t)) if aligned(&cfg, tgk, k) => {
                    Some((t as f64 * cfg[tgk].div as f64 / r.cfg.div as f64) as u64)
                }
                _ => None,
            };
            let (lo, hi) = match th {
                Some(t) => (t.saturating_sub(r.pre).max(avail_lo), valid.min(r.freeze_at)),
                None => (avail_lo, valid.min(r.freeze_at)),
            };
            let hi = hi.max(lo);
            // ring -> words [lo / spw, ceil(hi / spw)) in order
            let mut ring = std::mem::take(&mut r.ring);
            let cap = r.cap as usize;
            let s0 = r.stored.saturating_sub(r.cap); // first stored word still in the ring
            if r.stored > r.cap {
                ring.rotate_left((r.stored % r.cap) as usize);
            } else {
                ring.truncate(r.stored as usize);
            }
            debug_assert!(ring.len() <= cap);
            let wl = (lo / r.spw - s0) as usize;
            let wh = (((hi + r.spw - 1) / r.spw) - s0) as usize;
            ring.truncate(wh);
            ring.drain(..wl);
            ring.shrink_to_fit();
            let first = lo / r.spw * r.spw;
            let internal = r.cfg.cmode == 0;
            let mut gd = GroupData {
                cfg: r.cfg,
                w: r.w,
                spw: r.spw,
                words: ring,
                first,
                n: hi - first,
                levels: Vec::new(),
                flags: r.flags,
                scale: if internal { period(&r.cfg) } else { 1.0 },
                offset: 0.0,
                total: r.end_count,
            };
            // x = (first + s) * scale - origin: origin = the trigger (x = 0 there) on the trigger
            // group's scale (internal clocks share it; an external one only its own trigger)
            let origin = match tpos {
                Some((tgk, t)) if internal && cfg[tgk].cmode == 0 => t as f64 * period(&cfg[tgk]),
                Some((tgk, t)) if aligned(&cfg, tgk, k) => t as f64,
                _ => 0.0,
            };
            gd.offset = origin - first as f64 * gd.scale;
            gd.build_levels();
            groups[k] = Some(gd);
        }
        let unit = if groups.iter().flatten().all(|g| g.cfg.cmode == 0) { "ns" } else { "sample" };
        if cfg[0].en && cfg[1].en && !aligned(&cfg, 0, 1) {
            note.push("the groups run on different clocks: their x are not comparable".into());
        }
        Ok(Capture { id, groups, trig: tpos, unit, note: note.join("; ") })
    }
}

/// the sample indices of groups a and b match (div ratio aside): both on the internal clock, or both
/// on the same edges of the same clock input
fn aligned(cfg: &[GCfg; 2], a: usize, b: usize) -> bool {
    let (x, y) = (&cfg[a], &cfg[b]);
    (x.cmode == 0 && y.cmode == 0) || (x.cmode != 0 && x.cmode == y.cmode && (a ^ x.cksel as usize) == (b ^ y.cksel as usize))
}

fn gname(k: usize) -> &'static str {
    if k == 0 {
        "A"
    } else {
        "B"
    }
}

/// a data word of group k
#[inline]
fn store(
    g: &mut [GRun],
    k: usize,
    w: u64,
    tg: Option<usize>,
    tc: &Cond,
    lsb: u64,
    trig_pos: &mut Option<u64>,
    cfg: &[GCfg; 2],
) {
    let r = &mut g[k];
    let wi = r.words;
    r.words += 1;
    let prev = r.prev;
    r.prev = w;
    if !r.frozen {
        let i = (wi % r.cap) as usize;
        r.ring[i] = w;
        r.stored = r.words;
    }
    if tg == Some(k) && trig_pos.is_none() && !r.frozen {
        // armed once the pre-trigger samples are there
        let base = wi * r.spw;
        let mut h = if base + r.spw <= r.pre { 0 } else { hits(w, prev, r.w, tc, lsb) };
        if r.pre > base {
            h &= !0u64 << (r.w as u64 * (r.pre - base));
        }
        if wi == 0 && tc.edge {
            h &= !1;
        }
        if h != 0 {
            let t = wi * r.spw + (h.trailing_zeros() / r.w) as u64;
            *trig_pos = Some(t);
            for (j, q) in g.iter_mut().enumerate() {
                if !q.cfg.en {
                    continue;
                }
                if j == k {
                    q.freeze_at = t + q.post;
                } else if aligned(cfg, k, j) {
                    q.freeze_at = (t as f64 * cfg[k].div as f64 / q.cfg.div as f64) as u64 + q.post;
                }
            }
        }
    }
    let r = &mut g[k];
    if !r.frozen && r.freeze_at != u64::MAX && r.words * r.spw >= r.freeze_at {
        r.frozen = true;
    }
    // an ext-clock trigger group freezes the other groups with it
    if tg == Some(k) && g[k].frozen && trig_pos.is_some() {
        for q in g.iter_mut() {
            if q.freeze_at == u64::MAX {
                q.frozen = true;
            }
        }
    }
}

/// data words of group k: copied into the ring in runs (one word at a time
/// only while the trigger is looked for in this group)
fn store_block(
    g: &mut [GRun],
    k: usize,
    ws: &[u64],
    tg: Option<usize>,
    tc: &Cond,
    lsb: u64,
    trig_pos: &mut Option<u64>,
    cfg: &[GCfg; 2],
) {
    let mut i = 0;
    while i < ws.len() {
        if tg == Some(k) && trig_pos.is_none() && !g[k].frozen {
            store(g, k, ws[i], tg, tc, lsb, trig_pos, cfg);
            i += 1;
            continue;
        }
        let r = &mut g[k];
        let rest = &ws[i..];
        if r.frozen {
            r.words += rest.len() as u64;
            r.prev = *rest.last().unwrap();
            return;
        }
        let mut n = rest.len() as u64;
        if r.freeze_at != u64::MAX {
            let lim = ((r.freeze_at + r.spw - 1) / r.spw).saturating_sub(r.words);
            n = n.min(lim.max(1));
        }
        let mut done = 0u64;
        while done < n {
            let at = ((r.words + done) % r.cap) as usize;
            let m = (n - done).min(r.cap - at as u64) as usize;
            r.ring[at..at + m].copy_from_slice(&rest[done as usize..done as usize + m]);
            done += m as u64;
        }
        r.words += n;
        r.stored = r.words;
        r.prev = rest[n as usize - 1];
        if r.freeze_at != u64::MAX && r.words * r.spw >= r.freeze_at {
            r.frozen = true;
            if tg == Some(k) && trig_pos.is_some() {
                for q in g.iter_mut() {
                    if q.freeze_at == u64::MAX {
                        q.frozen = true;
                    }
                }
            }
        }
        i += n as usize;
    }
}

#[derive(Default)]
struct Parser {
    state: u8,
    hdr: u32,
    left: u32,
    have: u32,
    ev: [u32; 2],
    lo: u32,
    err: u64,
    scratch: Vec<u64>,
}

impl Parser {
    fn parse(&mut self, buf: &[u8], g: &mut [GRun], capid: u32, mut data: impl FnMut(&mut [GRun], usize, &[u64])) {
        let mut pos = 0;
        while pos + 4 <= buf.len() {
            // fast path: whole 64-bit words of a DATA payload
            if self.state == 1 && self.hdr >> 28 == 1 && self.have & 1 == 0 && self.left >= 2 && pos + 8 <= buf.len() {
                let m = ((self.left / 2) as usize).min((buf.len() - pos) / 8);
                let k = ((self.hdr >> 26) & 3) as usize;
                self.scratch.clear();
                self.scratch.extend(buf[pos..pos + 8 * m].chunks_exact(8).map(|c| u64::from_le_bytes(c.try_into().unwrap())));
                data(g, k, &self.scratch);
                pos += 8 * m;
                self.have += 2 * m as u32;
                self.left -= 2 * m as u32;
                if self.left == 0 {
                    self.state = 0;
                }
                continue;
            }
            let c = &buf[pos..pos + 4];
            pos += 4;
            let w = u32::from_le_bytes([c[0], c[1], c[2], c[3]]);
            if self.state == 0 {
                let ty = w >> 28;
                let k = ((w >> 26) & 3) as usize;
                if k > 1 || (w >> 24 & 3) != 0 || !(ty == 1 || ty == 4 || ty == 5) {
                    self.err += 1;
                    continue;
                }
                self.hdr = w;
                self.left = w & 0xFFFF;
                self.have = 0;
                if ty == 1 {
                    let r = &mut g[k];
                    if r.started == 0 || r.ended > 0 {
                        self.err += 1;
                    }
                    if (w >> 16) & 0xFF != r.nseq & 0xFF {
                        r.seqerr += 1;
                    }
                    r.nseq += 1;
                }
                if self.left > 0 {
                    self.state = 1;
                }
            } else {
                let ty = self.hdr >> 28;
                let k = ((self.hdr >> 26) & 3) as usize;
                if ty == 1 {
                    if self.have & 1 == 1 {
                        data(g, k, &[(w as u64) << 32 | self.lo as u64]);
                    } else {
                        self.lo = w;
                    }
                } else if self.have < 2 {
                    self.ev[self.have as usize] = w;
                }
                self.have += 1;
                self.left -= 1;
                if self.left == 0 {
                    self.state = 0;
                    if ty != 1 && (self.hdr >> 16) & 0xFF == capid {
                        let b = (self.ev[1] as u64) << 32 | self.ev[0] as u64;
                        let r = &mut g[k];
                        if ty == 4 {
                            r.started += 1;
                            r.nseq = 0;
                        } else {
                            r.ended += 1;
                            r.end_count = b & 0xFFFF_FFFF_FFFF;
                            r.flags = ((b >> 56) & 0xF) as u32;
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- queries

#[derive(Serialize)]
pub struct GroupMeta {
    ch: u32,
    clock: &'static str,
    rate: Option<f64>,
    scale: f64,
    offset: f64,
    first: u64,
    n: u64,
    total: u64,
    flags: u32,
    x_first: f64,
    x_last: f64,
}

impl Capture {
    pub fn meta(&self) -> serde_json::Value {
        let gm: Vec<Option<GroupMeta>> = self
            .groups
            .iter()
            .map(|g| {
                g.as_ref().map(|g| GroupMeta {
                    ch: g.w,
                    clock: ["int", "rise", "fall", "both"][g.cfg.cmode as usize],
                    rate: if g.cfg.cmode == 0 { Some(800e6 / g.cfg.div as f64) } else { None },
                    scale: g.scale,
                    offset: g.offset,
                    first: g.first,
                    n: g.n,
                    total: g.total,
                    flags: g.flags,
                    x_first: -g.offset,
                    x_last: g.n as f64 * g.scale - g.offset,
                })
            })
            .collect();
        serde_json::json!({
            "id": self.id, "unit": self.unit, "groups": gm, "note": self.note,
            "trigger": self.trig.map(|(g, s)| serde_json::json!({"group": g, "sample": s})),
        })
    }

    /// binary view of group g over x0..x1 on n pixels:
    ///   mode 0: [0u32][n u32][0 f64] then n x (OR u8, AND u8); AND & !OR != 0: no data
    ///   mode 1: [1u32][count u32][first sample (relative) f64] then count samples (u8)
    pub fn view(&self, k: usize, x0: f64, x1: f64, n: usize) -> Option<Vec<u8>> {
        let g = self.groups.get(k)?.as_ref()?;
        let n = n.clamp(1, 16384);
        let s0 = (x0 + g.offset) / g.scale;
        let s1 = (x1 + g.offset) / g.scale;
        let spp = (s1 - s0) / n as f64;
        let mut out = Vec::new();
        if spp < 2.0 {
            let a = s0.floor().max(0.0) as u64;
            let b = (s1.ceil() as i64 + 1).clamp(0, g.n as i64) as u64;
            let (a, b) = (a.min(b), b);
            out.extend_from_slice(&1u32.to_le_bytes());
            out.extend_from_slice(&((b - a) as u32).to_le_bytes());
            out.extend_from_slice(&(a as f64).to_le_bytes());
            for s in a..b {
                out.push(g.sample(s));
            }
        } else {
            out.extend_from_slice(&0u32.to_le_bytes());
            out.extend_from_slice(&(n as u32).to_le_bytes());
            out.extend_from_slice(&0f64.to_le_bytes());
            for i in 0..n {
                let a = (s0 + i as f64 * spp).floor().max(0.0) as u64;
                let b = ((s0 + (i + 1) as f64 * spp).floor().max(0.0) as u64).min(g.n);
                if a >= b {
                    out.extend_from_slice(&[0x00, 0xFF]);
                } else {
                    let v = g.summary(a, b);
                    out.extend_from_slice(&[(v >> 8) as u8, v as u8]);
                }
            }
        }
        Some(out)
    }

    /// next (dir > 0) / previous match of an 8-character condition after / before x
    pub fn find(&self, k: usize, x: f64, dir: i32, cond: &str) -> Result<Option<f64>, String> {
        let g = self.groups.get(k).and_then(|g| g.as_ref()).ok_or("group not captured")?;
        let c = make_cond(cond.as_bytes(), g.w)?;
        let s = (x + g.offset) / g.scale;
        let from = if dir >= 0 { s.floor() as i64 } else { s.ceil() as i64 };
        Ok(g.find(from, dir, &c).map(|s| s as f64 * g.scale - g.offset))
    }

    /// VCD of x0..x1 (both groups, CH0..15 as wires), at most `limit` changes
    pub fn vcd(&self, x0: f64, x1: f64, limit: usize) -> String {
        use std::fmt::Write;
        let ps = self.unit == "ns";
        let mut ev: Vec<(i64, usize, u8)> = Vec::new(); // (time, group, value)
        let mut truncated = false;
        for (k, g) in self.groups.iter().enumerate() {
            let Some(g) = g else { continue };
            let a = (((x0 + g.offset) / g.scale).floor().max(0.0) as u64).min(g.n);
            let b = (((x1 + g.offset) / g.scale).ceil().max(0.0) as u64).min(g.n);
            let mut last: i32 = -1;
            for s in a..b {
                let v = g.sample(s);
                if v as i32 != last {
                    let x = s as f64 * g.scale - g.offset;
                    let t = if ps { (x * 1000.0).round() as i64 } else { x.round() as i64 };
                    ev.push((t, k, v));
                    last = v as i32;
                    if ev.len() >= limit {
                        truncated = true;
                        break;
                    }
                }
            }
        }
        ev.sort_by_key(|e| (e.0, e.1));
        let mut o = String::new();
        let _ = writeln!(o, "$comment SLogic16U3 capture {}{} $end", self.id, if truncated { " (truncated)" } else { "" });
        let _ = writeln!(o, "$timescale {} $end", if ps { "1ps" } else { "1ns" });
        let _ = writeln!(o, "$scope module la $end");
        let ids: Vec<String> = (0..16).map(|i| format!("{}", (b'!' + i as u8) as char)).collect();
        for (k, g) in self.groups.iter().enumerate() {
            if let Some(g) = g {
                for c in 0..g.w as usize {
                    let _ = writeln!(o, "$var wire 1 {} CH{} $end", ids[k * 8 + c], k * 8 + c);
                }
            }
        }
        let _ = writeln!(o, "$upscope $end\n$enddefinitions $end");
        let t_base = ev.first().map(|e| e.0).unwrap_or(0).min(0);
        let mut cur: [i32; 2] = [-1, -1];
        let mut last_t = i64::MIN;
        for (t, k, v) in ev {
            if t != last_t {
                let _ = writeln!(o, "#{}", t - t_base);
                last_t = t;
            }
            let w = self.groups[k].as_ref().unwrap().w as usize;
            for c in 0..w {
                let b = (v >> c) & 1;
                if cur[k] < 0 || ((cur[k] as u8 >> c) & 1) != b {
                    let _ = writeln!(o, "{}{}", b, ids[k * 8 + c]);
                }
            }
            cur[k] = v as i32;
        }
        o
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gd(w: u32, samples: &[u8]) -> GroupData {
        let spw = 64 / w as u64;
        let mut words = vec![0u64; (samples.len() as u64 + spw - 1) as usize / spw as usize];
        for (i, &s) in samples.iter().enumerate() {
            words[i / spw as usize] |= (s as u64) << (w as u64 * (i as u64 % spw));
        }
        let mut g = GroupData {
            cfg: GCfg { en: true, wlog: w.trailing_zeros(), ..Default::default() },
            w,
            spw,
            words,
            first: 0,
            n: samples.len() as u64,
            levels: Vec::new(),
            flags: 0,
            scale: 1.0,
            offset: 0.0,
            total: samples.len() as u64,
        };
        g.build_levels();
        g
    }

    fn lcg(n: usize, w: u32, seed: u64) -> Vec<u8> {
        let mut x = seed;
        (0..n)
            .map(|i| {
                x = x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                // runs of equal samples, so that levels and edges both occur
                if i % 7 < 4 { ((x >> 33) as u8) & ((1u32 << w) - 1) as u8 } else { 0 }
            })
            .collect()
    }

    #[test]
    fn summary_matches_scan() {
        for &w in &[1u32, 2, 4, 8] {
            let s = lcg(5000, w, w as u64);
            let g = gd(w, &s);
            for &(a, b) in &[(0usize, 1usize), (3, 700), (255, 257), (0, 5000), (513, 4999), (1000, 1600), (17, 4096)] {
                let (o, an) = s[a..b].iter().fold((0u8, 0xFFu8), |(o, an), &v| (o | v, an & v));
                let m = ((1u32 << w) - 1) as u8;
                assert_eq!(g.summary(a as u64, b as u64), ((o as u16) << 8) | (an & m) as u16, "w {w} {a}..{b}");
            }
        }
    }

    #[test]
    fn find_matches_scan() {
        for &w in &[1u32, 2, 4, 8] {
            let s = lcg(3000, w, 7 + w as u64);
            let g = gd(w, &s);
            for code in ["1XXXXXXX", "0XXXXXXX", "RXXXXXXX", "FXXXXXXX", "EXXXXXXX", "R1XXXXXX", "XF0XXXXX", "EE1RXXXX", "0000XXXX"] {
                let codes = &code.as_bytes()[..8];
                if codes.iter().enumerate().any(|(i, &c)| c != b'X' && i as u32 >= w) {
                    continue;
                }
                let c = make_cond(codes, w).unwrap();
                let ok = |i: usize| {
                    codes.iter().enumerate().all(|(ch, &cc)| {
                        let cur = (s[i] >> ch) & 1;
                        let prev = if i > 0 { (s[i - 1] >> ch) & 1 } else { 2 };
                        match cc {
                            b'X' => true,
                            b'0' => cur == 0,
                            b'1' => cur == 1,
                            b'R' => prev == 0 && cur == 1,
                            b'F' => prev == 1 && cur == 0,
                            b'E' => prev != 2 && prev != cur,
                            _ => false,
                        }
                    })
                };
                for &from in &[-1i64, 0, 5, 63, 64, 1000, 2999] {
                    let want = ((from + 1).max(0) as usize..s.len()).find(|&i| ok(i)).map(|i| i as u64);
                    assert_eq!(g.find(from, 1, &c), want, "w {w} {code} fwd {from}");
                    let want = (0..(from.max(0) as usize).min(s.len())).rev().find(|&i| ok(i)).map(|i| i as u64);
                    assert_eq!(g.find(from, -1, &c), want, "w {w} {code} back {from}");
                }
            }
        }
    }
}
