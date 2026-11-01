// Brick breaker on 128x192: 12 columns x up to 9 rows of bricks, a paddle
// at the bottom, walls left / right / top.
//
// The ball's angle off the paddle follows where it lands on it (up to 60
// degrees), it speeds up a little with every paddle hit and with every
// stage. Some bricks drop capsules: W wide paddle, M multi-ball (each ball
// splits in three), S slow ball, 1UP. Silver bricks take several hits.
// Stages cycle through four layouts. A game lasts at most 3 minutes
// (TIME UP), the clock is in the middle of the top line.
use crate::gfx::{scale, Canvas, Rgb, H, W};
use crate::input::{Input, Key};
use crate::{mmss, Rng, TIME_LIMIT};

const COLS: usize = 12;
const ROWS: usize = 9;
const BX0: f32 = 4.0; // bricks: left edge, 10 px a column
const BY0: f32 = 24.0; // top edge, 6 px a row
const BRW: f32 = 10.0;
const BRH: f32 = 6.0;
const TOP: f32 = 12.0; // inside of the top wall
const LEFT: f32 = 2.0;
const RIGHT: f32 = 126.0;
const PADDLE_Y: f32 = 178.0;
const R: f32 = 1.5; // ball radius
const HF: f32 = H as f32;

const ROW_COLOURS: [Rgb; 8] = [
    [255, 40, 40],
    [255, 130, 0],
    [255, 220, 0],
    [60, 230, 60],
    [0, 220, 255],
    [40, 90, 255],
    [180, 50, 255],
    [255, 60, 180],
];
const SILVER: Rgb = [190, 190, 210];

#[derive(Clone, Copy)]
struct Brick {
    hp: u8,
    silver: bool,
    c: Rgb,
}

struct Ball {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
}

#[derive(Clone, Copy, PartialEq)]
enum Cap {
    Wide,
    Multi,
    Slow,
    Life,
}

struct Capsule {
    x: f32,
    y: f32,
    kind: Cap,
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

pub struct Bricks {
    rng: Rng,
    scene: Scene,
    tick: u64,
    grid: [[Option<Brick>; COLS]; ROWS],
    balls: Vec<Ball>,
    held: bool, // the ball sits on the paddle
    held_t: u32,
    px: f32,
    wide: i32, // ticks left
    speed: f32,
    stage: u32,
    score: u64,
    hi: u64,
    lives: i32,
    caps: Vec<Capsule>,
    sparks: Vec<Spark>,
    msg_t: i32, // "STAGE n" / "CLEAR"
    clear_t: i32,
    over_t: i32,
    time_left: i32,
    time_up: bool,
    paused: bool,
}

impl Bricks {
    pub fn new(seed: u64, hi: u64) -> Bricks {
        let mut g = Bricks {
            rng: Rng::new(seed),
            scene: Scene::Title,
            tick: 0,
            grid: [[None; COLS]; ROWS],
            balls: Vec::new(),
            held: true,
            held_t: 0,
            px: 64.0,
            wide: 0,
            speed: 1.5,
            stage: 1,
            score: 0,
            hi,
            lives: 3,
            caps: Vec::new(),
            sparks: Vec::new(),
            msg_t: 0,
            clear_t: 0,
            over_t: 0,
            time_left: TIME_LIMIT,
            time_up: false,
            paused: false,
        };
        g.layout();
        g
    }

    fn start(&mut self) {
        let (hi, seed) = (self.hi, self.rng.next());
        *self = Bricks::new(seed, hi);
        self.scene = Scene::Play;
        self.serve();
        self.msg_t = 120;
    }

    fn base_speed(&self) -> f32 {
        (1.4 + 0.1 * self.stage as f32).min(2.6)
    }

    fn serve(&mut self) {
        self.balls.clear();
        self.balls.push(Ball { x: self.px, y: PADDLE_Y - R - 0.5, vx: 0.0, vy: 0.0 });
        self.held = true;
        self.held_t = 0;
        self.speed = self.base_speed();
        self.wide = 0;
    }

    /// the bricks of the current stage
    fn layout(&mut self) {
        let s = self.stage;
        let silver_hp = (2 + s / 4).min(5) as u8;
        for r in 0..ROWS {
            for c in 0..COLS {
                let (cf, rf) = (c as i32, r as i32);
                let on = match (s - 1) % 4 {
                    0 => (1..8).contains(&rf),
                    1 => rf >= 1 && (cf - 5).abs().min((cf - 6).abs()) <= rf - 1, // pyramid
                    2 => rf >= 1 && (cf + rf) % 2 == 0,                             // checker
                    _ => {
                        // diamond with a silver rim on top
                        let d = (cf * 2 - 11).abs() + (rf * 2 - 8).abs();
                        d <= 10 && d != 6
                    }
                };
                self.grid[r][c] = if !on {
                    None
                } else if r == 1 && s >= 2 || (s % 4 == 0 && r <= 2) {
                    Some(Brick { hp: silver_hp, silver: true, c: SILVER })
                } else {
                    Some(Brick { hp: 1, silver: false, c: ROW_COLOURS[r % 8] })
                };
            }
        }
    }

    fn paddle_w(&self) -> f32 {
        if self.wide > 0 {
            32.0
        } else {
            20.0
        }
    }

    fn burst(&mut self, x: f32, y: f32, c: Rgb, n: usize) {
        for _ in 0..n {
            let a = self.rng.range(0.0, std::f32::consts::TAU);
            let v = self.rng.range(0.3, 1.6);
            self.sparks.push(Spark { x, y, vx: a.cos() * v, vy: a.sin() * v, life: 25, c });
        }
    }

    /// moves one ball by its velocity in small steps; false: lost
    fn move_ball(&mut self, i: usize) -> bool {
        let (vx, vy) = (self.balls[i].vx, self.balls[i].vy);
        let n = ((vx.abs().max(vy.abs())) / 0.7).ceil().max(1.0) as i32;
        let (pw, px, cap) = (self.paddle_w(), self.px, self.base_speed() + 0.9);
        let mut speed = self.speed;
        let mut alive = true;
        for _ in 0..n {
            let (ox, oy) = (self.balls[i].x, self.balls[i].y);
            let b = &mut self.balls[i];
            b.x += b.vx / n as f32;
            b.y += b.vy / n as f32;
            if b.x < LEFT + R {
                b.x = LEFT + R;
                b.vx = b.vx.abs();
            }
            if b.x > RIGHT - R {
                b.x = RIGHT - R;
                b.vx = -b.vx.abs();
            }
            if b.y < TOP + R {
                b.y = TOP + R;
                b.vy = b.vy.abs();
            }
            // paddle: the angle follows the landing point
            if b.vy > 0.0 && b.y + R >= PADDLE_Y && b.y <= PADDLE_Y + 3.0 && (b.x - px).abs() <= pw / 2.0 + R {
                let rel = ((b.x - px) / (pw / 2.0)).clamp(-1.0, 1.0);
                let a = rel * 60f32.to_radians();
                speed = (speed + 0.03).min(cap);
                b.vx = speed * a.sin();
                b.vy = -speed * a.cos();
                b.y = PADDLE_Y - R;
                continue;
            }
            if b.y > HF + 4.0 {
                alive = false;
                break;
            }
            // bricks: the cell of the ball's centre
            let (cx, cy) = (b.x, b.y);
            let col = ((cx - BX0) / BRW).floor() as i32;
            let row = ((cy - BY0) / BRH).floor() as i32;
            if col < 0 || col >= COLS as i32 || row < 0 || row >= ROWS as i32 {
                continue;
            }
            let (c, r) = (col as usize, row as usize);
            if self.grid[r][c].is_none() {
                continue;
            }
            let pcol = ((ox - BX0) / BRW).floor() as i32;
            let prow = ((oy - BY0) / BRH).floor() as i32;
            if pcol != col {
                b.vx = -b.vx;
            }
            if prow != row || pcol == col {
                b.vy = -b.vy;
            }
            b.x = ox;
            b.y = oy;
            self.hit_brick(r, c);
            break;
        }
        self.speed = speed;
        alive
    }

    fn hit_brick(&mut self, r: usize, c: usize) {
        let Some(mut br) = self.grid[r][c] else { return };
        let (x, y) = (BX0 + c as f32 * BRW + 5.0, BY0 + r as f32 * BRH + 3.0);
        br.hp -= 1;
        if br.hp > 0 {
            self.grid[r][c] = Some(br);
            self.burst(x, y, [255, 255, 255], 3);
            return;
        }
        self.grid[r][c] = None;
        self.score += if br.silver { 50 * self.stage as u64 } else { 10 + 10 * (ROWS - r) as u64 };
        self.burst(x, y, br.c, 8);
        if self.rng.chance(0.25) {
            let p = self.rng.f();
            let kind = if p < 0.35 {
                Cap::Wide
            } else if p < 0.7 {
                Cap::Multi
            } else if p < 0.96 {
                Cap::Slow
            } else {
                Cap::Life
            };
            self.caps.push(Capsule { x, y, kind });
        }
    }

    /// bot: under the landing point of the lowest falling ball, aimed a
    /// little towards the remaining bricks
    fn bot(&self) -> (f32, bool) {
        let target = self
            .balls
            .iter()
            .filter(|b| b.vy > 0.0)
            .max_by(|a, b| a.y.total_cmp(&b.y))
            .map(|b| {
                // straight line with wall reflections down to the paddle
                let t = (PADDLE_Y - R - b.y) / b.vy;
                let mut x = b.x + b.vx * t - (LEFT + R);
                let span = RIGHT - LEFT - 2.0 * R;
                x = x.rem_euclid(2.0 * span);
                if x > span {
                    x = 2.0 * span - x;
                }
                x + LEFT + R
            });
        let (mut sx, mut n) = (0.0, 0.0);
        for r in 0..ROWS {
            for c in 0..COLS {
                if self.grid[r][c].is_some() {
                    sx += BX0 + c as f32 * BRW + 5.0;
                    n += 1.0;
                }
            }
        }
        let bricks_x = if n > 0.0 { sx / n } else { 64.0 };
        let target = match target {
            // a few bricks left: aim at the lowest one (straight or off a wall)
            Some(t) if n <= 8.0 && n > 0.0 => {
                let (r, c) = (0..ROWS)
                    .rev()
                    .flat_map(|r| (0..COLS).map(move |c| (r, c)))
                    .filter(|&(r, c)| self.grid[r][c].is_some())
                    .min_by(|a, b| {
                        let d = |(r, c): (usize, usize)| (ROWS - r) as f32 * 20.0 + (BX0 + c as f32 * BRW - t).abs();
                        d(*a).total_cmp(&d(*b))
                    })
                    .unwrap();
                let (bx, by) = (BX0 + c as f32 * BRW + 5.0, BY0 + r as f32 * BRH + 3.0);
                let dy = PADDLE_Y - R - by;
                let a = [bx, 2.0 * (LEFT + R) - bx, 2.0 * (RIGHT - R) - bx]
                    .iter()
                    .map(|&x| (x - t).atan2(dy))
                    .min_by(|a, b| a.abs().total_cmp(&b.abs()))
                    .unwrap()
                    .clamp(-55f32.to_radians(), 55f32.to_radians());
                t - a / 60f32.to_radians() * self.paddle_w() / 2.0
            }
            // the aim drifts with time so that the ball does not settle on one path
            Some(t) => t - (bricks_x - t).signum() * self.paddle_w() * (0.2 + 0.25 * (self.tick as f32 * 0.0137).sin()),
            None => self.balls.first().map_or(64.0, |b| b.x),
        };
        let dx = ((target - self.px) / 3.0).clamp(-1.0, 1.0);
        (dx, self.held && self.held_t > 50)
    }

    fn play(&mut self, inp: Option<&mut Input>) {
        let (dx, launch) = match inp {
            Some(i) => {
                if i.take(Key::Pause) {
                    self.paused = !self.paused;
                }
                let dx = i.held(Key::Right) as i32 as f32 - i.held(Key::Left) as i32 as f32;
                (dx, i.take(Key::Space) | i.take(Key::Up) | i.take(Key::A))
            }
            None => self.bot(),
        };
        if self.paused {
            return;
        }
        self.time_left -= 1;
        if self.time_left <= 0 {
            self.scene = Scene::Over;
            self.over_t = 0;
            self.time_up = true;
            return;
        }
        self.msg_t = (self.msg_t - 1).max(0);
        if self.clear_t > 0 {
            self.clear_t -= 1;
            if self.clear_t == 0 {
                self.stage += 1;
                self.layout();
                self.serve();
                self.msg_t = 120;
            }
            return;
        }
        let pw = self.paddle_w();
        self.px = (self.px + dx * 2.4).clamp(LEFT + pw / 2.0, RIGHT - pw / 2.0);
        self.wide = (self.wide - 1).max(0);
        if self.held {
            self.held_t += 1;
            self.balls[0].x = self.px + 3.0;
            self.balls[0].y = PADDLE_Y - R - 0.5;
            if launch {
                self.held = false;
                let a = -20f32.to_radians();
                self.balls[0].vx = self.speed * a.sin();
                self.balls[0].vy = -self.speed * a.cos();
            }
        } else {
            let mut i = 0;
            while i < self.balls.len() {
                if self.move_ball(i) {
                    i += 1;
                } else {
                    self.balls.swap_remove(i);
                }
            }
            if self.balls.is_empty() {
                self.lives -= 1;
                self.burst(self.px, PADDLE_Y, [255, 80, 80], 30);
                if self.lives < 0 {
                    self.scene = Scene::Over;
                    self.over_t = 0;
                    return;
                }
                self.caps.clear();
                self.serve();
            }
        }
        // capsules
        let (px, pw) = (self.px, self.paddle_w());
        let mut got = Vec::new();
        self.caps.retain_mut(|c| {
            c.y += 0.8;
            let hit = c.y + 3.0 >= PADDLE_Y && c.y - 3.0 <= PADDLE_Y + 3.0 && (c.x - px).abs() < pw / 2.0 + 5.0;
            if hit {
                got.push(c.kind);
            }
            !hit && c.y < HF + 4.0
        });
        for k in got {
            self.score += 100;
            match k {
                Cap::Wide => self.wide = 900,
                Cap::Slow => {
                    self.speed = self.base_speed() * 0.8;
                    for b in &mut self.balls {
                        let m = (b.vx * b.vx + b.vy * b.vy).sqrt().max(0.01);
                        b.vx *= self.speed / m;
                        b.vy *= self.speed / m;
                    }
                }
                Cap::Multi if !self.held => {
                    let mut add = Vec::new();
                    for b in &self.balls {
                        for d in [-25f32, 25.0] {
                            let (s, c) = d.to_radians().sin_cos();
                            add.push(Ball { x: b.x, y: b.y, vx: b.vx * c - b.vy * s, vy: b.vx * s + b.vy * c });
                        }
                    }
                    if self.balls.len() + add.len() <= 12 {
                        self.balls.extend(add);
                    }
                }
                Cap::Multi => {}
                Cap::Life => self.lives += 1,
            }
        }
        if self.grid.iter().all(|r| r.iter().all(|b| b.is_none())) {
            self.clear_t = 150;
            self.score += 1000 * self.stage as u64;
            self.caps.clear();
        }
    }

    // ---------------------------------------------------------------
    fn render(&self, c: &mut Canvas) {
        c.clear([0, 0, 10]);
        // walls
        let wall = [80, 80, 110];
        c.rect(0, 10, 2, H as i32 - 10, wall);
        c.rect(126, 10, 2, H as i32 - 10, wall);
        c.rect(0, 10, W as i32, 2, wall);
        if self.scene == Scene::Title {
            return self.render_title(c);
        }
        for r in 0..ROWS {
            for col in 0..COLS {
                if let Some(b) = self.grid[r][col] {
                    let (x, y) = ((BX0 + col as f32 * BRW) as i32, (BY0 + r as f32 * BRH) as i32);
                    let base = if b.silver { scale(b.c, 0.6 + 0.1 * b.hp as f32) } else { b.c };
                    c.rect(x, y, 9, 5, scale(base, 0.75));
                    c.rect(x, y, 9, 1, scale(base, 1.3));
                    c.rect(x, y + 4, 9, 1, scale(base, 0.4));
                    if b.silver && (self.tick / 4 + col as u64 * 3) % 40 == 0 {
                        c.rect(x, y, 9, 5, [255, 255, 255]);
                    }
                }
            }
        }
        for cp in &self.caps {
            let (col, s) = match cp.kind {
                Cap::Wide => ([40, 90, 255], "W"),
                Cap::Multi => ([0, 200, 200], "M"),
                Cap::Slow => ([255, 130, 0], "S"),
                Cap::Life => ([120, 120, 130], "1"),
            };
            c.rect(cp.x as i32 - 5, cp.y as i32 - 4, 11, 9, col);
            c.text(s, cp.x as i32 - 2, cp.y as i32 - 3, 1, [255, 255, 255]);
        }
        // paddle
        let pw = self.paddle_w() as i32;
        let x0 = self.px as i32 - pw / 2;
        c.rect(x0, PADDLE_Y as i32, pw, 3, [200, 200, 220]);
        c.rect(x0, PADDLE_Y as i32, 3, 3, [255, 60, 60]);
        c.rect(x0 + pw - 3, PADDLE_Y as i32, 3, 3, [255, 60, 60]);
        c.rect(x0 + 3, PADDLE_Y as i32, pw - 6, 1, [255, 255, 255]);
        if self.scene == Scene::Play {
            for b in &self.balls {
                c.disc(b.x, b.y, R + 0.3, [255, 255, 255]);
            }
        }
        for s in &self.sparks {
            c.padd(s.x as i32, s.y as i32, scale(s.c, s.life as f32 / 25.0));
        }
        // HUD
        c.text(&format!("{:06}", self.score), 1, 1, 1, [255, 255, 255]);
        c.text(&format!("HI{:06}", self.hi), 80, 1, 1, [255, 230, 0]);
        let tc = if self.time_left > 600 { [255, 255, 255] } else if self.tick / 15 % 2 == 0 { [255, 40, 40] } else { [120, 0, 0] };
        c.text_centre(&mmss(self.time_left), 1, 1, tc);
        for i in 0..self.lives.clamp(0, 8) {
            c.rect(4 + 7 * i, H as i32 - 4, 5, 2, [200, 200, 220]);
        }
        let mid = 120;
        if self.msg_t > 0 {
            c.text_centre(&format!("STAGE {}", self.stage), mid, 2, [255, 255, 255]);
        }
        if self.clear_t > 0 {
            c.text_centre("CLEAR!", mid, 2, [255, 230, 0]);
        }
        if self.paused {
            c.text_centre("PAUSE", mid, 2, [255, 255, 255]);
        }
        if self.scene == Scene::Over {
            let (w1, w2, col) = if self.time_up { ("TIME", "UP", [255, 230, 0]) } else { ("GAME", "OVER", [255, 60, 60]) };
            c.text_centre(w1, mid - 10, 3, col);
            c.text_centre(w2, mid + 14, 3, col);
            if self.over_t > 60 && self.tick / 30 % 2 == 0 {
                c.text_centre("ENTER: RETRY", mid + 44, 1, [255, 255, 255]);
            }
        }
    }

    fn render_title(&self, c: &mut Canvas) {
        // a wall of bricks that lights up row by row
        for r in 0..6 {
            for col in 0..COLS {
                let lit = ((self.tick / 6) as usize + col + r) % 18 < 9;
                let k = if lit { 1.0 } else { 0.35 };
                let (x, y) = ((BX0 + col as f32 * BRW) as i32, 20 + r as i32 * 6);
                c.rect(x, y, 9, 5, scale(ROW_COLOURS[r], k));
            }
        }
        c.text_centre("BRICKS", 66, 3, [255, 255, 255]);
        let bx = 64.0 + 50.0 * (self.tick as f32 * 0.031).sin();
        let by = 110.0 - 14.0 * (self.tick as f32 * 0.09).sin().abs();
        c.disc(bx, by, R + 0.3, [255, 255, 255]);
        c.rect(54, 124, 20, 3, [200, 200, 220]);
        if self.tick / 30 % 2 == 0 {
            c.text_centre("PRESS ENTER", 138, 1, [255, 255, 255]);
        }
        let g = [150, 150, 170];
        c.text("MOVE   LEFT RIGHT", 6, 154, 1, g);
        c.text("LAUNCH SPACE", 6, 164, 1, g);
        c.text_centre(&format!("HI {:06}", self.hi), 180, 1, [255, 230, 0]);
    }
}

impl crate::Game for Bricks {
    fn step(&mut self, mut inp: Option<&mut Input>) {
        self.tick += 1;
        for s in &mut self.sparks {
            s.x += s.vx;
            s.y += s.vy;
            s.vy += 0.05;
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
        format!("stage {}  score {:06}  balls {}  time {}", self.stage, self.score, self.lives.max(0), mmss(self.time_left))
    }
    fn hi(&self) -> u64 {
        self.hi
    }
}
