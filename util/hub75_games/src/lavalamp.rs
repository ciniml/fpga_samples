// A lava lamp on 128x192 (a demo, no game).
//
// Wax blobs in a tapered glass: each has a temperature; the lamp at the
// bottom heats it, it rises (buoyancy minus drag), cools near the top and
// sinks again. The wax is drawn as metaballs (sum of r^2 / d^2 over the
// blobs, inside where it is above 1), so blobs merge and pinch apart. The
// shading follows the field (bright, glowing centres), the liquid lights up
// near the bulb, and the colours of wax and liquid change slowly.
use crate::fx::{mix, new_buf, noise, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::Input;
use crate::Rng;

const TOP: f32 = 30.0; // inside of the glass
const BOT: f32 = 160.0;
const CX: f32 = 64.0;

// wax / liquid colour pairs, changing every 40 s
const THEMES: [(Col, Col); 4] = [
    ([1.0, 0.25, 0.05], [0.25, 0.05, 0.35]),
    ([0.2, 1.0, 0.3], [0.05, 0.1, 0.35]),
    ([1.0, 0.2, 0.6], [0.05, 0.2, 0.3]),
    ([1.0, 0.75, 0.1], [0.35, 0.05, 0.1]),
];

/// half width of the inside of the glass (narrow at the top)
fn half_width(y: f32) -> f32 {
    let k = ((y - TOP) / (BOT - TOP)).clamp(0.0, 1.0);
    16.0 + 16.0 * k
}

struct Blob {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    r: f32,
    heat: f32, // 0 cold .. 1 hot
}

pub struct LavaLamp {
    tick: u64,
    blobs: Vec<Blob>,
}

impl LavaLamp {
    pub fn new(seed: u64, _hi: u64) -> LavaLamp {
        let mut rng = Rng::new(seed);
        let blobs = (0..8)
            .map(|i| Blob {
                x: CX + rng.range(-12.0, 12.0),
                y: if i < 3 { BOT - 4.0 } else { rng.range(TOP + 20.0, BOT - 10.0) },
                vx: 0.0,
                vy: 0.0,
                r: if i < 3 { rng.range(8.0, 10.0) } else { rng.range(4.5, 7.0) },
                heat: rng.f(),
            })
            .collect();
        LavaLamp { tick: 0, blobs }
    }

    fn update(&mut self) {
        self.tick += 1;
        let t = self.tick as f32;
        let n = self.blobs.len();
        for i in 0..n {
            let (bx, by, br) = (self.blobs[i].x, self.blobs[i].y, self.blobs[i].r);
            // soft push apart so they do not all pile up in one place
            let (mut fx, mut fy) = (0.0, 0.0);
            for j in 0..n {
                if i != j {
                    let (dx, dy) = (bx - self.blobs[j].x, by - self.blobs[j].y);
                    let d = (dx * dx + dy * dy).sqrt().max(0.5);
                    let reach = br + self.blobs[j].r;
                    if d < reach {
                        let k = 0.0015 * (reach - d);
                        fx += dx / d * k;
                        fy += dy / d * k;
                    }
                }
            }
            let b = &mut self.blobs[i];
            // heated only near the bulb, cooled only near the top (big blobs
            // change slowly), so a blob goes all the way up and all the way down
            let rate = 0.006 * (8.0 / b.r);
            if b.y > BOT - 22.0 {
                b.heat += (1.0 - b.heat) * rate;
            } else if b.y < TOP + 28.0 {
                b.heat -= b.heat * rate;
            } else {
                b.heat += (0.45 - b.heat) * 0.0004; // one stuck halfway sinks in the end
            }
            let buoy = (b.heat - 0.5) * -0.006;
            b.vy = (b.vy + buoy + fy) * 0.985;
            b.vx = (b.vx + fx + 0.002 * noise(t * 0.01 + i as f32 * 7.0, 81)) * 0.97;
            b.x += b.vx;
            b.y += b.vy;
            let w = half_width(b.y) - b.r * 0.6;
            if (b.x - CX).abs() > w {
                b.x = CX + (b.x - CX).signum() * w;
                b.vx *= -0.3;
            }
            if b.y > BOT - b.r * 0.4 {
                b.y = BOT - b.r * 0.4;
                b.vy = b.vy.min(0.0);
            }
            if b.y < TOP + b.r * 0.4 {
                b.y = TOP + b.r * 0.4;
                b.vy = b.vy.max(0.0);
            }
        }
    }

    fn theme(&self) -> (Col, Col) {
        let p = self.tick as f32 / (40.0 * 60.0);
        let (i, f) = (p.floor() as usize, smooth(0.85, 1.0, p.fract()));
        let (a, b) = (THEMES[i % THEMES.len()], THEMES[(i + 1) % THEMES.len()]);
        (mix(a.0, b.0, f), mix(a.1, b.1, f))
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let (wax, liquid) = self.theme();
        for y in 0..H {
            let fy = y as f32;
            for x in 0..W {
                let fx = x as f32;
                let dx = fx + 0.5 - CX;
                // room: dark, a little of the lamp's light on the wall
                let glow = 0.06 / (1.0 + (dx * dx + (fy - 120.0).powi(2)) / 2500.0);
                let mut c = [0.01 + glow * wax[0], 0.01 + glow * wax[1], 0.02 + glow * wax[2]];
                let w = half_width(fy);
                if fy >= TOP - 2.0 && fy < BOT + 2.0 && dx.abs() < w + 2.0 {
                    if dx.abs() >= w || fy < TOP || fy >= BOT {
                        c = [0.12, 0.12, 0.14]; // glass rim
                    } else {
                        // liquid, lit from the bulb below; the field of the blobs
                        let lit = 0.35 + 0.65 * smooth(TOP, BOT + 20.0, fy);
                        let side = 1.0 - (dx / w).powi(2) * 0.5;
                        // a layer of wax on the bottom that the blobs leave and join
                        let mut f = (7.0 / (BOT + 3.0 - fy)).powi(2);
                        for b in &self.blobs {
                            let (ex, ey) = (fx + 0.5 - b.x, fy + 0.5 - b.y);
                            f += b.r * b.r / (ex * ex + ey * ey * 1.15 + 0.5);
                        }
                        c = [liquid[0] * lit * side, liquid[1] * lit * side, liquid[2] * lit * side];
                        if f > 1.0 {
                            // inside the wax: brighter towards the middle and lower down
                            let core = smooth(1.0, 3.0, f);
                            let k = (0.55 + 0.45 * core) * (0.6 + 0.4 * lit) * side;
                            c = [wax[0] * k + 0.15 * core, wax[1] * k + 0.08 * core, wax[2] * k + 0.04 * core];
                        } else {
                            // a soft halo just outside
                            let h = smooth(0.6, 1.0, f) * 0.25;
                            for i in 0..3 {
                                c[i] += wax[i] * h;
                            }
                        }
                        // highlight on the glass
                        let hl = smooth(0.0, 1.0, 1.0 - ((dx / w) + 0.6).abs() * 6.0) * 0.12;
                        for v in &mut c {
                            *v += hl;
                        }
                    }
                }
                // metal cap and base
                let metal = |k: f32| -> Col {
                    let s = 0.25 + 0.35 * (1.0 - k * k) + 0.1 * noise(fy * 0.8, 82);
                    [s, s * 0.95, s * 0.9]
                };
                if fy >= TOP - 14.0 && fy < TOP - 2.0 {
                    let cw = 10.0 + (fy - (TOP - 14.0)) * 0.6;
                    if dx.abs() < cw {
                        c = metal(dx / cw);
                    }
                }
                if fy >= BOT + 2.0 && fy < 186.0 {
                    let k = (fy - BOT - 2.0) / (186.0 - BOT - 2.0);
                    let bw = 34.0 - 14.0 * (k * 2.0 - 1.0).abs().min(1.0) * if k < 0.5 { 1.0 } else { -0.4 };
                    if dx.abs() < bw {
                        c = metal(dx / bw);
                        // the bulb glows through the slot at the top of the base
                        if fy < BOT + 6.0 {
                            let flick = 0.9 + 0.1 * noise(t * 0.2, 83);
                            c = [1.0 * flick, 0.8 * flick, 0.5 * flick];
                        }
                    }
                }
                buf[y * W + x] = c;
            }
        }
    }
}

impl crate::Game for LavaLamp {
    fn step(&mut self, _inp: Option<&mut Input>) {
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.5);
    }
    fn status(&self) -> String {
        format!("blobs {}", self.blobs.len())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
