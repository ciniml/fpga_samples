//! serial-bridge: a small web server that owns one serial port and exposes
//! it to a browser UI through a protocol-agnostic HTTP API, and serves the
//! plain HTML/JS host UIs (BERT, trace viewer) embedded at build time.
//!
//! The FPGA-side protocols are all command/response byte streams, so the
//! whole UI logic stays in the browser; the server only moves bytes:
//!
//!   GET  /                      index (links to the UIs)
//!   GET  /bert, /trace          embedded UIs (eda/easycdr_bert/host/bert.html,
//!                               eda/easycdr_trace/host/web/index.html)
//!   GET  /api/ports             list serial ports
//!   GET  /api/state             {open, port, baud}
//!   POST /api/open              {port, baud}
//!   POST /api/close
//!   POST /api/flush             drop pending RX bytes, cancel a pending xfer
//!   POST /api/xfer              {write:[u8], read:n, timeout_ms} -> {data:[u8], timeout:bool}
//!
//! The SLogic16U3 logic analyzer (eda/slogic16u3_la) is served too: its
//! capture runs here (USB 3.0, see la.rs) and the UI asks for views of it:
//!
//!   GET  /la, /wave.js          LA UI (eda/slogic16u3_la/host/web/la.html) and the
//!                               waveform view shared with the trace viewer
//!   *    /api/la/...            see la.rs
//!
//! /api/xfer writes the bytes, then reads until `read` bytes arrived or
//! the timeout elapsed. Requests are serialised on the port (one at a time).

use axum::{
    extract::{Query, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse},
    routing::{get, post},
    Json, Router,
};
use clap::Parser;

mod la;
use serde::{Deserialize, Serialize};
use std::{
    io::{Read, Write},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};

const BERT_HTML: &str = include_str!("../../../eda/easycdr_bert/host/bert.html");
const TRACE_HTML: &str = include_str!("../../../eda/easycdr_trace/host/web/index.html");
const LA_HTML: &str = include_str!("../../../eda/slogic16u3_la/host/web/la.html");
const WAVE_JS: &str = include_str!("../../../eda/easycdr_trace/host/web/wave.js");

#[derive(Parser, Debug)]
#[command(version, about)]
struct Args {
    /// Serial port to open at startup (e.g. /dev/ttyUSB2). Can also be
    /// opened later from the UI.
    #[arg(short, long)]
    port: Option<String>,
    /// Baud rate for --port
    #[arg(short, long, default_value_t = 115200)]
    baud: u32,
    /// Listen address
    #[arg(short, long, default_value = "127.0.0.1:8080")]
    listen: String,
    /// Serve the UIs from this repository checkout instead of the copies
    /// built in (for editing them without rebuilding)
    #[arg(long)]
    ui_root: Option<std::path::PathBuf>,
}

static UI_ROOT: std::sync::OnceLock<Option<std::path::PathBuf>> = std::sync::OnceLock::new();

/// a UI file: from --ui-root when given, else the built-in copy
fn ui_file(path: &str, built_in: &'static str) -> String {
    if let Some(Some(root)) = UI_ROOT.get() {
        if let Ok(s) = std::fs::read_to_string(root.join(path)) {
            return s;
        }
    }
    built_in.to_string()
}

struct PortState {
    port: Option<Box<dyn serialport::SerialPort>>,
    name: String,
    baud: u32,
}

struct AppState {
    la: la::LaShared,
    port: Mutex<PortState>,
    /// bumped by flush/open/close: an xfer that observes a change aborts
    cancel_gen: AtomicU64,
}

type Shared = Arc<AppState>;

#[derive(Deserialize)]
struct OpenReq {
    port: String,
    baud: u32,
}

#[derive(Deserialize)]
struct XferReq {
    #[serde(default)]
    write: Vec<u8>,
    #[serde(default)]
    read: usize,
    #[serde(default = "default_timeout")]
    timeout_ms: u64,
}
fn default_timeout() -> u64 {
    5000
}

#[derive(Serialize)]
struct XferResp {
    data: Vec<u8>,
    timeout: bool,
}

#[derive(Serialize)]
struct StateResp {
    open: bool,
    port: String,
    baud: u32,
}

#[derive(Serialize)]
struct PortInfo {
    name: String,
    kind: String,
}

fn err(status: StatusCode, msg: impl ToString) -> (StatusCode, Json<serde_json::Value>) {
    (status, Json(serde_json::json!({ "error": msg.to_string() })))
}

fn open_port(st: &mut PortState, name: &str, baud: u32) -> Result<(), String> {
    let p = serialport::new(name, baud)
        .timeout(Duration::from_millis(20))
        .open()
        .map_err(|e| format!("open {name}: {e}"))?;
    st.port = Some(p);
    st.name = name.to_string();
    st.baud = baud;
    Ok(())
}

async fn index() -> Html<&'static str> {
    Html(
        "<!doctype html><meta charset=utf-8><title>serial-bridge</title>\
         <body style='font:14px system-ui;padding:16px'><h1>serial-bridge</h1>\
         <ul><li><a href='/bert'>EasyCDR BERT</a></li>\
         <li><a href='/trace'>EasyCDR Trace Viewer</a></li>\
         <li><a href='/la'>SLogic16U3 Logic Analyzer</a></li></ul>\
         <p>API: <code>/api/ports</code>, <code>/api/state</code>, <code>/api/open</code>, \
         <code>/api/close</code>, <code>/api/flush</code>, <code>/api/xfer</code></p>",
    )
}

async fn bert() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], ui_file("eda/easycdr_bert/host/bert.html", BERT_HTML))
}

async fn trace() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], ui_file("eda/easycdr_trace/host/web/index.html", TRACE_HTML))
}

async fn la_page() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], ui_file("eda/slogic16u3_la/host/web/la.html", LA_HTML))
}

async fn wave_js() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], ui_file("eda/easycdr_trace/host/web/wave.js", WAVE_JS))
}

// ---------------------------------------------------------------- logic analyzer

type ApiErr = (StatusCode, Json<serde_json::Value>);

async fn la_device(State(app): State<Shared>) -> Json<serde_json::Value> {
    let la = app.la.clone();
    Json(tokio::task::spawn_blocking(move || la.device()).await.unwrap())
}

async fn la_capture(State(app): State<Shared>, Json(req): Json<la::CaptureReq>) -> Result<Json<serde_json::Value>, ApiErr> {
    let id = app.la.start(req).map_err(|e| err(StatusCode::BAD_REQUEST, e))?;
    Ok(Json(serde_json::json!({ "id": id })))
}

async fn la_stop(State(app): State<Shared>) -> StatusCode {
    app.la.request_stop();
    StatusCode::NO_CONTENT
}

async fn la_status(State(app): State<Shared>) -> Json<la::Status> {
    Json(app.la.status())
}

fn la_cap(app: &Shared) -> Result<Arc<la::Capture>, ApiErr> {
    app.la.cap.read().unwrap().clone().ok_or_else(|| err(StatusCode::NOT_FOUND, "no capture"))
}

async fn la_meta(State(app): State<Shared>) -> Result<Json<serde_json::Value>, ApiErr> {
    Ok(Json(la_cap(&app)?.meta()))
}

#[derive(Deserialize)]
struct ViewQ {
    g: usize,
    x0: f64,
    x1: f64,
    n: usize,
}

async fn la_view(State(app): State<Shared>, Query(q): Query<ViewQ>) -> Result<impl IntoResponse, ApiErr> {
    let cap = la_cap(&app)?;
    let v = tokio::task::spawn_blocking(move || cap.view(q.g, q.x0, q.x1, q.n)).await.unwrap();
    let v = v.ok_or_else(|| err(StatusCode::NOT_FOUND, "group not captured"))?;
    Ok(([(header::CONTENT_TYPE, "application/octet-stream")], v))
}

#[derive(Deserialize)]
struct FindQ {
    g: usize,
    x: f64,
    dir: i32,
    cond: String,
}

async fn la_find(State(app): State<Shared>, Query(q): Query<FindQ>) -> Result<Json<serde_json::Value>, ApiErr> {
    let cap = la_cap(&app)?;
    let r = tokio::task::spawn_blocking(move || cap.find(q.g, q.x, q.dir, &q.cond)).await.unwrap();
    let x = r.map_err(|e| err(StatusCode::BAD_REQUEST, e))?;
    Ok(Json(serde_json::json!({ "x": x })))
}

#[derive(Deserialize)]
struct VcdQ {
    x0: f64,
    x1: f64,
    #[serde(default = "vcd_limit")]
    limit: usize,
}
fn vcd_limit() -> usize {
    20_000_000
}

async fn la_vcd(State(app): State<Shared>, Query(q): Query<VcdQ>) -> Result<impl IntoResponse, ApiErr> {
    let cap = la_cap(&app)?;
    let id = cap.id;
    let v = tokio::task::spawn_blocking(move || cap.vcd(q.x0, q.x1, q.limit)).await.unwrap();
    Ok((
        [
            (header::CONTENT_TYPE, "text/plain; charset=utf-8".to_string()),
            (header::CONTENT_DISPOSITION, format!("attachment; filename=\"la_{id}.vcd\"")),
        ],
        v,
    ))
}

async fn ports() -> Result<Json<Vec<PortInfo>>, (StatusCode, Json<serde_json::Value>)> {
    let list = serialport::available_ports().map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, e))?;
    Ok(Json(
        list.into_iter()
            .map(|p| PortInfo {
                name: p.port_name,
                kind: match p.port_type {
                    serialport::SerialPortType::UsbPort(u) => format!(
                        "usb {:04x}:{:04x} {}",
                        u.vid,
                        u.pid,
                        u.product.unwrap_or_default()
                    ),
                    serialport::SerialPortType::PciPort => "pci".into(),
                    serialport::SerialPortType::BluetoothPort => "bluetooth".into(),
                    serialport::SerialPortType::Unknown => "unknown".into(),
                },
            })
            .collect(),
    ))
}

fn state_of(st: &PortState) -> StateResp {
    StateResp {
        open: st.port.is_some(),
        port: st.name.clone(),
        baud: st.baud,
    }
}

/// Run `f` with the port state locked, on the blocking pool (an xfer may be
/// holding the lock for up to its timeout; never block a tokio worker on it).
async fn with_port<T: Send + 'static>(
    app: &Shared,
    cancel_pending: bool,
    f: impl FnOnce(&mut PortState) -> T + Send + 'static,
) -> T {
    if cancel_pending {
        app.cancel_gen.fetch_add(1, Ordering::SeqCst);
    }
    let app2 = app.clone();
    tokio::task::spawn_blocking(move || {
        let mut st = app2.port.lock().unwrap();
        f(&mut st)
    })
    .await
    .expect("blocking task panicked")
}

async fn state(State(app): State<Shared>) -> Json<StateResp> {
    Json(with_port(&app, false, |st| state_of(st)).await)
}

async fn open(
    State(app): State<Shared>,
    Json(req): Json<OpenReq>,
) -> Result<Json<StateResp>, (StatusCode, Json<serde_json::Value>)> {
    with_port(&app, true, move |st| {
        st.port = None;
        open_port(st, &req.port, req.baud)?;
        Ok(state_of(st))
    })
    .await
    .map(Json)
    .map_err(|e: String| err(StatusCode::BAD_REQUEST, e))
}

async fn close(State(app): State<Shared>) -> Json<StateResp> {
    Json(
        with_port(&app, true, |st| {
            st.port = None;
            state_of(st)
        })
        .await,
    )
}

async fn flush(State(app): State<Shared>) -> StatusCode {
    // cancel a pending xfer, then drop whatever is in the RX buffer
    with_port(&app, true, |st| {
        if let Some(p) = st.port.as_mut() {
            let _ = p.clear(serialport::ClearBuffer::Input);
        }
    })
    .await;
    StatusCode::NO_CONTENT
}

async fn xfer(
    State(app): State<Shared>,
    Json(req): Json<XferReq>,
) -> Result<Json<XferResp>, (StatusCode, Json<serde_json::Value>)> {
    let app2 = app.clone();
    let res = tokio::task::spawn_blocking(move || -> Result<XferResp, String> {
        let mut st = app2.port.lock().unwrap();
        let my_gen = app2.cancel_gen.load(Ordering::SeqCst);
        let port = st.port.as_mut().ok_or_else(|| "port not open".to_string())?;
        if !req.write.is_empty() {
            port.write_all(&req.write).map_err(|e| format!("write: {e}"))?;
            port.flush().map_err(|e| format!("flush: {e}"))?;
        }
        let mut data = Vec::with_capacity(req.read);
        let deadline = Instant::now() + Duration::from_millis(req.timeout_ms);
        let mut buf = [0u8; 4096];
        let mut timeout = false;
        while data.len() < req.read {
            if app2.cancel_gen.load(Ordering::SeqCst) != my_gen {
                return Err("cancelled".into());
            }
            if Instant::now() >= deadline {
                timeout = true;
                break;
            }
            let want = (req.read - data.len()).min(buf.len());
            match port.read(&mut buf[..want]) {
                Ok(0) => {}
                Ok(n) => data.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::TimedOut => {}
                Err(e) => return Err(format!("read: {e}")),
            }
        }
        Ok(XferResp { data, timeout })
    })
    .await
    .map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, e))?;
    res.map(Json).map_err(|e| err(StatusCode::BAD_REQUEST, e))
}

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let mut st = PortState {
        port: None,
        name: args.port.clone().unwrap_or_default(),
        baud: args.baud,
    };
    if let Some(p) = &args.port {
        match open_port(&mut st, p, args.baud) {
            Ok(()) => eprintln!("opened {p} @ {}", args.baud),
            Err(e) => eprintln!("warning: {e} (open it from the UI)"),
        }
    }
    UI_ROOT.set(args.ui_root.clone()).unwrap();
    let app = Arc::new(AppState {
        la: la::new(),
        port: Mutex::new(st),
        cancel_gen: AtomicU64::new(0),
    });

    let router = Router::new()
        .route("/", get(index))
        .route("/bert", get(bert))
        .route("/trace", get(trace))
        .route("/api/ports", get(ports))
        .route("/api/state", get(state))
        .route("/api/open", post(open))
        .route("/api/close", post(close))
        .route("/api/flush", post(flush))
        .route("/api/xfer", post(xfer))
        .route("/la", get(la_page))
        .route("/wave.js", get(wave_js))
        .route("/api/la/device", get(la_device))
        .route("/api/la/capture", post(la_capture))
        .route("/api/la/stop", post(la_stop))
        .route("/api/la/status", get(la_status))
        .route("/api/la/meta", get(la_meta))
        .route("/api/la/view", get(la_view))
        .route("/api/la/find", get(la_find))
        .route("/api/la/vcd", get(la_vcd))
        .with_state(app);

    let listener = tokio::net::TcpListener::bind(&args.listen)
        .await
        .unwrap_or_else(|e| panic!("bind {}: {e}", args.listen));
    eprintln!("serial-bridge listening on http://{}/", args.listen);
    axum::serve(listener, router).await.unwrap();
}
