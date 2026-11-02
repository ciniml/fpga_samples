// A game controller (PS5 DualSense, or another one the kernel knows as a
// gamepad) through evdev: /dev/input/eventN, read without blocking, found
// again after it is unplugged. The kernel driver (hid-playstation) gives
// the standard gamepad codes, over USB and Bluetooth alike. The device has
// to be readable: a udev rule such as
//   SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="054c",
//   ATTRS{idProduct}=="0ce6|0df2", MODE="0666"
// (/etc/udev/rules.d/70-dualsense.rules; a local desktop session gets it
// anyway).
//
// Buttons as keys: d-pad / left stick = arrows, cross = Space, circle and
// triangle = B, square = A, L1 / R1 = Hold, options = Start, create = Pause,
// PS = Home, L2 / R2 = volume down / up, L3 / R3 = mute. The volume
// buttons do not count as "any button" (the arcade's call to play).
use crate::input::{Key, NKEYS};
use std::fs::File;
use std::io::{ErrorKind, Read};
use std::os::unix::fs::OpenOptionsExt;
use std::time::{Duration, Instant};

const O_NONBLOCK: i32 = 0o4000;
const EV_KEY: u16 = 1;
const EV_ABS: u16 = 3;
const BTN_SOUTH: u16 = 0x130;

/// the key of a button (evdev code)
fn button(code: u16) -> Option<Key> {
    Some(match code {
        0x130 => Key::Space,           // cross
        0x131 | 0x133 => Key::B,       // circle, triangle
        0x134 => Key::A,               // square
        0x136 | 0x137 => Key::Hold,    // L1, R1
        0x13a => Key::Pause,           // create
        0x13b => Key::Start,           // options
        0x13c => Key::Home,            // PS
        0x138 => Key::VolDown,         // L2
        0x139 => Key::VolUp,           // R2
        0x13d | 0x13e => Key::Mute,    // L3, R3
        _ => return None,
    })
}

pub struct Gamepad {
    dev: Option<File>,
    pub name: String,
    next_scan: Instant,
    hat: (i32, i32),
    stick: (i32, i32), // -1, 0, 1 with hysteresis
    buttons: Vec<u16>, // held
    keys: [bool; NKEYS],
}

/// the event device of a gamepad: has BTN_SOUTH, is not the motion sensors
/// or the touchpad of a DualSense
fn find() -> Option<(File, String)> {
    let mut list: Vec<_> = std::fs::read_dir("/sys/class/input").ok()?.flatten().map(|e| e.file_name()).collect();
    list.sort();
    for n in list {
        let n = n.to_string_lossy().to_string();
        if !n.starts_with("event") {
            continue;
        }
        let sys = format!("/sys/class/input/{}/device", n);
        let name = std::fs::read_to_string(format!("{}/name", sys)).unwrap_or_default().trim().to_string();
        if name.contains("Motion") || name.contains("Touchpad") {
            continue;
        }
        // capabilities/key: hex words, the most significant first
        let caps = std::fs::read_to_string(format!("{}/capabilities/key", sys)).unwrap_or_default();
        let words: Vec<u64> = caps.split_whitespace().rev().map(|w| u64::from_str_radix(w, 16).unwrap_or(0)).collect();
        let (w, b) = ((BTN_SOUTH / 64) as usize, BTN_SOUTH % 64);
        if words.get(w).map_or(true, |v| v >> b & 1 == 0) {
            continue;
        }
        if let Ok(f) = std::fs::OpenOptions::new().read(true).custom_flags(O_NONBLOCK).open(format!("/dev/input/{}", n)) {
            return Some((f, name));
        }
    }
    None
}

impl Gamepad {
    pub fn new() -> Gamepad {
        let mut g = Gamepad {
            dev: None,
            name: String::new(),
            next_scan: Instant::now(),
            hat: (0, 0),
            stick: (0, 0),
            buttons: Vec::new(),
            keys: [false; NKEYS],
        };
        g.scan();
        g
    }

    /// never looks for a controller (an input that stays still)
    pub fn none() -> Gamepad {
        Gamepad {
            dev: None,
            name: String::new(),
            next_scan: Instant::now() + Duration::from_secs(10 * 365 * 86400),
            hat: (0, 0),
            stick: (0, 0),
            buttons: Vec::new(),
            keys: [false; NKEYS],
        }
    }

    pub fn connected(&self) -> bool {
        self.dev.is_some()
    }

    fn scan(&mut self) {
        self.next_scan = Instant::now() + Duration::from_secs(2);
        if let Some((f, name)) = find() {
            self.dev = Some(f);
            self.name = name;
        }
    }

    /// reads what is pending; `f(key, down)` for every key that changed,
    /// `f` gets every button press too (`any`: a press of any button)
    pub fn poll(&mut self, mut f: impl FnMut(Key, bool), mut any: impl FnMut()) {
        if self.dev.is_none() {
            if Instant::now() >= self.next_scan {
                self.scan();
            }
            if self.dev.is_none() {
                return;
            }
        }
        let mut buf = [0u8; 24 * 64];
        loop {
            let n = match self.dev.as_mut().unwrap().read(&mut buf) {
                Ok(0) => {
                    self.lost();
                    break;
                }
                Ok(n) => n,
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(_) => {
                    self.lost();
                    break;
                }
            };
            // struct input_event: timeval (16), type, code (u16), value (i32)
            for ev in buf[..n].chunks_exact(24) {
                let ty = u16::from_ne_bytes([ev[16], ev[17]]);
                let code = u16::from_ne_bytes([ev[18], ev[19]]);
                let v = i32::from_ne_bytes([ev[20], ev[21], ev[22], ev[23]]);
                match ty {
                    EV_KEY => {
                        self.buttons.retain(|&b| b != code);
                        if v != 0 {
                            self.buttons.push(code);
                            if v == 1 && !matches!(button(code), Some(Key::VolDown | Key::VolUp | Key::Mute)) {
                                any();
                            }
                        }
                    }
                    EV_ABS => match code {
                        0x10 => self.hat.0 = v.signum(),
                        0x11 => self.hat.1 = v.signum(),
                        0 => self.stick.0 = axis(self.stick.0, v),
                        1 => self.stick.1 = axis(self.stick.1, v),
                        _ => {}
                    },
                    _ => {}
                }
            }
        }
        self.update(&mut f);
    }

    /// unplugged: everything up, look for it again
    fn lost(&mut self) {
        self.dev = None;
        self.hat = (0, 0);
        self.stick = (0, 0);
        self.buttons.clear();
        self.next_scan = Instant::now() + Duration::from_secs(1);
    }

    fn update(&mut self, f: &mut impl FnMut(Key, bool)) {
        let x = if self.hat.0 != 0 { self.hat.0 } else { self.stick.0 };
        let y = if self.hat.1 != 0 { self.hat.1 } else { self.stick.1 };
        let mut now = [false; NKEYS];
        now[Key::Left as usize] = x < 0;
        now[Key::Right as usize] = x > 0;
        now[Key::Up as usize] = y < 0;
        now[Key::Down as usize] = y > 0;
        for &b in &self.buttons {
            if let Some(k) = button(b) {
                now[k as usize] = true;
            }
        }
        for (i, (&a, &b)) in self.keys.iter().zip(now.iter()).enumerate() {
            if a != b {
                f(KEYS[i], b);
            }
        }
        self.keys = now;
    }
}

const KEYS: [Key; NKEYS] =
    [Key::Left, Key::Right, Key::Up, Key::Down, Key::A, Key::B, Key::Space, Key::Hold, Key::Start, Key::Pause, Key::Quit, Key::Home, Key::VolDown, Key::VolUp, Key::Mute];

/// a stick axis (0..255, 128 centre) to -1 / 0 / 1, with hysteresis
fn axis(old: i32, v: i32) -> i32 {
    match old {
        -1 if v < 100 => -1,
        1 if v > 156 => 1,
        _ if v < 64 => -1,
        _ if v > 192 => 1,
        _ => 0,
    }
}
