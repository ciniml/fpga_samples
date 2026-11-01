// The game: a vertical scrolling shooter on 128x192, 60 ticks a second.
//
// Each stage is ~40 s of enemy waves (random picks, denser and faster
// every stage), a warning, then a boss with three bullet patterns that
// change with its health. The ship fires by itself; power items widen the
// shot (3 levels), a bomb clears the bullets and hurts every enemy.
use crate::gfx::{scale, Canvas, Rgb, Sprite, H, W};
use crate::input::{Input, Key};

/// one tick of controls (from the keyboard or the bot)
#[derive(Default, Clone, Copy)]
pub struct Ctl {
    pub dx: f32, // -1..1
    pub dy: f32,
    pub bomb: bool,  // edges
    pub start: bool,
    pub pause: bool,
}
use std::f32::consts::PI;

const STAGE_LEN: u32 = 40 * 60;
const WF: f32 = W as f32;
const HF: f32 = H as f32;

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn f(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
    fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f()
    }
    fn chance(&mut self, p: f32) -> bool {
        self.f() < p
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Zako,
    Diver,
    Turret,
    Boss,
}

struct Enemy {
    kind: Kind,
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    x0: f32,
    amp: f32,
    hp: i32,
    max_hp: i32,
    t: u32,
    flash: u8,
    dived: bool,
}

impl Enemy {
    fn new(kind: Kind, x: f32, y: f32, vx: f32, vy: f32, hp: i32) -> Enemy {
        Enemy { kind, x, y, vx, vy, x0: x, amp: 0.0, hp, max_hp: hp, t: 0, flash: 0, dived: false }
    }
    /// half size of the hit box
    fn half(&self) -> (f32, f32) {
        match self.kind {
            Kind::Zako => (4.0, 3.5),
            Kind::Diver => (4.0, 4.0),
            Kind::Turret => (7.0, 5.5),
            Kind::Boss => (15.0, 8.0),
        }
    }
    fn score(&self, stage: u32) -> u64 {
        match self.kind {
            Kind::Zako => 100,
            Kind::Diver => 150,
            Kind::Turret => 1000,
            Kind::Boss => 10000 * stage as u64,
        }
    }
}

struct Bullet {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    big: bool,
}

struct Shot {
    x: f32,
    y: f32,
    vx: f32,
}

struct Particle {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    max: i32,
    c: Rgb,
}

#[derive(Clone, Copy, PartialEq)]
enum ItemKind {
    Power,
    Bomb,
}

struct Item {
    x: f32,
    y: f32,
    kind: ItemKind,
}

struct Star {
    x: f32,
    y: f32,
    v: f32,
}

struct Sprites {
    ship: [Sprite; 2],
    zako: [Sprite; 2],
    diver: Sprite,
    turret: Sprite,
    boss: Sprite,
    life: Sprite,
}

fn sprites() -> Sprites {
    Sprites {
        ship: [
            Sprite::parse(&[
                "....W....", "....W....", "...WCW...", "...WCW...", "..WWCWW..", ".BWWWWWB.", "BBWWRWWBB",
                "B.WW.WW.B", "...Y.Y...", "...O.O...",
            ]),
            Sprite::parse(&[
                "....W....", "....W....", "...WCW...", "...WCW...", "..WWCWW..", ".BWWWWWB.", "BBWWRWWBB",
                "B.WW.WW.B", "...O.O...", "...R.R...",
            ]),
        ],
        zako: [
            Sprite::parse(&[".G.....G.", "..G...G..", ".GGGGGGG.", "GGRGGGRGG", "GGGGGGGGG", "G.G...G.G", ".G.....G."]),
            Sprite::parse(&[".G.....G.", "G.G...G.G", ".GGGGGGG.", "GGRGGGRGG", "GGGGGGGGG", "..G...G..", ".G.....G."]),
        ],
        diver: Sprite::parse(&[
            "M.......M", "MM.....MM", ".MMMMMMM.", "..MMWMM..", "..MMMMM..", "...MMM...", "...MPM...", "....M....",
        ]),
        turret: Sprite::parse(&[
            "...KKKKKKKKK...", "..KkkkkkkkkkK..", ".KkOOOOOOOOOkK.", "KkOOOYYYYYOOOkK", "KkOORRRRRRROOkK",
            "KkOORDDDDDROOkK", "KkOORDDDDDROOkK", ".KkOORRRRROOkK.", "..KkOOOOOOOkK..", "...KKKKRKKKK...",
            "......KRK......",
        ]),
        boss: Sprite::parse(&[
            "..........KKKKKKKKKKK..........",
            "........KKPPPPPPPPPPPKK........",
            "......KKPPPPMMMMMMMPPPPKK......",
            "....KKPPPPMMMWWWWWMMMPPPPKK....",
            "..KKPPPPPMMMWWRRRWWMMMPPPPPKK..",
            ".KPPPPPPMMMWWRRYRRWWMMMPPPPPPK.",
            "KPPKKPPMMMMWWRRRRRWWMMMMPPKKPPK",
            "KPKCCKPPMMMMWWWWWWWMMMMPPKCCKPK",
            "KPKCCKPPPMMMMMMMMMMMMMPPPKCCKPK",
            "KPPKKPPPPPPMMMMMMMMMPPPPPPKKPPK",
            ".KPPPPPKKPPPPPPPPPPPPPKKPPPPPK.",
            "..KPPPKRRKPPPKKKKKPPPKRRKPPPK..",
            "...KPKRYYRKPKRRRRRKPKRYYRKPK...",
            "....K.KRRK.KRYYYYYRK.KRRK.K....",
            ".......KK...KRRRRRK...KK.......",
            ".............KKKKK.............",
        ]),
        life: Sprite::parse(&["..W..", ".WCW.", "BWWWB", "B.R.B"]),
    }
}

#[derive(PartialEq)]
enum Scene {
    Title,
    Play,
    Over,
}

pub struct Stg {
    rng: Rng,
    scene: Scene,
    pub tick: u64,
    t: u32, // stage time
    pub stage: u32,
    pub score: u64,
    pub hi: u64,
    lives: i32,
    bombs: i32,
    power: u32,
    px: f32,
    py: f32,
    dead: i32,   // > 0: exploded, respawning
    invuln: i32, // ticks left
    shot_cd: i32,
    wave_cd: i32,
    warning: i32,
    clear: i32,
    flash: i32,
    over: i32,
    paused: bool,
    enemies: Vec<Enemy>,
    bullets: Vec<Bullet>,
    shots: Vec<Shot>,
    parts: Vec<Particle>,
    items: Vec<Item>,
    stars: Vec<Star>,
    spr: Sprites,
}

impl Stg {
    pub fn new(seed: u64, hi: u64) -> Stg {
        let mut rng = Rng(seed | 1);
        let stars = (0..70)
            .map(|i| Star { x: rng.range(0.0, WF), y: rng.range(0.0, HF), v: [0.3, 0.7, 1.4][i % 3] })
            .collect();
        Stg {
            rng,
            scene: Scene::Title,
            tick: 0,
            t: 0,
            stage: 1,
            score: 0,
            hi,
            lives: 2,
            bombs: 3,
            power: 1,
            px: 64.0,
            py: 170.0,
            dead: 0,
            invuln: 0,
            shot_cd: 0,
            wave_cd: 120,
            warning: 0,
            clear: 0,
            flash: 0,
            over: 0,
            paused: false,
            enemies: Vec::new(),
            bullets: Vec::new(),
            shots: Vec::new(),
            parts: Vec::new(),
            items: Vec::new(),
            stars,
            spr: sprites(),
        }
    }

    fn start(&mut self) {
        let hi = self.hi;
        let seed = self.rng.next();
        *self = Stg::new(seed, hi);
        self.scene = Scene::Play;
        self.invuln = 120;
    }

    /// one tick
    pub fn update(&mut self, ctl: &Ctl) {
        self.tick += 1;
        for s in &mut self.stars {
            s.y += s.v;
            if s.y >= HF {
                s.y -= HF;
                s.x = self.rng.range(0.0, WF);
            }
        }
        match self.scene {
            Scene::Title => {
                if ctl.start {
                    self.start();
                }
            }
            Scene::Over => {
                self.over += 1;
                self.step_world();
                if self.over > 60 && ctl.start {
                    self.start();
                } else if self.over > 600 {
                    self.scene = Scene::Title;
                }
            }
            Scene::Play => {
                if ctl.pause {
                    self.paused = !self.paused;
                }
                if !self.paused {
                    self.play(ctl);
                }
            }
        }
    }

    /// attract mode: keep below the nearest enemy, step away from the
    /// bullets coming close, bomb when cornered; starts the next game
    pub fn bot(&self) -> Ctl {
        let mut ctl = Ctl { start: self.tick % 120 == 0, ..Ctl::default() };
        if self.scene != Scene::Play || self.dead > 0 {
            return ctl;
        }
        let target = self
            .enemies
            .iter()
            .filter(|e| e.y > 0.0 && e.y < self.py - 20.0)
            .min_by(|a, b| (a.x - self.px).abs().total_cmp(&(b.x - self.px).abs()))
            .map_or(64.0, |e| e.x);
        let (mut fx, mut fy) = ((target - self.px) * 0.08, (165.0 - self.py) * 0.05);
        let mut danger = 0;
        for b in &self.bullets {
            let (dx, dy) = (self.px - b.x, self.py - b.y);
            let d2 = dx * dx + dy * dy;
            if d2 < 26.0 * 26.0 && (b.vx * dx + b.vy * dy) > 0.0 {
                let w = 60.0 / (d2 + 4.0);
                fx += dx * w;
                fy += dy * w * 0.5;
                if d2 < 7.0 * 7.0 {
                    danger += 1;
                }
            }
        }
        for e in &self.enemies {
            let (dx, dy) = (self.px - e.x, self.py - e.y);
            if dx.abs() < 14.0 && dy.abs() < 24.0 && dy > -6.0 {
                fx += dx.signum() * 1.5;
                fy += 0.8;
            }
        }
        ctl.dx = fx.clamp(-1.0, 1.0);
        ctl.dy = fy.clamp(-1.0, 1.0);
        ctl.bomb = danger >= 2 && self.invuln == 0;
        ctl
    }

    fn bullet_speed(&self) -> f32 {
        0.9 + 0.12 * self.stage.min(8) as f32
    }

    fn fire(&mut self, x: f32, y: f32, ang: f32, v: f32, big: bool) {
        if self.bullets.len() < 400 {
            self.bullets.push(Bullet { x, y, vx: ang.cos() * v, vy: ang.sin() * v, big });
        }
    }

    fn explode(&mut self, x: f32, y: f32, n: usize, spd: f32) {
        for _ in 0..n {
            let a = self.rng.range(0.0, 2.0 * PI);
            let v = self.rng.range(0.2, spd);
            let life = self.rng.range(15.0, 40.0) as i32;
            let c = if self.rng.chance(0.3) { [255, 255, 200] } else { [255, 160, 0] };
            self.parts.push(Particle { x, y, vx: a.cos() * v, vy: a.sin() * v, life, max: life, c });
        }
    }

    fn play(&mut self, ctl: &Ctl) {
        self.t += 1;
        // ---- ship ----
        if self.dead > 0 {
            self.dead -= 1;
            if self.dead == 0 {
                if self.lives < 0 {
                    self.scene = Scene::Over;
                    self.over = 0;
                    self.hi = self.hi.max(self.score);
                } else {
                    self.px = 64.0;
                    self.py = 170.0;
                    self.invuln = 150;
                }
            }
        } else {
            let (mut dx, mut dy) = (ctl.dx, ctl.dy);
            if dx != 0.0 && dy != 0.0 && dx.abs() + dy.abs() > 1.2 {
                dx *= 0.75;
                dy *= 0.75;
            }
            self.px = (self.px + dx * 1.8).clamp(5.0, WF - 5.0);
            self.py = (self.py + dy * 1.8).clamp(14.0, HF - 8.0);
            self.invuln = (self.invuln - 1).max(0);
            self.shot_cd -= 1;
            if self.shot_cd <= 0 {
                self.shot_cd = 5;
                let (x, y) = (self.px, self.py - 5.0);
                self.shots.push(Shot { x: x - 2.0, y, vx: 0.0 });
                self.shots.push(Shot { x: x + 2.0, y, vx: 0.0 });
                if self.power >= 2 {
                    self.shots.push(Shot { x: x - 3.0, y: y + 2.0, vx: -0.8 });
                    self.shots.push(Shot { x: x + 3.0, y: y + 2.0, vx: 0.8 });
                }
                if self.power >= 3 {
                    self.shots.push(Shot { x: x - 4.0, y: y + 3.0, vx: -1.8 });
                    self.shots.push(Shot { x: x + 4.0, y: y + 3.0, vx: 1.8 });
                }
            }
            if ctl.bomb && self.bombs > 0 {
                self.bombs -= 1;
                self.flash = 24;
                self.invuln = self.invuln.max(90);
                let bl: Vec<(f32, f32)> = self.bullets.iter().map(|b| (b.x, b.y)).collect();
                for (x, y) in bl {
                    self.parts.push(Particle { x, y, vx: 0.0, vy: -0.5, life: 20, max: 20, c: [120, 200, 255] });
                    self.score += 10;
                }
                self.bullets.clear();
                for e in &mut self.enemies {
                    if e.y > 0.0 {
                        e.hp -= if e.kind == Kind::Boss { 40 } else { 25 };
                        e.flash = 4;
                    }
                }
            }
        }

        // ---- stage flow ----
        if self.clear > 0 {
            self.clear -= 1;
            if self.clear == 0 {
                self.stage += 1;
                self.t = 0;
                self.wave_cd = 120;
            }
        } else if self.t < STAGE_LEN {
            self.wave_cd -= 1;
            if self.wave_cd <= 0 {
                self.spawn_wave();
                let base = (105.0 - 10.0 * self.stage as f32).max(50.0);
                self.wave_cd = self.rng.range(base * 0.7, base * 1.2) as i32;
            }
        } else if self.t == STAGE_LEN {
            self.warning = 150;
        } else if self.warning > 0 {
            self.warning -= 1;
            if self.warning == 0 {
                let hp = 260 + 120 * self.stage as i32;
                self.enemies.push(Enemy::new(Kind::Boss, 64.0, -12.0, 0.0, 0.5, hp));
            }
        }

        self.step_enemies();
        self.step_world();
        self.collide();
    }

    fn spawn_wave(&mut self) {
        let s = self.stage as f32;
        let pick = self.rng.f();
        if pick < 0.28 {
            // sine line
            let x0 = self.rng.range(30.0, 98.0);
            let amp = self.rng.range(15.0, 30.0);
            for i in 0..5 {
                let mut e = Enemy::new(Kind::Zako, x0, -8.0 - 16.0 * i as f32, 0.0, 0.8 + 0.05 * s, 1);
                e.amp = amp;
                self.enemies.push(e);
            }
        } else if pick < 0.48 {
            // V formation
            let xc = self.rng.range(30.0, 98.0);
            for i in -2i32..=2 {
                let e = Enemy::new(Kind::Zako, xc + 12.0 * i as f32, -8.0 - 8.0 * i.abs() as f32, 0.0, 1.0, 1);
                self.enemies.push(e);
            }
        } else if pick < 0.66 {
            // divers
            for _ in 0..3 {
                let x = self.rng.range(12.0, 116.0);
                let y = self.rng.range(-30.0, -8.0);
                self.enemies.push(Enemy::new(Kind::Diver, x, y, 0.0, 0.7, 2));
            }
        } else if pick < 0.82 {
            // side sweep
            let left = self.rng.chance(0.5);
            let y = self.rng.range(20.0, 60.0);
            for i in 0..6 {
                let x = if left { -8.0 - 14.0 * i as f32 } else { WF + 8.0 + 14.0 * i as f32 };
                let vx = if left { 1.3 } else { -1.3 };
                self.enemies.push(Enemy::new(Kind::Zako, x, y + 3.0 * i as f32, vx, 0.25, 1));
            }
        } else if self.t > 300 {
            let x = self.rng.range(20.0, 108.0);
            let hp = 14 + 3 * self.stage as i32;
            self.enemies.push(Enemy::new(Kind::Turret, x, -8.0, 0.0, 0.35, hp));
        }
    }

    fn step_enemies(&mut self) {
        let bs = self.bullet_speed();
        let stage = self.stage;
        let mut shots: Vec<(f32, f32, f32, f32, bool)> = Vec::new(); // x, y, angle, speed, big
        let (px, py) = (self.px, self.py);
        for i in 0..self.enemies.len() {
            let r = self.rng.f();
            let e = &mut self.enemies[i];
            e.t += 1;
            e.flash = e.flash.saturating_sub(1);
            let aim = (py - e.y).atan2(px - e.x);
            match e.kind {
                Kind::Zako => {
                    if e.amp > 0.0 {
                        e.x = e.x0 + e.amp * (e.t as f32 * 0.04).sin();
                    } else {
                        e.x += e.vx;
                    }
                    e.y += e.vy;
                    let p = 0.002 + 0.0015 * stage.min(8) as f32;
                    if e.y > 10.0 && e.y < 120.0 && r < p {
                        shots.push((e.x, e.y, aim, bs, false));
                    }
                }
                Kind::Diver => {
                    if !e.dived && e.y > 30.0 + (e.x0 % 30.0) {
                        e.dived = true;
                        let a = aim;
                        e.vx = a.cos() * 2.0;
                        e.vy = a.sin().max(0.4) * 2.0;
                        shots.push((e.x, e.y, aim, bs, false));
                    }
                    e.x += e.vx;
                    e.y += e.vy;
                }
                Kind::Turret => {
                    if e.y < 40.0 {
                        e.y += e.vy * 2.0;
                    } else {
                        e.y += e.vy * 0.4;
                    }
                    let period = 70u32.saturating_sub(stage.min(6) * 6);
                    if e.t % period == 0 && e.y > 0.0 {
                        let n: i32 = if stage >= 3 { 5 } else { 3 };
                        for k in 0..n {
                            let a = aim + 0.22 * (k - n / 2) as f32;
                            shots.push((e.x, e.y + 5.0, a, bs * 1.1, true));
                        }
                    }
                }
                Kind::Boss => {
                    if e.y < 34.0 {
                        e.y += e.vy;
                    } else {
                        let tt = e.t as f32;
                        e.x = 64.0 + 34.0 * (tt * 0.011).sin();
                        e.y = 34.0 + 6.0 * (tt * 0.023).sin();
                        let frac = e.hp as f32 / e.max_hp as f32;
                        let (x, y) = (e.x, e.y + 6.0);
                        if frac > 0.66 {
                            if e.t % 5 == 0 {
                                for arm in 0..3 {
                                    let a = tt * 0.09 + arm as f32 * 2.0 * PI / 3.0;
                                    shots.push((x, y, a, bs * 0.9, false));
                                }
                            }
                            if e.t % 70 == 0 {
                                shots.push((x, y, aim, bs * 1.4, true));
                            }
                        } else if frac > 0.33 {
                            if e.t % 32 == 0 {
                                for k in -3..=3 {
                                    shots.push((x, y, aim + 0.16 * k as f32, bs * 1.2, false));
                                }
                            }
                            if e.t % 90 == 45 {
                                for k in 0..20 {
                                    shots.push((x, y, k as f32 * 2.0 * PI / 20.0 + tt, bs * 0.8, true));
                                }
                            }
                        } else {
                            if e.t % 4 == 0 {
                                for arm in 0..2 {
                                    let a = arm as f32 * PI;
                                    shots.push((x, y, tt * 0.13 + a, bs, false));
                                    shots.push((x, y, -tt * 0.11 + a, bs * 0.8, false));
                                }
                            }
                            if e.t % 50 == 0 {
                                shots.push((x, y, aim, bs * 1.6, true));
                            }
                        }
                    }
                }
            }
        }
        for (x, y, a, v, big) in shots {
            self.fire(x, y, a, v, big);
        }
        // (enemies with hp <= 0 are scored and removed in collide())
        self.enemies.retain(|e| e.y < HF + 16.0 && e.x > -40.0 && e.x < WF + 40.0);
    }

    fn step_world(&mut self) {
        for s in &mut self.shots {
            s.x += s.vx;
            s.y -= 5.0;
        }
        self.shots.retain(|s| s.y > -4.0 && s.x > -2.0 && s.x < WF + 2.0);
        for b in &mut self.bullets {
            b.x += b.vx;
            b.y += b.vy;
        }
        self.bullets.retain(|b| b.x > -4.0 && b.x < WF + 4.0 && b.y > -4.0 && b.y < HF + 4.0);
        for p in &mut self.parts {
            p.x += p.vx;
            p.y += p.vy;
            p.vx *= 0.96;
            p.vy *= 0.96;
            p.life -= 1;
        }
        self.parts.retain(|p| p.life > 0);
        for it in &mut self.items {
            it.y += 0.6;
        }
        self.items.retain(|it| it.y < HF + 6.0);
        self.flash = (self.flash - 1).max(0);
    }

    fn collide(&mut self) {
        // shots → enemies
        let mut killed: Vec<usize> = Vec::new();
        for s in &mut self.shots {
            for (i, e) in self.enemies.iter_mut().enumerate() {
                let (hw, hh) = e.half();
                if e.hp > 0 && e.y > -4.0 && (s.x - e.x).abs() < hw + 1.0 && (s.y - e.y).abs() < hh + 2.0 {
                    e.hp -= 1;
                    if e.kind != Kind::Boss || e.t % 8 == 0 {
                        e.flash = 2; // the boss is hit all the time: blink now and then
                    }
                    s.y = -100.0;
                    if e.hp <= 0 {
                        killed.push(i);
                    }
                    break;
                }
            }
        }
        for (i, e) in self.enemies.iter().enumerate() {
            if e.hp <= 0 && !killed.contains(&i) {
                killed.push(i); // bombed
            }
        }
        killed.sort_unstable();
        killed.dedup();
        for &i in killed.iter().rev() {
            let e = self.enemies.remove(i);
            self.score += e.score(self.stage);
            match e.kind {
                Kind::Zako | Kind::Diver => self.explode(e.x, e.y, 10, 1.5),
                Kind::Turret => {
                    self.explode(e.x, e.y, 30, 2.0);
                    let kind = if self.rng.chance(0.25) { ItemKind::Bomb } else { ItemKind::Power };
                    self.items.push(Item { x: e.x, y: e.y, kind });
                }
                Kind::Boss => {
                    for k in 0..6 {
                        let (dx, dy) = ((k as f32 * 1.7).sin() * 12.0, (k as f32 * 2.3).cos() * 6.0);
                        self.explode(e.x + dx, e.y + dy, 30, 2.5);
                    }
                    self.flash = 30;
                    for b in std::mem::take(&mut self.bullets) {
                        self.parts.push(Particle { x: b.x, y: b.y, vx: 0.0, vy: -0.6, life: 25, max: 25, c: [255, 230, 0] });
                        self.score += 50;
                    }
                    self.items.push(Item { x: e.x - 8.0, y: e.y, kind: ItemKind::Power });
                    self.items.push(Item { x: e.x + 8.0, y: e.y, kind: ItemKind::Bomb });
                    self.clear = 240;
                }
            }
        }
        self.hi = self.hi.max(self.score);
        if self.dead > 0 || self.scene != Scene::Play {
            return;
        }
        // items
        let (px, py) = (self.px, self.py);
        let mut got: Vec<ItemKind> = Vec::new();
        self.items.retain(|it| {
            let hit = (it.x - px).abs() < 7.0 && (it.y - py).abs() < 8.0;
            if hit {
                got.push(it.kind);
            }
            !hit
        });
        for k in got {
            match k {
                ItemKind::Power if self.power < 3 => self.power += 1,
                ItemKind::Bomb if self.bombs < 5 => self.bombs += 1,
                _ => self.score += 2000,
            }
        }
        if self.invuln > 0 {
            return;
        }
        // bullets / bodies → ship (hit box 3x3 around the cockpit)
        let hit_b = self.bullets.iter().any(|b| {
            let r: f32 = if b.big { 2.6 } else { 1.8 };
            (b.x - px).powi(2) + (b.y - py).powi(2) < (r + 1.5).powi(2)
        });
        let hit_e = self.enemies.iter().any(|e| {
            let (hw, hh) = e.half();
            (e.x - px).abs() < hw - 1.0 && (e.y - py).abs() < hh - 1.0
        });
        if hit_b || hit_e {
            self.explode(px, py, 50, 2.5);
            self.flash = 12;
            self.lives -= 1;
            self.power = (self.power - 1).max(1);
            self.bombs = self.bombs.max(2);
            self.bullets.clear();
            self.dead = 100;
        }
    }

    // ---------------------------------------------------------------
    fn render(&self, c: &mut Canvas) {
        c.clear([0, 0, 6]);
        for s in &self.stars {
            let k = (s.v * 120.0) as u8;
            let col = if s.v > 1.0 { [k, k, 255] } else { [k, k, k.saturating_add(30)] };
            c.pset(s.x as i32, s.y as i32, col);
            if s.v > 1.0 {
                c.pset(s.x as i32, s.y as i32 - 1, scale(col, 0.4));
            }
        }
        match self.scene {
            Scene::Title => self.draw_title(c),
            _ => self.draw_play(c),
        }
        if self.flash > 0 {
            let k = (self.flash * 8).min(200) as u8;
            for p in &mut c.px {
                for i in 0..3 {
                    p[i] = p[i].saturating_add(k);
                }
            }
        }
    }

    fn draw_title(&self, c: &mut Canvas) {
        let t = self.tick as f32;
        let hue = |o: f32| -> Rgb {
            let f = |n: f32| ((t * 0.04 + o + n).sin() * 0.5 + 0.5) * 255.0;
            [f(0.0) as u8, f(2.1) as u8, f(4.2) as u8]
        };
        c.text_centre("HUB75", 30, 3, hue(0.0));
        c.text_centre("SHOOTER", 58, 2, hue(1.5));
        c.sprite(&self.spr.ship[(self.tick / 4 % 2) as usize], 64.0, 95.0 + 3.0 * (t * 0.05).sin(), None);
        if self.tick / 30 % 2 == 0 {
            c.text_centre("PRESS ENTER", 118, 1, [255, 255, 255]);
        }
        let g = [150, 150, 170];
        c.text("MOVE  ARROW/WASD", 4, 140, 1, g);
        c.text("BOMB  X", 4, 150, 1, g);
        c.text("PAUSE P  QUIT Q", 4, 160, 1, g);
        c.text_centre(&format!("HI {:07}", self.hi), 178, 1, [255, 230, 0]);
    }

    fn draw_play(&self, c: &mut Canvas) {
        for it in &self.items {
            let (col, ch) = match it.kind {
                ItemKind::Power => ([255, 40, 40], "P"),
                ItemKind::Bomb => ([40, 200, 80], "B"),
            };
            c.rect(it.x as i32 - 4, it.y as i32 - 5, 9, 10, col);
            c.text(ch, it.x as i32 - 2, it.y as i32 - 3, 1, [255, 255, 255]);
        }
        for e in &self.enemies {
            let tint = if e.flash > 0 { Some([255, 255, 255]) } else { None };
            let s = match e.kind {
                Kind::Zako => &self.spr.zako[(e.t / 8 % 2) as usize],
                Kind::Diver => &self.spr.diver,
                Kind::Turret => &self.spr.turret,
                Kind::Boss => &self.spr.boss,
            };
            c.sprite(s, e.x, e.y, tint);
        }
        for s in &self.shots {
            for k in 0..4 {
                let col = if k == 0 { [255, 255, 255] } else { [255, 230, 60] };
                c.pset(s.x as i32, s.y as i32 + k, col);
            }
        }
        if self.dead == 0 && self.scene == Scene::Play && (self.invuln == 0 || self.tick / 3 % 2 == 0) {
            c.sprite(&self.spr.ship[(self.tick / 3 % 2) as usize], self.px, self.py, None);
        }
        for p in &self.parts {
            c.padd(p.x as i32, p.y as i32, scale(p.c, p.life as f32 / p.max as f32));
        }
        for b in &self.bullets {
            if b.big {
                c.disc(b.x, b.y, 2.6, [255, 60, 60]);
                c.disc(b.x, b.y, 1.2, [255, 230, 230]);
            } else {
                c.disc(b.x, b.y, 1.8, [255, 40, 200]);
                c.pset(b.x as i32, b.y as i32, [255, 220, 255]);
            }
        }
        // HUD
        c.rect(0, 0, W as i32, 9, [0, 0, 0]);
        c.text(&format!("{:07}", self.score), 1, 1, 1, [255, 255, 255]);
        c.text(&format!("HI{:07}", self.hi), 74, 1, 1, [255, 230, 0]);
        if let Some(b) = self.enemies.iter().find(|e| e.kind == Kind::Boss) {
            let w = (b.hp.max(0) as f32 / b.max_hp as f32 * 120.0) as i32;
            c.rect(4, 10, 120, 3, [60, 0, 0]);
            c.rect(4, 10, w, 3, [255, 60, 60]);
        }
        for i in 0..self.lives.max(0) {
            c.sprite(&self.spr.life, 4.0 + 7.0 * i as f32, HF - 4.0, None);
        }
        for i in 0..self.bombs {
            c.rect(W as i32 - 6 - 7 * i, H as i32 - 7, 5, 5, [40, 200, 80]);
        }
        let mid = 80;
        if self.scene == Scene::Play && self.t < 150 && self.clear == 0 {
            c.text_centre(&format!("STAGE {}", self.stage), mid, 2, [255, 255, 255]);
        }
        if self.warning > 0 && self.warning / 15 % 2 == 0 {
            c.rect(0, mid - 6, W as i32, 2, [255, 0, 0]);
            c.rect(0, mid + 18, W as i32, 2, [255, 0, 0]);
            c.text_centre("WARNING", mid, 2, [255, 40, 40]);
        }
        if self.clear > 0 && self.clear < 200 {
            c.text_centre("STAGE", mid - 8, 2, [255, 230, 0]);
            c.text_centre("CLEAR", mid + 10, 2, [255, 230, 0]);
        }
        if self.paused {
            c.text_centre("PAUSE", mid, 2, [255, 255, 255]);
        }
        if self.scene == Scene::Over {
            c.text_centre("GAME", mid - 10, 3, [255, 60, 60]);
            c.text_centre("OVER", mid + 14, 3, [255, 60, 60]);
            if self.over > 60 && self.tick / 30 % 2 == 0 {
                c.text_centre("ENTER: RETRY", mid + 46, 1, [255, 255, 255]);
            }
        }
    }
}

fn ctl_from(inp: &mut Input) -> Ctl {
    let axis = |a: Key, b: Key| inp.held(b) as i32 as f32 - inp.held(a) as i32 as f32;
    let (dx, dy) = (axis(Key::Left, Key::Right), axis(Key::Up, Key::Down));
    Ctl {
        dx,
        dy,
        bomb: inp.take(Key::B),
        start: inp.take(Key::Start) | inp.take(Key::Space) | inp.take(Key::A),
        pause: inp.take(Key::Pause),
    }
}

impl crate::Game for Stg {
    fn step(&mut self, inp: Option<&mut Input>) {
        let ctl = match inp {
            Some(i) => ctl_from(i),
            None => self.bot(),
        };
        self.update(&ctl);
    }
    fn draw(&self, c: &mut Canvas) {
        self.render(c);
    }
    fn status(&self) -> String {
        format!("stage {}  score {:07}", self.stage, self.score)
    }
    fn hi(&self) -> u64 {
        self.hi
    }
}
