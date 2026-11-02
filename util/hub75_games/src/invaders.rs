// Invaders-style shooter on 128x192: a formation of 8 x 5 aliens steps
// sideways and down (faster as it thins out), four shields that crumble
// pixel by pixel, a UFO now and then, one cannon shot on screen at a time.
//
// Rows score 30 / 20 / 20 / 10 / 10, the UFO 50..300. Each new wave
// starts lower and steps faster. An extra cannon at 1500 points. The game
// ends when the cannons run out or the aliens reach the ground, or with
// ALL CLEAR (and a bonus for the cannons left) after the third wave, so a
// game takes about 3 minutes.
use crate::audio::{self, sfx, Tone};
use crate::gfx::{scale, Canvas, Rgb, Sprite, W};
use crate::input::{Input, Key};
use crate::Rng;

const WAVES: u32 = 3;
const COLS: usize = 8;
const ROWS: usize = 5;
const DXA: f32 = 13.0; // alien spacing
const DYA: f32 = 11.0;
const PLAYER_Y: f32 = 178.0;
const GROUND: i32 = 183;
const SHIELD_Y: i32 = 152;
const SHW: usize = 18;
const SHH: usize = 12;
const SHIELD_X: [i32; 4] = [7, 39, 71, 103]; // left edges
const WF: f32 = W as f32;

const SHIELD: [&str; SHH] = [
    "....##########....",
    "...############...",
    "..##############..",
    ".################.",
    "##################",
    "##################",
    "##################",
    "##################",
    "######......######",
    "#####........#####",
    "#####........#####",
    "#####........#####",
];

struct Sprites {
    alien: [[Sprite; 2]; 3],
    cannon: Sprite,
    ufo: Sprite,
}

fn sprites() -> Sprites {
    Sprites {
        alien: [
            [
                Sprite::parse(&["....M....", "...MMM...", "..MMMMM..", ".MM.M.MM.", ".MMMMMMM.", "..M.M.M..", ".M.....M."]),
                Sprite::parse(&["....M....", "...MMM...", "..MMMMM..", ".MM.M.MM.", ".MMMMMMM.", "...M.M...", "..M.M.M.."]),
            ],
            [
                Sprite::parse(&["..G...G..", "...G.G...", "..GGGGG..", ".GG.G.GG.", "GGGGGGGGG", "G.GGGGG.G", "G.G...G.G"]),
                Sprite::parse(&["..G...G..", "G..G.G..G", "G.GGGGG.G", "GGG.G.GGG", "GGGGGGGGG", ".GGGGGGG.", "..G...G.."]),
            ],
            [
                Sprite::parse(&["..CCCCC..", ".CCCCCCC.", "CCC.C.CCC", "CCCCCCCCC", "..CC.CC..", ".CC.C.CC.", "CC.....CC"]),
                Sprite::parse(&["..CCCCC..", ".CCCCCCC.", "CCC.C.CCC", "CCCCCCCCC", ".CC.C.CC.", "CC.....CC", ".CC...CC."]),
            ],
        ],
        cannon: Sprite::parse(&[
            ".....G.....", "....GGG....", "..GGGGGGG..", ".GGGGGGGGG.", "GGGGGGGGGGG", "GGGGGGGGGGG",
        ]),
        ufo: Sprite::parse(&["....RRRRR....", "..RRRRRRRRR..", ".RR.RR.RR.RR.", "RRRRRRRRRRRRR", "..RRR...RRR.."]),
    }
}

fn row_type(r: usize) -> usize {
    match r {
        0 => 0,
        1 | 2 => 1,
        _ => 2,
    }
}

struct Bomb {
    x: f32,
    y: f32,
    vy: f32,
    zig: bool,
}

struct Spark {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    c: Rgb,
}

#[derive(PartialEq)]
enum Scene {
    Title,
    Play,
    Over,
}

pub struct Invaders {
    rng: Rng,
    scene: Scene,
    tick: u64,
    alive: [[bool; COLS]; ROWS],
    ox: f32, // centre of alien (0, 0)
    oy: f32,
    dir: f32,
    step_cd: i32,
    frame: usize,
    px: f32,
    shot: Option<(f32, f32)>,
    bombs: Vec<Bomb>,
    shields: [[[bool; SHW]; SHH]; 4],
    ufo: Option<(f32, f32)>, // x, vx
    ufo_cd: i32,
    march: usize,
    ufo_msg: Option<(f32, u64, i32)>, // x, points, ticks
    wave: u32,
    score: u64,
    hi: u64,
    lives: i32,
    extra: bool,
    dead: i32,
    wave_t: i32, // pause before the next wave
    over_t: i32,
    all_clear: bool,
    bonus: u64,
    paused: bool,
    sparks: Vec<Spark>,
    spr: Sprites,
}

impl Invaders {
    pub fn new(seed: u64, hi: u64) -> Invaders {
        let mut g = Invaders {
            rng: Rng::new(seed),
            scene: Scene::Title,
            tick: 0,
            alive: [[true; COLS]; ROWS],
            ox: 18.0,
            oy: 30.0,
            dir: 1.0,
            step_cd: 30,
            frame: 0,
            px: 64.0,
            shot: None,
            bombs: Vec::new(),
            shields: [[[false; SHW]; SHH]; 4],
            ufo: None,
            ufo_cd: 1200,
            march: 0,
            ufo_msg: None,
            wave: 1,
            score: 0,
            hi,
            lives: 2,
            extra: false,
            dead: 0,
            wave_t: 0,
            over_t: 0,
            all_clear: false,
            bonus: 0,
            paused: false,
            sparks: Vec::new(),
            spr: sprites(),
        };
        g.new_wave();
        g
    }

    fn start(&mut self) {
        let (hi, seed) = (self.hi, self.rng.next());
        *self = Invaders::new(seed, hi);
        self.scene = Scene::Play;
        self.wave_t = 90;
        sfx::start();
    }

    fn new_wave(&mut self) {
        self.alive = [[true; COLS]; ROWS];
        self.ox = 18.0;
        self.oy = 30.0 + 6.0 * (self.wave - 1).min(5) as f32;
        self.dir = 1.0;
        self.bombs.clear();
        self.shot = None;
        for s in &mut self.shields {
            for (y, row) in SHIELD.iter().enumerate() {
                for (x, ch) in row.chars().enumerate() {
                    s[y][x] = ch == '#';
                }
            }
        }
    }

    /// ticks per formation step with n aliens left (2 px a step, at most 1 px a tick)
    fn step_period(&self, n: usize) -> i32 {
        (1 + n as i32 * 20 / 40 - (self.wave as i32 - 1) * 3).max(2)
    }

    fn count(&self) -> usize {
        self.alive.iter().flatten().filter(|&&a| a).count()
    }

    fn alien_pos(&self, c: usize, r: usize) -> (f32, f32) {
        (self.ox + c as f32 * DXA, self.oy + r as f32 * DYA)
    }

    fn burst(&mut self, x: f32, y: f32, c: Rgb, n: usize) {
        for _ in 0..n {
            let a = self.rng.range(0.0, std::f32::consts::TAU);
            let v = self.rng.range(0.3, 1.8);
            self.sparks.push(Spark { x, y, vx: a.cos() * v, vy: a.sin() * v, life: 25, c });
        }
    }

    /// a bullet / alien pixel at (x, y) on a shield: knock out a ragged
    /// spot; true if it hit
    fn shield_hit(&mut self, x: f32, y: f32, r: i32) -> bool {
        let (xi, yi) = (x as i32, y as i32);
        for (i, &sx) in SHIELD_X.iter().enumerate() {
            let (lx, ly) = (xi - sx, yi - SHIELD_Y);
            if lx < 0 || ly < 0 || lx >= SHW as i32 || ly >= SHH as i32 || !self.shields[i][ly as usize][lx as usize] {
                continue;
            }
            for dy in -r..=r {
                for dx in -r..=r {
                    let (qx, qy) = (lx + dx, ly + dy);
                    if qx >= 0 && qy >= 0 && qx < SHW as i32 && qy < SHH as i32 && (dx * dx + dy * dy <= r * r) {
                        if self.rng.chance(0.75) {
                            self.shields[i][qy as usize][qx as usize] = false;
                        }
                    }
                }
            }
            return true;
        }
        false
    }

    /// bot: under the lowest alien of the nearest column, out of the way of
    /// bombs falling close above
    fn bot(&self) -> (f32, bool) {
        // where each column's lowest alien will be when a shot fired now
        // reaches it (the formation folded back at the walls)
        let (mut minx, mut maxx) = (f32::MAX, f32::MIN);
        for r in 0..ROWS {
            for c in 0..COLS {
                if self.alive[r][c] {
                    let (x, _) = self.alien_pos(c, r);
                    minx = minx.min(x);
                    maxx = maxx.max(x);
                }
            }
        }
        let v = self.dir * 2.0 / self.step_period(self.count()) as f32;
        let (lo, hi) = (8.0 - minx, WF - 8.0 - maxx); // room for the formation offset
        let lead = |y: f32| {
            let d = v * (PLAYER_Y - 4.0 - y) / 4.0;
            let span = (hi - lo).max(0.1);
            let mut o = (d - lo).rem_euclid(2.0 * span);
            if o > span {
                o = 2.0 * span - o;
            }
            o + lo
        };
        let mut target = self.px;
        let mut best = f32::MAX;
        for c in 0..COLS {
            if let Some(r) = (0..ROWS).rev().find(|&r| self.alive[r][c]) {
                let (x, y) = self.alien_pos(c, r);
                let x = x + lead(y);
                let d = (x - self.px).abs() + r as f32 * 0.5;
                if d < best {
                    best = d;
                    target = x;
                }
            }
        }
        if let Some((ux, _)) = self.ufo {
            if (ux - self.px).abs() < 20.0 {
                target = ux;
            }
        }
        // step aside from shield pixels that would stop the shot
        let blocked = |x: f32| {
            let xi = x as i32;
            SHIELD_X.iter().enumerate().any(|(i, &sx)| {
                xi >= sx && xi < sx + SHW as i32 && (0..SHH).any(|y| self.shields[i][y][(xi - sx) as usize])
            })
        };
        if let Some(k) = [0.0f32, -2.0, 2.0, -3.5, 3.5].iter().find(|&&k| !blocked(target + k)) {
            target += k;
        }
        let mut dx = ((target - self.px) / 2.0).clamp(-1.0, 1.0);
        for b in &self.bombs {
            if (b.x - self.px).abs() < 9.0 && b.y > PLAYER_Y - 45.0 && b.y < PLAYER_Y + 2.0 {
                let away = if b.x > self.px { -1.0 } else { 1.0 };
                dx = if (self.px < 12.0 && away < 0.0) || (self.px > WF - 12.0 && away > 0.0) { -away } else { away };
            }
        }
        (dx, (target - self.px).abs() < 3.0 && !blocked(self.px))
    }

    fn play(&mut self, inp: Option<&mut Input>) {
        let (dx, fire) = match inp {
            Some(i) => {
                if i.take(Key::Pause) {
                    self.paused = !self.paused;
                }
                let dx = i.held(Key::Right) as i32 as f32 - i.held(Key::Left) as i32 as f32;
                let fire = i.held(Key::Space) | i.held(Key::A) | i.held(Key::Up);
                i.take(Key::Space);
                (dx, fire)
            }
            None => self.bot(),
        };
        if self.paused {
            return;
        }
        if self.wave_t > 0 {
            self.wave_t -= 1;
            return;
        }
        if let Some(m) = &mut self.ufo_msg {
            m.2 -= 1;
            if m.2 <= 0 {
                self.ufo_msg = None;
            }
        }
        // ---- cannon ----
        if self.dead > 0 {
            self.dead -= 1;
            if self.dead == 0 {
                if self.lives < 0 {
                    self.scene = Scene::Over;
                    self.over_t = 0;
                    sfx::game_over();
                    return;
                }
                self.px = 64.0;
            }
            return; // everything waits while the cannon explodes
        }
        self.px = (self.px + dx * 1.4).clamp(7.0, WF - 7.0);
        if fire && self.shot.is_none() {
            self.shot = Some((self.px, PLAYER_Y - 4.0));
            audio::play(Tone::new(1800.0, 0.035, 10.0).glide(500.0).square().len(0.09));
        }
        // ---- formation ----
        let n = self.count();
        self.step_cd -= 1;
        if self.step_cd <= 0 {
            self.step_cd = self.step_period(n);
            self.frame ^= 1;
            // the march: four rising bass notes (C D E G), one a step
            const MARCH: [f32; 4] = [130.8, 146.8, 164.8, 196.0];
            self.march = (self.march + 1) % 4;
            audio::play(Tone::new(MARCH[self.march], 0.09, 10.0).square().len(0.07));
            let (mut minx, mut maxx) = (f32::MAX, f32::MIN);
            for r in 0..ROWS {
                for c in 0..COLS {
                    if self.alive[r][c] {
                        let (x, _) = self.alien_pos(c, r);
                        minx = minx.min(x);
                        maxx = maxx.max(x);
                    }
                }
            }
            if (self.dir > 0.0 && maxx + 2.0 + 5.0 > WF - 1.0) || (self.dir < 0.0 && minx - 2.0 - 5.0 < 1.0) {
                self.oy += 4.0;
                self.dir = -self.dir;
            } else {
                self.ox += 2.0 * self.dir;
            }
        }
        // the aliens eat the shields and land
        let mut landed = false;
        for r in 0..ROWS {
            for c in 0..COLS {
                if self.alive[r][c] {
                    let (x, y) = self.alien_pos(c, r);
                    if y + 3.0 >= SHIELD_Y as f32 {
                        for k in -4..=4 {
                            self.shield_hit(x + k as f32, y + 3.0, 1);
                        }
                    }
                    if y + 3.0 >= PLAYER_Y - 2.0 {
                        landed = true;
                    }
                }
            }
        }
        if landed {
            sfx::die();
            self.burst(self.px, PLAYER_Y, [80, 255, 80], 40);
            self.lives = -1;
            self.dead = 90;
            return;
        }
        // ---- alien bombs ----
        let cap = (2 + self.wave as usize / 2).min(5);
        if self.bombs.len() < cap && self.rng.chance(0.03 + 0.006 * self.wave as f32) {
            let c = (self.rng.next() % COLS as u64) as usize;
            if let Some(r) = (0..ROWS).rev().find(|&r| self.alive[r][c]) {
                let (x, y) = self.alien_pos(c, r);
                let zig = self.rng.chance(0.5);
                self.bombs.push(Bomb { x, y: y + 4.0, vy: 1.1 + 0.1 * self.wave.min(8) as f32, zig });
            }
        }
        let mut i = 0;
        while i < self.bombs.len() {
            let (x, y) = {
                let b = &mut self.bombs[i];
                b.y += b.vy;
                (b.x, b.y)
            };
            let mut gone = y > GROUND as f32;
            if !gone && self.shield_hit(x, y + 2.0, 2) {
                gone = true;
            }
            if !gone && (x - self.px).abs() < 5.5 && y + 2.0 >= PLAYER_Y - 2.0 && y <= PLAYER_Y + 3.0 {
                sfx::die();
                self.burst(self.px, PLAYER_Y, [80, 255, 80], 40);
                self.lives -= 1;
                self.dead = 90;
                self.bombs.clear();
                self.shot = None;
                return;
            }
            if gone {
                if y > GROUND as f32 {
                    self.burst(x, GROUND as f32, [255, 255, 255], 3);
                }
                self.bombs.swap_remove(i);
            } else {
                i += 1;
            }
        }
        // ---- cannon shot ----
        if let Some((sx, sy)) = self.shot {
            let ny = sy - 4.0;
            let mut hit = ny < 12.0;
            if !hit && self.shield_hit(sx, ny, 1) {
                hit = true;
            }
            // shot vs bomb
            if !hit {
                if let Some(j) = self.bombs.iter().position(|b| (b.x - sx).abs() < 2.0 && (b.y - ny).abs() < 4.0) {
                    self.bombs.swap_remove(j);
                    self.burst(sx, ny, [255, 255, 255], 5);
                    sfx::hit();
                    hit = true;
                }
            }
            if !hit {
                'f: for r in 0..ROWS {
                    for c in 0..COLS {
                        if self.alive[r][c] {
                            let (x, y) = self.alien_pos(c, r);
                            if (x - sx).abs() <= 4.5 && (y - ny).abs() <= 4.0 {
                                self.alive[r][c] = false;
                                self.score += [30, 20, 20, 10, 10][r];
                                let col = [[255, 40, 200], [40, 230, 60], [0, 220, 255]][row_type(r)];
                                self.burst(x, y, col, 14);
                                sfx::explode(0.15);
                                hit = true;
                                break 'f;
                            }
                        }
                    }
                }
            }
            if !hit {
                if let Some((ux, _)) = self.ufo {
                    if (ux - sx).abs() < 7.0 && (ny - 18.0).abs() < 4.0 {
                        let pts = [50, 100, 150, 300][(self.rng.next() % 4) as usize];
                        self.score += pts;
                        self.burst(ux, 18.0, [255, 60, 60], 30);
                        self.ufo_msg = Some((ux, pts, 90));
                        self.ufo = None;
                        sfx::explode(0.6);
                        sfx::pickup();
                        hit = true;
                    }
                }
            }
            self.shot = if hit { None } else { Some((sx, ny)) };
        }
        // ---- UFO ----
        match self.ufo {
            Some((x, vx)) => {
                // the UFO: short rising chirps
                if self.tick % 10 == 0 {
                    audio::play(Tone::new(700.0, 0.03, 10.0).glide(1500.0).harm(0.3).len(0.1));
                }
                let nx = x + vx;
                self.ufo = if nx < -10.0 || nx > WF + 10.0 { None } else { Some((nx, vx)) };
            }
            None => {
                self.ufo_cd -= 1;
                if self.ufo_cd <= 0 && n > 6 {
                    self.ufo_cd = self.rng.range(900.0, 1800.0) as i32;
                    self.ufo = Some(if self.rng.chance(0.5) { (-8.0, 0.8) } else { (WF + 8.0, -0.8) });
                }
            }
        }
        if !self.extra && self.score >= 1500 {
            self.extra = true;
            self.lives += 1;
            sfx::extend();
        }
        if self.count() == 0 && self.wave == WAVES {
            self.bonus = 500 * (self.lives.max(0) as u64 + 1);
            self.score += self.bonus;
            self.all_clear = true;
            self.scene = Scene::Over;
            self.over_t = 0;
            sfx::fanfare();
        } else if self.count() == 0 {
            sfx::clear();
            self.wave += 1;
            self.new_wave();
            self.wave_t = 120;
        }
    }

    // ---------------------------------------------------------------
    fn render(&self, c: &mut Canvas) {
        c.clear([0, 0, 0]);
        if self.scene == Scene::Title {
            return self.render_title(c);
        }
        let dying = self.dead > 0;
        for r in 0..ROWS {
            for col in 0..COLS {
                if self.alive[r][col] {
                    let (x, y) = self.alien_pos(col, r);
                    c.sprite(&self.spr.alien[row_type(r)][self.frame], x, y, None);
                }
            }
        }
        for (i, &sx) in SHIELD_X.iter().enumerate() {
            for y in 0..SHH {
                for x in 0..SHW {
                    if self.shields[i][y][x] {
                        c.pset(sx + x as i32, SHIELD_Y + y as i32, [40, 230, 60]);
                    }
                }
            }
        }
        if let Some((ux, _)) = self.ufo {
            c.sprite(&self.spr.ufo, ux, 18.0, None);
        }
        if let Some((x, p, _)) = self.ufo_msg {
            let s = p.to_string();
            c.text(&s, x as i32 - s.len() as i32 * 3, 15, 1, [255, 80, 80]);
        }
        for b in &self.bombs {
            let wig = if b.zig && (b.y as i32 / 3) % 2 == 0 { 1 } else { 0 };
            for k in 0..4 {
                let o = if b.zig { if (b.y as i32 + k) % 4 < 2 { wig } else { -wig } } else { 0 };
                c.pset(b.x as i32 + o, b.y as i32 + k, [255, 255, 255]);
            }
        }
        if let Some((sx, sy)) = self.shot {
            c.rect(sx as i32, sy as i32, 1, 4, [255, 255, 120]);
        }
        if self.scene == Scene::Play && !dying {
            c.sprite(&self.spr.cannon, self.px, PLAYER_Y, None);
        } else if dying && self.tick / 4 % 2 == 0 {
            c.sprite(&self.spr.cannon, self.px, PLAYER_Y, Some([255, 120, 0]));
        }
        c.rect(0, GROUND, W as i32, 1, [40, 230, 60]);
        for s in &self.sparks {
            c.padd(s.x as i32, s.y as i32, scale(s.c, s.life as f32 / 25.0));
        }
        // HUD
        c.text(&format!("{:05}", self.score), 1, 1, 1, [255, 255, 255]);
        c.text(&format!("HI{:05}", self.hi), 86, 1, 1, [255, 230, 0]);
        for i in 0..self.lives.clamp(0, 5) {
            c.rect(3 + 8 * i, GROUND + 4, 6, 3, [40, 230, 60]);
        }
        c.text(&format!("WAVE {}", self.wave), 76, GROUND + 2, 1, [140, 140, 160]);
        let mid = 96;
        if self.scene == Scene::Play && self.wave_t > 0 {
            c.text_centre(&format!("WAVE {}", self.wave), mid, 2, [255, 255, 255]);
            if self.wave == WAVES {
                c.text_centre("FINAL", mid + 20, 1, [255, 120, 60]);
            }
        }
        if self.paused {
            c.text_centre("PAUSE", mid, 2, [255, 255, 255]);
        }
        if self.scene == Scene::Over && self.all_clear {
            c.rect(14, mid - 14, 100, 66, [0, 0, 0]);
            c.text_centre("ALL", mid - 10, 3, [255, 230, 0]);
            c.text_centre("CLEAR", mid + 14, 3, [255, 230, 0]);
            c.text_centre(&format!("BONUS {}", self.bonus), mid + 42, 1, [255, 255, 255]);
        } else if self.scene == Scene::Over {
            c.rect(14, mid - 14, 100, 66, [0, 0, 0]);
            c.text_centre("GAME", mid - 10, 3, [255, 60, 60]);
            c.text_centre("OVER", mid + 14, 3, [255, 60, 60]);
            if self.over_t > 60 && self.tick / 30 % 2 == 0 {
                c.text_centre("ENTER: RETRY", mid + 42, 1, [255, 255, 255]);
            }
        }
    }

    fn render_title(&self, c: &mut Canvas) {
        c.text_centre("INVADERS", 26, 2, [255, 255, 255]);
        let f = (self.tick / 30 % 2) as usize;
        let rows: [(usize, &str, Rgb); 3] =
            [(0, "= 30", [255, 40, 200]), (1, "= 20", [40, 230, 60]), (2, "= 10", [0, 220, 255])];
        for (i, (t, s, col)) in rows.iter().enumerate() {
            let y = 60 + i as i32 * 16;
            c.sprite(&self.spr.alien[*t][f], 44.0, y as f32 + 3.0, None);
            c.text(s, 56, y, 1, *col);
        }
        c.sprite(&self.spr.ufo, 44.0, 111.0, None);
        c.text("= ???", 56, 108, 1, [255, 60, 60]);
        if self.tick / 30 % 2 == 0 {
            c.text_centre("PRESS ENTER", 132, 1, [255, 255, 255]);
        }
        let g = [150, 150, 170];
        c.text("MOVE  LEFT RIGHT", 10, 150, 1, g);
        c.text("FIRE  SPACE", 10, 160, 1, g);
        c.text_centre(&format!("HI {:05}", self.hi), 178, 1, [255, 230, 0]);
    }
}

impl crate::Game for Invaders {
    fn sound(&self) -> bool {
        true
    }
    fn step(&mut self, mut inp: Option<&mut Input>) {
        self.tick += 1;
        for s in &mut self.sparks {
            s.x += s.vx;
            s.y += s.vy;
            s.vx *= 0.95;
            s.vy *= 0.95;
            s.life -= 1;
        }
        self.sparks.retain(|s| s.life > 0);
        let bot = inp.is_none();
        let start = match inp.as_deref_mut() {
            Some(i) => i.take(Key::Start) | (self.scene != Scene::Play && i.take(Key::Space)),
            None => self.tick % 150 == 0 && self.scene == Scene::Title, // (the end screen: 5 s)
        };
        match self.scene {
            Scene::Title => {
                if start {
                    self.start();
                    if let Some(i) = inp {
                        i.flush();
                    }
                }
            }
            Scene::Over => {
                self.over_t += 1;
                if self.over_t > 60 && (start || (bot && self.over_t > 300)) {
                    self.start();
                    if let Some(i) = inp {
                        i.flush();
                    }
                } else if self.over_t > 900 {
                    self.scene = Scene::Title;
                }
            }
            Scene::Play => self.play(inp),
        }
        self.hi = self.hi.max(self.score);
    }
    fn draw(&self, c: &mut Canvas) {
        self.render(c);
    }
    fn status(&self) -> String {
        format!("wave {}  score {:05}  cannons {}", self.wave, self.score, self.lives.max(0) + 1)
    }
    fn hi(&self) -> u64 {
        self.hi
    }
}
