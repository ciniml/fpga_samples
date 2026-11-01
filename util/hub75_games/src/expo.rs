// A demo for 超エレキ万博2026 (ELEKI EXPO 2026, CQ出版社, 2026-11-03 at
// ベルサール秋葉原) on 128x192, shown at the booth W40 ふがふが in 匠の電子工作館:
// a loop of about a minute.
//
// 1. boot: a terminal types a boot log ("SYSTEM BOOT SEQUENCE", "LOADING
//    000%"... "> ALL SYSTEMS GO", as on the expo's site), then glitches out
// 2. title: 超エレキ / 万博2026 glowing over a circuit board whose traces
//    carry pulses of light, with sparks jumping between the letters
// 3. the booth: hall, number, name and what it shows
// 4. the motto エンジニアを技術で癒す！ under an oscilloscope drawing
//    Lissajous figures that end in a heart
// 5. the seven halls, scrolling up like credits (this booth marked)
// 6. a countdown to the close (18:00) with a bar for the day, thanks after
//    (EXPO_NOW="2026-11-03 15:00:00" pretends a time, for a rehearsal)
use crate::fx::{add, mix, new_buf, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};
use crate::Rng;
use chrono::{Local, NaiveDate, NaiveDateTime};
use std::f32::consts::TAU;

const SCENES: [u64; 6] = [8 * 60, 10 * 60, 10 * 60, 9 * 60, 15 * 60, 10 * 60];
const BOOTH_HALL: usize = 1; // 匠の電子工作館
const FADE: u64 = 20;
const HALLS: [(&str, &str); 7] = [
    ("未来", "エレクトロニクス館"),
    ("匠の", "電子工作館"),
    ("チャレンジ", "電子工作館"),
    ("先進", "テクノロジ館"),
    ("ジュニア", "応援館"),
    ("実習", "テクノロジ館"),
    ("体験", "エレクトロニクス館"),
];
const BOOT: [&str; 9] = [
    "CQ-BIOS 2026.11",
    "SYSTEM BOOT SEQUENCE",
    "MEMORY ....... OK",
    "HUB75 PANELS .. OK",
    "ETHER 1000M ... OK",
    "FPGA GW3A ..... OK",
    "LOADING 000%",
    "",
    "> ALL SYSTEMS GO",
];

fn open_time() -> NaiveDateTime {
    NaiveDate::from_ymd_opt(2026, 11, 3).unwrap().and_hms_opt(10, 30, 0).unwrap()
}
fn close_time() -> NaiveDateTime {
    NaiveDate::from_ymd_opt(2026, 11, 3).unwrap().and_hms_opt(18, 0, 0).unwrap()
}

/// the local time; EXPO_NOW="2026-11-03 15:00:00" pretends that it is then
/// (the clock runs on from there), for a rehearsal
fn now() -> NaiveDateTime {
    static OFFSET: std::sync::OnceLock<chrono::TimeDelta> = std::sync::OnceLock::new();
    let real = Local::now().naive_local();
    let off = OFFSET.get_or_init(|| {
        std::env::var("EXPO_NOW")
            .ok()
            .and_then(|v| NaiveDateTime::parse_from_str(&v, "%Y-%m-%d %H:%M:%S").ok())
            .map_or(chrono::TimeDelta::zero(), |t| t - real)
    });
    real + *off
}

/// a soft halo around a mask: two box blurs
fn blur(mask: &[f32], r: i32) -> Vec<f32> {
    let mut a = mask.to_vec();
    for _ in 0..2 {
        let mut b = vec![0.0; W * H];
        for y in 0..H {
            for x in 0..W {
                let mut s = 0.0;
                for dx in -r..=r {
                    let xx = (x as i32 + dx).clamp(0, W as i32 - 1) as usize;
                    s += a[y * W + xx];
                }
                b[y * W + x] = s / (2 * r + 1) as f32;
            }
        }
        for y in 0..H {
            for x in 0..W {
                let mut s = 0.0;
                for dy in -r..=r {
                    let yy = (y as i32 + dy).clamp(0, H as i32 - 1) as usize;
                    s += b[yy * W + x];
                }
                a[y * W + x] = s / (2 * r + 1) as f32;
            }
        }
    }
    a
}

pub struct Expo {
    rng: Rng,
    tick: u64,
    scene: usize,
    t: u64,
    traces: Vec<Vec<(i32, i32)>>, // the pixels of each trace in order
    board: Vec<f32>,              // trace / pad mask
    pulses: Vec<(usize, f32, f32)>, // trace, position, speed
    scope: Vec<f32>,              // phosphor of the oscilloscope
    sparks: Vec<Vec<(f32, f32)>>,
}

impl Expo {
    pub fn new(seed: u64, _hi: u64) -> Expo {
        let mut rng = Rng::new(seed);
        // circuit traces: walks on a 4 px grid in 8 directions, mostly straight
        let dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
        let mut traces = Vec::new();
        let mut board = vec![0.0f32; W * H];
        for _ in 0..34 {
            let (mut x, mut y) = ((rng.next() % 32) as i32 * 4 + 2, (rng.next() % 48) as i32 * 4 + 2);
            let mut d = (rng.next() % 8) as usize & !1; // start straight
            let mut path = vec![(x, y)];
            for _ in 0..(8 + rng.next() % 30) {
                if rng.chance(0.2) {
                    d = (d + if rng.chance(0.5) { 1 } else { 7 }) % 8;
                }
                for _ in 0..4 {
                    x += dirs[d].0;
                    y += dirs[d].1;
                    path.push((x, y));
                }
                if x < 2 || y < 2 || x >= W as i32 - 2 || y >= H as i32 - 2 {
                    break;
                }
            }
            for &(px, py) in &path {
                if px >= 0 && py >= 0 && (px as usize) < W && (py as usize) < H {
                    board[py as usize * W + px as usize] = 1.0;
                }
            }
            // pads at both ends
            for &(px, py) in [path[0], *path.last().unwrap()].iter() {
                for dy in -1..=1 {
                    for dx in -1..=1 {
                        let (qx, qy) = (px + dx, py + dy);
                        if qx >= 0 && qy >= 0 && (qx as usize) < W && (qy as usize) < H {
                            board[qy as usize * W + qx as usize] = 2.0;
                        }
                    }
                }
            }
            traces.push(path);
        }
        Expo { rng, tick: 0, scene: 0, t: 0, traces, board, pulses: Vec::new(), scope: vec![0.0; W * H], sparks: Vec::new() }
    }

    fn update(&mut self, next: bool) {
        self.tick += 1;
        self.t += 1;
        let len = SCENES[self.scene];
        if next && self.t < len - FADE {
            self.t = len - FADE;
        }
        if self.t >= len {
            self.t = 0;
            self.scene = (self.scene + 1) % SCENES.len();
            self.scope.fill(0.0);
        }
        // pulses running along the traces
        if self.rng.chance(0.25) {
            let i = (self.rng.next() % self.traces.len() as u64) as usize;
            let v = self.rng.range(0.8, 2.2);
            self.pulses.push((i, 0.0, v));
        }
        for p in &mut self.pulses {
            p.1 += p.2;
        }
        let traces = &self.traces;
        self.pulses.retain(|p| (p.1 as usize) < traces[p.0].len());
        // the oscilloscope: Lissajous figures, the last one a heart
        if self.scene == 3 {
            for v in &mut self.scope {
                *v *= 0.6;
            }
            let f = self.t as f32 / SCENES[3] as f32;
            let stage = (f * 4.0).min(3.999) as usize;
            // the whole figure every tick, the beam's last stretch brighter
            for k in 0..900 {
                let s = k as f32 / 900.0 * TAU + self.tick as f32 * 0.05;
                let bright = if k > 820 { 0.5 } else { 0.22 };
                let (x, y) = match stage {
                    0 => ((s * 1.0 + self.tick as f32 * 0.02).sin(), (s * 1.0).sin()),
                    1 => ((s * 1.0 + self.tick as f32 * 0.015).sin(), (s * 2.0).sin()),
                    2 => ((s * 3.0 + self.tick as f32 * 0.01).sin(), (s * 2.0).sin()),
                    _ => {
                        let a = s * 1.0;
                        let hx = 16.0 * a.sin().powi(3) / 17.0;
                        let hy = (13.0 * a.cos() - 5.0 * (2.0 * a).cos() - 2.0 * (3.0 * a).cos() - (4.0 * a).cos()) / 17.0;
                        let beat = 1.0 + 0.08 * (self.tick as f32 * 0.25).sin().max(0.0);
                        (hx * beat, hy * beat + 0.1)
                    }
                };
                let (px, py) = (64.0 + x * 52.0, 58.0 - y * 40.0);
                if px >= 0.0 && py >= 0.0 && (px as usize) < W && (py as usize) < H {
                    let p = &mut self.scope[py as usize * W + px as usize];
                    *p = (*p + bright).min(1.4);
                }
            }
        }
        // sparks between the title letters
        if self.scene == 1 && self.rng.chance(0.15) {
            let (mut x, mut y) = (self.rng.range(10.0, 118.0), self.rng.range(58.0, 120.0));
            let mut bolt = vec![(x, y)];
            let a = self.rng.range(0.0, TAU);
            for _ in 0..8 {
                x += a.cos() * 3.0 + self.rng.range(-2.0, 2.0);
                y += a.sin() * 3.0 + self.rng.range(-2.0, 2.0);
                bolt.push((x, y));
            }
            self.sparks.push(bolt);
        }
        if self.tick % 3 == 0 {
            self.sparks.clear();
        }
    }

    fn circuit(&self, buf: &mut [Col], k: f32) {
        for y in 0..H {
            for x in 0..W {
                let b = self.board[y * W + x];
                buf[y * W + x] = match b as i32 {
                    0 => [0.0, 0.025 * k, 0.03 * k],
                    1 => [0.0, 0.12 * k, 0.07 * k],
                    _ => [0.35 * k, 0.28 * k, 0.08 * k], // gold pads
                };
            }
        }
        for &(i, pos, _) in &self.pulses {
            let path = &self.traces[i];
            for tail in 0..10 {
                let j = pos as i32 - tail;
                if j >= 0 {
                    let (x, y) = path[j as usize];
                    let v = (1.0 - tail as f32 / 10.0) * k;
                    add(buf, x, y, [0.2 * v, 0.9 * v, 1.0 * v]);
                }
            }
        }
    }

    /// text with a colour function and a glow around it
    fn glow_text(buf: &mut [Col], lines: &[(Font, &str, i32)], col: impl Fn(i32, i32) -> Col, glow: Col) {
        let mut mask = vec![0.0f32; W * H];
        let mut px = Vec::new();
        for &(f, s, y) in lines {
            for (x, yy) in jp::pixels(f, s, jp::centre_x(f, s), y) {
                if x >= 0 && yy >= 0 && (x as usize) < W && (yy as usize) < H {
                    mask[yy as usize * W + x as usize] = 1.0;
                    px.push((x, yy));
                }
            }
        }
        let halo = blur(&mask, 3);
        for i in 0..W * H {
            let h = halo[i] * 1.6;
            for k in 0..3 {
                buf[i][k] += glow[k] * h;
            }
        }
        for (x, y) in px {
            buf[y as usize * W + x as usize] = col(x, y);
        }
    }

    fn boot(&self, buf: &mut [Col]) {
        let t = self.t as i32;
        let green = [0.25, 1.0, 0.4];
        // each line types at a character a tick, then pauses; LOADING counts for 130 ticks
        let (mut start, mut y) = (10, 8);
        for (i, line) in BOOT.iter().enumerate() {
            if t < start {
                break;
            }
            let n = ((t - start) as usize).min(line.len());
            let mut s = line[..n].to_string();
            let dur = if i == 6 { 140 } else { line.len() as i32 + 8 };
            if i == 6 {
                let pct = ((t - start) * 100 / 130).clamp(0, 100);
                s = format!("LOADING {:03}%", pct);
                let w = pct * 116 / 100;
                for yy in y + 16..y + 22 {
                    for x in 6..6 + w {
                        buf[yy as usize * W + x as usize] = green;
                    }
                }
            }
            let col = if i == 8 && t / 10 % 2 == 0 { [0.9, 1.0, 0.9] } else { green };
            jp::draw(buf, Font::S12, &s, 6, y, col);
            y += if i == 6 { 14 } else { 16 };
            start += dur;
        }
        // cursor
        if t / 15 % 2 == 0 {
            for yy in y..y + 11 {
                for x in 6..12 {
                    buf[(yy as usize).min(H - 1) * W + x] = green;
                }
            }
        }
        // scan lines
        for y in (0..H).step_by(2) {
            for x in 0..W {
                for v in &mut buf[y * W + x] {
                    *v *= 0.75;
                }
            }
        }
    }

    fn title(&self, buf: &mut [Col]) {
        self.circuit(buf, 0.8);
        let t = self.tick as f32;
        let sweep = (self.t as f32 * 1.5) % 260.0 - 60.0; // a highlight running across
        Self::glow_text(
            buf,
            &[(Font::S12, "ELEKI EXPO", 30), (Font::B24, "超エレキ", 56), (Font::B24, "万博2026", 88)],
            |x, y| {
                let g = smooth(14.0, 0.0, ((x + y) as f32 * 0.7 - sweep).abs());
                let base = mix([1.0, 0.85, 0.1], [1.0, 0.45, 0.05], ((y - 56) as f32 / 60.0).clamp(0.0, 1.0));
                let base = if y < 50 { [0.3, 0.9, 1.0] } else { base };
                mix(base, [1.0, 1.0, 1.0], g)
            },
            [0.6, 0.4, 0.05],
        );
        for bolt in &self.sparks {
            for s in bolt.windows(2) {
                crate::fx::line(buf, s[0].0, s[0].1, s[1].0, s[1].1, 1.0, [0.6, 0.9, 1.0]);
            }
        }
        let pulse = 0.75 + 0.25 * (t * 0.08).sin();
        jp::draw_centre(buf, Font::S12, "先進テクノロジの祭典", 132, [0.9 * pulse, 0.95 * pulse, 1.0 * pulse]);
        jp::draw_centre(buf, Font::S12, "2026.11.3 TUE", 160, [0.4, 0.9, 1.0]);
    }

    fn booth(&self, buf: &mut [Col]) {
        self.circuit(buf, 0.4);
        let t = self.tick as f32;
        jp::draw_centre(buf, Font::B16, "匠の電子工作館", 6, [0.5, 0.85, 1.0]);
        let sweep = (self.t as f32 * 1.5) % 260.0 - 60.0;
        Self::glow_text(
            buf,
            &[(Font::B24, "W40", 30), (Font::B24, "ふがふが", 64)],
            |x, y| {
                let g = smooth(14.0, 0.0, ((x + y) as f32 * 0.7 - sweep).abs());
                let base = if y < 60 { [1.0, 0.85, 0.15] } else { [1.0, 0.45, 0.65] };
                mix(base, [1.0, 1.0, 1.0], g)
            },
            [0.5, 0.25, 0.2],
        );
        for x in 10..118 {
            buf[101 * W + x] = [0.2, 0.5, 0.6];
        }
        // what the booth shows, a line at a time
        let lines = ["FPGAを使った", "デジタルサイネージ用", "LEDマトリクスの", "点灯制御"];
        for (k, l) in lines.iter().enumerate() {
            let start = 40.0 + k as f32 * 25.0;
            let p = smooth(start, start + 20.0, self.t as f32);
            if p > 0.0 {
                let c = [0.95 * p, 0.95 * p, 1.0 * p];
                jp::draw_centre(buf, Font::S12, l, 108 + k as i32 * 15, c);
            }
        }
        let k = 0.7 + 0.3 * (t * 0.12).sin();
        jp::draw_centre(buf, Font::S12, "GW3A / HUB75", 174, [0.3 * k, 1.0 * k, 0.5 * k]);
    }

    fn motto(&self, buf: &mut [Col]) {
        for p in buf.iter_mut() {
            *p = [0.0, 0.01, 0.01];
        }
        // the scope: a bezel, a graticule, the phosphor
        let (x0, y0, x1, y1) = (4, 14, 124, 102);
        for y in y0 - 2..y1 + 2 {
            for x in x0 - 2..x1 + 2 {
                let edge = y < y0 || y >= y1 || x < x0 || x >= x1;
                let i = y as usize * W + x as usize;
                buf[i] = if edge {
                    [0.2, 0.2, 0.22]
                } else if (x - 64) % 12 == 0 || (y - 58) % 11 == 0 {
                    let major = x == 64 || y == 58;
                    if major { [0.05, 0.16, 0.1] } else { [0.02, 0.07, 0.045] }
                } else {
                    [0.005, 0.025, 0.02]
                };
                let s = self.scope[i];
                if !edge && s > 0.0 {
                    buf[i] = [buf[i][0] + 0.3 * s, buf[i][1] + 1.0 * s, buf[i][2] + 0.5 * s];
                }
            }
        }
        jp::draw(buf, Font::S12, "CH1", 6, 2, [0.9, 0.9, 0.2]);
        jp::draw(buf, Font::S12, "1kHz", 98, 2, [0.6, 0.6, 0.65]);
        let beat = 0.8 + 0.2 * (self.tick as f32 * 0.25).sin().max(0.0);
        Self::glow_text(
            buf,
            &[(Font::B16, "エンジニアを", 114), (Font::B16, "技術で癒す！", 138)],
            |_, _| [1.0 * beat, 0.55 * beat, 0.75 * beat],
            [0.5, 0.15, 0.3],
        );
        jp::draw_centre(buf, Font::S12, "超エレキ万博2026", 172, [0.4, 0.9, 1.0]);
    }

    fn halls(&self, buf: &mut [Col]) {
        self.circuit(buf, 0.3);
        let top = 28;
        let scroll = 160.0 - self.t as f32 * 0.45;
        for (k, (a, b)) in HALLS.iter().enumerate() {
            let y = (scroll + k as f32 * 36.0) as i32;
            if y < top - 34 || y > H as i32 {
                continue;
            }
            let hue = k as f32 / 7.0;
            let col = [0.5 + 0.5 * (TAU * hue).cos(), 0.5 + 0.5 * (TAU * (hue + 0.33)).cos(), 0.5 + 0.5 * (TAU * (hue + 0.67)).cos()];
            // a numbered badge
            for yy in y + 6..y + 22 {
                for xx in 1..17 {
                    let d = ((xx as f32 - 8.5).powi(2) + (yy as f32 - (y + 14) as f32).powi(2)).sqrt();
                    if d < 7.5 && yy >= top && (yy as usize) < H {
                        buf[yy as usize * W + xx] = col;
                    }
                }
            }
            let mut draw = |f: Font, s: &str, x: i32, yy: i32, c: Col| {
                for (px, py) in jp::pixels(f, s, x, yy) {
                    if py >= top && px >= 0 && (px as usize) < W && (py as usize) < H {
                        buf[py as usize * W + px as usize] = c;
                    }
                }
            };
            draw(Font::S12, &(k + 1).to_string(), 6, y + 8, [0.0, 0.0, 0.0]);
            draw(Font::S12, a, 20, y + 2, col);
            draw(Font::S12, b, 20, y + 16, [0.95, 0.95, 1.0]);
            if k == BOOTH_HALL && self.tick / 20 % 3 != 0 {
                // this booth
                draw(Font::B16, "W40", 90, y + 1, [1.0, 0.85, 0.15]);
                draw(Font::S12, "ここ!", 93, y + 20, [1.0, 0.5, 0.6]);
            }
        }
        // the heading on a bar
        for y in 0..top - 2 {
            for x in 0..W {
                buf[y as usize * W + x] = [0.04, 0.05, 0.12];
            }
        }
        jp::draw_centre(buf, Font::B16, "7つの館", 4, [1.0, 0.85, 0.2]);
    }

    fn countdown(&self, buf: &mut [Col]) {
        self.circuit(buf, 0.45);
        let now = now();
        let (open, close) = (open_time(), close_time());
        let t = self.tick as f32;
        let glow = |buf: &mut [Col], lines: &[(Font, &str, i32)], col: Col| {
            Self::glow_text(buf, lines, |_, _| col, [col[0] * 0.4, col[1] * 0.4, col[2] * 0.4]);
        };
        if now < close {
            let left = (close - now).num_seconds();
            if now >= open {
                let k = 0.88 + 0.12 * (t * 0.1).sin();
                glow(buf, &[(Font::B24, "開催中", 10)], [1.0 * k, 0.35 * k, 0.45 * k]);
            }
            jp::draw_centre(buf, Font::B16, "閉幕まで", 52, [1.0, 1.0, 1.0]);
            let (d, h, m, s) = (left / 86400, left / 3600 % 24, left / 60 % 60, left % 60);
            let hms = format!("{:02}:{:02}:{:02}", h, m, s);
            if d > 0 {
                let days = format!("あと{}日", d);
                glow(buf, &[(Font::B24, &days, 76), (Font::B24, &hms, 108)], [1.0, 0.8, 0.15]);
            } else {
                glow(buf, &[(Font::B24, &hms, 84)], [1.0, 0.8, 0.15]);
            }
            // how much of the day (10:30 - 18:00) has gone
            let day = (close - open).num_seconds() as f32;
            let frac = ((now - open).num_seconds() as f32 / day).clamp(0.0, 1.0);
            for y in 146..152 {
                for x in 8..120 {
                    let on = ((x - 8) as f32) < frac * 112.0;
                    buf[y * W + x] = if on { [0.3, 0.9, 1.0] } else { [0.05, 0.1, 0.15] };
                }
            }
            jp::draw(buf, Font::S12, "10:30", 6, 154, [0.5, 0.6, 0.7]);
            jp::draw(buf, Font::S12, "18:00", 92, 154, [0.5, 0.6, 0.7]);
        } else {
            glow(buf, &[(Font::B16, "ご来場", 50), (Font::B16, "ありがとう", 74), (Font::B16, "ございました", 98)], [1.0, 0.85, 0.3]);
            jp::draw_centre(buf, Font::S12, "また会いましょう", 140, [0.4, 0.9, 1.0]);
        }
        jp::draw_centre(buf, Font::S12, "超エレキ万博2026", 172, [0.6, 0.7, 0.8]);
    }

    /// the end of the boot: rows jump sideways, colours split
    fn glitch(rng: &mut Rng, buf: &mut [Col]) {
        let src = buf.to_vec();
        for y in 0..H {
            let shift = if rng.chance(0.3) { rng.range(-20.0, 20.0) as i32 } else { 0 };
            for x in 0..W {
                let sx = (x as i32 + shift).rem_euclid(W as i32) as usize;
                let rx = (x as i32 + shift + 3).rem_euclid(W as i32) as usize;
                buf[y * W + x] = [src[y * W + rx][0], src[y * W + sx][1], src[y * W + sx][2]];
            }
        }
    }
}

impl crate::Game for Expo {
    fn step(&mut self, inp: Option<&mut Input>) {
        let next = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(next);
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        match self.scene {
            0 => self.boot(&mut buf),
            1 => self.title(&mut buf),
            2 => self.booth(&mut buf),
            3 => self.motto(&mut buf),
            4 => self.halls(&mut buf),
            _ => self.countdown(&mut buf),
        }
        let len = SCENES[self.scene];
        if self.scene == 0 && self.t + 30 > len {
            // glitch out of the boot screen (draw is &self: a throwaway rng)
            Self::glitch(&mut Rng::new(self.tick), &mut buf);
        }
        let fade = if self.scene == 0 { (self.t as f32 / 10.0).min(1.0) } else { (self.t.min(len - self.t) as f32 / FADE as f32).min(1.0) };
        to_canvas(&buf, c, fade, 1.4);
    }
    fn status(&self) -> String {
        format!("scene {}", ["boot", "title", "booth", "motto", "halls", "countdown"][self.scene])
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
