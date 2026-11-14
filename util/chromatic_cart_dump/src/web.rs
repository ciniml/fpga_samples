// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Web UI: `chromatic_cart_dump serve`. One worker thread owns the cartridge reader (USB, opened
//! per operation because an FPGA load re-enumerates it) and refreshes the status every second
//! while idle; the browser polls /api/state. The cartridge stays write-protected by the FPGA
//! whatever is asked here (rtl/chromatic/cart_bus.veryl), and the FPGA load is SRAM only.

use crate::header::{Header, Mapper};
use crate::link::{Link, SimLink, UsbLink};
use crate::ops::{self, DumpOpts, Progress, SaveOpts};
use crate::proto::{Reader, Status};
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::Command,
    sync::{mpsc, Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tiny_http::{Header as HttpHeader, Method, Request, Response, Server};

const INDEX: &str = include_str!("web/index.html");
const LOG_LINES: usize = 300;

pub fn default_bitstream() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../eda/chromatic_cart_dump/build/chromatic/impl/pnr/chromatic_cart_dump.fs"))
}

#[derive(Default)]
struct State {
    device: Value,
    header: Value,
    job: Option<String>,
    phase: String,
    done: usize,
    total: usize,
    log: VecDeque<Value>,
    log_seq: u64,
    result: Value,
    error: Option<String>,
}

type Shared = Arc<Mutex<State>>;

fn now_ms() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0) }

fn log(st: &Shared, level: &str, msg: impl Into<String>) {
    let msg = msg.into();
    eprintln!("[{level}] {msg}");
    let mut s = st.lock().unwrap();
    s.log_seq += 1;
    let seq = s.log_seq;
    s.log.push_back(json!({"seq": seq, "t": now_ms(), "level": level, "msg": msg}));
    while s.log.len() > LOG_LINES {
        s.log.pop_front();
    }
}

enum AnyLink {
    Usb(UsbLink),
    Sim(SimLink),
}

impl Link for AnyLink {
    fn send(&mut self, d: &[u8]) -> Result<(), String> {
        match self {
            AnyLink::Usb(l) => l.send(d),
            AnyLink::Sim(l) => l.send(d),
        }
    }
    fn recv(&mut self, b: &mut [u8]) -> Result<(), String> {
        match self {
            AnyLink::Usb(l) => l.recv(b),
            AnyLink::Sim(l) => l.recv(b),
        }
    }
}

struct Worker {
    st: Shared,
    out: PathBuf,
    bitstream: PathBuf,
    sim: Option<String>,
}

struct WebProgress<'a> {
    st: &'a Shared,
}

impl Progress for WebProgress<'_> {
    fn step(&mut self, phase: &str, done: usize, total: usize) {
        let mut s = self.st.lock().unwrap();
        s.phase = phase.to_string();
        s.done = done;
        s.total = total;
    }
    fn note(&mut self, msg: &str) { log(self.st, "warn", msg); }
}

fn status_json(s: &Status) -> Value {
    json!({
        "present": true, "cart": s.cart(), "switch_on": s.switch_on(), "power_req": s.power_req(),
        "pwr_en": s.pwr_en(), "ready": s.ready(), "legacy": s.legacy(), "rst_high": s.rst_high,
        "ram_mode": s.ram_mode(), "ram_on": s.ram_on, "reject_cnt": s.reject_cnt, "err": s.err,
        "describe": s.describe(),
    })
}

fn header_json(h: &Header) -> Value {
    let m = h.mapper();
    let ram = match m {
        Mapper::Mbc2 => "512 x 4 bit (MBC2)".to_string(),
        Mapper::Mbc7 => "EEPROM (93LC56 256 B / 93LC66 512 B)".to_string(),
        _ => format!("{} KiB", h.ram_size() >> 10),
    };
    json!({
        "title": h.title(), "cgb": format!("{:02x}", h.cgb()), "is_cgb": h.is_cgb(), "sgb": h.sgb(),
        "cart_type": format!("{:02x}", h.cart_type()), "mapper": m.name(), "rom_supported": ops::supported(m),
        "rom_code": format!("{:02x}", h.rom_code()), "rom_banks": h.rom_banks(),
        "rom_kib": h.rom_banks().map(|n| n * 16),
        "ram_code": format!("{:02x}", h.ram_code()), "ram": ram, "battery": h.battery(),
        "header_ok": h.header_ok(), "header_checksum": format!("{:02x}", h.header_checksum()),
        "header_checksum_calc": format!("{:02x}", h.header_checksum_calc()),
        "global_checksum": format!("{:04x}", h.global_checksum()),
        "save": match ops::ram_layout(m, h) {
            Ok(_) if m == Mapper::Mbc7 => json!({"ok": true, "bytes": 512, "eeprom": true}),
            Ok((nb, bs)) => json!({"ok": true, "bytes": nb * bs}),
            Err(e) => json!({"ok": false, "why": e}),
        },
    })
}

/// write `data` as <base>.<ext>, or <base>-2.<ext>, ... (an identical existing file is reused)
fn store(dir: &Path, base: &str, ext: &str, data: &[u8]) -> Result<(String, bool), String> {
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for i in 1.. {
        let name = if i == 1 { format!("{base}.{ext}") } else { format!("{base}-{i}.{ext}") };
        let p = dir.join(&name);
        match fs::read(&p) {
            Ok(d) if d == data => return Ok((name, true)),
            Ok(_) => continue,
            Err(_) => {
                fs::write(&p, data).map_err(|e| format!("{}: {e}", p.display()))?;
                return Ok((name, false));
            }
        }
    }
    unreachable!()
}

impl Worker {
    fn open(&self) -> Result<Reader<AnyLink>, String> {
        let l = match &self.sim {
            Some(exe) => AnyLink::Sim(SimLink::spawn(exe)?),
            None => AnyLink::Usb(UsbLink::open()?),
        };
        Ok(Reader::new(l))
    }

    fn close(&self, r: Reader<AnyLink>) {
        if let AnyLink::Sim(l) = r.link {
            if let Err(e) = l.finish() {
                log(&self.st, "error", e);
            }
        }
    }

    fn refresh(&self) {
        let v = match self.open() {
            Ok(mut r) => {
                let v = match r.status() {
                    Ok(s) => status_json(&s),
                    Err(e) => json!({"present": false, "error": e}),
                };
                self.close(r);
                v
            }
            Err(e) => json!({"present": false, "error": e}),
        };
        self.st.lock().unwrap().device = v;
    }

    fn run(&self, job: Value) {
        let kind = job["kind"].as_str().unwrap_or("").to_string();
        {
            let mut s = self.st.lock().unwrap();
            s.phase = String::new();
            s.done = 0;
            s.total = 0;
            s.error = None;
            s.result = Value::Null;
        }
        log(&self.st, "info", format!("start: {kind}"));
        let t0 = Instant::now();
        let res = match kind.as_str() {
            "load" => self.load_fpga(),
            _ => self.open().and_then(|mut r| {
                let res = self.cart_job(&mut r, &kind, &job);
                // whatever happened: make sure the slot is off and the RAM disabled
                if res.is_err() {
                    let _ = r.ram_mode(false);
                    let _ = r.power(false);
                }
                self.close(r);
                res
            }),
        };
        match res {
            Ok(v) => {
                log(&self.st, "info", format!("done: {kind} ({:.1} s)", t0.elapsed().as_secs_f64()));
                self.st.lock().unwrap().result = v;
            }
            Err(e) => {
                log(&self.st, "error", format!("{kind}: {e}"));
                self.st.lock().unwrap().error = Some(e);
            }
        }
        self.refresh();
        self.st.lock().unwrap().job = None;
    }

    fn cart_job(&self, r: &mut Reader<AnyLink>, kind: &str, job: &Value) -> Result<Value, String> {
        let force = job["force"].as_bool().unwrap_or(false);
        let mut p = WebProgress { st: &self.st };
        match kind {
            "header" => {
                let h = ops::powered(r, false, |r| ops::read_header(r))?;
                let v = header_json(&h);
                self.st.lock().unwrap().header = v.clone();
                Ok(json!({"kind": "header"}))
            }
            "dump" => {
                let o = DumpOpts { verify: job["verify"].as_bool().unwrap_or(true), mapper: None, banks: None, mbc1m: false, force };
                let d = ops::powered(r, false, |r| {
                    let h = ops::read_header(r)?;
                    self.st.lock().unwrap().header = header_json(&h);
                    ops::dump_rom(r, &o, &mut p)
                })?;
                if !d.global_ok() {
                    log(&self.st, "warn", format!("global checksum mismatch (calculated {:04x}, header {:04x}): compare the SHA-1 with a known-good list", d.global_calc, d.header.global_checksum()));
                }
                let ext = if d.header.is_cgb() { "gbc" } else { "gb" };
                let (name, existed) = store(&self.out, &ops::sanitize(&d.header.title()), ext, &d.rom)?;
                log(&self.st, "info", format!("{name}: {} bytes{}", d.rom.len(), if existed { " (identical to the existing file)" } else { "" }));
                Ok(json!({
                    "kind": "rom", "file": name, "existed": existed, "size": d.rom.len(), "mapper": d.mapper.name(),
                    "mbc1m": d.mbc1m, "verified": d.verified, "global_ok": d.global_ok(),
                    "global_calc": format!("{:04x}", d.global_calc), "secs": d.secs,
                    "crc32": format!("{:08x}", crc32fast::hash(&d.rom)), "sha1": ops::sha1_hex(&d.rom),
                }))
            }
            "save" => {
                let o = SaveOpts { mapper: None, force };
                let d = ops::powered(r, false, |r| {
                    let h = ops::read_header(r)?;
                    self.st.lock().unwrap().header = header_json(&h);
                    ops::read_save(r, &o, &mut p)
                })?;
                let s = r.status()?;
                if s.ram_on || s.ram_mode() {
                    return Err(format!("the reader still reports {}", s.describe()));
                }
                let (name, existed) = store(&self.out, &ops::sanitize(&d.header.title()), "sav", &d.ram)?;
                log(&self.st, "info", format!("{name}: {} bytes{}", d.ram.len(), if existed { " (identical to the existing file)" } else { "" }));
                Ok(json!({
                    "kind": "save", "file": name, "existed": existed, "size": d.ram.len(), "banks": d.banks,
                    "bank_size": d.bank_size, "all_ff": d.all_ff(), "secs": d.secs,
                    "crc32": format!("{:08x}", crc32fast::hash(&d.ram)), "sha1": ops::sha1_hex(&d.ram),
                }))
            }
            k => Err(format!("unknown job '{k}'")),
        }
    }

    /// SRAM load only: openFPGALoader without --write-flash / -f
    fn load_fpga(&self) -> Result<Value, String> {
        if self.sim.is_some() {
            return Err("not available with --sim".into());
        }
        let bs = &self.bitstream;
        if !bs.is_file() {
            return Err(format!("{}: not found (build eda/chromatic_cart_dump with make)", bs.display()));
        }
        log(&self.st, "info", format!("openFPGALoader --cable gwu2x {} (SRAM)", bs.display()));
        {
            let mut s = self.st.lock().unwrap();
            s.phase = "FPGA".into();
            s.done = 0;
            s.total = 1;
        }
        let out = Command::new("openFPGALoader")
            .arg("--cable")
            .arg("gwu2x")
            .arg(bs)
            .output()
            .map_err(|e| format!("openFPGALoader: {e}"))?;
        let text = String::from_utf8_lossy(&out.stdout).to_string() + &String::from_utf8_lossy(&out.stderr);
        for l in text.split(['\n', '\r']).map(str::trim).filter(|l| !l.is_empty() && !l.contains("[=")) {
            log(&self.st, "fpga", l);
        }
        if !out.status.success() {
            return Err(format!("openFPGALoader failed ({}): is the console on and connected?", out.status));
        }
        // wait for the reader to enumerate
        let t0 = Instant::now();
        while t0.elapsed() < Duration::from_secs(10) {
            std::thread::sleep(Duration::from_millis(500));
            if let Ok(mut r) = self.open() {
                if r.status().is_ok() {
                    self.st.lock().unwrap().done = 1;
                    return Ok(json!({"kind": "load"}));
                }
            }
        }
        Err("loaded, but the reader did not appear on USB within 10 s".into())
    }
}

fn files_json(dir: &Path) -> Value {
    let mut v: Vec<(u64, Value)> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let ext = name.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
            if !matches!(ext.as_str(), "gb" | "gbc" | "sav") {
                return None;
            }
            let md = e.metadata().ok()?;
            let mt = md.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_secs();
            Some((mt, json!({"name": name, "size": md.len(), "mtime": mt})))
        })
        .collect();
    v.sort_by(|a, b| b.0.cmp(&a.0));
    Value::Array(v.into_iter().map(|x| x.1).collect())
}

fn hdr(k: &str, v: &str) -> HttpHeader { HttpHeader::from_bytes(k.as_bytes(), v.as_bytes()).unwrap() }

fn reply_json(req: Request, code: u16, v: &Value) {
    let _ = req.respond(
        Response::from_string(v.to_string())
            .with_status_code(code)
            .with_header(hdr("Content-Type", "application/json"))
            .with_header(hdr("Cache-Control", "no-store")),
    );
}

fn handle(mut req: Request, st: &Shared, tx: &Mutex<mpsc::Sender<Value>>, out: &Path, bitstream: &Path) {
    let url = req.url().split('?').next().unwrap_or("").to_string();
    match (req.method(), url.as_str()) {
        (Method::Get, "/") => {
            let _ = req.respond(Response::from_string(INDEX).with_header(hdr("Content-Type", "text/html; charset=utf-8")));
        }
        (Method::Get, "/api/state") => {
            let since: u64 = req.url().split("since=").nth(1).and_then(|x| x.split('&').next()?.parse().ok()).unwrap_or(0);
            let v = {
                let s = st.lock().unwrap();
                json!({
                    "device": s.device, "header": s.header, "job": s.job, "phase": s.phase, "done": s.done,
                    "total": s.total, "result": s.result, "error": s.error,
                    "log": s.log.iter().filter(|l| l["seq"].as_u64().unwrap_or(0) > since).cloned().collect::<Vec<_>>(),
                    "bitstream": bitstream.display().to_string(), "bitstream_ok": bitstream.is_file(),
                    "out": out.display().to_string(),
                })
            };
            reply_json(req, 200, &v);
        }
        (Method::Get, "/api/files") => reply_json(req, 200, &files_json(out)),
        (Method::Post, "/api/job") => {
            let mut body = String::new();
            let _ = req.as_reader().take(4096).read_to_string(&mut body);
            let job: Value = match serde_json::from_str(&body) {
                Ok(v) => v,
                Err(e) => return reply_json(req, 400, &json!({"error": e.to_string()})),
            };
            let kind = job["kind"].as_str().unwrap_or("").to_string();
            if !matches!(kind.as_str(), "load" | "header" | "dump" | "save") {
                return reply_json(req, 400, &json!({"error": format!("unknown job '{kind}'")}));
            }
            {
                let mut s = st.lock().unwrap();
                if let Some(j) = &s.job {
                    let j = j.clone();
                    drop(s);
                    return reply_json(req, 409, &json!({"error": format!("busy: {j}")}));
                }
                s.job = Some(kind);
            }
            let _ = tx.lock().unwrap().send(job);
            reply_json(req, 202, &json!({"ok": true}));
        }
        (Method::Get, u) if u.starts_with("/files/") => {
            let name = percent_decode(&u["/files/".len()..]);
            let ok = !name.is_empty() && !name.contains('/') && !name.contains('\\') && !name.starts_with('.');
            let p = out.join(&name);
            match (ok, fs::read(&p)) {
                (true, Ok(d)) => {
                    let _ = req.respond(
                        Response::from_data(d)
                            .with_header(hdr("Content-Type", "application/octet-stream"))
                            .with_header(hdr("Content-Disposition", &format!("attachment; filename=\"{name}\""))),
                    );
                }
                _ => reply_json(req, 404, &json!({"error": "not found"})),
            }
        }
        _ => reply_json(req, 404, &json!({"error": "not found"})),
    }
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

pub fn serve(bind: &str, out: &Path, bitstream: &Path, sim: Option<String>) -> Result<(), String> {
    fs::create_dir_all(out).map_err(|e| format!("{}: {e}", out.display()))?;
    let st: Shared = Arc::new(Mutex::new(State::default()));
    let (tx, rx) = mpsc::channel::<Value>();
    let w = Worker { st: st.clone(), out: out.to_path_buf(), bitstream: bitstream.to_path_buf(), sim: sim.clone() };
    std::thread::spawn(move || {
        w.refresh();
        loop {
            match rx.recv_timeout(Duration::from_secs(1)) {
                Ok(job) => w.run(job),
                // the simulator is started per operation: no periodic status there
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if w.sim.is_none() {
                        w.refresh();
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    });
    let server = Server::http(bind).map_err(|e| format!("{bind}: {e}"))?;
    log(&st, "info", format!("listening on http://{bind}/ (dumps in {})", out.display()));
    let tx = Arc::new(Mutex::new(tx));
    let out = Arc::new(out.to_path_buf());
    let bitstream = Arc::new(bitstream.to_path_buf());
    for req in server.incoming_requests() {
        let (st, tx, out, bitstream) = (st.clone(), tx.clone(), out.clone(), bitstream.clone());
        std::thread::spawn(move || handle(req, &st, &tx, &out, &bitstream));
    }
    Ok(())
}
