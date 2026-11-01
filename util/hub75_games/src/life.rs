// Conway's Game of Life on 128x192 (a demo, no game): 64 x 96 cells of
// 2 x 2 pixels (easier to see on the LEDs), wrapping at the edges, 20
// generations a second.
//
// A cell's colour tells its age: newborn cells are white-cyan, then they
// turn through green and blue to deep violet for the old, still parts.
// Dead cells leave a dim red-violet afterglow that fades, so movement shows
// as trails. When the board has settled (the population hardly changes for
// a while) or after 75 s, it is seeded again: a random soup, or a
// few patterns (glider guns, R-pentominoes, acorns) on an empty board.
use crate::fx::{mix, new_buf, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::Rng;

const EVERY: u64 = 3; // ticks per generation
const MAX_GENS: u32 = 1500;
const GW: usize = W / 2;
const GH: usize = H / 2;

const GUN: [&str; 9] = [
    "........................O...........",
    "......................O.O...........",
    "............OO......OO............OO",
    "...........O...O....OO............OO",
    "OO........O.....O...OO..............",
    "OO........O...O.OO....O.O...........",
    "..........O.....O.......O...........",
    "...........O...O....................",
    "............OO......................",
];
const R_PENTO: [&str; 3] = [".OO", "OO.", ".O."];
const ACORN: [&str; 3] = [".O.....", "...O...", "OO..OOO"];

pub struct Life {
    rng: Rng,
    tick: u64,
    age: Vec<u16>,  // 0 dead, else generations alive
    glow: Vec<f32>, // afterglow of dead cells
    gens: u32,
    pops: Vec<usize>,
    fade: f32, // for the reseed
}

impl Life {
    pub fn new(seed: u64, _hi: u64) -> Life {
        let mut g = Life { rng: Rng::new(seed), tick: 0, age: vec![0; GW * GH], glow: vec![0.0; GW * GH], gens: 0, pops: Vec::new(), fade: 1.0 };
        g.seed();
        g
    }

    fn stamp(&mut self, pat: &[&str], x0: usize, y0: usize, flip: bool) {
        for (y, row) in pat.iter().enumerate() {
            for (x, ch) in row.chars().enumerate() {
                if ch == 'O' {
                    let xx = if flip { x0 + row.len() - 1 - x } else { x0 + x };
                    self.age[((y0 + y) % GH) * GW + xx % GW] = 1;
                }
            }
        }
    }

    fn seed(&mut self) {
        self.age.fill(0);
        self.gens = 0;
        self.pops.clear();
        match self.rng.next() % 3 {
            0 => {
                // random soup, denser in blobs
                for i in 0..GW * GH {
                    let (x, y) = ((i % GW) as f32, (i / GW) as f32);
                    let blob = 0.5 + 0.5 * ((x * 0.14).sin() * (y * 0.1).cos());
                    if self.rng.chance(0.12 + 0.25 * blob) {
                        self.age[i] = 1;
                    }
                }
            }
            1 => {
                // two glider guns firing at each other
                self.stamp(&GUN, 2, 8, false);
                self.stamp(&GUN, GW - 38, 76, true);
                self.stamp(&R_PENTO, 30, 46, false);
            }
            _ => {
                for _ in 0..3 {
                    let x = (self.rng.next() % (GW as u64 - 10)) as usize;
                    let y = (self.rng.next() % (GH as u64 - 10)) as usize;
                    if self.rng.chance(0.5) {
                        self.stamp(&ACORN, x, y, false);
                    } else {
                        self.stamp(&R_PENTO, x, y, false);
                    }
                }
            }
        }
    }

    fn generation(&mut self) {
        let mut next = vec![0u16; GW * GH];
        let alive = |a: &Vec<u16>, x: usize, y: usize| (a[y * GW + x] != 0) as u8;
        let mut pop = 0;
        for y in 0..GH {
            let (yu, yd) = ((y + GH - 1) % GH, (y + 1) % GH);
            for x in 0..GW {
                let (xl, xr) = ((x + GW - 1) % GW, (x + 1) % GW);
                let n = alive(&self.age, xl, yu) + alive(&self.age, x, yu) + alive(&self.age, xr, yu)
                    + alive(&self.age, xl, y) + alive(&self.age, xr, y)
                    + alive(&self.age, xl, yd) + alive(&self.age, x, yd) + alive(&self.age, xr, yd);
                let i = y * GW + x;
                let a = self.age[i];
                next[i] = if (a != 0 && (n == 2 || n == 3)) || (a == 0 && n == 3) { a.saturating_add(1).max(1) } else { 0 };
                if a != 0 && next[i] == 0 {
                    self.glow[i] = 1.0;
                }
                pop += (next[i] != 0) as usize;
            }
        }
        self.age = next;
        self.gens += 1;
        self.pops.push(pop);
    }

    /// settled: the population moved less than 3 % over the last 200 generations
    fn settled(&self) -> bool {
        if self.pops.len() < 300 {
            return false;
        }
        let w = &self.pops[self.pops.len() - 200..];
        let (lo, hi) = (w.iter().min().unwrap(), w.iter().max().unwrap());
        (hi - lo) as f32 <= (*hi as f32 * 0.03).max(6.0) || *hi == 0
    }

    fn update(&mut self, reseed: bool) {
        self.tick += 1;
        for g in &mut self.glow {
            *g *= 0.93;
        }
        if self.fade < 1.0 {
            // fading out for a reseed, then in again
            self.fade -= 0.03;
            if self.fade <= 0.0 {
                self.seed();
                self.fade = 1.0;
                self.glow.fill(0.0);
            }
            return;
        }
        if self.tick % EVERY == 0 {
            self.generation();
        }
        if reseed || self.settled() || self.gens >= MAX_GENS {
            self.fade = 0.999;
        }
    }

    fn render(&self, buf: &mut [Col]) {
        for i in 0..W * H {
            let j = (i / W / 2) * GW + (i % W) / 2;
            let a = self.age[j];
            buf[i] = if a != 0 {
                let k = ((a - 1) as f32 / 40.0).min(1.0);
                if k < 0.3 {
                    mix([0.85, 1.0, 1.0], [0.1, 1.0, 0.5], k / 0.3)
                } else if k < 0.7 {
                    mix([0.1, 1.0, 0.5], [0.1, 0.4, 1.0], (k - 0.3) / 0.4)
                } else {
                    mix([0.1, 0.4, 1.0], [0.45, 0.1, 0.7], (k - 0.7) / 0.3)
                }
            } else {
                let g = self.glow[j];
                [0.35 * g, 0.03 * g, 0.25 * g]
            };
        }
    }
}

impl crate::Game for Life {
    fn step(&mut self, inp: Option<&mut Input>) {
        let reseed = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(reseed);
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, self.fade.min(1.0), 1.4);
    }
    fn status(&self) -> String {
        format!("gen {}  pop {}", self.gens, self.pops.last().unwrap_or(&0))
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
