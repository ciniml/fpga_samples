// Fireflies over a meadow at night on 128x192 (a demo, no game).
//
// Each firefly drifts on smooth noise and flashes when its phase wraps: a
// quick rise and a slower fade, with a soft yellow-green glow. Flashes
// nudge the phases of the fireflies nearby forward (pulse coupling), so
// over a minute or so the meadow drifts into flashing together in waves,
// as some real fireflies do; every two minutes they are shaken up again.
// Grass sways in front, trees stand dark against a deep blue sky with
// stars and a thin moon.
use crate::fx::{add, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::Input;
use crate::Rng;

const N: usize = 45;
const PERIOD: f32 = 110.0; // ticks between flashes
const FLASH: f32 = 0.24; // part of the period that is the flash
const COUPLE: f32 = 0.024; // phase nudge from a neighbour's flash
const RESET: u64 = 120 * 60;
const HF: f32 = H as f32;
const WF: f32 = W as f32;

struct Fly {
    x: f32,
    y: f32,
    ph: f32, // 0..1, flashes at the start
    rate: f32,
    seed: u32,
}

pub struct Fireflies {
    rng: Rng,
    tick: u64,
    flies: Vec<Fly>,
    stars: Vec<(i32, i32, f32)>,
    blades: Vec<(f32, f32, f32, f32)>, // root x, height, lean, phase
}

/// brightness over the phase: quick rise, slower fall
fn flash(ph: f32) -> f32 {
    if ph < FLASH * 0.3 {
        smooth(0.0, FLASH * 0.3, ph)
    } else if ph < FLASH {
        1.0 - smooth(FLASH * 0.3, FLASH, ph)
    } else {
        0.0
    }
}

fn treeline(x: f32) -> f32 {
    // two dark trees and a low hedge
    let hedge = 140.0 + 3.0 * noise(x * 0.1, 91);
    let tree = |cx: f32, w: f32, top: f32| {
        let d = (x - cx).abs() / w;
        if d < 1.0 {
            top + (1.0 - (1.0 - d * d).sqrt()) * 40.0 + 3.0 * noise(x * 0.5, 92)
        } else {
            HF
        }
    };
    hedge.min(tree(22.0, 20.0, 70.0)).min(tree(108.0, 16.0, 88.0))
}

impl Fireflies {
    pub fn new(seed: u64, _hi: u64) -> Fireflies {
        let mut rng = Rng::new(seed);
        let flies = (0..N)
            .map(|i| Fly {
                x: rng.range(4.0, WF - 4.0),
                y: rng.range(70.0, 175.0),
                ph: rng.f(),
                rate: 1.0 / (PERIOD * rng.range(0.96, 1.04)),
                seed: 100 + i as u32,
            })
            .collect();
        let stars = (0..50).map(|_| ((rng.next() % W as u64) as i32, (rng.next() % 110) as i32, rng.range(0.0, 6.28))).collect();
        let blades = (0..160).map(|_| (rng.range(-2.0, WF + 2.0), rng.range(8.0, 26.0), rng.range(-0.4, 0.4), rng.range(0.0, 6.28))).collect();
        Fireflies { rng, tick: 0, flies, stars, blades }
    }

    fn update(&mut self) {
        self.tick += 1;
        let t = self.tick as f32;
        if self.tick % RESET == 0 {
            for f in &mut self.flies {
                f.ph = self.rng.f();
            }
        }
        // who flashes this tick
        let mut fired: Vec<(f32, f32)> = Vec::new();
        for f in &mut self.flies {
            f.ph += f.rate;
            if f.ph >= 1.0 {
                f.ph -= 1.0;
                fired.push((f.x, f.y));
            }
            // drift on noise, kept inside the meadow
            let s = f.seed;
            f.x += 0.35 * noise(t * 0.008, s) + 0.1 * noise(t * 0.05, s + 1000);
            f.y += 0.25 * noise(t * 0.007, s + 2000) + 0.08 * noise(t * 0.05, s + 3000);
            f.x += (WF / 2.0 - f.x) * 0.002; // a weak pull to the middle keeps them off the edges
            f.y += (125.0 - f.y) * 0.002;
            f.x = f.x.clamp(2.0, WF - 2.0);
            f.y = f.y.clamp(60.0, 182.0);
        }
        // pulse coupling: a flash nearby pulls a dark firefly's phase forward
        for f in &mut self.flies {
            if f.ph < FLASH {
                continue; // flashing now, deaf
            }
            for &(x, y) in &fired {
                let d2 = (f.x - x).powi(2) + (f.y - y).powi(2);
                if d2 < 60.0 * 60.0 {
                    f.ph += COUPLE * (1.0 - d2 / 3600.0) * f.ph;
                    if f.ph >= 1.0 {
                        f.ph = 0.999; // flashes next tick, with the others
                    }
                }
            }
        }
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        for y in 0..H {
            let k = y as f32 / HF;
            for x in 0..W {
                let fx = x as f32;
                let mut c = [0.015 + 0.03 * k, 0.03 + 0.05 * k, 0.1 + 0.07 * k];
                if (y as f32) >= treeline(fx) {
                    let n = noise2(fx * 0.3, y as f32 * 0.3, 999, 93) * 0.004;
                    c = [0.004 + n, 0.012 + n, 0.01 + n];
                }
                buf[y * W + x] = c;
            }
        }
        for &(x, y, ph) in &self.stars {
            if (y as f32) < treeline(x as f32) {
                let b = (0.25 + 0.2 * (t * 0.05 + ph).sin()).max(0.0);
                add(buf, x, y, [b, b, b]);
            }
        }
        // a thin moon
        for y in 8..26 {
            for x in 82..100 {
                let (dx, dy) = (x as f32 - 91.0, y as f32 - 17.0);
                let (ex, ey) = (x as f32 - 95.0, y as f32 - 15.0);
                if dx * dx + dy * dy < 49.0 && ex * ex + ey * ey > 42.0 {
                    buf[y * W + x] = [0.9, 0.88, 0.7];
                }
            }
        }
        // fireflies: a bright point and a soft glow
        let mut light = 0.0;
        for f in &self.flies {
            let b = flash(f.ph);
            if b <= 0.0 {
                continue;
            }
            light += b;
            for dy in -6i32..=6 {
                for dx in -6i32..=6 {
                    let d2 = (dx * dx + dy * dy) as f32;
                    let g = b * if d2 < 0.5 { 1.2 } else { 0.7 / (1.0 + d2 * 0.45) };
                    add(buf, f.x as i32 + dx, f.y as i32 + dy, [0.75 * g, 1.0 * g, 0.2 * g]);
                }
            }
        }
        // grass in front, swaying, lit faintly when many flash at once
        let l = (light / 12.0).min(1.0);
        for &(rx, h, lean, ph) in &self.blades {
            let sway = lean + 0.25 * (t * 0.02 + ph).sin() + 0.2 * noise(t * 0.01 + rx * 0.05, 94);
            for k in 0..h as i32 {
                let f = k as f32 / h;
                let x = rx + sway * f * f * h * 0.6;
                let y = HF - 1.0 - k as f32;
                let v = 0.012 + 0.05 * f * l;
                let p = (y as usize) * W + x as usize;
                if x >= 0.0 && (x as usize) < W {
                    buf[p] = [v * 0.5, v * 1.2 + 0.006, v * 0.4];
                }
            }
        }
    }
}

impl crate::Game for Fireflies {
    fn step(&mut self, _inp: Option<&mut Input>) {
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.5);
    }
    fn status(&self) -> String {
        // how synchronised: length of the mean phase vector
        let (s, c) = self.flies.iter().fold((0.0, 0.0), |(s, c), f| {
            let a = f.ph * std::f32::consts::TAU;
            (s + a.sin(), c + a.cos())
        });
        format!("sync {:.2}", (s * s + c * c).sqrt() / N as f32)
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
