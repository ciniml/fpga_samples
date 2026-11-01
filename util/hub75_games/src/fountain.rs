// A musical fountain at night on 128x192 (a demo, no game).
//
// Seven nozzles in a basin shoot water drops that fly in arcs under
// gravity and fall back with a splash. A program of scenes changes every
// 8 s: one tall central jet, all at the same height, a wave running across,
// a fan that opens and closes, alternating pulses, an arch. Underwater
// lights colour each jet and change colour with the scenes. Drops are
// drawn into a glow buffer that fades a little each tick, so the jets read
// as streams. The basin surface ripples and reflects the light.
use crate::fx::{add, mix, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::Rng;
use std::f32::consts::PI;

const G: f32 = 0.06;
const SURFACE: f32 = 160.0; // water level of the basin
const SCENE: u64 = 8 * 60;
const NOZZLES: usize = 7;
const DECAY: f32 = 0.72;
const HF: f32 = H as f32;

const PALETTES: [[Col; 3]; 5] = [
    [[0.2, 0.5, 1.0], [0.3, 0.9, 1.0], [0.9, 0.95, 1.0]],
    [[1.0, 0.2, 0.6], [0.6, 0.2, 1.0], [0.2, 0.4, 1.0]],
    [[1.0, 0.6, 0.1], [1.0, 0.3, 0.1], [1.0, 0.9, 0.3]],
    [[0.2, 1.0, 0.4], [0.1, 0.8, 0.9], [0.8, 1.0, 0.3]],
    [[1.0, 0.2, 0.2], [0.2, 1.0, 0.3], [0.3, 0.4, 1.0]],
];

struct Drop {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    col: Col,
}

pub struct Fountain {
    rng: Rng,
    tick: u64,
    glow: Vec<Col>,
    drops: Vec<Drop>,
    splashes: Vec<(f32, f32, f32, f32, i32, Col)>,
    scene: usize,
    t: u64,
}

fn nozzle_x(i: usize) -> f32 {
    64.0 + (i as f32 - 3.0) * 15.0
}

impl Fountain {
    pub fn new(seed: u64, _hi: u64) -> Fountain {
        Fountain { rng: Rng::new(seed), tick: 0, glow: vec![[0.0; 3]; W * H], drops: Vec::new(), splashes: Vec::new(), scene: 0, t: 0 }
    }

    /// (launch height in px or 0 = off, sideways angle) of nozzle i now
    fn jet(&self, i: usize) -> (f32, f32) {
        let t = self.t as f32;
        let k = i as f32 - 3.0; // -3 .. 3
        let ramp = smooth(0.0, 40.0, t) * (1.0 - smooth(SCENE as f32 - 30.0, SCENE as f32, t));
        let (h, a) = match self.scene % 6 {
            0 => {
                // tall centre, low sides
                if i == 3 { (130.0, 0.0) } else { (30.0 + 8.0 * (3.0 - k.abs()), k * 0.12) }
            }
            1 => (70.0 + 40.0 * (t * 0.05 - k * 0.6).sin().max(-0.6), 0.0), // a wave running across
            2 => {
                // a fan opening and closing
                let open = 0.5 + 0.5 * (t * 0.02).sin();
                (100.0 - 10.0 * k.abs(), k * 0.16 * open)
            }
            3 => {
                // alternating pulses
                let on = ((t / 30.0) as usize + i) % 2 == 0;
                (if on { 110.0 } else { 0.0 }, 0.0)
            }
            4 => (60.0 + 15.0 * (3.0 - k.abs()), -k * 0.22), // an arch, the outer jets lean in
            _ => {
                // all together, rising and falling
                (40.0 + 80.0 * (0.5 + 0.5 * (t * 0.03).sin()), k * 0.04)
            }
        };
        (h * ramp, a)
    }

    fn colour(&self, i: usize) -> Col {
        let p = PALETTES[self.scene % PALETTES.len()];
        let k = (self.tick as f32 * 0.01 + i as f32 * 0.4).sin() * 0.5 + 0.5;
        if i % 2 == 0 { mix(p[0], p[1], k) } else { mix(p[1], p[2], k) }
    }

    fn update(&mut self, next: bool) {
        self.tick += 1;
        self.t += 1;
        if next && self.t < SCENE - 30 {
            self.t = SCENE - 30;
        }
        if self.t >= SCENE {
            self.t = 0;
            self.scene += 1;
        }
        for p in &mut self.glow {
            for c in p.iter_mut() {
                *c *= DECAY;
            }
        }
        for i in 0..NOZZLES {
            let (h, a) = self.jet(i);
            if h < 4.0 {
                continue;
            }
            let v = (2.0 * G * h).sqrt();
            let col = self.colour(i);
            for _ in 0..3 {
                let aa = a + self.rng.range(-0.03, 0.03);
                let vv = v * self.rng.range(0.96, 1.02);
                self.drops.push(Drop { x: nozzle_x(i), y: SURFACE, vx: aa.sin() * vv, vy: -aa.cos() * vv, col });
            }
        }
        for d in &mut self.drops {
            d.x += d.vx;
            d.y += d.vy;
            d.vy += G;
        }
        let mut sp = Vec::new();
        self.drops.retain(|d| {
            let alive = d.y <= SURFACE + 0.5 || d.vy < 0.0;
            if !alive {
                sp.push((d.x, d.col));
            }
            alive && d.x > -4.0 && d.x < W as f32 + 4.0
        });
        for (x, col) in sp {
            if self.rng.chance(0.3) {
                let a = self.rng.range(PI * 1.15, PI * 1.85);
                let v = self.rng.range(0.3, 0.9);
                self.splashes.push((x, SURFACE, a.cos() * v, a.sin() * v, 14, col));
            }
        }
        for s in &mut self.splashes {
            s.0 += s.2;
            s.1 += s.3;
            s.3 += 0.1;
            s.4 -= 1;
        }
        self.splashes.retain(|s| s.4 > 0);
        // drops into the glow, as short streaks
        for d in &self.drops {
            let n = (d.vx.abs().max(d.vy.abs()).ceil() as i32).clamp(1, 4);
            for k in 0..n {
                let f = k as f32 / n as f32;
                let (x, y) = (d.x - d.vx * f, d.y - d.vy * f);
                if x >= 0.0 && y >= 0.0 && (x as usize) < W && (y as usize) < H {
                    let p = &mut self.glow[y as usize * W + x as usize];
                    for i in 0..3 {
                        p[i] += d.col[i] * 0.12;
                    }
                }
            }
        }
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        // how much light the jets throw on the scene
        let mut lamp = [0.0f32; 3];
        for i in 0..NOZZLES {
            let (h, _) = self.jet(i);
            let c = self.colour(i);
            for k in 0..3 {
                lamp[k] += c[k] * (h / 130.0) / NOZZLES as f32;
            }
        }
        for y in 0..H {
            let fy = y as f32;
            for x in 0..W {
                let fx = x as f32;
                // night sky, a row of distant buildings, then the basin
                let k = fy / HF;
                let mut c = [0.01 + 0.02 * k, 0.012 + 0.025 * k, 0.04 + 0.05 * k];
                let sky = 105.0 + 12.0 * (noise(fx * 0.06, 101) > 0.1) as i32 as f32 * noise(fx * 0.02, 102).abs();
                if fy > sky && fy < SURFACE - 6.0 {
                    let win = noise2(fx * 0.5, fy * 0.5, 999, 103) > 0.55 && (x % 3 != 0) && (y % 3 != 0);
                    c = if win { [0.18, 0.14, 0.06] } else { [0.02, 0.022, 0.03] };
                }
                // basin rim
                if fy >= SURFACE - 6.0 && fy < SURFACE - 2.0 {
                    let s = 0.12 + 0.05 * noise(fx * 0.4, 104);
                    c = [s + lamp[0] * 0.3, s + lamp[1] * 0.3, s * 1.1 + lamp[2] * 0.3];
                }
                // basin water: dark, lit by the jets, rippling
                if fy >= SURFACE - 2.0 {
                    let d = (fy - SURFACE) / (HF - SURFACE);
                    let rip = smooth(0.4, 0.8, noise2(fx * 0.12, fy * 0.8 - t * 0.06, 999, 105));
                    let lit = (1.0 - d) * 0.6 + rip * 0.4;
                    c = [0.02 + lamp[0] * lit * 0.7, 0.04 + lamp[1] * lit * 0.7, 0.07 + lamp[2] * lit * 0.7];
                    // the bright pool around each nozzle
                    for i in 0..NOZZLES {
                        let (h, _) = self.jet(i);
                        let dx = (fx - nozzle_x(i)) / 6.0;
                        let g = (h / 130.0) * (-(dx * dx) - d * 3.0).exp() * 0.6;
                        let col = self.colour(i);
                        for k in 0..3 {
                            c[k] += col[k] * g;
                        }
                    }
                }
                let g = self.glow[y * W + x];
                buf[y * W + x] = [c[0] + g[0], c[1] + g[1], c[2] + g[2]];
            }
        }
        for s in &self.splashes {
            let v = s.4 as f32 / 14.0 * 0.6;
            add(buf, s.0 as i32, s.1 as i32, [s.5[0] * v + 0.2 * v, s.5[1] * v + 0.2 * v, s.5[2] * v + 0.2 * v]);
        }

    }
}

impl crate::Game for Fountain {
    fn step(&mut self, inp: Option<&mut Input>) {
        let next = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(next);
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.5);
    }
    fn status(&self) -> String {
        format!("scene {}  drops {}", self.scene % 6, self.drops.len())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
