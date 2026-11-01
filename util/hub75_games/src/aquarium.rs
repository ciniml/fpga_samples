// A tropical fish tank on 128x192 (a demo, no game).
//
// Light rays slant down from a shimmering surface, caustics play on the
// sand, seaweed sways, bubbles wobble up from an air stone. The fish are
// drawn from a formula in their own coordinates (u along the body from tail
// to head, v across): an oval body that bends as the tail beats, a tail
// fan, fins, stripes, an eye. They cruise, drift up and down, and turn
// round (squeezing to edge-on and back) at the glass or when they feel like
// it. Kinds: clownfish, a school of neon tetras, angelfish, yellow tangs.
use crate::fx::{add, mix, new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::Input;
use crate::Rng;

const SAND: f32 = 172.0;
const HF: f32 = H as f32;
const WF: f32 = W as f32;

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Clown,
    Neon,
    Angel,
    Tang,
}

struct Fish {
    kind: Kind,
    x: f32,
    y: f32,
    dir: f32, // +1 right, -1 left
    face: f32, // -1..1 while turning (the squeeze)
    speed: f32,
    len: f32, // half length
    seed: u32,
    leader: Option<(usize, f32, f32)>, // school: follow fish i at an offset
}

pub struct Aquarium {
    rng: Rng,
    tick: u64,
    fish: Vec<Fish>,
    bubbles: Vec<(f32, f32, f32, f32)>, // x, y, r, phase
    weeds: Vec<(f32, f32, f32, Col)>,   // root x, height, phase, colour
}

impl Aquarium {
    pub fn new(seed: u64, _hi: u64) -> Aquarium {
        let mut rng = Rng::new(seed);
        let mut fish = Vec::new();
        let mut add_fish = |rng: &mut Rng, kind: Kind, len: f32, speed: f32, leader: Option<(usize, f32, f32)>| {
            let n = fish.len();
            fish.push(Fish {
                kind,
                x: rng.range(15.0, WF - 15.0),
                y: rng.range(30.0, 150.0),
                dir: if rng.chance(0.5) { 1.0 } else { -1.0 },
                face: 1.0,
                speed,
                len,
                seed: 200 + n as u32 * 17,
                leader,
            });
            n
        };
        add_fish(&mut rng, Kind::Angel, 8.0, 0.25, None);
        add_fish(&mut rng, Kind::Tang, 9.0, 0.4, None);
        add_fish(&mut rng, Kind::Clown, 8.0, 0.45, None);
        add_fish(&mut rng, Kind::Clown, 7.0, 0.5, None);
        let lead = add_fish(&mut rng, Kind::Neon, 5.0, 0.6, None);
        for (dx, dy) in [(-9.0, -5.0), (-10.0, 6.0), (-19.0, 0.0), (-20.0, -9.0), (-21.0, 9.0), (-29.0, 3.0)] {
            add_fish(&mut rng, Kind::Neon, 5.0, 0.6, Some((lead, dx, dy)));
        }
        add_fish(&mut rng, Kind::Tang, 7.0, 0.35, None);
        let weeds = (0..9)
            .map(|i| {
                let x = 6.0 + i as f32 * 14.0 + rng.range(-4.0, 4.0);
                let red = i % 4 == 2;
                (x, rng.range(30.0, 75.0), rng.range(0.0, 6.28), if red { [0.6, 0.15, 0.2] } else { [0.15, 0.55, 0.15] })
            })
            .collect();
        Aquarium { rng, tick: 0, fish, bubbles: Vec::new(), weeds }
    }

    fn update(&mut self) {
        self.tick += 1;
        let t = self.tick as f32;
        for i in 0..self.fish.len() {
            if let Some((l, ox, oy)) = self.fish[i].leader {
                // keep station behind the leader, with a little wander
                let (lx, ly, ld, lf) = (self.fish[l].x, self.fish[l].y, self.fish[l].dir, self.fish[l].face);
                let f = &mut self.fish[i];
                let s = f.seed as f32;
                let (tx, ty) = (lx + ox * ld + 2.0 * noise(t * 0.02, f.seed), ly + oy + 2.0 * noise(t * 0.02 + s, f.seed + 1));
                f.x += (tx - f.x) * 0.05;
                f.y += (ty - f.y) * 0.05;
                f.dir = ld;
                f.face += (lf - f.face) * 0.3;
                continue;
            }
            let f = &mut self.fish[i];
            // turning: the face goes over to the new side
            f.face += (f.dir - f.face) * 0.12;
            let margin = f.len * 2.0 + 4.0;
            let want_turn = (f.dir > 0.0 && f.x > WF - margin) || (f.dir < 0.0 && f.x < margin) || self.rng.chance(0.0015);
            if want_turn && (f.face - f.dir).abs() < 0.05 {
                f.dir = -f.dir;
            }
            let sp = f.speed * (0.7 + 0.3 * noise(t * 0.01, f.seed + 2)) * f.face.abs().max(0.2);
            f.x += sp * f.face.signum();
            f.y += 0.25 * noise(t * 0.006, f.seed + 3);
            f.y = f.y.clamp(22.0, SAND - f.len * 1.6);
        }
        // bubbles from the air stone
        if self.tick % 9 == 0 {
            let r = self.rng.range(0.8, 2.0);
            let ph = self.rng.range(0.0, 6.28);
            self.bubbles.push((104.0 + self.rng.range(-1.5, 1.5), SAND - 2.0, r, ph));
        }
        for b in &mut self.bubbles {
            b.1 -= 0.5 + 0.25 * b.2;
            b.0 += 0.25 * (t * 0.15 + b.3).sin();
            b.2 += 0.004;
        }
        self.bubbles.retain(|b| b.1 > 8.0);
    }

    /// colour of fish f at body coordinates (u: -1 tail root .. 1 snout, v up), None outside
    fn fish_px(f: &Fish, u: f32, v: f32, t: f32) -> Option<Col> {
        let tall = match f.kind {
            Kind::Angel => 0.95,
            Kind::Tang => 0.75,
            Kind::Clown => 0.48,
            Kind::Neon => 0.32,
        };
        // the body bends as the tail beats
        let beat = (t * 0.3 + f.seed as f32).sin();
        let v = v - beat * 0.12 * (1.0 - u).powi(2) * tall;
        let body = if u.abs() < 1.0 { tall * (1.0 - u * u).sqrt() * (1.0 + 0.2 * u) } else { 0.0 };
        let inside = v.abs() < body;
        // tail fan behind the body
        let tail = u < -0.85 && u > -1.55 && v.abs() < (-0.85 - u) * tall * 1.2 + 0.08;
        // fins
        let fins = match f.kind {
            Kind::Angel => {
                let along = u > -0.6 && u < 0.4;
                along && v.abs() < body + (0.4 - u) * 1.6 && v.abs() > body * 0.5
                    || (u < -0.2 && u > -0.9 && v.abs() < body + 0.6 * (u + 0.9))
            }
            Kind::Tang => u > -0.7 && u < 0.5 && v.abs() < body + 0.18,
            _ => u > -0.5 && u < 0.2 && v > 0.0 && v < body + 0.15,
        };
        if !(inside || tail || fins) {
            return None;
        }
        let shade = 0.75 + 0.35 * (v / tall.max(0.1)).clamp(-1.0, 1.0); // lit from above
        // the eye
        if inside && (u - 0.62).powi(2) * 4.0 + (v - tall * 0.2).powi(2) / (tall * tall * 0.05) < 0.25 {
            return Some([0.02, 0.02, 0.02]);
        }
        let c: Col = match f.kind {
            Kind::Clown => {
                let band = |c: f32| (u - c).abs() < 0.11;
                let edge = |c: f32| (u - c).abs() < 0.16;
                if inside && (band(0.5) || band(-0.05) || band(-0.6)) {
                    [1.0, 1.0, 1.0]
                } else if inside && (edge(0.5) || edge(-0.05) || edge(-0.6)) {
                    [0.05, 0.03, 0.02]
                } else if tail || fins {
                    [1.0, 0.45, 0.05]
                } else {
                    [1.0, 0.4, 0.0]
                }
            }
            Kind::Neon => {
                if tail || fins {
                    [0.4, 0.45, 0.5]
                } else if v > body * 0.1 && v < body * 0.6 {
                    let k = 0.5 + 0.5 * (t * 0.05 + u * 3.0).sin(); // the stripe glints
                    mix([0.1, 0.6, 1.0], [0.4, 1.0, 1.0], k)
                } else if v <= body * 0.1 && u < 0.1 {
                    [1.0, 0.1, 0.15]
                } else {
                    [0.7, 0.72, 0.75]
                }
            }
            Kind::Angel => {
                let stripe = (u - 0.25).abs() < 0.08 || (u + 0.25).abs() < 0.1 || (u + 0.75).abs() < 0.07;
                if stripe {
                    [0.08, 0.08, 0.1]
                } else if fins && !inside {
                    [0.55, 0.6, 0.65]
                } else {
                    [0.85, 0.85, 0.8]
                }
            }
            Kind::Tang => {
                if tail && u < -1.0 {
                    [1.0, 0.85, 0.1]
                } else if inside && (u + 0.85).abs() < 0.06 {
                    [1.0, 1.0, 1.0] // the spine
                } else {
                    [1.0, 0.85, 0.05]
                }
            }
        };
        Some([c[0] * shade, c[1] * shade, c[2] * shade])
    }

    fn render(&self, buf: &mut [Col]) {
        let t = self.tick as f32;
        let sand_y = |x: f32| SAND + 3.0 * noise(x * 0.06, 111) + 1.5 * noise(x * 0.2, 112);
        for y in 0..H {
            let fy = y as f32;
            let k = fy / HF;
            for x in 0..W {
                let fx = x as f32;
                // water, lighter at the top
                let mut c = mix([0.05, 0.3, 0.42], [0.0, 0.05, 0.16], k.powf(0.8));
                // slanting light rays from the surface
                let ray = smooth(0.35, 0.9, noise((fx + fy * 0.35) * 0.06 + t * 0.002, 113)) * (1.0 - k) * 0.22;
                c = [c[0] + ray * 0.6, c[1] + ray * 0.9, c[2] + ray];
                // the shimmering surface
                if fy < 7.0 + 1.5 * noise(fx * 0.1 + t * 0.02, 114) {
                    let s = 0.3 + 0.25 * noise2(fx * 0.2, fy * 0.6 + t * 0.03, 999, 115);
                    c = [s * 0.6, s, s * 1.1];
                }
                // sand with caustics
                if fy >= sand_y(fx) {
                    let caus = (noise2(fx * 0.18 + t * 0.01, fy * 0.3, 999, 116) + noise2(fx * 0.15 - t * 0.008, fy * 0.25 + 9.0, 999, 117)).abs();
                    let web = smooth(0.25, 0.0, caus) * 0.35;
                    let grain = 0.85 + 0.15 * noise2(fx * 0.8, fy * 0.8, 999, 118);
                    c = [0.45 * grain + web, 0.36 * grain + web, 0.22 * grain + web * 0.8];
                }
                buf[y * W + x] = c;
            }
        }
        // rocks and the air stone
        for (rx, ry, rw, rh) in [(22.0, SAND + 2.0, 14.0, 10.0), (78.0, SAND + 4.0, 10.0, 7.0)] {
            for y in (ry - rh) as i32..(ry + 2.0) as i32 {
                for x in (rx - rw) as i32..(rx + rw) as i32 {
                    let (dx, dy) = ((x as f32 - rx) / rw, (y as f32 - ry) / rh);
                    if dx * dx + dy * dy < 1.0 + 0.15 * noise2(x as f32 * 0.4, y as f32 * 0.4, 999, 119) && x >= 0 && (x as usize) < W {
                        let s = 0.18 + 0.1 * (-dy) + 0.05 * noise2(x as f32 * 0.5, y as f32 * 0.5, 999, 120);
                        buf[y as usize * W + x as usize] = [s * 0.9, s, s * 1.05];
                    }
                }
            }
        }
        for x in 101..108 {
            for y in (SAND - 3.0) as usize..SAND as usize {
                buf[y * W + x] = [0.25, 0.25, 0.3];
            }
        }
        let draw_weed = |buf: &mut [Col], &(rx, h, ph, col): &(f32, f32, f32, Col)| {
            let base = sand_y(rx);
            for k in 0..h as i32 {
                let f = k as f32 / h;
                let sway = (t * 0.025 + ph + f * 2.5).sin() * f.powf(1.3) * 7.0 + noise(t * 0.01 + rx, 121) * f * 3.0;
                let x = rx + sway;
                let y = base - k as f32;
                let w = 1.6 * (1.0 - f * 0.6);
                for dx in -2..=2 {
                    let xx = x + dx as f32;
                    if (xx - x).abs() < w {
                        let s = 0.6 + 0.5 * f;
                        let p = (y as usize) * W + xx as usize;
                        if xx >= 0.0 && (xx as usize) < W {
                            buf[p] = [col[0] * s, col[1] * s, col[2] * s];
                        }
                    }
                }
            }
        };
        // back weeds, fish (small ones first), front weeds, bubbles
        for (i, w) in self.weeds.iter().enumerate() {
            if i % 2 == 0 {
                draw_weed(buf, w);
            }
        }
        let mut order: Vec<usize> = (0..self.fish.len()).collect();
        order.sort_by(|&a, &b| self.fish[a].len.total_cmp(&self.fish[b].len));
        for &i in &order {
            let f = &self.fish[i];
            // the squeeze while turning (never quite edge-on)
            let s = if f.face >= 0.0 { f.face.max(0.12) } else { f.face.min(-0.12) };
            let reach = (f.len * 1.7) as i32 + 2;
            let tall = f.len * 2.2;
            for dy in -(tall as i32)..=(tall as i32) {
                for dx in -reach..=reach {
                    let (px, py) = (f.x as i32 + dx, f.y as i32 + dy);
                    if px < 0 || py < 0 || px as usize >= W || py as usize >= H {
                        continue;
                    }
                    let u = dx as f32 / (f.len * s);
                    let v = -(dy as f32) / f.len;
                    if let Some(c) = Self::fish_px(f, u, v, t) {
                        buf[py as usize * W + px as usize] = c;
                    }
                }
            }
        }
        for (i, w) in self.weeds.iter().enumerate() {
            if i % 2 == 1 {
                draw_weed(buf, w);
            }
        }
        for &(bx, by, r, _) in &self.bubbles {
            for dy in -3i32..=3 {
                for dx in -3i32..=3 {
                    let d = ((dx * dx + dy * dy) as f32).sqrt();
                    let ring = (1.0 - (d - r).abs() * 1.5).max(0.0) * 0.35;
                    let hl = if dx == -1 && dy == -1 && r > 1.2 { 0.3 } else { 0.0 };
                    add(buf, bx as i32 + dx, by as i32 + dy, [ring * 0.7 + hl, ring + hl, ring + hl]);
                }
            }
        }
    }
}

impl crate::Game for Aquarium {
    fn step(&mut self, _inp: Option<&mut Input>) {
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.4);
    }
    fn status(&self) -> String {
        format!("fish {}  bubbles {}", self.fish.len(), self.bubbles.len())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
