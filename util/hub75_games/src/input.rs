// Keyboard from the terminal (works over ssh / tmux).
//
// A game needs "is the key held", which a terminal reports only with the
// kitty keyboard protocol (press / repeat / release events; kitty, WezTerm,
// foot, Ghostty, ...). Elsewhere a held key is only a stream of auto-repeat
// presses: a key counts as held until a short while after its last press
// (longer after the first one, which is followed by the auto-repeat delay),
// and the opposite direction cancels it at once.
//
// A game controller (gamepad.rs) adds to the same keys: it reports presses
// and releases, and the arrows repeat while held (like a keyboard's
// auto-repeat, for the moves that step per press). Without a terminal the
// controller alone can play (Input::pad_only).
//
// The emulator's web page (hub75emu) sends its keys back too, as UDP
// datagrams "key <name> <1 | 0>" to port KEY_PORT (Input::listen): they
// count like the controller's (press / release, the arrows repeat).
use crate::gamepad::Gamepad;
use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, KeyboardEnhancementFlags,
    PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use crossterm::{execute, terminal};
use std::io;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Key {
    Left,
    Right,
    Up,
    Down,
    A,     // z
    B,     // x / b
    Space, // space
    Hold,  // c / v
    Start,
    Pause,
    Quit,
    Home, // m / the controller's PS button: the arcade leaves the game
    VolDown, // - / L2
    VolUp,   // + / R2
    Mute,    // 0 / L3, R3
}
pub const NKEYS: usize = 15;

/// where hub75emu sends the page's keys (on the host the frames come from)
pub const KEY_PORT: u16 = 10006;

const FIRST_HOLD: Duration = Duration::from_millis(550); // > auto-repeat delay
const REPEAT_HOLD: Duration = Duration::from_millis(120); // > auto-repeat period

const PAD_DELAY: Duration = Duration::from_millis(220); // controller arrows: first repeat
const PAD_REPEAT: Duration = Duration::from_millis(70);

pub struct Input {
    pub releases: bool, // the terminal reports key releases
    term: bool,         // reading the terminal (raw mode)
    until: [Option<Instant>; NKEYS],
    pressed: [bool; NKEYS], // pressed since the last frame
    hits: [u32; NKEYS],     // presses + auto-repeats since the last frame
    pub pad: Gamepad,
    pad_held: [Option<Instant>; NKEYS], // held on the controller: the next repeat
    pad_any: bool,                      // a controller button since the last call
    pad_active: bool,                   // any controller press, the arrows too
    net: Option<UdpSocket>,             // the emulator page's keys
}

fn map(k: &KeyEvent) -> Option<Key> {
    if k.modifiers.contains(KeyModifiers::CONTROL) && k.code == KeyCode::Char('c') {
        return Some(Key::Quit);
    }
    Some(match k.code {
        KeyCode::Left | KeyCode::Char('a') | KeyCode::Char('h') => Key::Left,
        KeyCode::Right | KeyCode::Char('d') | KeyCode::Char('l') => Key::Right,
        KeyCode::Up | KeyCode::Char('w') | KeyCode::Char('k') => Key::Up,
        KeyCode::Down | KeyCode::Char('s') | KeyCode::Char('j') => Key::Down,
        KeyCode::Char('z') => Key::A,
        KeyCode::Char('x') | KeyCode::Char('b') => Key::B,
        KeyCode::Char(' ') => Key::Space,
        KeyCode::Char('c') | KeyCode::Char('v') => Key::Hold,
        KeyCode::Enter => Key::Start,
        KeyCode::Char('p') => Key::Pause,
        KeyCode::Char('q') | KeyCode::Esc => Key::Quit,
        KeyCode::Char('m') => Key::Home,
        KeyCode::Char('-') => Key::VolDown,
        KeyCode::Char('+') | KeyCode::Char('=') => Key::VolUp,
        KeyCode::Char('0') => Key::Mute,
        _ => return None,
    })
}

/// a key named by the emulator page (not Quit: a visitor must not stop it)
fn named(s: &str) -> Option<Key> {
    Some(match s {
        "Left" => Key::Left,
        "Right" => Key::Right,
        "Up" => Key::Up,
        "Down" => Key::Down,
        "A" => Key::A,
        "B" => Key::B,
        "Space" => Key::Space,
        "Hold" => Key::Hold,
        "Start" => Key::Start,
        "Pause" => Key::Pause,
        "Home" => Key::Home,
        "VolDown" => Key::VolDown,
        "VolUp" => Key::VolUp,
        "Mute" => Key::Mute,
        _ => return None,
    })
}

const ALL: [Key; NKEYS] =
    [Key::Left, Key::Right, Key::Up, Key::Down, Key::A, Key::B, Key::Space, Key::Hold, Key::Start, Key::Pause, Key::Quit, Key::Home, Key::VolDown, Key::VolUp, Key::Mute];

fn opposite(k: Key) -> Option<Key> {
    match k {
        Key::Left => Some(Key::Right),
        Key::Right => Some(Key::Left),
        Key::Up => Some(Key::Down),
        Key::Down => Some(Key::Up),
        _ => None,
    }
}

impl Input {
    /// raw mode, and the kitty protocol when the terminal has it
    pub fn new() -> io::Result<Input> {
        terminal::enable_raw_mode()?;
        let releases = terminal::supports_keyboard_enhancement().unwrap_or(false);
        if releases {
            execute!(
                io::stdout(),
                PushKeyboardEnhancementFlags(
                    KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES
                        | KeyboardEnhancementFlags::REPORT_EVENT_TYPES
                )
            )?;
        }
        let mut i = Input::pad_only();
        i.releases = releases;
        i.term = true;
        Ok(i)
    }

    /// the controller only (no terminal)
    pub fn pad_only() -> Input {
        Input {
            releases: true,
            term: false,
            until: [None; NKEYS],
            pressed: [false; NKEYS],
            hits: [0; NKEYS],
            pad: Gamepad::new(),
            pad_held: [None; NKEYS],
            pad_any: false,
            pad_active: false,
            net: None,
        }
    }

    /// also take the keys of the emulator's page (UDP KEY_PORT, all interfaces)
    pub fn listen(&mut self) -> io::Result<()> {
        let s = UdpSocket::bind(("0.0.0.0", KEY_PORT))?;
        s.set_nonblocking(true)?;
        self.net = Some(s);
        Ok(())
    }

    pub fn listening(&self) -> bool {
        self.net.is_some()
    }

    /// no keys at all (a game left on its end screen)
    pub fn none() -> Input {
        let mut i = Input::pad_only();
        i.pad = Gamepad::none();
        i
    }

    /// a press as if from a key (e.g. to start a game from a menu)
    pub fn press(&mut self, k: Key) {
        self.pressed[k as usize] = true;
        self.hits[k as usize] += 1;
    }

    /// any controller button pressed since the last call
    pub fn take_any_pad(&mut self) -> bool {
        std::mem::replace(&mut self.pad_any, false)
    }

    /// anything done on the controller (buttons, d-pad, stick) since the last call
    pub fn take_active(&mut self) -> bool {
        std::mem::replace(&mut self.pad_active, false)
    }

    /// reads all pending events
    pub fn poll(&mut self) -> io::Result<()> {
        let now = Instant::now();
        let mut evs = Vec::new();
        let mut any = false;
        self.pad.poll(|k, down| evs.push((k, down)), || any = true);
        if let Some(sock) = &self.net {
            let mut b = [0u8; 64];
            while let Ok(n) = sock.recv(&mut b) {
                let msg = String::from_utf8_lossy(&b[..n]);
                let mut w = msg.split_whitespace();
                let (Some("key"), Some(name), Some(d)) = (w.next(), w.next(), w.next()) else { continue };
                let down = d == "1";
                if name == "all" {
                    // the page lost the focus: everything up
                    evs.extend(ALL.iter().map(|&k| (k, false)));
                } else if let Some(k) = named(name) {
                    if down && !matches!(k, Key::VolDown | Key::VolUp | Key::Mute) {
                        any = true;
                    }
                    evs.push((k, down));
                }
            }
        }
        self.pad_any |= any;
        for (k, down) in evs {
            let i = k as usize;
            if down {
                self.pad_active = true;
                self.pressed[i] = true;
                self.hits[i] += 1;
                self.pad_held[i] = Some(now + PAD_DELAY);
                if let Some(o) = opposite(k) {
                    self.pad_held[o as usize] = None;
                }
            } else {
                self.pad_held[i] = None;
            }
        }
        // the arrows repeat while held
        for k in [Key::Left, Key::Right, Key::Up, Key::Down] {
            let i = k as usize;
            if let Some(t) = self.pad_held[i] {
                if now >= t {
                    self.hits[i] += 1;
                    self.pad_held[i] = Some(now + PAD_REPEAT);
                }
            }
        }
        while self.term && event::poll(Duration::ZERO)? {
            let Event::Key(k) = event::read()? else { continue };
            let Some(key) = map(&k) else { continue };
            let i = key as usize;
            match k.kind {
                KeyEventKind::Release => self.until[i] = None,
                kind => {
                    if kind == KeyEventKind::Press {
                        self.pressed[i] = true;
                    }
                    self.hits[i] += 1;
                    self.until[i] = Some(if self.releases {
                        now + Duration::from_secs(3600)
                    } else if self.until[i].map_or(false, |t| t > now) {
                        now + REPEAT_HOLD
                    } else {
                        now + FIRST_HOLD
                    });
                    if let Some(o) = opposite(key) {
                        self.until[o as usize] = None;
                    }
                }
            }
        }
        Ok(())
    }

    pub fn held(&self, k: Key) -> bool {
        self.pad_held[k as usize].is_some() || self.until[k as usize].map_or(false, |t| t > Instant::now())
    }

    /// pressed since the last call (edge)
    pub fn take(&mut self, k: Key) -> bool {
        std::mem::replace(&mut self.pressed[k as usize], false)
    }

    /// presses and auto-repeats since the last call (one step each, like a
    /// text cursor: for moves that follow the terminal's repeat rate)
    pub fn hits(&mut self, k: Key) -> u32 {
        std::mem::replace(&mut self.hits[k as usize], 0)
    }

    /// forget the edges and counts (e.g. after a scene change)
    pub fn flush(&mut self) {
        self.pressed = [false; NKEYS];
        self.hits = [0; NKEYS];
    }
}

impl Drop for Input {
    fn drop(&mut self) {
        if !self.term {
            return;
        }
        if self.releases {
            let _ = execute!(io::stdout(), PopKeyboardEnhancementFlags);
        }
        let _ = terminal::disable_raw_mode();
    }
}
