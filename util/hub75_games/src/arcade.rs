// The booth's arcade: the demos run (showcase; left / right on the
// controller: the previous / next one) until someone presses a button;
// then a menu of the four games and "pick a demo" (up / down to choose,
// cross / circle / options to go; the PS button goes back: from a game to
// the menu, from the menu to the demos). A demo picked by hand stays on
// (left / right: the others) until PS or 5 min without a press. A game
// runs to its own end (3 minutes, or the stages); back to the demos 10 s
// after it is over (unless it is started again), or after 20 s without a
// press in a menu. The high scores
// are kept in ~/.hub75_<game>_hi as when the games run alone. Volume: L2 /
// R2, mute: L3 / R3 (lib.rs, everywhere).
use crate::audio;
use crate::fx::{new_buf, to_canvas, Col};
use crate::gfx::{Canvas, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};
use crate::showcase::Showcase;
use crate::Game;

const MENU_IDLE: u32 = 20 * 60;
const OVER_WAIT: u32 = 10 * 60;
const DEMO_IDLE: u32 = 5 * 60 * 60;
const HINT: u32 = 240; // ticks the hint stays at the bottom
const DEMOS_ITEM: usize = 4; // the menu entry after the games

/// (file name, menu name)
const GAMES: [(&str, &str); 4] =
    [("stg", "シューティング"), ("blocks", "落ちものパズル"), ("bricks", "ブロックくずし"), ("invaders", "宇宙人げきたい")];

#[derive(PartialEq, Clone, Copy)]
enum Mode {
    Attract,
    Menu,
    DemoMenu,
    Demo,
    Play,
}

pub struct Arcade {
    show: Showcase,
    names: Vec<&'static str>,
    mode: Mode,
    sel: usize,  // menu: a game or DEMOS_ITEM
    dsel: usize, // demo menu
    game: Option<Box<dyn Game>>,
    idle: u32,
    over: u32,
    mode_t: u32, // ticks in this mode
    tick: u64,
    seed: u64,
    hi: [u64; 4],
}

fn hi_path(name: &str) -> std::path::PathBuf {
    std::env::var_os("HOME").map(std::path::PathBuf::from).unwrap_or_default().join(format!(".hub75_{}_hi", name))
}

/// a line of help at the bottom over a darkened band
fn hint(c: &mut Canvas, s: &str) {
    let mut buf: Vec<Col> = new_buf();
    jp::draw_centre(&mut buf, Font::S12, s, 178, [0.9, 0.9, 1.0]);
    for y in 175..191 {
        for x in 0..W {
            let b = buf[y * W + x];
            let p = &mut c.px[y * W + x];
            *p = if b[0] > 0.0 { [(b[0] * 255.0) as u8, (b[1] * 255.0) as u8, (b[2] * 255.0) as u8] } else { [p[0] / 4, p[1] / 4, p[2] / 4] };
        }
    }
}

/// the highlight box of a menu entry
fn select_box(buf: &mut [Col], y0: i32, y1: i32, tick: u64) {
    let pulse = 0.6 + 0.4 * (tick as f32 * 0.15).sin().abs();
    for yy in y0..y1 {
        for xx in 2..W as i32 - 2 {
            let edge = yy == y0 || yy == y1 - 1 || xx == 2 || xx == W as i32 - 3;
            buf[yy as usize * W + xx as usize] = if edge { [0.3 * pulse, 0.85 * pulse, pulse] } else { [0.02, 0.06, 0.12] };
        }
    }
}

impl Arcade {
    pub fn new(seed: u64, _hi: u64) -> Arcade {
        let hi = GAMES.map(|(n, _)| std::fs::read_to_string(hi_path(n)).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0));
        let show = Showcase::new(seed, 0);
        let names = show.names();
        Arcade { show, names, mode: Mode::Attract, sel: 0, dsel: 0, game: None, idle: 0, over: 0, mode_t: 0, tick: 0, seed, hi }
    }

    fn make(&mut self, k: usize) -> Box<dyn Game> {
        self.seed = self.seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let (s, hi) = (self.seed, self.hi[k]);
        match k {
            0 => Box::new(crate::stg::Stg::new(s, hi)),
            1 => Box::new(crate::blocks::Blocks::new(s, hi)),
            2 => Box::new(crate::bricks::Bricks::new(s, hi)),
            _ => Box::new(crate::invaders::Invaders::new(s, hi)),
        }
    }

    fn to(&mut self, m: Mode) {
        // keep the high score of the game left
        if let Some(g) = self.game.take() {
            let k = self.sel;
            if g.hi() > self.hi[k] {
                self.hi[k] = g.hi();
                let _ = std::fs::write(hi_path(GAMES[k].0), self.hi[k].to_string());
            }
        }
        self.show.hold = m == Mode::Demo;
        self.mode = m;
        self.idle = 0;
        self.over = 0;
        self.mode_t = 0;
        audio::new_scene();
        audio::set_fade(1.0);
    }

    /// up / down in a list of n
    fn choose(inp: &mut Input, sel: usize, n: usize) -> usize {
        let (up, down) = (inp.hits(Key::Up), inp.hits(Key::Down));
        if up + down == 0 {
            return sel;
        }
        audio::sfx::blip(880.0, 0.04);
        (sel as i32 + down as i32 - up as i32).rem_euclid(n as i32) as usize
    }

    fn go(inp: &mut Input) -> bool {
        inp.take(Key::Space) | inp.take(Key::B) | inp.take(Key::Start)
    }

    /// left / right: the previous / next demo
    fn flip(&mut self, inp: &mut Input) {
        let d = inp.take(Key::Right) as i32 - inp.take(Key::Left) as i32;
        if d != 0 {
            self.show.shift(d);
        }
    }
}

impl Game for Arcade {
    fn step(&mut self, inp: Option<&mut Input>) {
        self.tick += 1;
        self.mode_t += 1;
        let Some(inp) = inp else {
            // no input at all (--auto): just the demos
            self.show.step(None);
            return;
        };
        let any = inp.take_any_pad();
        self.idle = if inp.take_active() { 0 } else { self.idle + 1 };
        let home = inp.take(Key::Home);
        match self.mode {
            Mode::Attract => {
                self.flip(inp);
                if any || inp.take(Key::Start) {
                    inp.flush();
                    self.to(Mode::Menu);
                    audio::sfx::blip(1046.5, 0.05);
                } else {
                    self.show.step(None);
                }
            }
            Mode::Menu => {
                self.sel = Self::choose(inp, self.sel, GAMES.len() + 1);
                if home || self.idle > MENU_IDLE {
                    self.to(Mode::Attract);
                    audio::sfx::blip(523.3, 0.05);
                } else if Self::go(inp) {
                    inp.flush();
                    if self.sel == DEMOS_ITEM {
                        self.dsel = self.show.current();
                        self.to(Mode::DemoMenu);
                    } else {
                        let g = self.make(self.sel);
                        self.to(Mode::Play);
                        self.game = Some(g);
                        inp.press(Key::Start); // past the game's title screen
                    }
                }
            }
            Mode::DemoMenu => {
                self.dsel = Self::choose(inp, self.dsel, self.names.len());
                if home {
                    self.to(Mode::Menu);
                    audio::sfx::blip(523.3, 0.05);
                } else if self.idle > MENU_IDLE {
                    self.to(Mode::Attract);
                } else if Self::go(inp) {
                    inp.flush();
                    self.to(Mode::Demo);
                    self.show.select(self.dsel);
                }
            }
            Mode::Demo => {
                self.flip(inp);
                if home {
                    self.dsel = self.show.current();
                    self.to(Mode::DemoMenu);
                    audio::sfx::blip(523.3, 0.05);
                } else if self.idle > DEMO_IDLE {
                    self.to(Mode::Attract);
                } else {
                    self.show.step(None);
                }
            }
            Mode::Play => {
                if home {
                    inp.flush();
                    self.to(Mode::Menu);
                    audio::sfx::blip(523.3, 0.05);
                    return;
                }
                let g = self.game.as_mut().unwrap();
                g.step(Some(inp));
                self.over = if g.over() { self.over + 1 } else { 0 };
                if self.over > OVER_WAIT {
                    self.to(Mode::Attract);
                }
            }
        }
    }

    fn draw(&self, c: &mut Canvas) {
        let blink = self.tick / 30 % 4 != 3;
        match self.mode {
            Mode::Attract => {
                self.show.draw(c);
                if self.tick / 40 % 3 != 2 {
                    hint(c, "ボタンでゲーム開始");
                }
            }
            Mode::Menu => {
                let mut buf = new_buf();
                jp::draw_centre(&mut buf, Font::B16, "ゲームをえらぶ", 2, [1.0, 1.0, 1.0]);
                for k in 0..=GAMES.len() {
                    let y = 22 + k as i32 * 30;
                    let on = k == self.sel;
                    if on {
                        select_box(&mut buf, y - 2, y + 29, self.tick);
                    }
                    let col = if on { [1.0, 0.85, 0.3] } else { [0.5, 0.55, 0.65] };
                    if k == DEMOS_ITEM {
                        jp::draw(&mut buf, Font::B16, "デモをえらぶ", 8, y + 5, if on { [0.4, 0.9, 1.0] } else { col });
                    } else {
                        jp::draw(&mut buf, Font::B16, GAMES[k].1, 8, y, col);
                        let hi = format!("ハイスコア {}", self.hi[k]);
                        jp::draw(&mut buf, Font::S12, &hi, 8, y + 17, if on { [0.8, 0.9, 1.0] } else { [0.35, 0.4, 0.5] });
                    }
                }
                jp::draw_centre(&mut buf, Font::S12, "× 決定  PS デモへ", 177, [0.4, 0.9, 1.0]);
                to_canvas(&buf, c, 1.0, 1.4);
            }
            Mode::DemoMenu => {
                let mut buf = new_buf();
                jp::draw_centre(&mut buf, Font::B16, "デモをえらぶ", 2, [1.0, 1.0, 1.0]);
                let (n, rows) = (self.names.len(), 10);
                let first = self.dsel.saturating_sub(4).min(n.saturating_sub(rows));
                for (r, k) in (first..n.min(first + rows)).enumerate() {
                    let y = 24 + r as i32 * 14;
                    let on = k == self.dsel;
                    if on {
                        select_box(&mut buf, y - 1, y + 13, self.tick);
                    }
                    let col = if on { [1.0, 0.85, 0.3] } else { [0.55, 0.6, 0.7] };
                    jp::draw(&mut buf, Font::S12, self.names[k], 10, y, col);
                }
                // more above / below
                if first > 0 {
                    jp::draw(&mut buf, Font::S12, "^", 118, 24, [0.4, 0.5, 0.6]);
                }
                if first + rows < n {
                    jp::draw(&mut buf, Font::S12, "v", 118, 150, [0.4, 0.5, 0.6]);
                }
                jp::draw_centre(&mut buf, Font::S12, "× 決定  PS 戻る", 172, [0.4, 0.9, 1.0]);
                to_canvas(&buf, c, 1.0, 1.4);
            }
            Mode::Demo => {
                self.show.draw(c);
                if self.mode_t < HINT && blink {
                    hint(c, "左右 切替  PS 戻る");
                }
            }
            Mode::Play => {
                self.game.as_ref().unwrap().draw(c);
                if self.mode_t < HINT && blink {
                    hint(c, "PSボタン ゲーム終了");
                }
            }
        }
    }

    fn status(&self) -> String {
        match self.mode {
            Mode::Attract => format!("demos  {}", self.show.status()),
            Mode::Menu => format!("menu  {}", if self.sel == DEMOS_ITEM { "demos" } else { GAMES[self.sel].0 }),
            Mode::DemoMenu => format!("demo menu  {}", self.names[self.dsel]),
            Mode::Demo => format!("demo  {}", self.show.status()),
            Mode::Play => format!("{}  {}", GAMES[self.sel].0, self.game.as_ref().unwrap().status()),
        }
    }
    fn hi(&self) -> u64 {
        0
    }
    /// the games get their colours as drawn (inverse board gamma), the demos
    /// and the menus go through the demo gamma
    fn needs_keys(&self) -> bool {
        self.mode == Mode::Play
    }
    fn sound(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// the menus draw (HUB75_SNAP=dir: also as PPM files)
    #[test]
    fn menus() {
        let mut a = Arcade::new(1, 0);
        for (m, name) in [(Mode::Menu, "menu"), (Mode::DemoMenu, "demomenu")] {
            a.mode = m;
            a.sel = 1;
            a.dsel = 12;
            let mut c = Canvas::new();
            a.draw(&mut c);
            if let Some(dir) = std::env::var_os("HUB75_SNAP") {
                let mut f = Vec::from(format!("P6\n{} {}\n255\n", W, crate::gfx::H).as_bytes());
                c.px.iter().for_each(|p| f.extend_from_slice(p));
                std::fs::write(std::path::Path::new(&dir).join(format!("{}.ppm", name)), f).unwrap();
            }
        }
    }
}
