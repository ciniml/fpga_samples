// A clock on 128x192 (a demo, no game): the PC's local time on three faces
// that take turns every 20 s with a fade (Space / Enter: the next face).
//
// - analog: a dial with minute marks and numerals, hour and minute hands,
//   a red second hand that sweeps smoothly; the digital time and the date
//   below.
// - nixie tubes: hours, minutes, seconds in three rows of two tubes. Each
//   digit is a glowing orange stroke (distance to its polyline: a hot core
//   and a soft glow), the other cathodes show faintly behind it, a fine
//   mesh covers the glass, and a new digit fades in as the old one fades out.
// - 7-segment LEDs: big slanted red digits for hours and minutes, a blinking
//   colon, the date on top and a bar of 60 dots for the seconds.
//
// Sound: the analog face ticks and tocks every second, the nixie tubes
// click softly, the LEDs are silent; every quarter hour the Westminster
// chimes ring (one to four phrases), and on the hour the bell strikes the
// hours.
use crate::audio::{self, Bell, Burst};
use crate::fx::{line, new_buf, seg_dist, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};
use chrono::{Datelike, Local, NaiveDateTime, Timelike};
use std::f32::consts::{PI, TAU};

const FACE_LEN: u64 = 20 * 60;
const FADE: u64 = 30;
const WEEK: [&str; 7] = ["月", "火", "水", "木", "金", "土", "日"];

/// polylines of a nixie digit in a 10 x 16 box
fn nixie_digit(d: u32) -> Vec<Vec<(f32, f32)>> {
    let arc = |cx: f32, cy: f32, rx: f32, ry: f32, a0: f32, a1: f32| -> Vec<(f32, f32)> {
        (0..=24).map(|k| {
            let a = a0 + (a1 - a0) * k as f32 / 24.0;
            (cx + rx * a.cos(), cy + ry * a.sin())
        }).collect()
    };
    match d {
        0 => vec![arc(5.0, 8.0, 4.3, 7.5, 0.0, TAU)],
        1 => vec![vec![(2.8, 3.2), (5.6, 0.5), (5.6, 15.5)]],
        2 => {
            let mut p = arc(5.0, 4.5, 4.2, 4.0, PI, TAU + 0.5);
            p.extend([(0.8, 15.5), (9.4, 15.5)]);
            vec![p]
        }
        3 => {
            let mut p = vec![(1.0, 0.5), (9.0, 0.5), (4.6, 6.2)];
            p.extend(arc(5.0, 10.8, 4.4, 4.7, -PI / 2.0 - 0.1, PI * 0.85));
            vec![p]
        }
        4 => vec![vec![(7.2, 15.5), (7.2, 0.5), (0.6, 11.0), (9.6, 11.0)]],
        5 => {
            let mut p = vec![(9.0, 0.5), (1.8, 0.5), (1.2, 6.8)];
            p.extend(arc(5.0, 10.6, 4.4, 4.9, -PI * 0.75, PI * 0.8));
            vec![p]
        }
        6 => vec![arc(5.0, 11.2, 4.3, 4.3, 0.0, TAU), arc(10.5, 11.0, 9.8, 10.5, PI, PI * 1.38)],
        7 => vec![vec![(0.6, 0.5), (9.4, 0.5), (3.2, 15.5)]],
        8 => vec![arc(5.0, 4.0, 3.5, 3.5, 0.0, TAU), arc(5.0, 11.6, 4.3, 3.9, 0.0, TAU)],
        _ => vec![arc(5.0, 4.8, 4.3, 4.3, 0.0, TAU), arc(-0.5, 5.0, 9.8, 10.5, 0.0, PI * 0.38)],
    }
}

/// segments of a 7-segment digit (a..g) as lines in a 10 x 18 box
const SEGS: [((f32, f32), (f32, f32)); 7] = [
    ((1.5, 0.0), (8.5, 0.0)),   // a
    ((10.0, 1.5), (10.0, 7.5)), // b
    ((10.0, 10.5), (10.0, 16.5)), // c
    ((1.5, 18.0), (8.5, 18.0)), // d
    ((0.0, 10.5), (0.0, 16.5)), // e
    ((0.0, 1.5), (0.0, 7.5)),   // f
    ((1.5, 9.0), (8.5, 9.0)),   // g
];
const DIGIT_SEGS: [u8; 10] = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f];

pub struct Clock {
    tick: u64,
    face: u32,
    t: u64,
    nixie: Vec<Vec<Vec<(f32, f32)>>>,
    last_sec: Option<u32>,
}

impl Clock {
    pub fn new(_seed: u64, _hi: u64) -> Clock {
        Clock { tick: 0, face: 0, t: 0, nixie: (0..10).map(nixie_digit).collect(), last_sec: None }
    }

    fn date(now: &NaiveDateTime) -> String {
        format!("{}月{}日({})", now.month(), now.day(), WEEK[now.weekday().num_days_from_monday() as usize])
    }

    fn analog(&self, buf: &mut [Col], now: &NaiveDateTime) {
        let (cx, cy, r) = (64.0f32, 66.0f32, 58.0f32);
        for y in 0..H {
            for x in 0..W {
                let (dx, dy) = (x as f32 + 0.5 - cx, y as f32 + 0.5 - cy);
                let d = (dx * dx + dy * dy).sqrt();
                buf[y * W + x] = if d < r {
                    let k = 1.0 - d / r * 0.5;
                    [0.05 * k, 0.07 * k, 0.12 * k]
                } else if d < r + 2.5 {
                    [0.35, 0.36, 0.4] // the rim
                } else {
                    [0.01, 0.01, 0.02]
                };
            }
        }
        for m in 0..60 {
            let a = m as f32 / 60.0 * TAU - PI / 2.0;
            let (len, w) = if m % 5 == 0 { (7.0, 2.2) } else { (3.0, 1.0) };
            let (c, s) = (a.cos(), a.sin());
            line(buf, cx + c * (r - 2.0), cy + s * (r - 2.0), cx + c * (r - 2.0 - len), cy + s * (r - 2.0 - len), w, [0.85, 0.85, 0.9]);
        }
        for h in 1..=12 {
            let a = h as f32 / 12.0 * TAU - PI / 2.0;
            let s = h.to_string();
            let (x, y) = (cx + a.cos() * 41.0, cy + a.sin() * 41.0);
            jp::draw(buf, Font::S12, &s, (x - jp::width(Font::S12, &s) as f32 / 2.0) as i32, (y - 6.0) as i32, [0.75, 0.8, 0.9]);
        }
        let sec = now.second() as f32 + now.nanosecond().min(999_999_999) as f32 / 1e9;
        let min = now.minute() as f32 + sec / 60.0;
        let hour = (now.hour() % 12) as f32 + min / 60.0;
        let hand = |buf: &mut [Col], frac: f32, len: f32, tail: f32, w: f32, col: Col| {
            let a = frac * TAU - PI / 2.0;
            let (c, s) = (a.cos(), a.sin());
            line(buf, cx - c * tail, cy - s * tail, cx + c * len, cy + s * len, w, col);
        };
        hand(buf, hour / 12.0, 30.0, 6.0, 4.5, [0.95, 0.95, 1.0]);
        hand(buf, min / 60.0, 46.0, 6.0, 3.0, [0.95, 0.95, 1.0]);
        hand(buf, sec / 60.0, 52.0, 12.0, 1.3, [1.0, 0.15, 0.1]);
        for y in (cy - 4.0) as i32..(cy + 5.0) as i32 {
            for x in (cx - 4.0) as i32..(cx + 5.0) as i32 {
                if ((x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2)).sqrt() < 3.2 {
                    buf[y as usize * W + x as usize] = [1.0, 0.2, 0.1];
                }
            }
        }
        let hms = format!("{:02}:{:02}:{:02}", now.hour(), now.minute(), now.second());
        jp::draw_centre(buf, Font::B24, &hms, 134, [0.9, 0.95, 1.0]);
        jp::draw_centre(buf, Font::B16, &Self::date(now), 168, [0.6, 0.75, 1.0]);
    }

    fn nixie(&self, buf: &mut [Col], now: &NaiveDateTime) {
        for p in buf.iter_mut() {
            *p = [0.01, 0.008, 0.008];
        }
        let frac = now.nanosecond().min(999_999_999) as f32 / 1e9;
        // the digits now and a second ago: the change fades over 0.15 s
        let prev = *now - chrono::Duration::seconds(1);
        let fade = smooth(0.0, 0.15, frac);
        let rows = [(now.hour(), prev.hour()), (now.minute(), prev.minute()), (now.second(), prev.second())];
        for (row, &(v, pv)) in rows.iter().enumerate() {
            for k in 0..2 {
                let (d, pd) = if k == 0 { (v / 10, pv / 10) } else { (v % 10, pv % 10) };
                let (x0, y0) = (8 + k as i32 * 60, row as i32 * 64 + 2);
                self.tube(buf, x0, y0, d, if d == pd { None } else { Some((pd, 1.0 - fade)) }, if d == pd { 1.0 } else { fade });
            }
        }
    }

    /// one tube 52 x 60 at (x0, y0) showing digit d (and `old` fading out)
    fn tube(&self, buf: &mut [Col], x0: i32, y0: i32, d: u32, old: Option<(u32, f32)>, k: f32) {
        let (tw, th) = (52, 60);
        let sc = 2.55;
        let (ox, oy) = (x0 as f32 + (tw as f32 - 10.0 * sc) / 2.0, y0 as f32 + 6.0);
        for y in y0..y0 + th {
            for x in x0..x0 + tw {
                let (fx, fy) = (x as f32 + 0.5, y as f32 + 0.5);
                // the glass: rounded at the top, a socket below
                let (lx, ly) = (fx - x0 as f32 - tw as f32 / 2.0, fy - y0 as f32);
                let r = tw as f32 / 2.0 - 1.0;
                let inside = if ly < r { lx * lx + (ly - r).powi(2) < r * r } else { lx.abs() < r && ly < th as f32 - 6.0 };
                let rim = if ly < r { (lx * lx + (ly - r).powi(2)).sqrt() > r - 1.2 } else { lx.abs() > r - 1.2 };
                if !inside {
                    if ly >= th as f32 - 6.0 && lx.abs() < r - 2.0 {
                        buf[y as usize * W + x as usize] = [0.06, 0.05, 0.05]; // socket
                    }
                    continue;
                }
                let mut c: Col = [0.025, 0.02, 0.02];
                if rim {
                    c = [0.12, 0.13, 0.15];
                }
                // a fine hexagonal-ish mesh over the glass
                if (x + (y / 3) % 2 * 2) % 4 == 0 && y % 3 == 0 {
                    c = [c[0] + 0.03, c[1] + 0.025, c[2] + 0.02];
                }
                let (u, v) = ((fx - ox) / sc, (fy - oy) / sc);
                let dist = |n: u32| -> f32 {
                    let mut m = f32::MAX;
                    for pl in &self.nixie[n as usize] {
                        for s in pl.windows(2) {
                            m = m.min(seg_dist(u, v, s[0].0, s[0].1, s[1].0, s[1].1));
                        }
                    }
                    m * sc // in pixels
                };
                // unlit cathodes behind (only near the digit box)
                let near = (-1.0..11.0).contains(&u) && (-1.0..17.0).contains(&v);
                for n in (0..10).filter(|_| near) {
                    if dist(n) < 0.7 {
                        c = [c[0] + 0.035, c[1] + 0.015, c[2] + 0.005];
                    }
                }
                let mut glow = |n: u32, k: f32| {
                    let dd = dist(n);
                    let core = smooth(1.3, 0.4, dd) * k;
                    let halo = (-dd / 2.2).exp() * 0.55 * k;
                    for (i, (a, b)) in [(1.0, 1.0), (0.75, 0.38), (0.35, 0.05)].iter().enumerate() {
                        c[i] += a * core + b * halo;
                    }
                };
                glow(d, k);
                if let Some((pd, pk)) = old {
                    glow(pd, pk);
                }
                buf[y as usize * W + x as usize] = c;
            }
        }
    }

    fn seven(&self, buf: &mut [Col], now: &NaiveDateTime) {
        for p in buf.iter_mut() {
            *p = [0.012, 0.004, 0.004];
        }
        jp::draw_centre(buf, Font::S12, &Self::date(now), 1, [0.9, 0.35, 0.25]);
        let digit = |buf: &mut [Col], x0: f32, y0: f32, n: u32| {
            let sc = 3.6;
            let on = DIGIT_SEGS[n as usize];
            for y in y0 as i32 - 4..(y0 + 18.0 * sc) as i32 + 5 {
                for x in x0 as i32 - 8..(x0 + 10.0 * sc) as i32 + 8 {
                    if x < 0 || x as usize >= W || y < 0 || y as usize >= H {
                        continue;
                    }
                    let fy = (y as f32 + 0.5 - y0) / sc;
                    let fx = (x as f32 + 0.5 - x0) / sc + (fy - 9.0) * 0.12; // slant
                    let (mut lit, mut dim) = (f32::MAX, f32::MAX);
                    for (i, &((ax, ay), (bx, by))) in SEGS.iter().enumerate() {
                        let d = seg_dist(fx, fy, ax, ay, bx, by);
                        if on >> i & 1 != 0 {
                            lit = lit.min(d);
                        } else {
                            dim = dim.min(d);
                        }
                    }
                    let p = &mut buf[y as usize * W + x as usize];
                    let core = smooth(1.0, 0.7, lit);
                    let halo = (-(lit - 0.8).max(0.0) * 1.2).exp() * 0.25;
                    let off = smooth(1.0, 0.7, dim) * 0.08;
                    *p = [p[0] + core + halo + off, p[1] + core * 0.12 + halo * 0.05 + off * 0.1, p[2] + core * 0.08 + off * 0.1];
                }
            }
        };
        let (h, m) = (now.hour(), now.minute());
        digit(buf, 14.0, 18.0, h / 10);
        digit(buf, 72.0, 18.0, h % 10);
        digit(buf, 14.0, 104.0, m / 10);
        digit(buf, 72.0, 104.0, m % 10);
        // colon between the rows, on for the first half of each second
        if now.nanosecond() < 500_000_000 {
            for cx in [59.0f32, 69.0] {
                for y in 92..97 {
                    for x in (cx - 2.0) as i32..(cx + 2.0) as i32 {
                        buf[y * W + x as usize] = [1.0, 0.15, 0.1];
                    }
                }
            }
        }
        // the seconds: 60 dots
        for s in 0..60 {
            let x = 4 + s * 2;
            let c = if s <= now.second() as usize { [1.0, 0.2, 0.1] } else { [0.12, 0.02, 0.02] };
            buf[184 * W + x] = c;
            buf[185 * W + x] = c;
        }
    }
}

impl Clock {
    fn sound_second(&self, h: u32, m: u32, s: u32) {
        let seed = (self.tick as u32).wrapping_mul(2654435761);
        match self.face {
            0 => audio::play(Burst::new(seed, if s % 2 == 0 { 2600.0 } else { 2100.0 }, 6.0, 0.25, 0.005)),
            1 => audio::play(Burst::new(seed, 1400.0, 2.0, 0.08, 0.003)),
            _ => {}
        }
        if s != 0 || m % 15 != 0 {
            return;
        }
        // Westminster: phrases of four notes (E major, G#4 F#4 E4 B3)
        const N: [f32; 4] = [415.3, 370.0, 329.6, 246.9];
        const PHRASES: [[usize; 4]; 5] = [[0, 1, 2, 3], [2, 0, 1, 3], [2, 1, 0, 2], [0, 2, 1, 3], [3, 1, 0, 2]];
        let list: &[usize] = match m {
            15 => &[0],
            30 => &[1, 2],
            45 => &[3, 4, 0],
            _ => &[1, 2, 3, 4],
        };
        let mut at = 0.0;
        for &p in list {
            for (k, &n) in PHRASES[p].iter().enumerate() {
                let long = if k == 3 { 1.0 } else { 0.0 };
                audio::play(Bell::new(N[n], 0.12, 1.2).after(at));
                at += 0.6 + 0.6 * long;
            }
        }
        if m == 0 {
            at += 0.8;
            for _ in 0..(h + 11) % 12 + 1 {
                audio::play(Bell::new(164.8, 0.2, 2.0).after(at));
                at += 1.8;
            }
        }
    }
}

impl crate::Game for Clock {
    fn step(&mut self, inp: Option<&mut Input>) {
        self.tick += 1;
        let next = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        if next && self.t < FACE_LEN - FADE {
            self.t = FACE_LEN - FADE;
        }
        self.t += 1;
        if self.t >= FACE_LEN {
            self.t = 0;
            self.face = (self.face + 1) % 3;
        }
        let now = Local::now();
        let sec = now.second();
        if self.last_sec.is_some_and(|l| l != sec) {
            self.sound_second(now.hour(), now.minute(), sec);
        }
        self.last_sec = Some(sec);
    }
    fn draw(&self, c: &mut Canvas) {
        let now = Local::now().naive_local();
        let mut buf = new_buf();
        match self.face {
            0 => self.analog(&mut buf, &now),
            1 => self.nixie(&mut buf, &now),
            _ => self.seven(&mut buf, &now),
        }
        let fade = (self.t.min(FACE_LEN - self.t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.5);
    }
    fn status(&self) -> String {
        format!("{} {}", ["analog", "nixie", "7-segment"][self.face as usize], Local::now().format("%H:%M:%S"))
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
