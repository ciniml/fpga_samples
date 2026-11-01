// All the demos in turn, 40 s each with a fade (Space / Enter: the next
// one now). A demo pauses while the others run and goes on from there.
use crate::gfx::Canvas;
use crate::input::{Input, Key};
use crate::Game;

const LEN: u64 = 40 * 60;
const FADE: u64 = 45;

pub struct Showcase {
    demos: Vec<(&'static str, Box<dyn Game>)>,
    idx: usize,
    t: u64,
}

impl Showcase {
    pub fn new(seed: u64, _hi: u64) -> Showcase {
        let demos: Vec<(&'static str, Box<dyn Game>)> = vec![
            ("expo", Box::new(crate::expo::Expo::new(seed ^ 13, 0))),
            ("clock", Box::new(crate::clock::Clock::new(seed ^ 14, 0))),
            ("fireworks", Box::new(crate::fireworks::Fireworks::new(seed, 0))),
            ("flame", Box::new(crate::flame::Flame::new(seed ^ 1, 0))),
            ("waterfall", Box::new(crate::waterfall::Waterfall::new(seed ^ 2, 0))),
            ("aurora", Box::new(crate::aurora::Aurora::new(seed ^ 3, 0))),
            ("storm", Box::new(crate::storm::Storm::new(seed ^ 4, 0))),
            ("hourglass", Box::new(crate::hourglass::Hourglass::new(seed ^ 5, 0))),
            ("matrix", Box::new(crate::matrix::Matrix::new(seed ^ 6, 0))),
            ("lavalamp", Box::new(crate::lavalamp::LavaLamp::new(seed ^ 7, 0))),
            ("fireflies", Box::new(crate::fireflies::Fireflies::new(seed ^ 8, 0))),
            ("life", Box::new(crate::life::Life::new(seed ^ 9, 0))),
            ("fractal", Box::new(crate::fractal::Fractal::new(seed ^ 10, 0))),
            ("fountain", Box::new(crate::fountain::Fountain::new(seed ^ 11, 0))),
            ("aquarium", Box::new(crate::aquarium::Aquarium::new(seed ^ 12, 0))),
        ];
        Showcase { demos, idx: 0, t: 0 }
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
        if self.t >= LEN {
            self.t = 0;
            self.idx = (self.idx + 1) % self.demos.len();
        }
        self.demos[self.idx].1.step(None);
    }
    fn draw(&self, c: &mut Canvas) {
        self.demos[self.idx].1.draw(c);
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
        let (name, d) = &self.demos[self.idx];
        format!("{}: {}", name, d.status())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
