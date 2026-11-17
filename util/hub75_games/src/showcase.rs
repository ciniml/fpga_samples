// The demos in turn by a playlist (each its time, with a fade; Space /
// Enter: the next one now). A demo pauses while the others run and goes on
// from there, unless its playlist entry says to start it from the top
// (the explanations). The arcade also picks one by hand (select / shift)
// and can hold it.
//
// Playlists (--playlist): "expo" (ELEKI EXPO 2026: the eye candy, 40 s
// each), "edgetech" (EdgeTech+ 2026 at the CQ booth: the booth guide and
// the technical explanations between some eye candy), or a file of lines
// "<demo> <seconds> [start]" (# for comments).
use crate::gfx::Canvas;
use crate::input::{Input, Key};
use crate::Game;
use std::sync::Mutex;

const FADE: u64 = 45;

type Make = fn(u64) -> Box<dyn Game>;

/// (name, name on the menu, how to make it)
static DEMOS: [(&str, &str, Make); 19] = [
    ("expo", "超エレキ万博", |s| Box::new(crate::expo::Expo::new(s ^ 13, 0))),
    ("etbooth", "EdgeTech+案内", |s| Box::new(crate::etbooth::EtBooth::new(s ^ 16, 0))),
    ("bento", "お隣のお弁当", |s| Box::new(crate::bento::Bento::new(s ^ 18, 0))),
    ("techdeep", "技術解説", |s| Box::new(crate::techdeep::TechDeep::new(s ^ 17, 0))),
    ("explain", "しくみ解説", |s| Box::new(crate::explain::Explain::new(s ^ 15, 0))),
    ("clock", "時計", |s| Box::new(crate::clock::Clock::new(s ^ 14, 0))),
    ("fireworks", "花火", |s| Box::new(crate::fireworks::Fireworks::new(s, 0))),
    ("flame", "焚き火とろうそく", |s| Box::new(crate::flame::Flame::new(s ^ 1, 0))),
    ("waterfall", "夜の滝", |s| Box::new(crate::waterfall::Waterfall::new(s ^ 2, 0))),
    ("aurora", "オーロラ", |s| Box::new(crate::aurora::Aurora::new(s ^ 3, 0))),
    ("storm", "雷雨", |s| Box::new(crate::storm::Storm::new(s ^ 4, 0))),
    ("hourglass", "砂時計", |s| Box::new(crate::hourglass::Hourglass::new(s ^ 5, 0))),
    ("matrix", "文字の雨", |s| Box::new(crate::matrix::Matrix::new(s ^ 6, 0))),
    ("lavalamp", "ラバランプ", |s| Box::new(crate::lavalamp::LavaLamp::new(s ^ 7, 0))),
    ("fireflies", "蛍", |s| Box::new(crate::fireflies::Fireflies::new(s ^ 8, 0))),
    ("life", "ライフゲーム", |s| Box::new(crate::life::Life::new(s ^ 9, 0))),
    ("fractal", "フラクタル", |s| Box::new(crate::fractal::Fractal::new(s ^ 10, 0))),
    ("fountain", "噴水ショー", |s| Box::new(crate::fountain::Fountain::new(s ^ 11, 0))),
    ("aquarium", "水槽", |s| Box::new(crate::aquarium::Aquarium::new(s ^ 12, 0))),
];

/// ELEKI EXPO 2026: the eye candy and the event's own screen, 40 s each
const EXPO: &str = "
expo 40
clock 40
fireworks 40
flame 40
waterfall 40
aurora 40
storm 40
hourglass 40
matrix 40
lavalamp 40
fireflies 40
life 40
fractal 40
fountain 40
aquarium 40
";

/// EdgeTech+ 2026 (CQ booth DF-05): the booth guide about every 4 minutes,
/// the technical explanations from their start, eye candy between, and
/// the bento shop next door as a joke (about 10 minutes a round)
const EDGETECH: &str = "
etbooth 60 start
techdeep 120 start
fractal 30
fireworks 25
etbooth 60 start
explain 145 start
aurora 30
life 30
matrix 25
clock 20
bento 48 start
";

/// a playlist entry: the demo, its time in ticks, from its start each time
#[derive(Clone, Copy, Debug)]
pub struct Item {
    demo: usize,
    len: u64,
    start: bool,
}

/// a playlist by name (expo / edgetech) or from a file
pub fn playlist(name: &str) -> Result<Vec<Item>, String> {
    let text = match name {
        "expo" => EXPO.to_string(),
        "edgetech" => EDGETECH.to_string(),
        f => std::fs::read_to_string(f).map_err(|e| format!("--playlist {}: {} (or expo / edgetech)", f, e))?,
    };
    let mut list = Vec::new();
    for (n, line) in text.lines().enumerate() {
        let line = line.split('#').next().unwrap().trim();
        if line.is_empty() {
            continue;
        }
        let w: Vec<&str> = line.split_whitespace().collect();
        let bad = || format!("playlist {} line {}: \"{}\" (<demo> <seconds> [start])", name, n + 1, line);
        let demo = DEMOS.iter().position(|d| d.0 == w[0]).ok_or_else(|| {
            format!("{}: no demo {} ({})", bad(), w[0], DEMOS.iter().map(|d| d.0).collect::<Vec<_>>().join(" "))
        })?;
        let secs: f32 = w.get(1).and_then(|s| s.parse().ok()).filter(|&s: &f32| s >= 3.0).ok_or_else(bad)?;
        let start = match w.get(2) {
            None => false,
            Some(&"start") => true,
            _ => return Err(bad()),
        };
        list.push(Item { demo, len: (secs * 60.0) as u64, start });
    }
    if list.is_empty() {
        return Err(format!("playlist {}: empty", name));
    }
    Ok(list)
}

static PLAYLIST: Mutex<Option<Vec<Item>>> = Mutex::new(None);

/// the playlist the showcase (and the arcade's) will use
pub fn set_playlist(name: &str) -> Result<(), String> {
    *PLAYLIST.lock().unwrap() = Some(playlist(name)?);
    Ok(())
}

pub struct Showcase {
    demos: Vec<Box<dyn Game>>,
    list: Vec<Item>,
    pos: usize,
    idx: usize,
    t: u64,
    len: u64,
    /// stay on the current demo (no rotation)
    pub hold: bool,
    seed: u64,
}

impl Showcase {
    pub fn new(seed: u64, _hi: u64) -> Showcase {
        let list = PLAYLIST.lock().unwrap().clone().unwrap_or_else(|| playlist("expo").unwrap());
        let demos = DEMOS.iter().map(|d| (d.2)(seed)).collect();
        let mut s = Showcase { demos, list, pos: 0, idx: 0, t: 0, len: 0, hold: false, seed };
        s.go(0);
        s
    }

    /// the names on the menu
    pub fn names(&self) -> Vec<&'static str> {
        DEMOS.iter().map(|d| d.1).collect()
    }

    pub fn current(&self) -> usize {
        self.idx
    }

    /// show demo i now (fading in)
    pub fn select(&mut self, i: usize) {
        self.idx = i % self.demos.len();
        self.t = 0;
        crate::audio::new_scene();
    }

    /// the current demo again from its start (fading in)
    pub fn restart(&mut self) {
        self.demos[self.idx] = (DEMOS[self.idx].2)(self.seed);
        self.select(self.idx);
    }

    /// playlist entry p now
    fn go(&mut self, p: usize) {
        self.pos = p % self.list.len();
        let it = self.list[self.pos];
        self.len = it.len.max(2 * FADE + 1);
        self.idx = it.demo;
        if it.start {
            self.restart();
        } else {
            self.select(it.demo);
        }
    }

    /// a playlist entry picked at random, not the current one (`r` a random number)
    pub fn random(&mut self, r: u64) {
        let n = self.list.len();
        if n < 2 {
            self.go(0);
            return;
        }
        let p = (self.pos + 1 + (r % (n as u64 - 1)) as usize) % n;
        self.go(p);
    }

    /// the next (d = 1) or previous (d = -1): in the playlist, or (held) any demo
    pub fn shift(&mut self, d: i32) {
        if self.hold {
            self.select((self.idx as i32 + d).rem_euclid(self.demos.len() as i32) as usize);
        } else {
            self.go((self.pos as i32 + d).rem_euclid(self.list.len() as i32) as usize);
        }
    }

    fn fade(&self) -> f32 {
        if self.hold {
            return (self.t as f32 / FADE as f32).min(1.0);
        }
        (self.t.min(self.len.saturating_sub(self.t)) as f32 / FADE as f32).min(1.0)
    }
}

impl Game for Showcase {
    fn step(&mut self, inp: Option<&mut Input>) {
        let skip = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        if skip && !self.hold && self.t < self.len - FADE {
            self.t = self.len - FADE;
        }
        self.t += 1;
        if self.hold {
            self.t = self.t.min(FADE);
        } else if self.t >= self.len {
            self.go(self.pos + 1);
        }
        crate::audio::set_fade(self.fade());
        self.demos[self.idx].step(None);
    }
    fn draw(&self, c: &mut Canvas) {
        self.demos[self.idx].draw(c);
        let f = self.fade();
        if f < 1.0 {
            for p in &mut c.px {
                for v in p.iter_mut() {
                    *v = (*v as f32 * f) as u8;
                }
            }
        }
    }
    fn status(&self) -> String {
        format!("{} [{}/{}]: {}", DEMOS[self.idx].0, self.pos + 1, self.list.len(), self.demos[self.idx].status())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
    fn sound(&self) -> bool {
        true
    }
}
