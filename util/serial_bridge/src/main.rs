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
//! /api/xfer writes the bytes, then reads until `read` bytes arrived or
//! the timeout elapsed. Requests are serialised on the port (one at a time).

use axum::{
    extract::State,
    http::{header, StatusCode},
    response::{Html, IntoResponse},
    routing::{get, post},
    Json, Router,
};
use clap::Parser;
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
}

struct PortState {
    port: Option<Box<dyn serialport::SerialPort>>,
    name: String,
    baud: u32,
}

struct AppState {
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
         <li><a href='/trace'>EasyCDR Trace Viewer</a></li></ul>\
         <p>API: <code>/api/ports</code>, <code>/api/state</code>, <code>/api/open</code>, \
         <code>/api/close</code>, <code>/api/flush</code>, <code>/api/xfer</code></p>",
    )
}

async fn bert() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], BERT_HTML)
}

async fn trace() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], TRACE_HTML)
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
    let app = Arc::new(AppState {
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
        .with_state(app);

    let listener = tokio::net::TcpListener::bind(&args.listen)
        .await
        .unwrap_or_else(|e| panic!("bind {}: {e}", args.listen));
    eprintln!("serial-bridge listening on http://{}/", args.listen);
    axum::serve(listener, router).await.unwrap();
}
