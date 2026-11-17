// A joke for EdgeTech+ 2026: the bento shop next to the CQ booth, four
// pages of 12 s each.
//
// 0. a nobori banner "お弁当" waving, "絶賛販売中" on a yellow tape
// 1. a bento box filling up (a picture: the shop's menu is not known)
// 2. baked sweets and drinks, "お取り置きできます！"
// 3. a microwave that counts down and dings, then on to the CQ booth
//
// The words come from the shop's own signs (photo, 2026-11-17): お弁当
// 絶賛販売中, 焼菓子, 飲料, お取り置きできます！, レンジご利用ください.
use crate::audio::{self, Bell};
use crate::explain::{disc, fill, frame, header, line_in, CYAN, DIM, FADE, GOLD, WHITE};
use crate::fx::{add, new_buf, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};

const PAGE: u64 = 720;
const PAGES: u64 = 4;
const RED: Col = [0.9, 0.04, 0.06];
const YELLOW: Col = [1.0, 0.85, 0.0];
const DING: u64 = 380; // the microwave's ding, ticks into its page

fn sc(c: Col, k: f32) -> Col {
    [c[0] * k, c[1] * k, c[2] * k]
}

/// a small hash for speckles (0..1)
fn hash(x: i32, y: i32) -> f32 {
    let mut h = (x as u32).wrapping_mul(374761393) ^ (y as u32).wrapping_mul(668265263);
    h = (h ^ (h >> 13)).wrapping_mul(1274126177);
    (h & 0xffff) as f32 / 65535.0
}

pub struct Bento {
    pub(crate) t: u64,
    tick: u64,
}

impl Bento {
    pub fn new(_seed: u64, _hi: u64) -> Bento {
        Bento { t: 0, tick: 0 }
    }

    fn page(&self) -> u64 {
        self.t / PAGE
    }

    fn banner(&self, buf: &mut [Col], t: u64) {
        let tk = self.tick as f32;
        line_in(buf, t, 10, Font::S12, "お隣さんのご紹介", 4, WHITE);
        // the pole, then the cloth waving from it (rows shift with a wave
        // that grows away from the pole)
        let k = smooth(20.0, 50.0, t as f32);
        fill(buf, 41, 18, 2, 134, sc([0.5, 0.5, 0.55], k));
        fill(buf, 41, 20, 46, 2, sc([0.5, 0.5, 0.55], k));
        // flat cloth and letters, then each pixel taken from where the wave
        // moved it (no holes)
        let (cx0, cx1, cy0, cy1) = (43, 85, 22, 124);
        let mut text = vec![false; ((cx1 - cx0) * (cy1 - cy0)) as usize];
        for (i, ch) in ["お", "弁", "当"].iter().enumerate() {
            let x = 64 - jp::width(Font::B24, ch) / 2;
            for (px, py) in jp::pixels(Font::B24, ch, x, 28 + i as i32 * 31) {
                if (cx0..cx1).contains(&px) && (cy0..cy1).contains(&py) {
                    text[((py - cy0) * (cx1 - cx0) + px - cx0) as usize] = true;
                }
            }
        }
        for y in cy0..cy1 {
            let wave = (y as f32 * 0.07 - tk * 0.08).sin();
            let shade = 0.8 + 0.2 * (y as f32 * 0.07 - tk * 0.08).cos();
            for x in cx0..cx1 + 3 {
                let sx = cx0 + ((x - cx0) as f32 / (1.0 + wave * 2.5 / 40.0)).round() as i32;
                if !(cx0..cx1).contains(&sx) {
                    continue;
                }
                let c = if text[((y - cy0) * (cx1 - cx0) + sx - cx0) as usize] { WHITE } else { sc(RED, shade) };
                fill(buf, x, y, 1, 1, sc(c, k));
            }
        }
        // the tape, wobbling a little
        let kt = smooth(120.0, 140.0, t as f32);
        if kt > 0.0 {
            let y = 132 + ((tk * 0.1).sin() * 1.5).round() as i32;
            fill(buf, 14, y, 100, 22, sc(YELLOW, kt));
            jp::draw_centre(buf, Font::B16, "絶賛販売中", y + 3, [0.0, 0.0, 0.0]);
        }
        line_in(buf, t, 260, Font::S12, "(勝手に応援中)", 172, DIM);
    }

    fn bento(&self, buf: &mut [Col], t: u64) {
        header(buf, "お弁当");
        let (x0, y0, w, h) = (8, 30, 112, 88);
        let k = smooth(10.0, 40.0, t as f32);
        fill(buf, x0, y0, w, h, sc([0.4, 0.03, 0.03], k));
        fill(buf, x0 + 3, y0 + 3, w - 6, h - 6, sc([0.03, 0.02, 0.02], k));
        fill(buf, 62, y0 + 3, 2, h - 6, sc([0.4, 0.03, 0.03], k));
        fill(buf, 64, 72, 53, 2, sc([0.4, 0.03, 0.03], k));
        let names = ["ごはん", "からあげ", "卵焼き", "ブロッコリー", "ウインナー"];
        let at = |i: usize| 60.0 + i as f32 * 80.0;
        let shown = |i: usize| smooth(at(i), at(i) + 20.0, t as f32);
        // rice and an umeboshi
        let a = shown(0);
        if a > 0.0 {
            for y in 34..115 {
                for x in 12..61 {
                    let g = 0.75 + 0.25 * hash(x, y);
                    fill(buf, x, y, 1, 1, sc([0.85, 0.85, 0.78], a * g));
                }
            }
            disc(buf, 36.5, 74.5, 6.0, sc([0.75, 0.04, 0.1], a));
            disc(buf, 34.5, 72.5, 1.5, sc([1.0, 0.5, 0.5], a));
        }
        // karaage: lumpy brown pieces
        let a = shown(1);
        if a > 0.0 {
            for (cx, cy, r) in [(76.0, 46.0, 8.0), (94.0, 52.0, 9.0), (110.0, 44.0, 7.0), (84.0, 62.0, 7.0), (106.0, 63.0, 6.0)] {
                disc(buf, cx, cy, r, sc([0.5, 0.22, 0.04], a));
                for j in 0..6 {
                    let (dx, dy) = ((j as f32 * 1.9).cos() * r * 0.6, (j as f32 * 1.9).sin() * r * 0.6);
                    disc(buf, cx + dx, cy + dy, r * 0.35, sc([0.7, 0.36, 0.08], a));
                }
                disc(buf, cx - r * 0.3, cy - r * 0.35, r * 0.2, sc([1.0, 0.75, 0.35], a));
            }
        }
        // tamagoyaki: two slices with their rolls
        let a = shown(2);
        if a > 0.0 {
            for (i, x) in [66, 78].iter().enumerate() {
                fill(buf, *x, 78 + i as i32 * 3, 11, 30, sc([1.0, 0.78, 0.1], a));
                for s in [84, 92, 100] {
                    fill(buf, *x + 1, s + i as i32 * 3, 9, 1, sc([0.9, 0.55, 0.05], a));
                }
            }
        }
        // broccoli
        let a = shown(3);
        if a > 0.0 {
            fill(buf, 99, 92, 3, 8, sc([0.45, 0.65, 0.2], a));
            for (dx, dy) in [(-4.0, -2.0), (4.0, -2.0), (0.0, -5.0), (0.0, 0.0)] {
                disc(buf, 100.5 + dx, 86.0 + dy, 4.0, sc([0.05, 0.5, 0.1], a));
            }
            disc(buf, 98.0, 81.0, 1.2, sc([0.4, 0.9, 0.3], a));
        }
        // a tako-wiener at the bottom right
        let a = shown(4);
        if a > 0.0 {
            disc(buf, 108.5, 104.0, 5.0, sc([0.9, 0.12, 0.08], a));
            for l in 0..4 {
                fill(buf, 103 + l * 3, 108, 2, 5, sc([0.9, 0.12, 0.08], a));
            }
            disc(buf, 107.0, 102.0, 1.2, sc([1.0, 0.6, 0.5], a));
        }
        // the name of the newest one, then the call
        let newest = (0..names.len()).rev().find(|&i| t as f32 >= at(i));
        if t as f32 >= at(4) + 120.0 {
            line_in(buf, t, at(4) as u64 + 120, Font::B16, "絶賛販売中", 128, GOLD);
        } else if let Some(i) = newest {
            let kk = smooth(at(i), at(i) + 15.0, t as f32);
            jp::draw_centre(buf, Font::B16, names[i], 128, sc(WHITE, kk));
        }
        line_in(buf, t, 30, Font::S12, "※イメージ", 176, DIM);
    }

    fn snacks(&self, buf: &mut [Col], t: u64) {
        header(buf, "焼菓子・飲み物");
        let tk = self.tick as f32;
        // green tea and water, bobbing in turn
        let bob = |i: f32| ((tk * 0.08 + i * 1.6).sin() * 1.5).round() as i32;
        let k = smooth(20.0, 50.0, t as f32);
        let y = 40 + bob(0.0);
        fill(buf, 22, y + 4, 10, 6, sc([0.05, 0.3, 0.08], k));
        fill(buf, 18, y + 10, 18, 50, sc([0.15, 0.55, 0.2], k));
        fill(buf, 18, y + 26, 18, 14, sc([0.85, 0.85, 0.75], k));
        fill(buf, 20, y + 30, 14, 2, sc([0.15, 0.55, 0.2], k));
        fill(buf, 20, y + 34, 10, 2, sc([0.15, 0.55, 0.2], k));
        let ka = smooth(70.0, 100.0, t as f32);
        let y = 40 + bob(1.0);
        fill(buf, 52, y + 4, 10, 6, sc([0.1, 0.3, 0.8], ka));
        fill(buf, 48, y + 10, 18, 50, sc([0.25, 0.5, 0.75], ka));
        fill(buf, 50, y + 12, 3, 44, sc([0.6, 0.8, 1.0], ka));
        fill(buf, 48, y + 28, 18, 10, sc([0.1, 0.3, 0.8], ka));
        // cookies
        let kb = smooth(120.0, 150.0, t as f32);
        for (i, (cx, cy)) in [(90.0, 64.0), (106.0, 76.0), (90.0, 88.0)].iter().enumerate() {
            let cy = cy + bob(2.0 + i as f32) as f32;
            disc(buf, *cx, cy, 8.0, sc([0.7, 0.42, 0.15], kb));
            disc(buf, *cx, cy, 6.0, sc([0.82, 0.55, 0.22], kb));
            for j in 0..4 {
                let a = j as f32 * 1.7 + i as f32;
                disc(buf, cx + a.cos() * 3.5, cy + a.sin() * 3.5, 0.9, sc([0.25, 0.1, 0.03], kb));
            }
        }
        jp::draw(buf, Font::S12, "お茶", 15, 104, sc(WHITE, k));
        if ka > 0.0 {
            jp::draw(buf, Font::S12, "水", 51, 104, sc(WHITE, ka));
        }
        if kb > 0.0 {
            jp::draw(buf, Font::S12, "焼菓子", 80, 104, sc(WHITE, kb));
        }
        // the sign
        let kc = smooth(260.0, 290.0, t as f32);
        if kc > 0.0 {
            let pulse = 0.75 + 0.25 * (tk * 0.15).sin().abs();
            frame(buf, 6, 124, 116, 48, sc(WHITE, kc * pulse));
            frame(buf, 7, 125, 114, 46, sc(WHITE, kc * pulse * 0.4));
            jp::draw_centre(buf, Font::B16, "お取り置き", 131, sc(WHITE, kc));
            jp::draw_centre(buf, Font::S12, "できます！", 152, sc(GOLD, kc));
        }
    }

    fn microwave(&self, buf: &mut [Col], t: u64) {
        header(buf, "電子レンジ");
        let tk = self.tick as f32;
        let (x0, y0) = (12, 30);
        fill(buf, x0, y0, 104, 66, [0.35, 0.36, 0.4]);
        fill(buf, x0 + 2, y0 + 64, 100, 2, [0.2, 0.2, 0.22]);
        // the window: dark, lit orange while it runs
        let running = t >= 60 && t < DING;
        let glow = if running { 0.8 + 0.2 * (tk * 0.5).sin() } else { 0.15 };
        fill(buf, x0 + 5, y0 + 5, 66, 54, sc([0.9, 0.45, 0.1], glow * 0.35));
        frame(buf, x0 + 5, y0 + 5, 66, 54, [0.15, 0.15, 0.17]);
        // a bento on the turntable (its width swings as it turns)
        let ang = if running { (t - 60) as f32 * 0.05 } else if t >= DING { (DING - 60) as f32 * 0.05 } else { 0.0 };
        let bw = (10.0 + 12.0 * ang.cos().abs()) as i32;
        fill(buf, x0 + 38 - bw, y0 + 44, bw * 2, 8, [0.45, 0.04, 0.04]);
        fill(buf, x0 + 39 - bw, y0 + 45, bw * 2 - 2, 3, [0.85, 0.82, 0.7]);
        fill(buf, x0 + 14, y0 + 53, 48, 2, [0.25, 0.25, 0.28]);
        // the panel: the time left and a dial
        let left = if t < 60 {
            5
        } else if t < DING {
            5 - ((t - 60) * 5 / (DING - 60)) as i32
        } else {
            0
        };
        fill(buf, x0 + 76, y0 + 8, 24, 14, [0.02, 0.05, 0.02]);
        let lcd = if t >= DING && (self.tick / 15) % 2 == 0 { [0.1, 0.3, 0.1] } else { [0.3, 1.0, 0.4] };
        jp::draw(buf, Font::S12, &format!("0:{:02}", left), x0 + 77, y0 + 9, lcd);
        disc(buf, (x0 + 88) as f32, (y0 + 38) as f32, 7.0, [0.6, 0.6, 0.65]);
        let a = ang * 2.0;
        fill(buf, x0 + 88 + (a.cos() * 4.0) as i32, y0 + 38 + (a.sin() * 4.0) as i32, 2, 2, [0.1, 0.1, 0.1]);
        // ding: the word with rays around it
        if t >= DING {
            let k = smooth(DING as f32, DING as f32 + 8.0, t as f32);
            let r = 1.0 + 0.3 * (1.0 - smooth(DING as f32, DING as f32 + 30.0, t as f32));
            for j in 0..12 {
                let a = j as f32 * std::f32::consts::TAU / 12.0 + tk * 0.02;
                for d in 0..8 {
                    let rr = (26.0 + d as f32) * r;
                    add(buf, (64.0 + a.cos() * rr * 1.4) as i32, (62.0 + a.sin() * rr) as i32, sc(YELLOW, 0.5 * k));
                }
            }
            fill(buf, 30, 50, 68, 26, sc([0.0, 0.0, 0.0], k));
            jp::draw_centre(buf, Font::B24, "チン！", 51, sc(YELLOW, k));
        }
        line_in(buf, t, 20, Font::S12, "レンジご利用ください", 102, WHITE);
        line_in(buf, t, DING + 60, Font::S12, "※LEDでは温まりません", 120, DIM);
        line_in(buf, t, DING + 140, Font::S12, "おなかが満ちたら", 144, WHITE);
        line_in(buf, t, DING + 170, Font::B16, "CQ出版ブースへ", 160, CYAN);
    }
}

impl crate::Game for Bento {
    fn step(&mut self, inp: Option<&mut Input>) {
        let next = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.tick += 1;
        let pt = self.t % PAGE;
        if next && pt < PAGE - FADE {
            self.t += PAGE - FADE - pt;
        }
        self.t = (self.t + 1) % (PAGE * PAGES);
        let pt = self.t % PAGE;
        if pt == 1 {
            audio::play(Bell::new(880.0, 0.05, 0.5));
            audio::play(Bell::new(1318.5, 0.04, 0.5).after(0.12));
        }
        if self.page() == 3 && pt == DING {
            // the microwave's ding: one bright bell
            audio::play(Bell::new(1975.5, 0.09, 1.0));
        }
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        let t = self.t % PAGE;
        match self.page() {
            0 => self.banner(&mut buf, t),
            1 => self.bento(&mut buf, t),
            2 => self.snacks(&mut buf, t),
            _ => self.microwave(&mut buf, t),
        }
        debug_assert_eq!(buf.len(), W * H);
        let fade = (t.min(PAGE - t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.4);
    }
    fn status(&self) -> String {
        format!("page {}", ["banner", "bento", "snacks", "microwave"][self.page() as usize])
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Game;

    /// every page draws (HUB75_SNAP=dir: near the end of each, as PPM files)
    #[test]
    fn pages() {
        let mut b = Bento::new(1, 0);
        for p in 0..PAGES {
            while b.t != p * PAGE + PAGE - FADE - 1 {
                b.step(None);
            }
            let mut c = Canvas::new();
            b.draw(&mut c);
            if let Some(dir) = std::env::var_os("HUB75_SNAP") {
                let mut f = Vec::from(format!("P6\n{} {}\n255\n", W, H).as_bytes());
                c.px.iter().for_each(|p| f.extend_from_slice(p));
                std::fs::write(std::path::Path::new(&dir).join(format!("bento{}.ppm", p)), f).unwrap();
            }
        }
    }
}
