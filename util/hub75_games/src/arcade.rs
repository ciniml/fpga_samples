// The booth's arcade: the demos run (showcase) until someone presses a
// button on the game controller; then a menu of the four games (up / down
// to choose, cross / circle / options to play; the PS button leaves a
// game for the menu, and the menu for the demos). Back to the demos 10 s
// after a game is over (unless it is started again), or after 20 s
// without a press in the menu / 45 s in a game. The high scores are kept
// in ~/.hub75_<game>_hi as when the games run alone.
use crate::audio;
use crate::fx::{new_buf, to_canvas, Col};
use crate::gfx::{Canvas, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};
use crate::showcase::Showcase;
use crate::Game;

const MENU_IDLE: u32 = 20 * 60;
const PLAY_IDLE: u32 = 45 * 60;
const OVER_WAIT: u32 = 10 * 60;

/// (file name, menu name)
const GAMES: [(&str, &str); 4] =
    [("stg", "シューティング"), ("blocks", "落ちものパズル"), ("bricks", "ブロックくずし"), ("invaders", "宇宙人げきたい")];

#[derive(PartialEq, Clone, Copy)]
enum Mode {
    Attract,
    Menu,
    Play,
}

pub struct Arcade {
    show: Showcase,
    mode: Mode,
    sel: usize,
    game: Option<Box<dyn Game>>,
    idle: u32,
    over: u32,
    play_t: u32, // ticks since the game started
    tick: u64,
    seed: u64,
    hi: [u64; 4],
}

fn hi_path(name: &str) -> std::path::PathBuf {
    std::env::var_os("HOME").map(std::path::PathBuf::from).unwrap_or_default().join(format!(".hub75_{}_hi", name))
}

impl Arcade {
    pub fn new(seed: u64, _hi: u64) -> Arcade {
        let hi = GAMES.map(|(n, _)| std::fs::read_to_string(hi_path(n)).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0));
        Arcade { show: Showcase::new(seed, 0), mode: Mode::Attract, sel: 0, game: None, idle: 0, over: 0, play_t: 0, tick: 0, seed, hi }
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
        if m != Mode::Play {
            // keep the high score of the game left
            if let Some(g) = self.game.take() {
                let k = self.sel;
                if g.hi() > self.hi[k] {
                    self.hi[k] = g.hi();
                    let _ = std::fs::write(hi_path(GAMES[k].0), self.hi[k].to_string());
                }
            }
        }
        self.mode = m;
        self.idle = 0;
        self.over = 0;
        self.play_t = 0;
        audio::new_scene();
        audio::set_fade(1.0);
    }
}

impl Game for Arcade {
    fn step(&mut self, inp: Option<&mut Input>) {
        self.tick += 1;
        let Some(inp) = inp else {
            // no input at all (--auto): just the demos
            self.show.step(None);
            return;
        };
        let any = inp.take_any_pad();
        self.idle = if any { 0 } else { self.idle + 1 };
        match self.mode {
            Mode::Attract => {
                if any || inp.take(Key::Start) {
                    inp.flush();
                    self.to(Mode::Menu);
                    audio::sfx::blip(1046.5, 0.05);
                } else {
                    self.show.step(None);
                }
            }
            Mode::Menu if inp.take(Key::Home) => {
                self.to(Mode::Attract);
                audio::sfx::blip(523.3, 0.05);
            }
            Mode::Play if inp.take(Key::Home) => {
                inp.flush();
                self.to(Mode::Menu);
                audio::sfx::blip(523.3, 0.05);
            }
            Mode::Menu => {
                let (up, down) = (inp.hits(Key::Up), inp.hits(Key::Down));
                if up + down > 0 {
                    self.sel = (self.sel as i32 + down as i32 - up as i32).rem_euclid(GAMES.len() as i32) as usize;
                    audio::sfx::blip(880.0, 0.04);
                }
                if inp.take(Key::Space) | inp.take(Key::B) | inp.take(Key::Start) {
                    inp.flush();
                    let g = self.make(self.sel);
                    self.to(Mode::Play);
                    self.game = Some(g);
                    inp.press(Key::Start); // past the game's title screen
                } else if self.idle > MENU_IDLE {
                    self.to(Mode::Attract);
                }
            }
            Mode::Play => {
                let g = self.game.as_mut().unwrap();
                g.step(Some(inp));
                self.play_t += 1;
                self.over = if g.over() { self.over + 1 } else { 0 };
                if self.over > OVER_WAIT || self.idle > PLAY_IDLE {
                    self.to(Mode::Attract);
                }
            }
        }
    }

    fn draw(&self, c: &mut Canvas) {
        match self.mode {
            Mode::Attract => {
                self.show.draw(c);
                // a dark band with the invitation, blinking
                if self.tick / 40 % 3 != 2 {
                    let mut buf: Vec<Col> = new_buf();
                    jp::draw_centre(&mut buf, Font::S12, "ボタンでゲーム開始", 176, [1.0, 0.85, 0.3]);
                    for y in 172..190 {
                        for x in 0..W {
                            let b = buf[y * W + x];
                            let p = &mut c.px[y * W + x];
                            *p = if b[0] > 0.0 { [(b[0] * 255.0) as u8, (b[1] * 255.0) as u8, (b[2] * 255.0) as u8] } else { [p[0] / 5, p[1] / 5, p[2] / 5] };
                        }
                    }
                }
            }
            Mode::Menu => {
                let mut buf = new_buf();
                jp::draw_centre(&mut buf, Font::B16, "ゲームをえらぶ", 4, [1.0, 1.0, 1.0]);
                for (k, (_, name)) in GAMES.iter().enumerate() {
                    let y = 32 + k as i32 * 34;
                    let on = k == self.sel;
                    if on {
                        let pulse = 0.6 + 0.4 * (self.tick as f32 * 0.15).sin().abs();
                        for yy in y - 2..y + 31 {
                            for xx in 2..W as i32 - 2 {
                                let edge = yy == y - 2 || yy == y + 30 || xx == 2 || xx == W as i32 - 3;
                                buf[yy as usize * W + xx as usize] = if edge { [0.3 * pulse, 0.85 * pulse, pulse] } else { [0.02, 0.06, 0.12] };
                            }
                        }
                    }
                    let col = if on { [1.0, 0.85, 0.3] } else { [0.5, 0.55, 0.65] };
                    jp::draw(&mut buf, Font::B16, name, 8, y, col);
                    let hi = format!("ハイスコア {}", self.hi[k]);
                    jp::draw(&mut buf, Font::S12, &hi, 8, y + 17, if on { [0.8, 0.9, 1.0] } else { [0.35, 0.4, 0.5] });
                }
                jp::draw_centre(&mut buf, Font::S12, "十字 選択  × 決定", 166, [0.4, 0.9, 1.0]);
                jp::draw_centre(&mut buf, Font::S12, "PSボタン ゲーム終了", 180, [0.4, 0.5, 0.6]);
                to_canvas(&buf, c, 1.0, 1.4);
            }
            Mode::Play => {
                self.game.as_ref().unwrap().draw(c);
                // the first seconds: how to leave
                if self.play_t < 240 && self.tick / 30 % 4 != 3 {
                    let mut buf: Vec<Col> = new_buf();
                    jp::draw_centre(&mut buf, Font::S12, "PSボタン ゲーム終了", 178, [0.9, 0.9, 1.0]);
                    for y in 175..191 {
                        for x in 0..W {
                            let b = buf[y * W + x];
                            let p = &mut c.px[y * W + x];
                            *p = if b[0] > 0.0 { [(b[0] * 255.0) as u8, (b[1] * 255.0) as u8, (b[2] * 255.0) as u8] } else { [p[0] / 4, p[1] / 4, p[2] / 4] };
                        }
                    }
                }
            }
        }
    }

    fn status(&self) -> String {
        match self.mode {
            Mode::Attract => format!("demos  {}", self.show.status()),
            Mode::Menu => format!("menu  {}", GAMES[self.sel].0),
            Mode::Play => format!("{}  {}", GAMES[self.sel].0, self.game.as_ref().unwrap().status()),
        }
    }
    fn hi(&self) -> u64 {
        0
    }
    /// the games get their colours as drawn (inverse board gamma), the demos
    /// and the menu go through the demo gamma
    fn needs_keys(&self) -> bool {
        self.mode == Mode::Play
    }
    fn sound(&self) -> bool {
        true
    }
}
