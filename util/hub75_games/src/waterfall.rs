// A waterfall at night on 128x192 (a demo, no game).
//
// A river comes over the lip of a cliff and falls into a pool. The falling
// sheet is textured by the time each bit of water has been falling: a
// pixel shows the noise pattern that left the lip `tau(y)` ticks ago, so
// streaks stretch as the water speeds up. Edges fray, the bottom churns
// white; the pool has foam spreading from the impact, moonlit glints, mist
// drifting up and spray drops. Moon and stars above, mossy rock around.
//
// Sound: the steady rush of the fall, surging a little, with spray drops
// plipping now and then.
use crate::audio::{self, Keep, Water};
use crate::fx::{add, mix, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::Input;
use crate::Rng;

const LIP_Y: f32 = 40.0;
const POOL_Y: f32 = 160.0;
const V0: f32 = 0.5; // px / tick over the lip
const G: f32 = 0.03;
const MOON: (f32, f32) = (100.0, 16.0);
const HF: f32 = H as f32;

struct Drop {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    max: i32,
}

pub struct Waterfall {
    rng: Rng,
    tick: u64,
    drops: Vec<Drop>,
    stars: Vec<(i32, i32, f32)>,
    keep: Keep,
}

/// left / right edge of the falling sheet at height y
fn sheet(y: f32, t: f32) -> (f32, f32) {
    let k = ((y - LIP_Y) / (POOL_Y - LIP_Y)).clamp(0.0, 1.0);
    let wob = |s: u32| 1.2 * noise(y * 0.08 - t * 0.05, s) * k;
    (44.0 - 7.0 * k + wob(1), 86.0 + 7.0 * k + wob(2))
}

/// top of the cliff (sky above)
fn skyline(x: f32) -> f32 {
    let base = 30.0 + 6.0 * ((x - 64.0) / 64.0).powi(2) * -1.0;
    base + 3.0 * noise(x * 0.15, 9) + 2.0 * noise(x * 0.5, 10)
}

/// ticks a drop needs to fall from the lip to y
fn tau(y: f32) -> f32 {
    let d = (y - LIP_Y).max(0.0);
    ((V0 * V0 + 2.0 * G * d).sqrt() - V0) / G
}

impl Waterfall {
    pub fn new(seed: u64, _hi: u64) -> Waterfall {
        let mut rng = Rng::new(seed);
        let stars = (0..30)
            .map(|_| ((rng.next() % W as u64) as i32, (rng.next() % 30) as i32, rng.range(0.0, 6.28)))
            .collect();
        Waterfall { rng, tick: 0, drops: Vec::new(), stars, keep: Keep::default() }
    }

    fn update(&mut self) {
        self.tick += 1;
        let t = self.tick as f32;
        let (l, r) = sheet(POOL_Y, t);
        for _ in 0..7 {
            let x = self.rng.range(l + 2.0, r - 2.0);
            let life = self.rng.range(25.0, 60.0) as i32;
            let side = (x - 64.0) / 30.0;
            self.drops.push(Drop {
                x,
                y: POOL_Y + self.rng.range(-2.0, 3.0),
                vx: side * self.rng.range(0.2, 1.0) + self.rng.range(-0.4, 0.4),
                vy: -self.rng.range(0.4, 1.9),
                life,
                max: life,
            });
        }
        for d in &mut self.drops {
            d.x += d.vx;
            d.y += d.vy;
            d.vy += 0.05;
            d.life -= 1;
        }
        self.drops.retain(|d| d.life > 0 && d.y < POOL_Y + 8.0);
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        for y in 0..H {
            let fy = y as f32;
            let (l, r) = sheet(fy, t);
            let ty = tau(fy);
            for x in 0..W {
                let fx = x as f32;
                let sky_y = skyline(fx);
                let mut c: Col;
                if fy < sky_y {
                    // night sky and moon glow
                    let (dx, dy) = (fx - MOON.0, fy - MOON.1);
                    let d2 = dx * dx + dy * dy;
                    let glow = 0.18 / (1.0 + d2 / 150.0);
                    c = [0.02 + glow * 0.8, 0.03 + glow * 0.9, 0.08 + glow];
                    if d2 < 36.0 {
                        let shade = 0.85 + 0.15 * noise2(fx * 0.5, fy * 0.5, 999, 11);
                        c = [0.95 * shade, 0.93 * shade, 0.8 * shade];
                    }
                } else {
                    // rock: dark, moss here and there, lit a little from the right
                    let n = noise2(fx * 0.12, fy * 0.12, 999, 3) * 0.6 + noise2(fx * 0.4, fy * 0.4, 999, 4) * 0.4;
                    let moss = smooth(0.25, 0.55, noise2(fx * 0.07, fy * 0.09, 999, 5)) * (1.0 - smooth(140.0, 160.0, fy));
                    let lit = 0.6 + 0.4 * (fx / 128.0);
                    let rock = [0.15 + 0.07 * n, 0.15 + 0.07 * n, 0.18 + 0.08 * n];
                    c = mix(rock, [0.07, 0.2 + 0.06 * n, 0.07], moss * 0.8);
                    for v in &mut c {
                        *v *= lit;
                    }
                    // the cliff edge catches the moonlight
                    if fy - sky_y < 1.5 {
                        c = [0.35, 0.37, 0.4];
                    }
                }
                // the river above the lip, flowing towards us
                if fy >= sky_y + 2.0 && fy < LIP_Y {
                    let k = (fy - 30.0) / (LIP_Y - 30.0);
                    let (rl, rr) = (52.0 - 8.0 * k, 78.0 + 8.0 * k);
                    if fx > rl && fx < rr {
                        let n = noise2(fx * 0.25, fy * 0.5 - t * 0.12, 999, 6);
                        c = mix([0.12, 0.25, 0.35], [0.6, 0.75, 0.85], smooth(0.1, 0.8, n) * 0.7 + 0.2 * k);
                    }
                }
                // the falling sheet
                if fy >= LIP_Y && fy < POOL_Y + 2.0 {
                    let edge = (fx - l).min(r - fx);
                    let fray = 2.0 + 1.5 * noise2(fx * 0.3, (t - ty) * 0.15, 999, 7);
                    if edge > -1.0 {
                        let a = smooth(-1.0, fray, edge);
                        let k = (fy - LIP_Y) / (POOL_Y - LIP_Y);
                        let s = t - ty; // when this water left the lip
                        let n = 0.7 * noise2(fx * 0.55, s * 0.09, 999, 8) + 0.3 * noise2(fx * 1.3, s * 0.25, 999, 9);
                        let streak = smooth(-0.35, 0.75, n);
                        let churn = smooth(0.6, 1.0, k) * (0.5 + 0.5 * noise2(fx * 0.4, fy * 0.3 - t * 0.4, 999, 10));
                        let v = (0.35 + 0.65 * streak + 0.6 * churn).min(1.0);
                        let mut w = mix([0.12, 0.32, 0.48], [0.9, 0.97, 1.0], v);
                        if fy < LIP_Y + 3.0 {
                            w = mix(w, [0.75, 0.88, 0.95], 0.5); // the glassy lip
                        }
                        c = mix(c, w, a);
                    }
                }
                // the pool
                if fy >= POOL_Y {
                    let depth = (fy - POOL_Y) / (HF - POOL_Y);
                    let mut w = [0.04, 0.1, 0.16];
                    // moonlit glints on the ripples
                    let rip = noise2(fx * 0.12 + 0.3 * noise(fy, 12), fy * 0.9 - t * 0.02, 999, 13);
                    let g = smooth(0.55, 0.8, rip) * 0.35 * (0.4 + 0.6 * (fx / 128.0));
                    w = [w[0] + g * 0.8, w[1] + g * 0.9, w[2] + g];
                    // foam: thick at the impact, spreading and thinning
                    let dist = if fx < l { l - fx } else if fx > r { fx - r } else { 0.0 };
                    let spread = dist / (8.0 + 30.0 * depth);
                    let fo = noise2(fx * 0.3 + 0.5 * noise(fy * 0.7 + t * 0.03, 16), fy * 1.1 - t * 0.04, 999, 14);
                    let foam = (1.0 - spread).max(0.0) * smooth(0.0, 0.7, fo) * (1.0 - 0.6 * depth);
                    c = mix(w, [0.85, 0.92, 0.95], foam.min(1.0));
                }
                // mist rising from the pool
                let my = (POOL_Y - fy) / 45.0;
                if my > -0.4 && my < 1.0 {
                    let m = noise2(fx * 0.06, fy * 0.07 + t * 0.012, 999, 15) * 0.5 + 0.5;
                    let width = 1.0 - smooth(20.0, 60.0, (fx - 64.0).abs());
                    let a = (1.0 - my.abs()) * m * width * 0.35;
                    for (i, k) in [0.7, 0.8, 0.9].iter().enumerate() {
                        c[i] += k * a;
                    }
                }
                buf[y * W + x] = c;
            }
        }
        for &(x, y, ph) in &self.stars {
            if (y as f32) < skyline(x as f32) - 1.0 {
                let b = (0.3 + 0.25 * (t * 0.06 + ph).sin()).max(0.0);
                add(buf, x, y, [b, b, b]);
            }
        }
        for d in &self.drops {
            let k = d.life as f32 / d.max as f32;
            add(buf, d.x as i32, d.y as i32, [0.6 * k, 0.7 * k, 0.8 * k]);
        }
    }
}

impl crate::Game for Waterfall {
    fn step(&mut self, _inp: Option<&mut Input>) {
        if self.keep.start() {
            audio::play(Water::new(self.rng.next() as u32, 1800.0, 0.025, 3.0));
        }
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.7);
    }
    fn status(&self) -> String {
        format!("drops {}", self.drops.len())
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
