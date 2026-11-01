// Aurora over mountains and a lake on 128x192 (a demo, no game).
//
// Two or three curtains hang across a starry sky. Each has a bright green
// lower edge that drifts and folds, rays rising from it (purple to red
// towards the top) that shimmer sideways, and brightness waves running
// along it. Where a fold turns the curtain edge-on it looks brighter. Now
// and then a burst brightens everything for a while. The lake mirrors the
// sky with a ripple; a shooting star crosses now and then.
use crate::fx::{add, mix, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::Input;
use crate::Rng;

const HORIZON: usize = 150; // lake surface
const HF: f32 = H as f32;

struct Curtain {
    y: f32,     // mean height of the lower edge
    amp: f32,   // how far the edge wanders
    len: f32,   // ray length
    speed: f32, // drift
    seed: u32,
    gain: f32,
}

pub struct Aurora {
    rng: Rng,
    tick: u64,
    stars: Vec<(i32, i32, f32, f32)>, // x, y, phase, brightness
    curtains: Vec<Curtain>,
    burst: f32,
    meteor: Option<(f32, f32, f32, f32, i32)>, // x, y, vx, vy, life
}

/// mountain ridge height above the lake at column x (0 = horizon)
fn ridge(x: f32) -> f32 {
    let far = 14.0 + 7.0 * noise(x * 0.03, 21) + 3.0 * noise(x * 0.11, 22);
    far.max(0.0)
}

fn near_ridge(x: f32) -> f32 {
    (4.0 + 7.0 * noise(x * 0.045 + 3.0, 23) + 2.0 * noise(x * 0.2, 24)).max(0.0)
}

impl Aurora {
    pub fn new(seed: u64, _hi: u64) -> Aurora {
        let mut rng = Rng::new(seed);
        let stars = (0..90)
            .map(|_| {
                let y = (rng.f().powf(1.3) * (HORIZON as f32 - 20.0)) as i32;
                ((rng.next() % W as u64) as i32, y, rng.range(0.0, 6.28), rng.range(0.15, 0.6))
            })
            .collect();
        let curtains = vec![
            Curtain { y: 88.0, amp: 18.0, len: 55.0, speed: 0.6, seed: 1, gain: 1.0 },
            Curtain { y: 118.0, amp: 12.0, len: 35.0, speed: -0.4, seed: 2, gain: 0.7 },
            Curtain { y: 58.0, amp: 10.0, len: 40.0, speed: 0.3, seed: 3, gain: 0.45 },
        ];
        Aurora { rng, tick: 0, stars, curtains, burst: 0.0, meteor: None }
    }

    fn update(&mut self) {
        self.tick += 1;
        // a burst now and then: brighter and faster for a while
        if self.burst <= 0.0 && self.rng.chance(1.0 / 1500.0) {
            self.burst = 1.0;
        }
        self.burst = (self.burst - 1.0 / 600.0).max(0.0);
        if let Some(m) = &mut self.meteor {
            m.0 += m.2;
            m.1 += m.3;
            m.4 -= 1;
            if m.4 <= 0 {
                self.meteor = None;
            }
        } else if self.rng.chance(1.0 / 700.0) {
            let x = self.rng.range(10.0, 118.0);
            let dir = if x < 64.0 { 1.0 } else { -1.0 };
            self.meteor = Some((x, self.rng.range(5.0, 50.0), dir * self.rng.range(1.5, 2.5), self.rng.range(0.6, 1.2), 30));
        }
    }

    fn sky(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let b = self.burst.sin().max(0.0) * 0.8 + 1.0;
        for y in 0..HORIZON {
            let fy = y as f32;
            let k = fy / HORIZON as f32;
            for x in 0..W {
                buf[y * W + x] = [0.01, 0.015 + 0.02 * k, 0.05 + 0.05 * k];
            }
        }
        for &(x, y, ph, br) in &self.stars {
            let tw = br * (0.75 + 0.25 * (t * 0.07 + ph).sin());
            add(buf, x, y, [tw, tw, tw * 1.1]);
        }
        for (ci, c) in self.curtains.iter().enumerate() {
            let s = c.seed;
            let tt = t * (1.0 + self.burst * 1.5);
            for x in 0..W {
                let fx = x as f32;
                // the curtain is a band seen from below: a warped coordinate
                // along it; where it folds (u changes slowly) it is brighter
                let warp = |x: f32| x + 18.0 * noise(x * 0.025 + tt * 0.0025 * c.speed, s * 10 + 1);
                let u = warp(fx);
                let du = (warp(fx + 0.5) - warp(fx - 0.5)).abs();
                let fold = (1.0 / du.max(0.3)).min(2.5);
                let edge = c.y + c.amp * noise(fx * 0.02 + tt * 0.0012 * c.speed, s * 10 + 2)
                    + 3.0 * noise(fx * 0.08 + tt * 0.01, s * 10 + 3);
                // rays: fine stripes along the curtain that shimmer
                let ray = 0.55 + 0.45 * noise(u * 0.45 + tt * 0.02 * c.speed, s * 10 + 4);
                let ray = ray * (0.75 + 0.25 * noise(u * 1.3 - tt * 0.05, s * 10 + 5));
                // waves of brightness running along
                let wave = 0.55 + 0.45 * noise(u * 0.04 - tt * 0.006, s * 10 + 6);
                let len = c.len * (0.7 + 0.5 * noise(u * 0.06 + tt * 0.003, s * 10 + 7)) * (1.0 + 0.4 * self.burst);
                // each curtain comes and goes slowly
                let life = 0.3 + 0.7 * smooth(-0.3, 0.5, noise(t * 0.0006 + fx * 0.004, s * 10 + 8));
                let gain = c.gain * ray * wave * fold.sqrt() * b * life;
                let y0 = (edge - len * 1.6).max(0.0) as usize;
                let y1 = ((edge + 8.0) as usize).min(HORIZON);
                for y in y0..y1 {
                    let fy = y as f32;
                    let h = (edge - fy) / len; // 0 at the edge, 1 a ray length up
                    let a = if h < 0.0 {
                        (1.0 + h * len / 1.5).max(0.0) * 1.6 + 0.25 * (h * len / 3.0).exp() // a faint glow below
                    } else {
                        (-h * 1.8).exp() + 0.6 * (-h * len / 3.0).exp() // a bright rim at the edge
                    };
                    // green at the edge, purple higher up, a red fringe below in a burst
                    let mut col = mix([0.15, 1.0, 0.45], [0.55, 0.15, 0.85], smooth(0.25, 1.1, h));
                    if h < 0.0 {
                        col = mix(col, [1.0, 0.2, 0.4], self.burst * 0.7);
                    }
                    let v = a * gain * 1.5;
                    let p = &mut buf[y * W + x];
                    for i in 0..3 {
                        p[i] += col[i] * v;
                    }
                }
                let _ = ci;
            }
        }
        if let Some((x, y, vx, vy, life)) = self.meteor {
            for k in 0..10 {
                let f = 1.0 - k as f32 / 10.0;
                let v = f * life as f32 / 30.0;
                add(buf, (x - vx * k as f32 * 0.6) as i32, (y - vy * k as f32 * 0.6) as i32, [v, v, v * 0.9]);
            }
        }
        // mountains: a far ridge lit faintly green by the aurora, a near one black
        let glow = 0.04 + 0.03 * self.burst;
        for x in 0..W {
            let fx = x as f32;
            let (rf, rn) = (ridge(fx), near_ridge(fx));
            for y in 0..HORIZON {
                let above = HORIZON as f32 - y as f32;
                if above < rn {
                    buf[y * W + x] = [0.004, 0.006, 0.008];
                } else if above < rf {
                    let snow = smooth(rf - 4.0, rf - 1.0, above) * 0.5;
                    buf[y * W + x] = [0.015 + snow * glow, 0.02 + glow * (0.5 + snow * 2.0), 0.03 + snow * glow];
                }
            }
        }
    }

    fn render(&self, buf: &mut [Col]) {
        self.sky(buf);
        // the lake: the sky upside down, rippled and darker
        let t = self.tick as f32;
        for y in HORIZON..H {
            let d = (y - HORIZON) as f32;
            let k = d / (HF - HORIZON as f32);
            for x in 0..W {
                let fx = x as f32;
                let rip = 1.5 * (0.3 + k) * noise2(fx * 0.05, d * 0.6 - t * 0.03, 999, 31);
                let sx = (fx + rip).clamp(0.0, (W - 1) as f32) as usize;
                let sy = (HORIZON as f32 - 1.0 - d * 2.2).max(0.0) as usize; // seen at a low angle
                let src = buf[sy * W + sx];
                let dim = 0.7 - 0.25 * k;
                buf[y * W + x] = [src[0] * dim + 0.005, src[1] * dim + 0.01, src[2] * dim + 0.02];
            }
        }
    }
}

impl crate::Game for Aurora {
    fn step(&mut self, _inp: Option<&mut Input>) {
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.6);
    }
    fn status(&self) -> String {
        format!("{}", if self.burst > 0.0 { "burst" } else { "calm" })
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
