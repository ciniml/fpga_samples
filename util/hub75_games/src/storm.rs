// A thunderstorm on 128x192 (a demo, no game).
//
// Heavy clouds drift along the top, rain slants down and splashes on the
// hills. Every few seconds lightning strikes: a jagged channel grows from
// the cloud base to the ground with branches that die out in the air, and
// it flashes several times (return strokes) before it fades. The flash
// lights the clouds around the bolt, the sky and the ground. In between,
// flashes inside the clouds light them up without a bolt. A lone tree and a
// house with a lit window stand on the hill.
//
// Sound (the board's I2S output, audio.rs): rain all along, and thunder
// after each flash, later and duller the farther away it is (0.2 to 2.2 s
// after the light): a crack for close strikes, one per return stroke, then
// a rumble of several rolls of low noise.
use crate::audio::{self, Lp, Noise, Voice};
use crate::fx::{add, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::Rng;

const CLOUD_BASE: f32 = 52.0;
const HF: f32 = H as f32;
const WF: f32 = W as f32;
// brightness of a strike over time (ticks): stroke, dark, re-strokes
const STROKES: [f32; 24] = [
    1.0, 0.9, 0.5, 0.1, 0.05, 0.6, 1.0, 0.4, 0.1, 0.05, 0.05, 0.1, 0.8, 0.5, 0.25, 0.15, 0.1, 0.07, 0.05, 0.035, 0.025,
    0.015, 0.01, 0.0,
];

fn ground(x: f32) -> f32 {
    170.0 + 6.0 * noise(x * 0.025, 51) + 2.0 * noise(x * 0.1, 52)
}

struct Drop {
    x: f32,
    y: f32,
    v: f32,
}

struct Bolt {
    pts: Vec<(f32, f32, f32)>, // x, y, weight (1 main channel, less on branches)
    t: usize,
    x: f32, // where it lands (lights the clouds around)
}

pub struct Storm {
    rng: Rng,
    tick: u64,
    drops: Vec<Drop>,
    splashes: Vec<(f32, f32, f32, f32, i32)>,
    bolt: Option<Bolt>,
    next: i32,
    cloud_flash: Option<(f32, f32, i32)>, // x, y, ticks
    wind: f32,
}

impl Storm {
    pub fn new(seed: u64, _hi: u64) -> Storm {
        let mut rng = Rng::new(seed);
        let drops = (0..260)
            .map(|_| Drop { x: rng.range(-20.0, WF + 20.0), y: rng.range(30.0, HF), v: rng.range(3.0, 4.5) })
            .collect();
        Storm { rng, tick: 0, drops, splashes: Vec::new(), bolt: None, next: 90, cloud_flash: None, wind: -0.9 }
    }

    /// a jagged channel from (x, y) going down until `stop`; branches split off
    fn channel(&mut self, pts: &mut Vec<(f32, f32, f32)>, mut x: f32, mut y: f32, target: f32, w: f32, depth: u32) {
        let mut n = 0;
        loop {
            let dy = self.rng.range(2.0, 5.0);
            let pull = if w >= 1.0 { (target - x) * 0.06 } else { 0.0 };
            let dx = self.rng.range(-3.5, 3.5) + pull;
            let (nx, ny) = (x + dx, y + dy);
            // fill in the segment so the channel has no gaps
            let steps = (dx.abs().max(dy)).ceil() as i32;
            for k in 1..=steps {
                let f = k as f32 / steps as f32;
                pts.push((x + dx * f, y + dy * f, w));
            }
            x = nx;
            y = ny;
            n += 1;
            if y >= ground(x) || (w < 1.0 && n as f32 > 6.0 + 30.0 * w * self.rng.f()) || x < -10.0 || x > WF + 10.0 {
                break;
            }
            if depth < 2 && self.rng.chance(if w >= 1.0 { 0.12 } else { 0.06 }) {
                let side = if self.rng.chance(0.5) { -1.0 } else { 1.0 };
                let bw = w * self.rng.range(0.35, 0.6);
                let bx = x + side * 2.0;
                self.channel(pts, bx, y, bx + side * 30.0, bw, depth + 1);
            }
        }
    }

    /// thunder for a flash `dist` away (0 close .. 1 far)
    fn thunder(&mut self, dist: f32) {
        let seed = self.rng.next() as u32 | 1;
        let n = 2 + (self.rng.f() * 4.0) as usize;
        let mut c = self.rng.range(0.03, 0.15);
        let mut rolls = Vec::new();
        for k in 0..n {
            let amp = if k == 0 { 1.0 } else { self.rng.range(0.35, 0.9) } * (1.0 - 0.15 * k as f32);
            rolls.push((c, self.rng.range(0.04, 0.25) * (1.0 + dist), self.rng.range(0.2, 0.6) * (1.0 + dist), amp));
            c += self.rng.range(0.2, 0.6) * (1.0 + dist);
        }
        audio::play(Thunder::new(seed, dist, rolls));
    }

    fn strike(&mut self) {
        let d = self.rng.f();
        self.thunder(d * d);
        let x0 = self.rng.range(15.0, WF - 15.0);
        let target = (x0 + self.rng.range(-30.0, 30.0)).clamp(8.0, WF - 8.0);
        let mut pts = Vec::new();
        self.channel(&mut pts, x0, CLOUD_BASE - 6.0, target, 1.0, 0);
        let &(lx, ly, _) = pts.iter().filter(|p| p.2 >= 1.0).last().unwrap_or(&(x0, HF, 1.0));
        self.bolt = Some(Bolt { pts, t: 0, x: lx });
        // sparks where it lands
        for _ in 0..25 {
            let a = self.rng.range(3.4, 6.0);
            let v = self.rng.range(0.5, 2.0);
            self.splashes.push((lx, ly, a.cos() * v, a.sin() * v, 25));
        }
    }

    /// 0..1: how bright the current flash is
    fn flash(&self) -> f32 {
        let b = self.bolt.as_ref().map_or(0.0, |b| STROKES[b.t.min(STROKES.len() - 1)]);
        let c = self.cloud_flash.map_or(0.0, |(_, _, t)| if t % 5 < 2 { 0.35 } else { 0.1 });
        b.max(c)
    }

    fn update(&mut self, now: bool) {
        if self.tick == 0 {
            audio::play(Rain::new(self.rng.next() as u32 | 1));
        }
        self.tick += 1;
        let t = self.tick as f32;
        self.wind = -0.9 + 0.5 * noise(t * 0.003, 53);
        for d in &mut self.drops {
            d.x += self.wind;
            d.y += d.v;
            let g = ground(d.x);
            if d.y >= g {
                if self.rng.chance(0.5) {
                    for _ in 0..2 {
                        let vx = self.rng.range(-0.6, 0.6);
                        self.splashes.push((d.x, g - 1.0, vx, -self.rng.range(0.3, 0.9), 10));
                    }
                }
                d.y = self.rng.range(CLOUD_BASE - 20.0, CLOUD_BASE);
                d.x = self.rng.range(-10.0, WF + 40.0);
            }
        }
        for s in &mut self.splashes {
            s.0 += s.2;
            s.1 += s.3;
            s.3 += 0.12;
            s.4 -= 1;
        }
        self.splashes.retain(|s| s.4 > 0);
        if let Some(b) = &mut self.bolt {
            b.t += 1;
            if b.t >= STROKES.len() {
                self.bolt = None;
            }
        }
        if let Some(c) = &mut self.cloud_flash {
            c.2 -= 1;
            if c.2 <= 0 {
                self.cloud_flash = None;
            }
        }
        self.next -= 1;
        if now || self.next <= 0 {
            if now || self.rng.chance(0.65) {
                self.strike();
            } else {
                let d = self.rng.range(0.6, 1.0);
                self.thunder(d);
                let x = self.rng.range(10.0, WF - 10.0);
                self.cloud_flash = Some((x, self.rng.range(15.0, 45.0), self.rng.range(8.0, 20.0) as i32));
            }
            self.next = self.rng.range(90.0, 330.0) as i32;
        }
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let fl = self.flash();
        let (lx, ly) = match (&self.bolt, self.cloud_flash) {
            (Some(b), _) => (b.x, CLOUD_BASE),
            (None, Some((x, y, _))) => (x, y),
            _ => (64.0, 30.0),
        };
        // sky and clouds
        for y in 0..H {
            let fy = y as f32;
            for x in 0..W {
                let fx = x as f32;
                let mut c = [0.03, 0.033, 0.045];
                // the flash lights the air, most near the bolt
                let d2 = ((fx - lx).powi(2) + (fy - ly).powi(2) * 0.5) / 2500.0;
                let lit = fl / (1.0 + d2);
                c = [c[0] + 0.35 * lit, c[1] + 0.35 * lit, c[2] + 0.45 * lit];
                if fy < CLOUD_BASE + 24.0 {
                    let drift = t * 0.05;
                    let n = 0.55 * noise2((fx + drift) * 0.04, fy * 0.06, 999, 54)
                        + 0.3 * noise2((fx + drift * 1.6) * 0.1, fy * 0.13, 999, 55)
                        + 0.15 * noise2((fx + drift * 2.5) * 0.25, fy * 0.3, 999, 56);
                    // thick on top, ragged at the base
                    let dens = smooth(-0.3, 0.3, n + 1.0 - 1.1 * fy / CLOUD_BASE) * (1.0 - smooth(CLOUD_BASE - 8.0, CLOUD_BASE + 22.0, fy));
                    let shade = 0.5 + 0.5 * n; // bulges are lighter
                    let base = [0.3 * shade, 0.3 * shade, 0.36 * shade];
                    let glow = lit * (1.0 + 0.8 * n);
                    let cc = [base[0] + 0.45 * glow, base[1] + 0.45 * glow, base[2] + 0.55 * glow];
                    for i in 0..3 {
                        c[i] = c[i] * (1.0 - dens) + cc[i] * dens;
                    }
                }
                buf[y * W + x] = c;
            }
        }
        // the bolt: a white core and a violet glow
        if let Some(b) = &self.bolt {
            let k = STROKES[b.t.min(STROKES.len() - 1)];
            for &(x, y, w) in &b.pts {
                let v = k * w.powf(0.7);
                add(buf, x as i32, y as i32, [v * 1.2, v * 1.2, v * 1.4]);
                if w >= 1.0 {
                    for dy in -3i32..=3 {
                        for dx in -3i32..=3 {
                            let d2 = (dx * dx + dy * dy) as f32;
                            let g = v * 0.05 / (1.0 + d2);
                            add(buf, x as i32 + dx, y as i32 + dy, [g * 0.7, g * 0.6, g]);
                        }
                    }
                }
            }
        }
        // rain, brighter in a flash
        for d in &self.drops {
            let v = 0.25 + 0.5 * fl;
            for k in 0..4 {
                let f = 1.0 - k as f32 * 0.22;
                add(buf, (d.x - self.wind * k as f32 * 0.5) as i32, (d.y - d.v * k as f32 * 0.4) as i32, [v * f * 0.8, v * f * 0.9, v * f]);
            }
        }
        for s in &self.splashes {
            let v = s.4 as f32 / 25.0 * (0.5 + fl);
            add(buf, s.0 as i32, s.1 as i32, [v * 0.8, v * 0.85, v]);
        }
        // hills, a tree and a house, lit by the flash
        let house_x = 92;
        for x in 0..W {
            let fx = x as f32;
            let g = ground(fx);
            for y in g as usize..H {
                let fy = y as f32;
                let tex = 0.5 + 0.5 * noise2(fx * 0.3, fy * 0.3, 999, 57);
                let v = 0.02 + 0.18 * fl * (1.0 - (fy - g) / 30.0).max(0.2);
                buf[y * W + x] = [v * 0.7 * tex + 0.01, v * 0.9 * tex + 0.015, v * tex + 0.012];
            }
        }
        let sil = [0.008 + 0.08 * fl, 0.008 + 0.09 * fl, 0.012 + 0.11 * fl];
        // tree: a trunk and a ragged crown
        let (tx, ty) = (28.0, ground(28.0));
        for y in (ty - 34.0) as i32..ty as i32 + 1 {
            for x in (tx - 14.0) as i32..(tx + 14.0) as i32 {
                let (dx, dy) = (x as f32 - tx, y as f32 - (ty - 24.0));
                let crown = (dx * dx / 120.0 + dy * dy / 90.0) < 1.0 + 0.35 * noise2(x as f32 * 0.4, y as f32 * 0.4, 999, 58);
                let trunk = dx.abs() < 1.6 && y as f32 > ty - 18.0;
                if crown || trunk {
                    if x >= 0 && y >= 0 {
                        buf[y as usize * W + x as usize] = sil;
                    }
                }
            }
        }
        // house: walls, a roof, a warm window
        let hy = ground(house_x as f32 + 8.0) as i32;
        for y in hy - 12..hy + 1 {
            for x in house_x..house_x + 18 {
                buf[y as usize * W + x as usize] = sil;
            }
        }
        for k in 0..8 {
            for x in house_x - 2 + k..house_x + 20 - k {
                buf[(hy - 13 - k) as usize * W + x as usize] = sil;
            }
        }
        let wv = 0.75 + 0.1 * noise(t * 0.05, 59);
        for y in hy - 9..hy - 4 {
            for x in house_x + 5..house_x + 10 {
                buf[y as usize * W + x as usize] = [wv, wv * 0.6, wv * 0.2];
            }
        }
    }
}

impl crate::Game for Storm {
    fn step(&mut self, inp: Option<&mut Input>) {
        let now = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(now);
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.6);
    }
    fn status(&self) -> String {
        format!("{}", if self.bolt.is_some() { "STRIKE" } else { "rain" })
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

struct Thunder {
    t: usize,
    delay: usize,
    len: usize,
    noise: Noise,
    lo: [Lp; 2],
    mid: [Lp; 2],
    crack_lp: Lp,
    rolls: Vec<(f32, f32, f32, f32)>, // centre, rise, decay (s), amplitude
    crack: f32,
    loud: f32,
    dull: f32,
}

impl Thunder {
    fn new(seed: u32, dist: f32, rolls: Vec<(f32, f32, f32, f32)>) -> Thunder {
        let end = rolls.iter().map(|r| r.0 + 4.0 * r.2).fold(0.0, f32::max);
        Thunder {
            t: 0,
            delay: ((0.2 + 2.0 * dist) * audio::RATE) as usize,
            len: (end * audio::RATE) as usize,
            noise: Noise(seed),
            lo: [Lp::new(120.0), Lp::new(160.0)],
            mid: [Lp::new(250.0), Lp::new(900.0 - 500.0 * dist)],
            crack_lp: Lp::new(1500.0),
            rolls,
            crack: (1.0 - dist / 0.35).max(0.0),
            loud: 1.0 - 0.55 * dist,
            dull: dist,
        }
    }
}

impl Voice for Thunder {
    fn next(&mut self) -> Option<f32> {
        self.t += 1;
        if self.t < self.delay {
            return Some(0.0);
        }
        let s = (self.t - self.delay) as f32 / audio::RATE;
        if self.t - self.delay > self.len {
            return None;
        }
        let w = self.noise.next();
        // crack: high noise, one burst per return stroke (STROKES)
        let mut out = 0.0;
        if self.crack > 0.0 {
            let hi = w - self.crack_lp.run(w);
            let e: f32 = [(0.0, 1.0), (0.1, 0.7), (0.2, 0.55)]
                .iter()
                .filter(|(c, _)| s >= *c)
                .map(|(c, a)| a * (-(s - c) / 0.03).exp())
                .sum();
            out += 1.6 * self.crack * e * hi;
        }
        // rumble: low noise (the speaker is small: keep some of 250..900 Hz)
        let env: f32 = self
            .rolls
            .iter()
            .map(|&(c, r, d, a)| a * if s < c { (-((c - s) / r).powi(2)).exp() } else { (-(s - c) / d).exp() })
            .sum();
        let l0 = self.lo[0].run(w);
        let lo = self.lo[1].run(l0) * 14.0;
        let m1 = self.mid[0].run(w);
        let mid = (self.mid[1].run(w) - m1) * 4.0 * (1.0 - 0.6 * self.dull);
        out += self.loud * env * (lo + mid);
        Some(out)
    }
}

/// rain: soft band noise that swells slowly, and drops ticking on things
struct Rain {
    noise: Noise,
    hp: Lp,
    lp: Lp,
    tick_lp: Lp,
    t: u32,
    tick: f32,
}

impl Rain {
    fn new(seed: u32) -> Rain {
        Rain { noise: Noise(seed), hp: Lp::new(800.0), lp: Lp::new(6000.0), tick_lp: Lp::new(3000.0), t: 0, tick: 0.0 }
    }
}

impl Voice for Rain {
    fn next(&mut self) -> Option<f32> {
        self.t = self.t.wrapping_add(1);
        let w = self.noise.next();
        let band = self.lp.run(w) - self.hp.run(w);
        let swell = 1.0 + 0.3 * noise(self.t as f32 / audio::RATE * 0.4, 61);
        // a drop now and then: a short click
        if self.noise.next() > 0.9985 {
            self.tick = 0.1 + 0.2 * self.noise.next().abs();
        }
        self.tick *= 0.995;
        let click = self.tick_lp.run(w * self.tick);
        Some(0.07 * swell * band + click)
    }
}
