// All the demos in turn, 40 s each with a fade (Space / Enter: the next
// one now). A demo pauses while the others run and goes on from there.
// The arcade also picks one by hand (select / shift) and can hold it.
use crate::gfx::Canvas;
use crate::input::{Input, Key};
use crate::Game;

const LEN: u64 = 40 * 60;
const FADE: u64 = 45;

/// (name, name on the menu, in the rotation, how to make it, the demo)
type Entry = (&'static str, &'static str, bool, fn(u64) -> Box<dyn Game>, Box<dyn Game>);

pub struct Showcase {
    demos: Vec<Entry>,
    idx: usize,
    t: u64,
    /// stay on the current demo (no rotation)
    pub hold: bool,
    seed: u64,
}

impl Showcase {
    pub fn new(seed: u64, _hi: u64) -> Showcase {
        let e = |name, jp, rot, make: fn(u64) -> Box<dyn Game>| (name, jp, rot, make, make(seed));
        let demos: Vec<Entry> = vec![
            e("expo", "超エレキ万博", true, |s| Box::new(crate::expo::Expo::new(s ^ 13, 0))),
            e("clock", "時計", true, |s| Box::new(crate::clock::Clock::new(s ^ 14, 0))),
            e("fireworks", "花火", true, |s| Box::new(crate::fireworks::Fireworks::new(s, 0))),
            e("flame", "焚き火とろうそく", true, |s| Box::new(crate::flame::Flame::new(s ^ 1, 0))),
            e("waterfall", "夜の滝", true, |s| Box::new(crate::waterfall::Waterfall::new(s ^ 2, 0))),
            e("aurora", "オーロラ", true, |s| Box::new(crate::aurora::Aurora::new(s ^ 3, 0))),
            e("storm", "雷雨", true, |s| Box::new(crate::storm::Storm::new(s ^ 4, 0))),
            e("hourglass", "砂時計", true, |s| Box::new(crate::hourglass::Hourglass::new(s ^ 5, 0))),
            e("matrix", "文字の雨", true, |s| Box::new(crate::matrix::Matrix::new(s ^ 6, 0))),
            e("lavalamp", "ラバランプ", true, |s| Box::new(crate::lavalamp::LavaLamp::new(s ^ 7, 0))),
            e("fireflies", "蛍", true, |s| Box::new(crate::fireflies::Fireflies::new(s ^ 8, 0))),
            e("life", "ライフゲーム", true, |s| Box::new(crate::life::Life::new(s ^ 9, 0))),
            e("fractal", "フラクタル", true, |s| Box::new(crate::fractal::Fractal::new(s ^ 10, 0))),
            e("fountain", "噴水ショー", true, |s| Box::new(crate::fountain::Fountain::new(s ^ 11, 0))),
            e("aquarium", "水槽", true, |s| Box::new(crate::aquarium::Aquarium::new(s ^ 12, 0))),
            // about 2 minutes of its own: by hand only
            e("explain", "しくみ解説", false, |s| Box::new(crate::explain::Explain::new(s ^ 15, 0))),
        ];
        Showcase { demos, idx: 0, t: 0, hold: false, seed }
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

    /// the current demo again from its start (fading in)
    pub fn restart(&mut self) {
        let d = &mut self.demos[self.idx];
        d.4 = (d.3)(self.seed);
        self.select(self.idx);
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
        self.demos[self.idx].4.step(None);
    }
    fn draw(&self, c: &mut Canvas) {
        self.demos[self.idx].4.draw(c);
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
        format!("{}: {}", d.0, d.4.status())
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
