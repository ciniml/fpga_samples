// Fireworks over a night skyline on 128x192 (a demo, no game).
//
// Rockets climb with a spark trail and burst at the top of their flight
// into one of several shells: peony (a sphere seen from the side), chrysan-
// themum (sparks that leave trails), ring (a tilted circle), willow (gold,
// slow, drooping), palm (thick arms), crossette (stars that split in four),
// strobe (blinking), heart. Stars start white hot, take their colour and
// redden as they die. They are drawn into a glow buffer that fades a little
// every tick, which gives the streaks. A burst lights the sky; about every
// 45 s a finale fires many shells at once. Space / Enter: a finale now.
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::Rng;
use std::f32::consts::{PI, TAU};

const G: f32 = 0.035; // gravity, px / tick^2
const DECAY: f32 = 0.80; // glow left after a tick
const FINALE_EVERY: u64 = 45 * 60;
const FINALE_LEN: i32 = 7 * 60;
const HF: f32 = H as f32;
const WF: f32 = W as f32;

type Col = [f32; 3]; // 0..1 (and more for white hot)

const COLOURS: [Col; 9] = [
    [1.0, 0.15, 0.1],  // red
    [0.15, 1.0, 0.2],  // green
    [0.2, 0.35, 1.0],  // blue
    [1.0, 0.7, 0.15],  // gold
    [0.8, 0.2, 1.0],   // purple
    [0.1, 0.9, 1.0],   // cyan
    [1.0, 0.45, 0.05], // orange
    [1.0, 0.3, 0.6],   // pink
    [0.9, 0.9, 1.0],   // silver
];
const GOLD: Col = [1.0, 0.6, 0.15];

#[derive(Clone, Copy, PartialEq)]
enum Shell {
    Peony,
    Chrysanthemum,
    Ring,
    Willow,
    Palm,
    Crossette,
    Strobe,
    Heart,
}
const SHELLS: [Shell; 8] = [
    Shell::Peony,
    Shell::Chrysanthemum,
    Shell::Ring,
    Shell::Willow,
    Shell::Palm,
    Shell::Crossette,
    Shell::Strobe,
    Shell::Heart,
];

struct Rocket {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    shell: Shell,
    col: Col,
    col2: Col,
}

#[derive(Clone, Copy)]
struct Star {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    max: i32,
    col: Col,
    drag: f32,
    grav: f32,
    trail: bool,  // drops sparks that hang and fade
    strobe: u32,  // > 0: blinks with this period
    split: bool,  // crossette: four stars at half life
    hot: i32,     // ticks of white at the start
}

struct Building {
    x: i32,
    w: i32,
    h: i32,
    windows: Vec<(i32, i32, f32)>, // x, y, brightness
}

pub struct Fireworks {
    rng: Rng,
    tick: u64,
    glow: Vec<Col>,
    rockets: Vec<Rocket>,
    stars: Vec<Star>,
    sky_stars: Vec<(i32, i32, f32)>,
    city: Vec<Building>,
    flash: Col,
    next: i32,
    finale: i32,
    bursts: u64,
}

impl Fireworks {
    pub fn new(seed: u64, _hi: u64) -> Fireworks {
        let mut rng = Rng::new(seed);
        let mut city = Vec::new();
        let mut x = -2;
        while x < W as i32 {
            let w = 8 + (rng.next() % 14) as i32;
            let h = 8 + (rng.next() % 26) as i32;
            let mut windows = Vec::new();
            for wy in (H as i32 - h + 3..H as i32 - 2).step_by(4) {
                for wx in (x + 2..x + w - 2).step_by(3) {
                    if rng.chance(0.3) {
                        windows.push((wx, wy, rng.range(0.25, 0.7)));
                    }
                }
            }
            city.push(Building { x, w, h, windows });
            x += w + (rng.next() % 3) as i32;
        }
        let sky_stars = (0..40)
            .map(|_| ((rng.next() % W as u64) as i32, (rng.next() % 140) as i32, rng.range(0.0, TAU)))
            .collect();
        Fireworks {
            rng,
            tick: 0,
            glow: vec![[0.0; 3]; W * H],
            rockets: Vec::new(),
            stars: Vec::new(),
            sky_stars,
            city,
            flash: [0.0; 3],
            next: 30,
            finale: 0,
            bursts: 0,
        }
    }

    fn colour(&mut self) -> Col {
        COLOURS[(self.rng.next() % COLOURS.len() as u64) as usize]
    }

    fn launch(&mut self) {
        let shell = SHELLS[(self.rng.next() % SHELLS.len() as u64) as usize];
        let x = self.rng.range(20.0, WF - 20.0);
        let apex = self.rng.range(25.0, 85.0);
        let vy = -(2.0 * G * (HF - apex)).sqrt();
        let vx = (self.rng.range(25.0, WF - 25.0) - x) / (-vy / G) * 0.6;
        let col = self.colour();
        let col2 = if self.rng.chance(0.4) { self.colour() } else { col };
        self.rockets.push(Rocket { x, y: HF, vx, vy, shell, col, col2 });
    }

    fn star(&mut self, x: f32, y: f32, vx: f32, vy: f32, life: i32, col: Col) -> Star {
        let life = (life as f32 * self.rng.range(0.8, 1.2)) as i32;
        Star { x, y, vx, vy, life, max: life, col, drag: 0.975, grav: G * 0.5, trail: false, strobe: 0, split: false, hot: 6 }
    }

    fn burst(&mut self, r: &Rocket) {
        self.bursts += 1;
        let (x, y) = (r.x, r.y);
        let mut add: Vec<Star> = Vec::new();
        // a random point of a sphere seen from the side
        let sphere = |rng: &mut Rng| {
            let a = rng.range(0.0, TAU);
            let u = rng.range(-1.0, 1.0);
            let m = (1.0 - u * u).sqrt();
            (a.cos() * m, a.sin() * m)
        };
        let v = self.rng.range(1.6, 2.2);
        match r.shell {
            Shell::Peony | Shell::Chrysanthemum | Shell::Strobe => {
                for i in 0..110 {
                    let (dx, dy) = sphere(&mut self.rng);
                    let col = if i % 3 == 0 { r.col2 } else { r.col };
                    let mut s = self.star(x, y, dx * v, dy * v, 70, col);
                    s.trail = r.shell == Shell::Chrysanthemum;
                    if r.shell == Shell::Strobe {
                        s.strobe = 4 + (self.rng.next() % 4) as u32;
                        s.life += 30;
                        s.max = s.life;
                    }
                    add.push(s);
                }
            }
            Shell::Ring => {
                let tilt = self.rng.range(0.25, 1.0);
                let rot = self.rng.range(0.0, PI);
                for i in 0..56 {
                    let a = i as f32 * TAU / 56.0;
                    let (px, py) = (a.cos(), a.sin() * tilt);
                    let (dx, dy) = (px * rot.cos() - py * rot.sin(), px * rot.sin() + py * rot.cos());
                    add.push(self.star(x, y, dx * v, dy * v, 65, r.col));
                }
                for _ in 0..20 {
                    let (dx, dy) = sphere(&mut self.rng);
                    add.push(self.star(x, y, dx * 0.6, dy * 0.6, 40, r.col2));
                }
            }
            Shell::Willow => {
                for _ in 0..90 {
                    let (dx, dy) = sphere(&mut self.rng);
                    let mut s = self.star(x, y, dx * v * 0.8, dy * v * 0.8, 150, GOLD);
                    s.drag = 0.96;
                    s.grav = G * 0.35;
                    s.trail = true;
                    add.push(s);
                }
            }
            Shell::Palm => {
                let arms = 7 + (self.rng.next() % 4) as usize;
                let a0 = self.rng.range(0.0, TAU);
                for k in 0..arms {
                    let a = a0 + k as f32 * TAU / arms as f32;
                    for j in 0..9 {
                        let vv = v * (0.6 + 0.06 * j as f32);
                        let aa = a + self.rng.range(-0.05, 0.05);
                        let mut s = self.star(x, y, aa.cos() * vv, aa.sin() * vv, 90, GOLD);
                        s.trail = j == 8;
                        add.push(s);
                    }
                }
                for _ in 0..30 {
                    let (dx, dy) = sphere(&mut self.rng);
                    add.push(self.star(x, y, dx * 0.7, dy * 0.7, 50, r.col));
                }
            }
            Shell::Crossette => {
                for i in 0..14 {
                    let a = i as f32 * TAU / 14.0 + self.rng.range(-0.1, 0.1);
                    let mut s = self.star(x, y, a.cos() * v * 0.8, a.sin() * v * 0.8, 50, r.col);
                    s.split = true;
                    s.trail = true;
                    add.push(s);
                }
            }
            Shell::Heart => {
                for i in 0..70 {
                    let t = i as f32 * TAU / 70.0;
                    let hx = 16.0 * t.sin().powi(3);
                    let hy = -(13.0 * t.cos() - 5.0 * (2.0 * t).cos() - 2.0 * (3.0 * t).cos() - (4.0 * t).cos());
                    let mut s = self.star(x, y, hx * 0.11, hy * 0.11, 70, COLOURS[7]);
                    s.drag = 0.96;
                    s.grav = G * 0.2;
                    add.push(s);
                }
            }
        }
        // the flash of the burst lights the sky
        let k = 0.35;
        for i in 0..3 {
            self.flash[i] = (self.flash[i] + r.col[i] * k).min(0.6);
        }
        self.stars.extend(add);
    }

    /// adds col along the line from (x0, y0) to (x1, y1)
    fn streak(glow: &mut [Col], x0: f32, y0: f32, x1: f32, y1: f32, col: Col) {
        let n = ((x1 - x0).abs().max((y1 - y0).abs()).ceil() as i32).clamp(1, 8);
        for k in 0..n {
            let t = (k + 1) as f32 / n as f32;
            let (x, y) = (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t);
            if x >= 0.0 && y >= 0.0 && x < WF && y < HF {
                let p = &mut glow[y as usize * W + x as usize];
                for i in 0..3 {
                    p[i] += col[i];
                }
            }
        }
    }

    fn update(&mut self, finale_now: bool) {
        self.tick += 1;
        for p in &mut self.glow {
            for c in p.iter_mut() {
                *c *= DECAY;
            }
        }
        for c in &mut self.flash {
            *c *= 0.9;
        }
        // ---- launches ----
        if finale_now || (self.tick % FINALE_EVERY == 0 && self.finale == 0) {
            self.finale = FINALE_LEN;
        }
        if self.finale > 0 {
            self.finale -= 1;
            if self.finale % 7 == 0 && self.finale > 60 {
                self.launch();
            }
        } else {
            self.next -= 1;
            if self.next <= 0 {
                self.launch();
                if self.rng.chance(0.25) {
                    self.launch();
                }
                self.next = self.rng.range(35.0, 95.0) as i32;
            }
        }
        // ---- rockets ----
        let mut i = 0;
        while i < self.rockets.len() {
            let r = &mut self.rockets[i];
            let (ox, oy) = (r.x, r.y);
            r.x += r.vx;
            r.y += r.vy;
            r.vy += G;
            let (x, y, vy) = (r.x, r.y, r.vy);
            Self::streak(&mut self.glow, ox, oy, x, y, [0.9, 0.6, 0.3]);
            if self.rng.chance(0.7) {
                let s = Star {
                    x,
                    y,
                    vx: self.rng.range(-0.2, 0.2),
                    vy: self.rng.range(0.1, 0.5),
                    life: 12,
                    max: 12,
                    col: [1.0, 0.5, 0.15],
                    drag: 0.9,
                    grav: 0.0,
                    trail: false,
                    strobe: 0,
                    split: false,
                    hot: 0,
                };
                self.stars.push(s);
            }
            if vy >= -0.15 {
                let r = self.rockets.swap_remove(i);
                self.burst(&r);
            } else {
                i += 1;
            }
        }
        // ---- stars ----
        let mut born: Vec<Star> = Vec::new();
        for s in &mut self.stars {
            let (ox, oy) = (s.x, s.y);
            s.vx *= s.drag;
            s.vy = s.vy * s.drag + s.grav;
            s.x += s.vx;
            s.y += s.vy;
            s.life -= 1;
            let age = s.max - s.life;
            let f = s.life as f32 / s.max as f32;
            // white hot -> colour -> red and dim
            let mut c = if age < s.hot {
                let w = 1.0 - age as f32 / s.hot as f32;
                [s.col[0] + w, s.col[1] + w, s.col[2] + w]
            } else {
                let r = (1.0 - f).powi(3) * 0.6;
                [s.col[0], s.col[1] * (1.0 - r), s.col[2] * (1.0 - r)]
            };
            let b = f.powf(0.6) * 0.9;
            let lit = s.strobe == 0 || (self.tick as u32 + (s.x as u32)) / s.strobe % 2 == 0;
            for k in &mut c {
                *k *= if lit { b } else { 0.0 };
            }
            if s.strobe > 0 && lit {
                c = [b * 1.2, b * 1.2, b * 1.2]; // strobes blink white
            }
            Self::streak(&mut self.glow, ox, oy, s.x, s.y, c);
            if s.trail && s.life % 2 == 0 && self.rng.chance(0.6) {
                born.push(Star {
                    x: s.x,
                    y: s.y,
                    vx: 0.0,
                    vy: 0.05,
                    life: 25,
                    max: 25,
                    col: [s.col[0] * 0.5 + 0.25, s.col[1] * 0.4 + 0.15, s.col[2] * 0.3],
                    drag: 0.9,
                    grav: 0.004,
                    trail: false,
                    strobe: 0,
                    split: false,
                    hot: 0,
                });
            }
            if s.split && s.life == s.max / 2 {
                s.life = 0;
                let a0 = self.rng.range(0.0, PI / 2.0);
                for k in 0..4 {
                    let a = a0 + k as f32 * PI / 2.0;
                    born.push(Star {
                        vx: s.vx * 0.3 + a.cos() * 1.0,
                        vy: s.vy * 0.3 + a.sin() * 1.0,
                        life: 35,
                        max: 35,
                        split: false,
                        trail: false,
                        hot: 3,
                        ..*s
                    });
                }
            }
        }
        self.stars.retain(|s| s.life > 0 && s.y < HF + 2.0);
        self.stars.extend(born);
    }

    fn render(&self, c: &mut Canvas) {
        let t = self.tick as f32;
        let e = crate::fx::gamma(1.6);
        for y in 0..H {
            // night sky: deep blue on top, a little lighter at the horizon
            let k = y as f32 / HF;
            let sky = [0.01 + 0.02 * k, 0.01 + 0.025 * k, 0.05 + 0.06 * k];
            for x in 0..W {
                let g = self.glow[y * W + x];
                let mut p = [0u8; 3];
                for i in 0..3 {
                    let v = sky[i] + self.flash[i] * (0.3 + 0.7 * k) + g[i];
                    p[i] = (v.min(1.0).powf(e) * 255.0) as u8;
                }
                c.px[y * W + x] = p;
            }
        }
        // the stars and the city are drawn straight in panel colours: undo
        // the board's gamma for them
        let k = 1.0 / crate::fx::board_gamma();
        let u = |v: f32| ((v / 255.0).clamp(0.0, 1.0).powf(k) * 255.0) as u8;
        for &(x, y, ph) in &self.sky_stars {
            let b = (0.35 + 0.25 * (t * 0.05 + ph).sin()).max(0.0);
            let v = u(b * 127.5);
            c.padd(x, y, [v, v, v]);
        }
        // the skyline in front, lit a little by the bursts
        let lit = self.flash.iter().sum::<f32>() / 3.0;
        for b in &self.city {
            let col = [u(6.0 + 60.0 * lit), u(6.0 + 50.0 * lit), u(10.0 + 60.0 * lit)];
            c.rect(b.x, H as i32 - b.h, b.w, b.h, col);
            for &(wx, wy, wb) in &b.windows {
                let v = wb * (0.85 + 0.15 * (t * 0.01 + wx as f32).sin());
                c.rect(wx, wy, 2, 2, [u(200.0 * v), u(150.0 * v), u(60.0 * v)]);
            }
        }
    }
}

impl crate::Game for Fireworks {
    fn step(&mut self, inp: Option<&mut Input>) {
        let now = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(now);
    }
    fn draw(&self, c: &mut Canvas) {
        self.render(c);
    }
    fn status(&self) -> String {
        format!("bursts {}  stars {}{}", self.bursts, self.stars.len(), if self.finale > 0 { "  FINALE" } else { "" })
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
