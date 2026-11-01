// Keyboard from the terminal (works over ssh / tmux).
//
// A game needs "is the key held", which a terminal reports only with the
// kitty keyboard protocol (press / repeat / release events; kitty, WezTerm,
// foot, Ghostty, ...). Elsewhere a held key is only a stream of auto-repeat
// presses: a key counts as held until a short while after its last press
// (longer after the first one, which is followed by the auto-repeat delay),
// and the opposite direction cancels it at once.
use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, KeyboardEnhancementFlags,
    PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use crossterm::{execute, terminal};
use std::io;
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
}
const NKEYS: usize = 11;

const FIRST_HOLD: Duration = Duration::from_millis(550); // > auto-repeat delay
const REPEAT_HOLD: Duration = Duration::from_millis(120); // > auto-repeat period

pub struct Input {
    pub releases: bool, // the terminal reports key releases
    until: [Option<Instant>; NKEYS],
    pressed: [bool; NKEYS], // pressed since the last frame
    hits: [u32; NKEYS],     // presses + auto-repeats since the last frame
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
        _ => return None,
    })
}

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
        Ok(Input { releases, until: [None; NKEYS], pressed: [false; NKEYS], hits: [0; NKEYS] })
    }

    /// reads all pending events
    pub fn poll(&mut self) -> io::Result<()> {
        let now = Instant::now();
        while event::poll(Duration::ZERO)? {
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
        self.until[k as usize].map_or(false, |t| t > Instant::now())
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
        if self.releases {
            let _ = execute!(io::stdout(), PopKeyboardEnhancementFlags);
        }
        let _ = terminal::disable_raw_mode();
    }
}
