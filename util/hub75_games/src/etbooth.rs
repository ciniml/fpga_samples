// The booth guide for EdgeTech+ 2026 (CQ publishing's booth): four pages
// of 15 s each.
//
// 0. the event: dates, hours, the venue
// 1. the hall map (from the official floor map): this booth, CQ DF-05 in
//    hall D, and GOWIN at Marubun BG-05 in hall B, a dot walking the way
// 2. what the CQ booth has (from its entry in the official online guide)
// 3. these panels run on a GOWIN FPGA, and where GOWIN shows its own
//
// The facts (checked 2026-11-14): jasa.or.jp/expo (dates, hours, venue,
// registration), the online guide (booths: CQ出版社 DF-05, 丸文株式会社
// BG-05 with GOWIN), the floor map jasa.or.jp/expo/2026/pdf/floormap.jpg.
use crate::audio::{self, Bell};
use crate::explain::{disc, fill, frame, header, line_in, CYAN, DIM, FADE, GOLD, WHITE};
use crate::fx::{new_buf, smooth, to_canvas, Col};
use crate::gfx::{Canvas, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};

const PAGE: u64 = 900;
const PAGES: u64 = 4;
const MARU: Col = [1.0, 0.55, 0.15];

// the map: the halls' box on the floor map, normalised 0..1 across / down
const MAP: (i32, i32, i32, i32) = (2, 36, 124, 47);
const CQ: (f32, f32) = (0.283, 0.769); // DF-05
const MARUBUN: (f32, f32) = (0.922, 0.753); // BG-05
const HALLS: [(&str, f32, f32); 3] = [("D", 0.0, 0.36), ("C", 0.36, 0.66), ("B", 0.66, 1.0)];
const DOORS: [f32; 4] = [0.12, 0.526, 0.725, 0.937];
const AISLE: f32 = 0.9;

fn map_xy(p: (f32, f32)) -> (f32, f32) {
    (MAP.0 as f32 + p.0 * MAP.2 as f32, MAP.1 as f32 + p.1 * MAP.3 as f32)
}

fn sc(c: Col, k: f32) -> Col {
    [c[0] * k, c[1] * k, c[2] * k]
}

pub struct EtBooth {
    pub(crate) t: u64,
    tick: u64,
}

impl EtBooth {
    pub fn new(_seed: u64, _hi: u64) -> EtBooth {
        EtBooth { t: 0, tick: 0 }
    }

    fn page(&self) -> u64 {
        self.t / PAGE
    }

    fn event(&self, buf: &mut [Col], t: u64) {
        let tk = self.tick as f32;
        // traces running across behind the title
        for k in 0..6 {
            let y = 24 + k * 7;
            let x = ((tk * (0.6 + k as f32 * 0.15) + k as f32 * 37.0) % 170.0) as i32 - 20;
            fill(buf, 0, y, W as i32, 1, [0.04, 0.07, 0.14]);
            for d in 0..14 {
                fill(buf, x - d, y, 1, 1, sc(CYAN, 0.5 * (1.0 - d as f32 / 14.0)));
            }
        }
        let k = smooth(10.0, 40.0, t as f32);
        jp::glow_text(buf, &[(Font::B24, "EdgeTech+", 30)], |_, y| sc(crate::fx::mix(CYAN, WHITE, (y as f32 - 30.0) / 24.0), k), sc([0.1, 0.3, 0.6], k));
        line_in(buf, t, 60, Font::B16, "2026.11.18-20", 64, GOLD);
        line_in(buf, t, 100, Font::S12, "水〜金 10:00-17:00", 86, WHITE);
        line_in(buf, t, 120, Font::S12, "19日(木)のみ18時まで", 100, DIM);
        line_in(buf, t, 200, Font::B16, "パシフィコ横浜", 122, WHITE);
        line_in(buf, t, 220, Font::S12, "展示ホール", 142, DIM);
        line_in(buf, t, 320, Font::S12, "入場無料(事前登録制)", 170, CYAN);
    }

    fn map(&self, buf: &mut [Col], t: u64) {
        header(buf, "会場マップ");
        let (x0, y0, w, h) = MAP;
        let k = smooth(10.0, 40.0, t as f32);
        // the halls, the doors at the bottom
        for (i, (name, a, b)) in HALLS.iter().enumerate() {
            let xa = x0 + (a * w as f32) as i32;
            let xb = x0 + (b * w as f32) as i32;
            fill(buf, xa + 1, y0, xb - xa - 1, h, sc([0.05, 0.08, 0.16], k));
            // booths, a few rows of them
            for r in 0..4 {
                for c in 0..((xb - xa - 6) / 7) {
                    if (r * 7 + c + i as i32) % 5 == 0 {
                        continue;
                    }
                    fill(buf, xa + 4 + c * 7, y0 + 12 + r * 8, 5, 5, sc([0.11, 0.14, 0.24], k));
                }
            }
            let tw = jp::width(Font::S12, name);
            jp::draw(buf, Font::S12, name, (xa + xb - tw) / 2, y0 + 1, sc(DIM, k));
        }
        frame(buf, x0, y0, w, h, sc([0.3, 0.4, 0.6], k));
        for d in DOORS {
            let x = x0 + (d * w as f32) as i32;
            fill(buf, x - 1, y0 + h, 3, 3, sc([0.9, 0.2, 0.3], k));
        }
        // the way from here to GOWIN, then the two booths blinking
        let (cx, cy) = map_xy(CQ);
        let (mx, my) = map_xy(MARUBUN);
        let ay = y0 as f32 + AISLE * h as f32;
        let route = [(cx, cy), (cx, ay), (mx, ay), (mx, my)];
        let lens: Vec<f32> = route.windows(2).map(|p| (p[1].0 - p[0].0).abs() + (p[1].1 - p[0].1).abs()).collect();
        let total: f32 = lens.iter().sum();
        if t > 200 {
            let walk = ((t - 200) as f32 * 0.6) % (total + 40.0);
            let mut d = 0.0;
            for (i, l) in lens.iter().enumerate() {
                let (a, b) = (route[i], route[i + 1]);
                let n = *l as i32;
                for s in 0..n {
                    let f = s as f32 / *l;
                    let (x, y) = (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f);
                    let lit = d + s as f32 <= walk;
                    if s % 2 == 0 {
                        fill(buf, x as i32, y as i32, 1, 1, if lit { sc(GOLD, 0.8) } else { [0.12, 0.12, 0.08] });
                    }
                }
                if walk >= d && walk < d + l {
                    let f = (walk - d) / l;
                    disc(buf, a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, 1.6, WHITE);
                }
                d += l;
            }
        }
        let blink = 0.55 + 0.45 * (self.tick as f32 * 0.12).sin().abs();
        if t > 60 {
            disc(buf, cx, cy, 2.6, sc(CYAN, blink));
            // on a dark patch so the booths behind do not show through
            fill(buf, cx as i32 - 13, cy as i32 - 16, 26, 13, [0.0, 0.0, 0.0]);
            jp::draw(buf, Font::S12, "ここ", cx as i32 - 12, cy as i32 - 15, CYAN);
        }
        if t > 120 {
            disc(buf, mx, my, 2.6, sc(MARU, blink));
        }
        // the legend
        let ka = smooth(60.0, 80.0, t as f32);
        if ka > 0.0 {
            disc(buf, 7.0, 104.0, 3.0, sc(CYAN, ka));
            jp::draw(buf, Font::B16, "CQ出版社", 14, 95, sc(WHITE, ka));
            jp::draw(buf, Font::S12, "DF-05 ホールD", 14, 113, sc(CYAN, ka));
        }
        let kb = smooth(120.0, 140.0, t as f32);
        if kb > 0.0 {
            disc(buf, 7.0, 140.0, 3.0, sc(MARU, kb));
            jp::draw(buf, Font::B16, "丸文 (GOWIN)", 14, 131, sc(WHITE, kb));
            jp::draw(buf, Font::S12, "BG-05 ホールB", 14, 149, sc(MARU, kb));
        }
        line_in(buf, t, 260, Font::S12, "ホールD→C→Bへ", 172, DIM);
    }

    fn cq(&self, buf: &mut [Col], t: u64) {
        header(buf, "CQ出版社 DF-05");
        let items: [(&str, &str, Col); 3] = [
            ("Interface筆者の", "ミニ・セミナ", CYAN),
            ("学生による", "研究発表 (LT)", GOLD),
            ("Interface最新号", "書籍・キットの販売", [0.5, 1.0, 0.5]),
        ];
        for (i, (a, b, c)) in items.iter().enumerate() {
            let y = 34 + i as i32 * 42;
            let at = 40.0 + i as f32 * 90.0;
            let k = smooth(at, at + 25.0, t as f32);
            if k <= 0.0 {
                continue;
            }
            // a bullet that pulses once as the line comes in
            let p = 1.0 + 0.6 * (1.0 - smooth(at, at + 40.0, t as f32));
            fill(buf, 4, y + 6, (5.0 * p) as i32, (5.0 * p) as i32, sc(*c, k));
            jp::draw(buf, Font::S12, a, 14, y, sc(WHITE, k));
            jp::draw(buf, Font::S12, b, 14, y + 15, sc(*c, k));
        }
        line_in(buf, t, 360, Font::S12, "ぜひお立ち寄り", 162, WHITE);
        line_in(buf, t, 380, Font::S12, "ください", 176, WHITE);
    }

    fn gowin(&self, buf: &mut [Col], t: u64) {
        header(buf, "GOWIN FPGA");
        line_in(buf, t, 30, Font::S12, "このLED表示は", 28, WHITE);
        line_in(buf, t, 50, Font::B16, "GOWIN GW3A", 42, GOLD);
        line_in(buf, t, 70, Font::S12, "(Arora III) 1チップ", 60, DIM);
        line_in(buf, t, 120, Font::S12, "Ethernet受信から", 77, WHITE);
        line_in(buf, t, 140, Font::S12, "LEDの点灯まで", 90, WHITE);
        line_in(buf, t, 260, Font::S12, "GOWINの展示は", 110, WHITE);
        line_in(buf, t, 280, Font::B16, "丸文 BG-05", 124, MARU);
        line_in(buf, t, 300, Font::S12, "ホールB", 143, DIM);
        // an arrow pointing on to hall B
        let k = smooth(320.0, 340.0, t as f32);
        if k > 0.0 {
            let x = 98 + ((self.tick / 4) % 12) as i32;
            for d in 0..5 {
                fill(buf, x + d, 144 + d, 1, 9 - 2 * d, sc(MARU, k));
            }
            fill(buf, x - 12, 148, 12, 1, sc(MARU, k));
        }
        line_in(buf, t, 400, Font::S12, "各種IFソリューション", 162, CYAN);
        line_in(buf, t, 420, Font::S12, "中小規模FPGA新製品", 176, CYAN);
    }
}

impl crate::Game for EtBooth {
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
        if self.t % PAGE == 1 {
            // a two-note chime as each page comes in
            audio::play(Bell::new(1174.7, 0.05, 0.6));
            audio::play(Bell::new(1760.0, 0.04, 0.6).after(0.12));
        }
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        let t = self.t % PAGE;
        match self.page() {
            0 => self.event(&mut buf, t),
            1 => self.map(&mut buf, t),
            2 => self.cq(&mut buf, t),
            _ => self.gowin(&mut buf, t),
        }
        let fade = (t.min(PAGE - t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.4);
    }
    fn status(&self) -> String {
        format!("page {}", ["event", "map", "cq", "gowin"][self.page() as usize])
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
