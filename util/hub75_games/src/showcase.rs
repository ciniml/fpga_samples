// All the demos in turn, 40 s each with a fade (Space / Enter: the next
// one now). A demo pauses while the others run and goes on from there.
// The arcade also picks one by hand (select / shift) and can hold it.
use crate::gfx::Canvas;
use crate::input::{Input, Key};
use crate::Game;

const LEN: u64 = 40 * 60;
const FADE: u64 = 45;

/// (name, name on the menu, in the rotation)
type Entry = (&'static str, &'static str, bool, Box<dyn Game>);

pub struct Showcase {
    demos: Vec<Entry>,
    idx: usize,
    t: u64,
    /// stay on the current demo (no rotation)
    pub hold: bool,
}

impl Showcase {
    pub fn new(seed: u64, _hi: u64) -> Showcase {
        let demos: Vec<Entry> = vec![
            ("expo", "超エレキ万博", true, Box::new(crate::expo::Expo::new(seed ^ 13, 0))),
            ("clock", "時計", true, Box::new(crate::clock::Clock::new(seed ^ 14, 0))),
            ("fireworks", "花火", true, Box::new(crate::fireworks::Fireworks::new(seed, 0))),
            ("flame", "焚き火とろうそく", true, Box::new(crate::flame::Flame::new(seed ^ 1, 0))),
            ("waterfall", "夜の滝", true, Box::new(crate::waterfall::Waterfall::new(seed ^ 2, 0))),
            ("aurora", "オーロラ", true, Box::new(crate::aurora::Aurora::new(seed ^ 3, 0))),
            ("storm", "雷雨", true, Box::new(crate::storm::Storm::new(seed ^ 4, 0))),
            ("hourglass", "砂時計", true, Box::new(crate::hourglass::Hourglass::new(seed ^ 5, 0))),
            ("matrix", "文字の雨", true, Box::new(crate::matrix::Matrix::new(seed ^ 6, 0))),
            ("lavalamp", "ラバランプ", true, Box::new(crate::lavalamp::LavaLamp::new(seed ^ 7, 0))),
            ("fireflies", "蛍", true, Box::new(crate::fireflies::Fireflies::new(seed ^ 8, 0))),
            ("life", "ライフゲーム", true, Box::new(crate::life::Life::new(seed ^ 9, 0))),
            ("fractal", "フラクタル", true, Box::new(crate::fractal::Fractal::new(seed ^ 10, 0))),
            ("fountain", "噴水ショー", true, Box::new(crate::fountain::Fountain::new(seed ^ 11, 0))),
            ("aquarium", "水槽", true, Box::new(crate::aquarium::Aquarium::new(seed ^ 12, 0))),
            // about 2 minutes of its own: by hand only
            ("explain", "しくみ解説", false, Box::new(crate::explain::Explain::new(seed ^ 15, 0))),
        ];
        Showcase { demos, idx: 0, t: 0, hold: false }
    }

    /// the names on the menu
    pub fn names(&self) -> Vec<&'static str> {
        self.demos.iter().map(|d| d.1).collect()
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

    /// a demo of the rotation picked at random (`r` a random number)
    pub fn random(&mut self, r: u64) {
        let list: Vec<usize> = (0..self.demos.len()).filter(|&i| self.demos[i].2 && i != self.idx).collect();
        self.select(list[(r % list.len() as u64) as usize]);
    }

    /// the next (d = 1) or previous (d = -1) demo now
    pub fn shift(&mut self, d: i32) {
        let n = self.demos.len() as i32;
        let mut i = self.idx as i32;
        loop {
            i = (i + d).rem_euclid(n);
            // in the rotation, skip what is by hand only
            if self.hold || self.demos[i as usize].2 {
                break;
            }
        }
        self.select(i as usize);
    }
}

impl Game for Showcase {
    fn step(&mut self, inp: Option<&mut Input>) {
        let skip = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        if skip && self.t < LEN - FADE {
            self.t = LEN - FADE;
        }
        self.t += 1;
        if self.hold {
            self.t = self.t.min(FADE);
        }
        if self.t >= LEN {
            self.shift(1);
        }
        crate::audio::set_fade((self.t.min(LEN - self.t) as f32 / FADE as f32).min(1.0));
        self.demos[self.idx].3.step(None);
    }
    fn draw(&self, c: &mut Canvas) {
        self.demos[self.idx].3.draw(c);
        let f = (self.t.min(LEN - self.t) as f32 / FADE as f32).min(1.0);
        if f < 1.0 {
            for p in &mut c.px {
                for v in p.iter_mut() {
                    *v = (*v as f32 * f) as u8;
                }
            }
        }
    }
    fn status(&self) -> String {
        let d = &self.demos[self.idx];
        format!("{}: {}", d.0, d.3.status())
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
