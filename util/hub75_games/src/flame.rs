// Flickering flames on 128x192 (a demo, no game). Two scenes, 30 s each
// with a fade between them (Space / Enter: the other scene now):
//
// - bonfire: a heat field. Two hidden rows under the logs are kept hot
//   (a flickering envelope with wandering coals); every tick each cell takes
//   the average of the cells below it, sampled a little to the side by the
//   wind, minus a cooling map that scrolls up with the flames, which tears
//   them into tongues. Heat goes through a black-red-orange-yellow-white
//   palette. Embers rise and drift, the logs glow, the ground is lit by the
//   fire's brightness.
// - candles: three candles drawn from a formula, a teardrop that leans and
//   wobbles with smooth noise, white-yellow inside, orange outside, blue at
//   the root, with a halo; gusts now and then make all of them flicker.
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::fx::{mix, noise, noise2, smooth, Col};
use crate::Rng;

const SCENE_LEN: u64 = 30 * 60;
const FADE: u64 = 60;
const HF: f32 = H as f32;
const CH: usize = 256; // rows of the cooling map

/// heat 0..1.2 -> colour
fn fire_colour(v: f32) -> Col {
    const P: [(f32, Col); 7] = [
        (0.0, [0.0, 0.0, 0.0]),
        (0.15, [0.22, 0.0, 0.0]),
        (0.35, [0.75, 0.08, 0.0]),
        (0.55, [1.0, 0.35, 0.0]),
        (0.75, [1.0, 0.7, 0.08]),
        (0.95, [1.0, 0.92, 0.5]),
        (1.15, [1.0, 1.0, 0.9]),
    ];
    if v <= 0.0 {
        return [0.0; 3];
    }
    for k in 1..P.len() {
        if v < P[k].0 {
            let t = (v - P[k - 1].0) / (P[k].0 - P[k - 1].0);
            return mix(P[k - 1].1, P[k].1, t);
        }
    }
    P[P.len() - 1].1
}

struct Ember {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    max: i32,
    ph: f32,
}

struct Candle {
    x: f32,
    h: f32, // body height
    w: f32,
    seed: u32,
}

pub struct Flame {
    rng: Rng,
    tick: u64,
    scene: u32,
    scene_t: u64,
    heat: Vec<f32>, // W x (H + 2)
    cool: Vec<f32>, // W x CH
    coals: Vec<f32>,
    embers: Vec<Ember>,
    bright: f32, // smoothed brightness of the fire, lights the logs and ground
    candles: [Candle; 3],
}

impl Flame {
    pub fn new(seed: u64, _hi: u64) -> Flame {
        let mut rng = Rng::new(seed);
        // cooling map: two octaves of value noise, stretched upwards so that
        // the flames tear into tall tongues (wraps both ways)
        let mut cool: Vec<f32> = (0..W * CH)
            .map(|i| {
                let (x, y) = ((i % W) as f32, (i / W) as f32);
                let n = 0.65 * noise2(x / 8.0, y / 16.0, 16, 7) + 0.35 * noise2(x / 4.0, y / 8.0, 32, 8);
                // the map is CH rows tall: blend the end into the start
                let k = smooth(CH as f32 - 32.0, CH as f32, y);
                let m = 0.65 * noise2(x / 8.0, (y - CH as f32) / 16.0, 16, 7)
                    + 0.35 * noise2(x / 4.0, (y - CH as f32) / 8.0, 32, 8);
                n * (1.0 - k) + m * k
            })
            .collect();
        let (lo, hi) = cool.iter().fold((f32::MAX, f32::MIN), |(a, b), &v| (a.min(v), b.max(v)));
        for v in &mut cool {
            *v = ((*v - lo) / (hi - lo)).powf(2.0);
        }
        let coals = (0..W).map(|_| rng.f()).collect();
        Flame {
            rng,
            tick: 0,
            scene: 0,
            scene_t: 0,
            heat: vec![0.0; W * (H + 2)],
            cool,
            coals,
            embers: Vec::new(),
            bright: 0.5,
            candles: [
                Candle { x: 32.0, h: 62.0, w: 14.0, seed: 11 },
                Candle { x: 66.0, h: 96.0, w: 17.0, seed: 22 },
                Candle { x: 100.0, h: 44.0, w: 13.0, seed: 33 },
            ],
        }
    }

    fn step_fire(&mut self) {
        let t = self.tick as f32;
        // ---- sources: two hidden rows below the screen ----
        let cx = 64.0 + 8.0 * noise(t * 0.004, 1);
        let half = 36.0 + 6.0 * noise(t * 0.007, 2);
        let mut sum = 0.0;
        for x in 0..W {
            let c = &mut self.coals[x];
            *c = (*c + self.rng.range(-0.08, 0.08)).clamp(0.0, 1.0);
            let d = (x as f32 - cx) / half;
            let env = (1.0 - d * d).max(0.0).sqrt();
            let v = env * (0.75 + 0.45 * *c) * self.rng.range(0.85, 1.05);
            self.heat[H * W + x] = v;
            self.heat[(H + 1) * W + x] = v;
            sum += v;
        }
        self.bright += (sum / (W as f32 * 0.55) - self.bright) * 0.1;
        // ---- rise: average of the cells below, minus the cooling map ----
        let wind_t = 0.5 * noise(t * 0.006, 3) + 0.3 * noise(t * 0.023, 4);
        let scroll = self.tick as usize;
        for y in 0..H {
            // the wind bends the upper part more
            let wind = wind_t * (0.15 + 0.6 * (1.0 - y as f32 / HF));
            let row1 = (y + 1) * W;
            let row2 = (y + 2) * W;
            let crow = ((y + scroll) % CH) * W;
            for x in 0..W {
                let sx = x as f32 + wind;
                let at = |row: usize, xx: f32| {
                    let xi = xx.floor();
                    let f = xx - xi;
                    let xi = xi as i32;
                    let g = |i: i32| if i < 0 || i >= W as i32 { 0.0 } else { self.heat[row + i as usize] };
                    g(xi) * (1.0 - f) + g(xi + 1) * f
                };
                let v = (at(row1, sx - 1.0) + at(row1, sx) + at(row1, sx + 1.0) + at(row2, sx)) * 0.25;
                let c = 0.002 + 0.03 * self.cool[crow + x];
                self.heat[y * W + x] = (v - c).max(0.0);
            }
        }
        // ---- embers ----
        if self.rng.chance(0.35) {
            let x = cx + self.rng.range(-half * 0.6, half * 0.6);
            let life = self.rng.range(60.0, 160.0) as i32;
            self.embers.push(Ember {
                x,
                y: HF - 16.0,
                vx: self.rng.range(-0.2, 0.2),
                vy: self.rng.range(-1.6, -0.7),
                life,
                max: life,
                ph: self.rng.range(0.0, 6.28),
            });
        }
        for e in &mut self.embers {
            e.vx += 0.03 * noise(t * 0.05 + e.ph * 10.0, 5) + wind_t * 0.01;
            e.vx *= 0.97;
            e.vy *= 0.995;
            e.x += e.vx;
            e.y += e.vy;
            e.life -= 1;
        }
        self.embers.retain(|e| e.life > 0 && e.y > -2.0);
    }

    fn render_fire(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let b = self.bright;
        for y in 0..H {
            for x in 0..W {
                // a warm glow behind the fire
                let (dx, dy) = ((x as f32 - 64.0) / 60.0, (y as f32 - 160.0) / 90.0);
                let g = (0.09 * b / (1.0 + 4.0 * (dx * dx + dy * dy))).max(0.0);
                let f = fire_colour(self.heat[y * W + x]);
                buf[y * W + x] = [g + f[0], g * 0.35 + f[1], g * 0.08 + f[2]];
            }
        }
        for e in &self.embers {
            let k = e.life as f32 / e.max as f32;
            let fl = 0.6 + 0.4 * noise(t * 0.3 + e.ph * 7.0, 6);
            let (x, y) = (e.x as i32, e.y as i32);
            if x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
                let p = &mut buf[y as usize * W + x as usize];
                p[0] += k * fl;
                p[1] += k * fl * (0.25 + 0.4 * k);
                p[2] += k * fl * 0.05;
            }
        }
        // ground and two crossed logs at the bottom
        for y in H - 20..H {
            for x in 0..W {
                let (fx, fy) = (x as f32, y as f32);
                let p = &mut buf[y * W + x];
                if y >= H - 5 {
                    let lit = b * (1.0 - smooth(20.0, 70.0, (fx - 64.0).abs())) * 0.35;
                    *p = [0.04 + lit, 0.025 + lit * 0.4, 0.015 + lit * 0.1];
                }
                for &(x0, y0, x1, y1, s) in &[(14.0, 189.0, 112.0, 177.0, 7u32), (18.0, 176.0, 114.0, 189.0, 8u32)] {
                    let (vx, vy) = (x1 - x0, y1 - y0);
                    let u = (((fx - x0) * vx + (fy - y0) * vy) / (vx * vx + vy * vy)).clamp(0.0, 1.0);
                    let (qx, qy) = (x0 + vx * u - fx, y0 + vy * u - fy);
                    let d = (qx * qx + qy * qy).sqrt();
                    let r = 3.6;
                    if d < r {
                        let bark = 0.6 + 0.4 * noise(u * 14.0, s);
                        // the top side faces the fire; cracks glow in the middle
                        let top = smooth(-r, r, qy);
                        let mid = 1.0 - smooth(18.0, 46.0, (fx - 64.0).abs());
                        let crack = smooth(0.55, 0.9, noise(u * 90.0 + t * 0.01, s + 1)) * mid;
                        let glow = crack * (0.6 + 0.4 * noise(t * 0.08 + u * 20.0, s + 2)) * b;
                        *p = [
                            0.08 * bark + 0.25 * top * b * mid + glow,
                            0.045 * bark + 0.08 * top * b * mid + glow * 0.3,
                            0.02 * bark + glow * 0.03,
                        ];
                    }
                }
            }
        }
    }

    fn render_candles(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let table = H as i32 - 12;
        let gust = smooth(0.55, 0.9, noise(t * 0.004, 40)); // 0 calm .. 1 gust
        for y in 0..H {
            for x in 0..W {
                buf[y * W + x] = if y as i32 >= table { [0.05, 0.025, 0.012] } else { [0.012, 0.006, 0.004] };
            }
        }
        let mut flames: Vec<(f32, f32, f32)> = Vec::new(); // x, y, brightness
        for c in &self.candles {
            let top = table as f32 - c.h;
            let s = c.seed;
            let fl = 1.0 + 0.06 * noise(t * 0.15, s) + gust * 0.25 * noise(t * 0.6, s + 1);
            let hf = 30.0 * fl;
            let lean = 0.25 * noise(t * 0.01, s + 2) + gust * 0.9 * noise(t * 0.05, s + 3);
            let (fx, fy) = (c.x, top - 3.0); // root of the flame
            flames.push((fx + lean * hf * 0.3, fy - hf * 0.35, fl));
            // body: a lit cylinder, translucent and warm near the top
            for y in top as i32..table {
                for x in (c.x - c.w / 2.0) as i32..(c.x + c.w / 2.0) as i32 {
                    let u = (x as f32 + 0.5 - c.x) / (c.w / 2.0);
                    let shade = (1.0 - u * u).sqrt() * 0.75 + 0.25 - 0.15 * u;
                    let warm = (-(y as f32 - top) / 10.0).exp() * fl;
                    let p = &mut buf[y as usize * W + x as usize];
                    *p = [0.55 * shade + 0.5 * warm, 0.47 * shade + 0.28 * warm, 0.34 * shade + 0.08 * warm];
                }
            }
            // wick
            for k in 0..3 {
                let (x, y) = (c.x as usize, (top as i32 - 1 - k) as usize);
                buf[y * W + x] = if k == 2 { [0.6, 0.15, 0.0] } else { [0.05, 0.03, 0.02] };
            }
            // the flame: a teardrop around a bending axis
            for y in (fy - hf - 4.0) as i32..(fy + 3.0) as i32 {
                let h = (fy - y as f32) / hf; // 0 root .. 1 tip
                if !(-0.12..1.0).contains(&h) {
                    continue;
                }
                let hh = h.max(0.0);
                let axis = fx + lean * hh * hh * hf * 0.5 + 0.8 * hh * noise(t * 0.25 - hh * 3.0, s + 4);
                let r = 6.5 * (hh + 0.12).sqrt() * (1.0 - hh).powf(0.9) * (0.9 + 0.1 * fl);
                for x in (axis - 8.0) as i32..(axis + 9.0) as i32 {
                    if x < 0 || x >= W as i32 || y < 0 {
                        continue;
                    }
                    let d = (x as f32 + 0.5 - axis).abs() / r.max(0.3);
                    if d >= 1.0 {
                        continue;
                    }
                    let core = smooth(0.25, 0.85, 1.0 - d) * (1.0 - 0.5 * hh);
                    let mut col = mix([1.0, 0.42, 0.04], [1.0, 0.95, 0.7], core);
                    if h < 0.22 {
                        let blue = (1.0 - h / 0.22) * smooth(0.3, 0.9, d);
                        col = mix(col, [0.15, 0.25, 1.0], blue * 0.8);
                    }
                    let a = smooth(0.0, 0.35, 1.0 - d) * (1.0 - smooth(0.7, 1.0, hh) * 0.7);
                    let p = &mut buf[y as usize * W + x as usize];
                    for i in 0..3 {
                        p[i] = p[i] * (1.0 - a) + col[i] * a * 1.1;
                    }
                }
            }
        }
        // halos (and their light on the table)
        for y in 0..H {
            for x in 0..W {
                let mut g = 0.0;
                for &(hx, hy, fl) in &flames {
                    let (dx, dy) = (x as f32 - hx, (y as f32 - hy) * 0.8);
                    g += 0.28 * fl / (1.0 + (dx * dx + dy * dy) / 150.0);
                }
                let p = &mut buf[y * W + x];
                p[0] += g;
                p[1] += g * 0.45;
                p[2] += g * 0.12;
            }
        }
    }
}

impl crate::Game for Flame {
    fn step(&mut self, inp: Option<&mut Input>) {
        self.tick += 1;
        self.scene_t += 1;
        let skip = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        if skip && self.scene_t < SCENE_LEN - FADE {
            self.scene_t = SCENE_LEN - FADE; // fade out now
        }
        if self.scene_t >= SCENE_LEN {
            self.scene_t = 0;
            self.scene ^= 1;
        }
        // the fire keeps burning behind the candles, ready for its turn
        self.step_fire();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = vec![[0.0f32; 3]; W * H];
        if self.scene == 0 {
            self.render_fire(&mut buf);
        } else {
            self.render_candles(&mut buf);
        }
        let fade = (self.scene_t.min(SCENE_LEN - self.scene_t) as f32 / FADE as f32).min(1.0);
        for (p, b) in c.px.iter_mut().zip(&buf) {
            for i in 0..3 {
                p[i] = ((b[i] * fade).clamp(0.0, 1.0).powf(1.8) * 255.0) as u8;
            }
        }
    }
    fn status(&self) -> String {
        format!("{}", if self.scene == 0 { "bonfire" } else { "candles" })
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
