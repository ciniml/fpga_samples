// Falling-block puzzle on 128x192: a 10 x 20 well of 8 px cells on the
// left, next / hold / level / lines on the right, the score on top.
//
// Guideline-style rules: 7-bag randomiser, SRS rotation with wall kicks,
// hold (once per piece), ghost piece, 0.5 s lock delay (reset by moves, at
// most 15 times), gravity speeding up every 10 lines, 100 / 300 / 500 / 800
// x level for 1..4 lines, 1 / 2 points per cell of soft / hard drop.
// A game lasts at most 3 minutes (TIME UP), the clock is top right.
// Moves follow the key events (each press or auto-repeat is one step), so
// they work the same in every terminal.
use crate::audio::{self, sfx, Burst};
use crate::gfx::{scale, Canvas, Rgb, W};
use crate::input::{Input, Key};
use crate::{mmss, TIME_LIMIT};

const BW: usize = 10;
const BH: usize = 22; // 2 hidden rows on top
const CELL: i32 = 8;
const X0: i32 = 4; // well, left edge
const Y0: i32 = 30; // well, top of the first visible row
const LOCK_DELAY: i32 = 30;
const CLEAR_TICKS: i32 = 20;

const COLOURS: [Rgb; 9] = [
    [0, 0, 0],
    [0, 220, 255],  // I
    [255, 220, 0],  // O
    [180, 40, 255], // T
    [40, 220, 40],  // S
    [255, 30, 30],  // Z
    [30, 70, 255],  // J
    [255, 130, 0],  // L
    [90, 90, 100],  // game over fill
];

// state 0 in its box (I / O: 4x4, the rest 3x3), y down
const SHAPES: [[(i32, i32); 4]; 7] = [
    [(0, 1), (1, 1), (2, 1), (3, 1)], // I
    [(1, 0), (2, 0), (1, 1), (2, 1)], // O
    [(1, 0), (0, 1), (1, 1), (2, 1)], // T
    [(1, 0), (2, 0), (0, 1), (1, 1)], // S
    [(0, 0), (1, 0), (1, 1), (2, 1)], // Z
    [(0, 0), (0, 1), (1, 1), (2, 1)], // J
    [(2, 0), (0, 1), (1, 1), (2, 1)], // L
];

// SRS kicks (x, y up) for 0>R, R>0, R>2, 2>R, 2>L, L>2, L>0, 0>L
const KICKS: [[(i32, i32); 5]; 8] = [
    [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
    [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
];
const KICKS_I: [[(i32, i32); 5]; 8] = [
    [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
    [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
];

/// cells of piece `k` in rotation `r` (box coordinates)
fn cells(k: usize, r: usize) -> [(i32, i32); 4] {
    let n = if k <= 1 { 3 } else { 2 }; // box size - 1
    let mut c = SHAPES[k];
    if k != 1 {
        for _ in 0..r {
            for p in &mut c {
                *p = (n - p.1, p.0); // clockwise
            }
        }
    }
    c
}

#[derive(Clone, Copy)]
struct Piece {
    k: usize,
    r: usize,
    x: i32,
    y: i32,
}

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

type Board = [[u8; BW]; BH];

pub struct Blocks {
    rng: Rng,
    scene: Scene,
    tick: u64,
    board: Board,
    cur: Piece,
    next: usize,
    bag: Vec<usize>,
    hold: Option<usize>,
    hold_used: bool,
    grav: f32,
    lock: i32,
    resets: i32,
    clearing: Vec<usize>,
    clear_t: i32,
    last_clear: usize,
    score: u64,
    hi: u64,
    lines: u32,
    level: u32,
    over_t: i32,
    time_left: i32,
    time_up: bool,
    paused: bool,
    sparks: Vec<Spark>,
    plan: Option<(usize, i32)>, // bot: rotation, x
    rain: Vec<(f32, f32, usize, usize)>, // title: x, y, kind, rotation
}

fn fits(b: &Board, p: &Piece) -> bool {
    cells(p.k, p.r).iter().all(|&(cx, cy)| {
        let (x, y) = (p.x + cx, p.y + cy);
        x >= 0 && x < BW as i32 && y < BH as i32 && (y < 0 || b[y as usize][x as usize] == 0)
    })
}

impl Blocks {
    pub fn new(seed: u64, hi: u64) -> Blocks {
        let mut g = Blocks {
            rng: Rng(seed | 1),
            scene: Scene::Title,
            tick: 0,
            board: [[0; BW]; BH],
            cur: Piece { k: 0, r: 0, x: 3, y: 0 },
            next: 0,
            bag: Vec::new(),
            hold: None,
            hold_used: false,
            grav: 0.0,
            lock: 0,
            resets: 0,
            clearing: Vec::new(),
            clear_t: 0,
            last_clear: 0,
            score: 0,
            hi,
            lines: 0,
            level: 1,
            over_t: 0,
            time_left: TIME_LIMIT,
            time_up: false,
            paused: false,
            sparks: Vec::new(),
            plan: None,
            rain: Vec::new(),
        };
        for i in 0..9 {
            let (k, r) = (g.draw_bag(), (g.rng.next() % 4) as usize);
            g.rain.push((4.0 + 14.0 * i as f32, -30.0 * i as f32, k, r));
        }
        g
    }

    fn draw_bag(&mut self) -> usize {
        if self.bag.is_empty() {
            self.bag = (0..7).collect();
            for i in (1..7).rev() {
                let j = (self.rng.next() % (i as u64 + 1)) as usize;
                self.bag.swap(i, j);
            }
        }
        self.bag.pop().unwrap()
    }

    fn start(&mut self) {
        let (hi, seed) = (self.hi, self.rng.next());
        *self = Blocks::new(seed, hi);
        self.scene = Scene::Play;
        self.next = self.draw_bag();
        self.spawn(None);
        sfx::start();
    }

    /// next piece (or `k` from the hold); false: it does not fit
    fn spawn(&mut self, k: Option<usize>) -> bool {
        let k = k.unwrap_or_else(|| {
            let k = self.next;
            self.next = self.draw_bag();
            k
        });
        self.cur = Piece { k, r: 0, x: 3, y: 1 };
        self.grav = 0.0;
        self.lock = 0;
        self.resets = 0;
        self.plan = None;
        if !fits(&self.board, &self.cur) {
            self.scene = Scene::Over;
            self.over_t = 0;
            self.hi = self.hi.max(self.score);
            sfx::game_over();
            return false;
        }
        true
    }

    /// ticks per row
    fn gravity(&self) -> f32 {
        let l = (self.level.min(15) - 1) as f32;
        (0.8 - l * 0.007).powf(l) * 60.0
    }

    fn try_move(&mut self, dx: i32, dy: i32) -> bool {
        let p = Piece { x: self.cur.x + dx, y: self.cur.y + dy, ..self.cur };
        if fits(&self.board, &p) {
            self.cur = p;
            self.moved();
            true
        } else {
            false
        }
    }

    fn rotate(&mut self, cw: bool) {
        let from = self.cur.r;
        let to = if cw { (from + 1) % 4 } else { (from + 3) % 4 };
        let idx = match (from, cw) {
            (0, true) => 0,
            (1, true) => 2,
            (2, true) => 4,
            (3, true) => 6,
            (0, false) => 7,
            (1, false) => 1,
            (2, false) => 3,
            _ => 5,
        };
        let table = if self.cur.k == 0 { &KICKS_I } else { &KICKS };
        for &(kx, ky) in &table[idx] {
            let p = Piece { r: to, x: self.cur.x + kx, y: self.cur.y - ky, ..self.cur };
            if fits(&self.board, &p) {
                self.cur = p;
                self.moved();
                sfx::blip(900.0, 0.025);
                return;
            }
        }
    }

    /// a move on the ground restarts the lock delay (at most 15 times)
    fn moved(&mut self) {
        if self.lock > 0 && self.resets < 15 {
            self.lock = 0;
            self.resets += 1;
        }
    }

    fn ghost_y(&self) -> i32 {
        let mut p = self.cur;
        while fits(&self.board, &Piece { y: p.y + 1, ..p }) {
            p.y += 1;
        }
        p.y
    }

    fn lock_piece(&mut self) {
        for (cx, cy) in cells(self.cur.k, self.cur.r) {
            let (x, y) = (self.cur.x + cx, self.cur.y + cy);
            if y >= 0 {
                self.board[y as usize][x as usize] = self.cur.k as u8 + 1;
            }
        }
        self.hold_used = false;
        self.clearing = (0..BH).filter(|&y| self.board[y].iter().all(|&c| c != 0)).collect();
        audio::play(Burst::new(self.rng.next() as u32, 350.0, 2.0, 0.15, 0.03));
        if self.clearing.is_empty() {
            self.spawn(None);
        } else {
            // 1..4 lines: more notes, a four-line clear a run up
            let n = self.clearing.len();
            let run: Vec<(f32, f32)> = [523.3, 659.3, 784.0, 1046.5, 1318.5, 1568.0, 2093.0][..n + 1 + if n == 4 { 2 } else { 0 }]
                .iter()
                .map(|&f| (f, 0.05))
                .collect();
            sfx::notes(&run, 0.06, 0.08);
            self.clear_t = CLEAR_TICKS;
            let n = self.clearing.len();
            self.last_clear = n;
            self.score += [0, 100, 300, 500, 800][n] * self.level as u64;
            for &y in &self.clearing.clone() {
                for x in 0..BW {
                    for _ in 0..(if n == 4 { 3 } else { 1 }) {
                        let c = COLOURS[self.board[y][x] as usize];
                        let (vx, vy) = ((self.rng.f() - 0.5) * 3.0, -self.rng.f() * 2.5);
                        let px = (X0 + x as i32 * CELL + 4) as f32;
                        let py = (Y0 + (y as i32 - 2) * CELL + 4) as f32;
                        self.sparks.push(Spark { x: px, y: py, vx, vy, life: 40, c });
                    }
                }
            }
        }
    }

    fn finish_clear(&mut self) {
        let mut rows: Vec<[u8; BW]> = (0..BH).filter(|y| !self.clearing.contains(y)).map(|y| self.board[y]).collect();
        while rows.len() < BH {
            rows.insert(0, [0; BW]);
        }
        self.board.copy_from_slice(&rows);
        self.lines += self.clearing.len() as u32;
        if 1 + self.lines / 10 > self.level {
            sfx::extend();
        }
        self.level = 1 + self.lines / 10;
        self.clearing.clear();
        self.spawn(None);
    }

    fn play(&mut self, inp: Option<&mut Input>) {
        if !self.paused {
            self.time_left -= 1;
            if self.time_left <= 0 {
                self.scene = Scene::Over;
                self.over_t = 0;
                self.time_up = true;
                self.hi = self.hi.max(self.score);
                sfx::game_over();
                return;
            }
            if self.time_left <= 600 && self.time_left % 60 == 0 {
                sfx::blip(1568.0, 0.04);
            }
        }
        if self.clear_t > 0 {
            self.clear_t -= 1;
            if self.clear_t == 0 {
                self.finish_clear();
            }
            return;
        }
        // ---- controls ----
        let (mut left, mut right, mut down, mut cw, mut ccw, mut drop, mut hold) = (0, 0, 0, 0, 0, false, false);
        match inp {
            Some(i) => {
                left = i.hits(Key::Left);
                right = i.hits(Key::Right);
                down = i.hits(Key::Down);
                cw = i.hits(Key::Up) + i.hits(Key::B);
                ccw = i.hits(Key::A);
                drop = i.take(Key::Space);
                hold = i.take(Key::Hold);
                if i.take(Key::Pause) {
                    self.paused = !self.paused;
                }
                if self.paused {
                    return;
                }
            }
            None => {
                let (r, x) = *self.plan.get_or_insert_with(|| best_move(&self.board, self.cur.k));
                if self.tick % 4 == 0 {
                    if self.cur.r != r {
                        cw = 1;
                    } else if self.cur.x < x {
                        right = 1;
                    } else if self.cur.x > x {
                        left = 1;
                    } else {
                        drop = true;
                    }
                }
            }
        }
        if hold && !self.hold_used {
            let k = self.cur.k;
            let from = self.hold.replace(k);
            self.hold_used = true;
            sfx::blip(1200.0, 0.03);
            if !self.spawn(from) {
                return;
            }
        }
        for _ in 0..cw {
            self.rotate(true);
        }
        for _ in 0..ccw {
            self.rotate(false);
        }
        for _ in 0..left {
            if self.try_move(-1, 0) {
                sfx::blip(500.0, 0.02);
            }
        }
        for _ in 0..right {
            if self.try_move(1, 0) {
                sfx::blip(500.0, 0.02);
            }
        }
        for _ in 0..down {
            if self.try_move(0, 1) {
                self.score += 1;
                self.grav = 0.0;
            }
        }
        if drop {
            let y = self.ghost_y();
            self.score += 2 * (y - self.cur.y) as u64;
            for (cx, cy) in cells(self.cur.k, self.cur.r) {
                for yy in self.cur.y + cy..y + cy {
                    let px = (X0 + (self.cur.x + cx) * CELL + 4) as f32;
                    let c = scale(COLOURS[self.cur.k + 1], 0.5);
                    if self.rng.f() < 0.3 {
                        self.sparks.push(Spark { x: px, y: (Y0 + (yy - 2) * CELL) as f32, vx: 0.0, vy: 0.0, life: 10, c });
                    }
                }
            }
            self.cur.y = y;
            audio::play(Burst::new(self.rng.next() as u32, 200.0, 1.5, 0.3, 0.05));
            self.lock_piece();
            return;
        }
        // ---- gravity and lock ----
        self.grav += 1.0;
        if self.grav >= self.gravity() {
            self.grav = 0.0;
            self.try_move(0, 1);
        }
        if fits(&self.board, &Piece { y: self.cur.y + 1, ..self.cur }) {
            self.lock = 0;
        } else {
            self.lock += 1;
            if self.lock >= LOCK_DELAY {
                self.lock_piece();
            }
        }
    }

    // ---------------------------------------------------------------
    fn cell(c: &mut Canvas, x: i32, y: i32, col: Rgb, size: i32) {
        c.rect(x, y, size, size, scale(col, 0.75));
        c.rect(x, y, size, 1, scale(col, 1.3));
        c.rect(x, y, 1, size, scale(col, 1.15));
        c.rect(x, y + size - 1, size, 1, scale(col, 0.35));
        c.rect(x + size - 1, y, 1, size, scale(col, 0.45));
    }

    fn mini(c: &mut Canvas, k: usize, x: i32, y: i32, dim: bool) {
        // centred in a 32 x 20 box, 6 px cells
        let cs = cells(k, 0);
        let (minx, maxx) = (cs.iter().map(|p| p.0).min().unwrap(), cs.iter().map(|p| p.0).max().unwrap());
        let (miny, maxy) = (cs.iter().map(|p| p.1).min().unwrap(), cs.iter().map(|p| p.1).max().unwrap());
        let ox = x + (32 - (maxx - minx + 1) * 6) / 2 - minx * 6;
        let oy = y + (20 - (maxy - miny + 1) * 6) / 2 - miny * 6;
        let col = if dim { scale(COLOURS[k + 1], 0.35) } else { COLOURS[k + 1] };
        for (cx, cy) in cs {
            Self::cell(c, ox + cx * 6, oy + cy * 6, col, 6);
        }
    }

    fn render(&self, c: &mut Canvas) {
        c.clear([0, 0, 0]);
        if self.scene == Scene::Title {
            return self.render_title(c);
        }
        // well
        c.rect(X0 - 1, Y0 - 1, BW as i32 * CELL + 2, 20 * CELL + 2, [70, 70, 90]);
        c.rect(X0, Y0, BW as i32 * CELL, 20 * CELL, [6, 6, 14]);
        for x in 1..BW as i32 {
            for y in 0..20 {
                c.pset(X0 + x * CELL, Y0 + y * CELL, [25, 25, 40]);
            }
        }
        let flash = self.clear_t > 0 && (self.clear_t / 3) % 2 == 0;
        for y in 2..BH {
            let gray = self.scene == Scene::Over && (BH - 1 - y) as i32 * 3 < self.over_t;
            for x in 0..BW {
                let v = self.board[y][x];
                if v == 0 {
                    continue;
                }
                let mut col = COLOURS[if gray { 8 } else { v as usize }];
                if self.clearing.contains(&y) {
                    if flash {
                        col = [255, 255, 255];
                    } else {
                        col = scale(col, self.clear_t as f32 / CLEAR_TICKS as f32);
                    }
                }
                Self::cell(c, X0 + x as i32 * CELL, Y0 + (y as i32 - 2) * CELL, col, CELL);
            }
        }
        if self.scene == Scene::Play && self.clear_t == 0 {
            let gy = self.ghost_y();
            let gc = scale(COLOURS[self.cur.k + 1], 0.35);
            for (cx, cy) in cells(self.cur.k, self.cur.r) {
                let (x, y) = (X0 + (self.cur.x + cx) * CELL, Y0 + (gy + cy - 2) * CELL);
                if gy + cy >= 2 {
                    c.rect(x, y, CELL, 1, gc);
                    c.rect(x, y + CELL - 1, CELL, 1, gc);
                    c.rect(x, y, 1, CELL, gc);
                    c.rect(x + CELL - 1, y, 1, CELL, gc);
                }
            }
            // the lock delay dims the piece a little
            let col = scale(COLOURS[self.cur.k + 1], 1.0 - 0.4 * self.lock as f32 / LOCK_DELAY as f32);
            for (cx, cy) in cells(self.cur.k, self.cur.r) {
                if self.cur.y + cy >= 2 {
                    Self::cell(c, X0 + (self.cur.x + cx) * CELL, Y0 + (self.cur.y + cy - 2) * CELL, col, CELL);
                }
            }
        }
        for s in &self.sparks {
            c.padd(s.x as i32, s.y as i32, scale(s.c, s.life as f32 / 40.0));
        }
        // side
        let sx = 90;
        let g = [140, 140, 160];
        c.text("NEXT", sx, Y0, 1, g);
        Self::mini(c, self.next, sx - 2, Y0 + 10, false);
        c.text("HOLD", sx, Y0 + 38, 1, g);
        if let Some(k) = self.hold {
            Self::mini(c, k, sx - 2, Y0 + 48, self.hold_used);
        }
        c.text("LEVEL", sx, Y0 + 78, 1, g);
        c.text(&format!("{}", self.level), sx, Y0 + 88, 2, [255, 255, 255]);
        c.text("LINES", sx, Y0 + 110, 1, g);
        c.text(&format!("{}", self.lines), sx, Y0 + 120, 1, [255, 255, 255]);
        c.text("HI", sx, Y0 + 140, 1, g);
        c.text(&format!("{}", self.hi), sx, Y0 + 150, 1, [255, 230, 0]);
        // top
        c.text("SCORE", 4, 2, 1, g);
        c.text(&format!("{:07}", self.score), 4, 12, 2, [255, 255, 255]);
        c.text("TIME", 100, 2, 1, g);
        let tc = if self.time_left > 600 { [255, 255, 255] } else if self.tick / 15 % 2 == 0 { [255, 40, 40] } else { [120, 0, 0] };
        c.text(&mmss(self.time_left), 100, 14, 1, tc);
        if self.clear_t > 0 && self.last_clear >= 2 {
            let (s, col) = match self.last_clear {
                2 => ("DOUBLE", [0, 220, 255]),
                3 => ("TRIPLE", [255, 130, 0]),
                _ => ("4 LINES!", [255, 230, 0]),
            };
            c.text_centre(s, 2, 1, col);
        }
        if self.paused {
            c.rect(X0, Y0 + 70, 80, 20, [0, 0, 0]);
            c.text("PAUSE", X0 + 25, Y0 + 77, 1, [255, 255, 255]);
        }
        if self.scene == Scene::Over && self.over_t > 66 {
            c.rect(X0 + 4, Y0 + 56, 72, 50, [0, 0, 0]);
            if self.time_up {
                c.text("TIME", X0 + 16, Y0 + 62, 2, [255, 230, 0]);
                c.text("UP", X0 + 28, Y0 + 80, 2, [255, 230, 0]);
            } else {
                c.text("GAME", X0 + 16, Y0 + 62, 2, [255, 60, 60]);
                c.text("OVER", X0 + 16, Y0 + 80, 2, [255, 60, 60]);
            }
            if self.tick / 30 % 2 == 0 {
                c.text("ENTER", X0 + 25, Y0 + 97, 1, [255, 255, 255]);
            }
        }
    }

    fn render_title(&self, c: &mut Canvas) {
        for &(x, y, k, r) in &self.rain {
            for (cx, cy) in cells(k, r) {
                Self::cell(c, x as i32 + cx * 6, y as i32 + cy * 6, scale(COLOURS[k + 1], 0.45), 6);
            }
        }
        let letters = ["B", "L", "O", "C", "K", "S"];
        for (i, l) in letters.iter().enumerate() {
            let bob = ((self.tick as f32 * 0.08 + i as f32 * 0.7).sin() * 3.0) as i32;
            let x = (W as i32 - 6 * 18 + 3) / 2 + i as i32 * 18;
            c.rect(x - 2, 38 + bob - 2, 19, 25, [0, 0, 0]);
            c.text(l, x, 38 + bob, 3, COLOURS[i + 1]);
        }
        if self.tick / 30 % 2 == 0 {
            c.text_centre("PRESS ENTER", 92, 1, [255, 255, 255]);
        }
        let g = [150, 150, 170];
        c.rect(0, 112, W as i32, 62, [0, 0, 0]);
        c.text("MOVE    LEFT RIGHT", 2, 114, 1, g);
        c.text("DROP    DOWN SPACE", 2, 124, 1, g);
        c.text("ROTATE  UP X  Z", 2, 134, 1, g);
        c.text("HOLD    C", 2, 144, 1, g);
        c.text("PAUSE P  QUIT Q", 2, 154, 1, g);
        c.text_centre(&format!("HI {:07}", self.hi), 178, 1, [255, 230, 0]);
    }
}

/// bot: the placement (rotation, x) with the best board after it
/// (aggregate height, lines, holes, bumpiness)
fn best_move(b: &Board, k: usize) -> (usize, i32) {
    let mut best = (0, 3);
    let mut best_v = f32::MIN;
    for r in 0..4 {
        for x in -2..BW as i32 {
            let mut p = Piece { k, r, x, y: 0 };
            if !fits(b, &p) {
                continue;
            }
            while fits(b, &Piece { y: p.y + 1, ..p }) {
                p.y += 1;
            }
            let mut nb = *b;
            for (cx, cy) in cells(k, r) {
                let y = p.y + cy;
                if y >= 0 {
                    nb[y as usize][(p.x + cx) as usize] = 1;
                }
            }
            let full: Vec<usize> = (0..BH).filter(|&y| nb[y].iter().all(|&c| c != 0)).collect();
            let rows: Vec<[u8; BW]> = (0..BH).filter(|y| !full.contains(y)).map(|y| nb[y]).collect();
            let off = BH - rows.len();
            let mut heights = [0i32; BW];
            let mut holes = 0;
            for x in 0..BW {
                let mut seen = false;
                for (i, row) in rows.iter().enumerate() {
                    if row[x] != 0 {
                        if !seen {
                            heights[x] = (BH - off - i) as i32;
                            seen = true;
                        }
                    } else if seen {
                        holes += 1;
                    }
                }
            }
            let agg: i32 = heights.iter().sum();
            let bump: i32 = heights.windows(2).map(|w| (w[0] - w[1]).abs()).sum();
            let v = -0.51 * agg as f32 + 0.76 * full.len() as f32 - 0.36 * holes as f32 - 0.18 * bump as f32;
            if v > best_v {
                best_v = v;
                best = (r, x);
            }
        }
    }
    best
}

impl crate::Game for Blocks {
    fn sound(&self) -> bool {
        true
    }
    fn step(&mut self, mut inp: Option<&mut Input>) {
        self.tick += 1;
        for s in &mut self.sparks {
            s.x += s.vx;
            s.y += s.vy;
            s.vy += 0.12;
            s.life -= 1;
        }
        self.sparks.retain(|s| s.life > 0);
        let bot = inp.is_none();
        let start = match inp.as_deref_mut() {
            Some(i) => i.take(Key::Start) | i.take(Key::Space),
            None => self.tick % 150 == 0 && self.scene == Scene::Title, // (the end screen: 5 s)
        };
        match self.scene {
            Scene::Title => {
                for d in &mut self.rain {
                    d.1 += 0.6;
                }
                for i in 0..self.rain.len() {
                    if self.rain[i].1 > 200.0 {
                        let (k, r) = (self.draw_bag(), (self.rng.next() % 4) as usize);
                        self.rain[i] = (self.rain[i].0, -30.0, k, r);
                    }
                }
                if start {
                    self.start();
                    if let Some(i) = inp {
                        i.flush();
                    }
                }
            }
            Scene::Over => {
                self.over_t += 1;
                if self.over_t > 90 && (start || (bot && self.over_t > 300)) {
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
        format!("level {}  lines {}  score {:07}  time {}", self.level, self.lines, self.score, mmss(self.time_left))
    }
    fn hi(&self) -> u64 {
        self.hi
    }
}
