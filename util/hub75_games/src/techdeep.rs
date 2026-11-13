// The technical explanation for EdgeTech+ (an engineering crowd): eight
// slides of 15 s each, more numbers and wiring than explain (which goes on
// how a panel shows a picture at all).
//
// 0. the title and the chapters
// 1. the system: PC → RGMII PHY → MAC → UDP → DDR2 → bit planes → HUB75 ×16,
//    the clock domains
// 2. the UDP protocol: the packet, the ports, the ack
// 3. 1000 Mbit/s: RGMII nibbles on both edges of 125 MHz, a byte a clock
// 4. the DDR2 frame buffer: two pages, the bandwidth, the read tuning
// 5. driving HUB75: 16 lanes, 1/32 scan, CLK / LAT / OE, 8-bit BCM
// 6. Veryl: a piece of the real source, the numbers of the RTL
// 7. the GW3A-LV20 used: resources and Fmax of the build in the flash
//
// Numbers from eda/ethernet_hub75 (README, the place-and-route report of
// build/dk_led_rxcard_gw3a20_ddrplane_16p_c8: the 16-panel 8-bit DDR2 build
// with audio that is in the board's flash).
use crate::audio::{self, Bell, Tone};
use crate::explain::{disc, fill, frame, header, hue, line_in, pic, CYAN, DIM, FADE, GOLD, WHITE};
use crate::fx::{new_buf, smooth, to_canvas, Col};
use crate::gfx::Canvas;
use crate::input::{Input, Key};
use crate::jp::{self, Font};

const SLIDE: u64 = 900;
const SLIDES: u64 = 8;
const GREEN: Col = [0.45, 1.0, 0.5];
const PINK: Col = [1.0, 0.45, 0.8];
const LINE: Col = [0.25, 0.3, 0.45];

fn sc(c: Col, k: f32) -> Col {
    [c[0] * k, c[1] * k, c[2] * k]
}

/// a box with a label, fading in at `at`
fn block(buf: &mut [Col], t: u64, at: u64, x: i32, y: i32, w: i32, h: i32, s: &str, c: Col) {
    let k = smooth(at as f32, at as f32 + 20.0, t as f32);
    if k <= 0.0 {
        return;
    }
    fill(buf, x + 1, y + 1, w - 2, h - 2, sc(c, 0.12 * k));
    frame(buf, x, y, w, h, sc(c, k));
    let tw = jp::width(Font::S12, s);
    jp::draw(buf, Font::S12, s, x + (w - tw) / 2, y + (h - 12) / 2, sc(WHITE, k));
}

/// a down arrow between boxes with dots running along it
fn flow(buf: &mut [Col], t: u64, at: u64, tick: u64, x: i32, y0: i32, y1: i32, c: Col) {
    let k = smooth(at as f32, at as f32 + 20.0, t as f32);
    if k <= 0.0 {
        return;
    }
    fill(buf, x, y0, 1, y1 - y0, sc(LINE, k));
    let n = (y1 - y0).max(1);
    let y = y0 + ((tick / 2) as i32 % n);
    fill(buf, x - 1, y, 3, 2, sc(c, k));
}

/// a labelled bar: `v` of `max`, growing from `at`
fn bar(buf: &mut [Col], t: u64, at: u64, y: i32, name: &str, v: f32, max: f32, text: &str, c: Col) {
    let k = smooth(at as f32, at as f32 + 20.0, t as f32);
    if k <= 0.0 {
        return;
    }
    jp::draw(buf, Font::S12, name, 2, y, sc(DIM, k));
    let tw = jp::width(Font::S12, text);
    jp::draw(buf, Font::S12, text, 126 - tw, y, sc(WHITE, k));
    frame(buf, 2, y + 14, 124, 7, sc(LINE, k));
    let g = smooth(at as f32 + 10.0, at as f32 + 60.0, t as f32);
    let w = (v / max * 122.0 * g) as i32;
    fill(buf, 3, y + 15, w.max(1), 5, sc(c, k));
}

pub struct TechDeep {
    t: u64,
    tick: u64,
}

impl TechDeep {
    pub fn new(_seed: u64, _hi: u64) -> TechDeep {
        TechDeep { t: 0, tick: 0 }
    }

    fn slide(&self) -> u64 {
        self.t / SLIDE
    }

    fn title(&self, buf: &mut [Col], t: u64) {
        let tk = self.tick as f32;
        let k = smooth(10.0, 40.0, t as f32);
        jp::glow_text(buf, &[(Font::B16, "技術解説", 18)], |_, _| sc(GOLD, k), sc([0.4, 0.25, 0.0], k));
        line_in(buf, t, 40, Font::S12, "Ethernet → HUB75", 42, CYAN);
        line_in(buf, t, 60, Font::S12, "FPGA 1チップで", 56, WHITE);
        let ch = ["① システム構成", "② UDPプロトコル", "③ 1000Mbps受信", "④ DDR2バッファ", "⑤ HUB75駆動", "⑥ Veryl", "⑦ リソース"];
        for (i, s) in ch.iter().enumerate() {
            let at = 120 + i as u64 * 30;
            line_in(buf, t, at, Font::S12, s, 80 + i as i32 * 15, if i % 2 == 0 { WHITE } else { DIM });
        }
        // a cursor stepping down the chapters
        if t > 360 {
            let i = ((t - 360) / 40) % 7;
            let y = 80 + i as i32 * 15;
            fill(buf, 0, y + 2, 2, 9, sc(GOLD, 0.6 + 0.4 * (tk * 0.2).sin().abs()));
        }
    }

    fn system(&self, buf: &mut [Col], t: u64) {
        header(buf, "① 構成");
        let tk = self.tick;
        block(buf, t, 20, 26, 26, 76, 14, "PC (UDP送信)", WHITE);
        flow(buf, t, 40, tk, 64, 40, 44, CYAN);
        block(buf, t, 50, 22, 44, 84, 14, "PHY RTL8211E", CYAN);
        flow(buf, t, 70, tk, 64, 58, 76, CYAN);
        // the FPGA: what is inside
        let k = smooth(80.0, 100.0, t as f32);
        if k > 0.0 {
            frame(buf, 4, 62, 120, 104, sc(GOLD, k * 0.8));
            jp::draw(buf, Font::S12, "GW3A", 7, 63, sc(GOLD, k));
        }
        block(buf, t, 110, 30, 76, 68, 14, "MAC・CRC", CYAN);
        flow(buf, t, 130, tk, 64, 90, 94, CYAN);
        block(buf, t, 140, 30, 94, 68, 14, "UDP 振り分け", CYAN);
        // sound to the side
        let ka = smooth(160.0, 180.0, t as f32);
        if ka > 0.0 {
            fill(buf, 98, 101, 6, 1, sc(LINE, ka));
        }
        block(buf, t, 160, 104, 94, 20, 14, "I2S", PINK);
        flow(buf, t, 170, tk, 64, 108, 112, GREEN);
        block(buf, t, 180, 18, 112, 92, 14, "DDR2 2面 128KB", GREEN);
        flow(buf, t, 200, tk, 64, 126, 130, GREEN);
        block(buf, t, 210, 18, 130, 92, 14, "ビットプレーン", GOLD);
        flow(buf, t, 230, tk, 64, 144, 148, GOLD);
        block(buf, t, 240, 18, 148, 92, 14, "HUB75 ×16レーン", GOLD);
        // the link and the clock domains
        line_in(buf, t, 300, Font::S12, "1000BASE-T / RGMII", 168, DIM);
        line_in(buf, t, 360, Font::S12, "125/83.3/50 MHz", 181, DIM);
    }

    fn protocol(&self, buf: &mut [Col], t: u64) {
        header(buf, "② UDP");
        // a packet: the headers, the offset, the pixels (widths not to scale
        // for the headers)
        let parts: [(&str, i32, Col); 5] = [("Eth", 20, DIM), ("IP", 14, DIM), ("UDP", 20, DIM), ("ofs", 20, GOLD), ("RGB565", 50, CYAN)];
        let mut x = 2;
        for (i, (s, w, c)) in parts.iter().enumerate() {
            let at = 20 + i as u64 * 20;
            let k = smooth(at as f32, at as f32 + 20.0, t as f32);
            if k > 0.0 {
                fill(buf, x, 30, w - 1, 12, sc(*c, 0.35 * k));
                let tw = jp::width(Font::S12, s);
                if tw <= *w {
                    jp::draw(buf, Font::S12, s, x + (w - tw) / 2, 30, sc(WHITE, k));
                }
            }
            x += w;
        }
        line_in(buf, t, 140, Font::S12, "ofs: 2B (BE)", 46, GOLD);
        line_in(buf, t, 160, Font::S12, "RGB565 512画素", 60, CYAN);
        // the ports
        let ports: [(&str, &str, Col); 4] = [("10004", "映像", CYAN), ("10005", "色テーブル", GOLD), ("10002", "音声", PINK), ("10006", "状態", GREEN)];
        for (i, (p, s, c)) in ports.iter().enumerate() {
            let at = 240 + i as u64 * 30;
            let k = smooth(at as f32, at as f32 + 20.0, t as f32);
            if k > 0.0 {
                let y = 80 + i as i32 * 14;
                jp::draw(buf, Font::S12, p, 8, y, sc(*c, k));
                jp::draw(buf, Font::S12, s, 46, y, sc(WHITE, k));
            }
        }
        // the frame goes, the ack comes back
        let k = smooth(400.0, 420.0, t as f32);
        if k > 0.0 {
            let ph = ((t - 400) % 120) as f32 / 120.0;
            fill(buf, 4, 142, 120, 1, sc(LINE, k));
            if ph < 0.6 {
                for j in 0..4 {
                    let x = (ph / 0.6 * 130.0) as i32 - j * 10;
                    fill(buf, x, 139, 7, 3, sc(CYAN, k));
                }
            } else {
                let x = 124 - ((ph - 0.6) / 0.4 * 124.0) as i32;
                fill(buf, x, 144, 5, 3, sc(GOLD, k));
            }
            jp::draw(buf, Font::S12, "ack: de ad be ef", 16, 150, sc(GOLD, k));
        }
        line_in(buf, t, 500, Font::S12, "256x256=128パケット", 166, WHITE);
        line_in(buf, t, 520, Font::S12, "GbEで1.12ms/フレーム", 180, WHITE);
    }

    fn rgmii(&self, buf: &mut [Col], t: u64) {
        header(buf, "③ RGMII");
        line_in(buf, t, 20, Font::S12, "4bit × 両エッジ", 30, WHITE);
        // a scrolling timing diagram: RXC, RXD nibbles on both edges, the byte
        let k = smooth(60.0, 80.0, t as f32);
        if k > 0.0 {
            let sh = ((self.tick / 3) % 16) as i32;
            jp::draw(buf, Font::S12, "RXC", 2, 52, sc(DIM, k));
            jp::draw(buf, Font::S12, "RXD", 2, 72, sc(DIM, k));
            for x in 26..126 {
                let p = (x + sh) % 16;
                let hi = p < 8;
                let y = if hi { 52 } else { 62 };
                fill(buf, x, y, 1, 1, sc(CYAN, k));
                if p == 0 || p == 8 {
                    fill(buf, x, 52, 1, 11, sc(CYAN, k));
                }
                // a nibble per half period, changing between the edges
                let q = (x + sh + 4) % 8;
                if q == 0 {
                    fill(buf, x, 72, 1, 10, sc(GOLD, k));
                } else {
                    fill(buf, x, 72, 1, 1, sc(GOLD, k));
                    fill(buf, x, 81, 1, 1, sc(GOLD, k));
                }
                let n = (x + sh + 4) / 8;
                if q == 4 {
                    let s = if n % 2 == 0 { "L" } else { "H" };
                    jp::draw(buf, Font::S12, s, x - 2, 71, sc(WHITE, k));
                }
            }
        }
        line_in(buf, t, 200, Font::S12, "125MHz × 8bit", 96, GOLD);
        line_in(buf, t, 220, Font::S12, "= 1000Mbps", 110, GOLD);
        line_in(buf, t, 320, Font::S12, "IDDR + IODELAYで受け", 128, WHITE);
        line_in(buf, t, 340, Font::S12, "1クロック1バイト処理", 142, WHITE);
        line_in(buf, t, 440, Font::S12, "PHYの遅延はMDIOで設定", 160, DIM);
        line_in(buf, t, 460, Font::S12, "10/100Mも自動判別", 174, DIM);
    }

    fn ddr2(&self, buf: &mut [Col], t: u64) {
        header(buf, "④ DDR2");
        // two pages: one written from the network, one read for the panels
        let front = (self.tick / 90) % 2;
        let fill_rows = ((self.tick % 90) * 24 / 90) as i32;
        for pg in 0..2u64 {
            let x = 10 + pg as i32 * 60;
            let k = smooth(20.0 + pg as f32 * 20.0, 40.0 + pg as f32 * 20.0, t as f32);
            if k <= 0.0 {
                continue;
            }
            let reading = pg == front;
            frame(buf, x, 30, 48, 26, sc(if reading { GOLD } else { GREEN }, k));
            let rows = if reading { 24 } else { fill_rows };
            for yy in 0..rows {
                for xx in 0..46 {
                    let c = pic((xx as f32 + 0.5) / 46.0, (yy as f32 + 0.5) / 24.0, 0.0);
                    crate::explain::put(buf, x + 1 + xx, 31 + yy, sc(c, 0.8 * k));
                }
            }
            let s = if reading { "表示" } else { "書込" };
            jp::draw(buf, Font::S12, s, x + 12, 58, sc(if reading { GOLD } else { GREEN }, k));
        }
        line_in(buf, t, 120, Font::S12, "そろったら切替 (返事)", 74, WHITE);
        // the bandwidth: write + read of the 667 MB/s peak
        bar(buf, t, 200, 92, "書込", 96.0, 667.0, "96MB/s", GREEN);
        bar(buf, t, 260, 116, "読出", 113.0, 667.0, "113MB/s", GOLD);
        line_in(buf, t, 320, Font::S12, "ピーク667MB/sの約3割", 142, DIM);
        line_in(buf, t, 420, Font::S12, "読出位置を自動調整", 162, CYAN);
        line_in(buf, t, 440, Font::S12, "RD_LAT × RD_SEL", 176, CYAN);
    }

    fn hub75(&self, buf: &mut [Col], t: u64) {
        header(buf, "⑤ HUB75");
        // 16 lanes side by side, all shifting at once
        let k = smooth(20.0, 40.0, t as f32);
        if k > 0.0 {
            let ph = (self.tick % 64) as i32;
            for l in 0..16 {
                let x = 4 + l * 7 + l / 4 * 2;
                frame(buf, x, 28, 6, 20, sc(LINE, k));
                let h = (ph * 18 / 64).max(1);
                fill(buf, x + 1, 29 + 18 - h, 4, h, sc(hue(l as f32 / 16.0), 0.8 * k));
            }
            jp::draw(buf, Font::S12, "16レーン同時にシフト", 6, 50, sc(WHITE, k));
        }
        // the signals: 64 clocks a row, LAT, then OE on for the plane's time
        let ks = smooth(140.0, 160.0, t as f32);
        if ks > 0.0 {
            let names = ["CLK", "LAT", "OE"];
            for (i, n) in names.iter().enumerate() {
                jp::draw(buf, Font::S12, n, 2, 70 + i as i32 * 16, sc(DIM, ks));
            }
            let sh = (self.tick / 2) as i32;
            for x in 24..126 {
                let p = (x + sh) % 80;
                // CLK: a burst during the shift
                let clk = p < 60 && (p / 2) % 2 == 0;
                fill(buf, x, if clk { 72 } else { 80 }, 1, 1, sc(CYAN, ks));
                let lat = p == 62 || p == 63;
                fill(buf, x, if lat { 88 } else { 96 }, 1, 1, sc(GOLD, ks));
                let oe = p >= 66;
                fill(buf, x, if oe { 104 } else { 112 }, 1, 1, sc(PINK, ks));
            }
        }
        line_in(buf, t, 300, Font::S12, "CLK 16.7MHz", 120, WHITE);
        line_in(buf, t, 320, Font::S12, "1/32スキャン 2行同時", 134, WHITE);
        line_in(buf, t, 340, Font::S12, "8bit BCM (8面)", 148, WHITE);
        line_in(buf, t, 440, Font::B16, "432Hz", 160, GOLD);
        line_in(buf, t, 460, Font::S12, "書き換え/秒", 178, DIM);
    }

    fn veryl(&self, buf: &mut [Col], t: u64) {
        header(buf, "⑥ Veryl");
        // a piece of src/common/audio_i2s.veryl, typed in
        let code: [(&str, Col); 10] = [
            ("module AudioI2s #(", PINK),
            ("  param RATE: u32", WHITE),
            ("        = 48000,", GOLD),
            (") (", WHITE),
            (" i_clk : input clock,", CYAN),
            (" o_bclk: output logic", CYAN),
            (") {", WHITE),
            ("  var acc: logic<32>;", WHITE),
            ("  always_ff {", PINK),
            ("    acc += INC; ...", WHITE),
        ];
        let typed = (t.saturating_sub(20) / 3) as usize;
        let mut n = 0;
        for (i, (s, c)) in code.iter().enumerate() {
            let y = 28 + i as i32 * 12;
            let len = s.chars().count();
            let show = typed.saturating_sub(n).min(len);
            n += len;
            if show == 0 {
                break;
            }
            let part: String = s.chars().take(show).collect();
            jp::draw(buf, Font::S12, &part, 2, y, *c);
            if show < len && (self.tick / 15) % 2 == 0 {
                fill(buf, 2 + show as i32 * 6, y + 1, 5, 10, WHITE);
            }
        }
        line_in(buf, t, 520, Font::S12, "RTLはすべてVeryl", 152, GOLD);
        line_in(buf, t, 540, Font::S12, "31ファイル 9845行", 166, WHITE);
        line_in(buf, t, 600, Font::S12, "検証: Verilator", 180, DIM);
    }

    fn resources(&self, buf: &mut [Col], t: u64) {
        header(buf, "⑦ リソース");
        line_in(buf, t, 10, Font::S12, "GW3A-LV20 16枚版", 28, DIM);
        bar(buf, t, 40, 42, "ロジック", 9682.0, 23040.0, "43%", CYAN);
        bar(buf, t, 80, 66, "FF", 5227.0, 23736.0, "23%", GREEN);
        bar(buf, t, 120, 90, "BSRAM", 27.0, 120.0, "27/120", GOLD);
        bar(buf, t, 160, 114, "I/O", 171.0, 238.0, "171/238", PINK);
        line_in(buf, t, 300, Font::S12, "Fmax (制約)", 137, DIM);
        line_in(buf, t, 330, Font::S12, "sys 125.2MHz (125)", 150, WHITE);
        line_in(buf, t, 360, Font::S12, "DRAM 121.9MHz (83.3)", 164, WHITE);
        line_in(buf, t, 390, Font::S12, "表示 100.7MHz (50)", 178, WHITE);
        // the tight one blinks
        if t > 420 && (self.tick / 20) % 2 == 0 {
            disc(buf, 120.0, 156.0, 1.5, GOLD);
        }
    }
}

impl crate::Game for TechDeep {
    fn step(&mut self, inp: Option<&mut Input>) {
        let next = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.tick += 1;
        let st = self.t % SLIDE;
        if next && st < SLIDE - FADE {
            self.t += SLIDE - FADE - st;
        }
        self.t = (self.t + 1) % (SLIDE * SLIDES);
        let st = self.t % SLIDE;
        if st == 1 {
            audio::play(Bell::new(1046.5, 0.05, 0.6));
            audio::play(Bell::new(1568.0, 0.04, 0.6).after(0.1));
        }
        // the Veryl slide types: a soft key click a character
        if self.slide() == 6 && st >= 20 && st < 20 + 3 * 190 && st % 3 == 0 {
            audio::play(Tone::new(2400.0, 0.012, 10.0).len(0.01));
        }
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        let t = self.t % SLIDE;
        match self.slide() {
            0 => self.title(&mut buf, t),
            1 => self.system(&mut buf, t),
            2 => self.protocol(&mut buf, t),
            3 => self.rgmii(&mut buf, t),
            4 => self.ddr2(&mut buf, t),
            5 => self.hub75(&mut buf, t),
            6 => self.veryl(&mut buf, t),
            _ => self.resources(&mut buf, t),
        }
        let fade = (t.min(SLIDE - t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.4);
    }
    fn status(&self) -> String {
        let names = ["title", "system", "protocol", "rgmii", "ddr2", "hub75", "veryl", "resources"];
        format!("slide {}", names[self.slide() as usize])
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
    use crate::gfx::{H, W};
    use crate::Game;

    /// every slide draws (HUB75_SNAP=dir: near the end of each, as PPM files)
    #[test]
    fn slides() {
        let mut d = TechDeep::new(1, 0);
        let mut e = crate::etbooth::EtBooth::new(1, 0);
        for s in 0..SLIDES {
            while d.t != s * SLIDE + SLIDE - FADE - 1 {
                d.step(None);
            }
            if s < 4 {
                while e.t != s * 900 + 900 - FADE - 1 {
                    e.step(None);
                }
            }
            for (name, g) in [("techdeep", &d as &dyn Game), ("etbooth", &e as &dyn Game)] {
                if name == "etbooth" && s >= 4 {
                    continue;
                }
                let mut c = Canvas::new();
                g.draw(&mut c);
                if let Some(dir) = std::env::var_os("HUB75_SNAP") {
                    let mut f = Vec::from(format!("P6\n{} {}\n255\n", W, H).as_bytes());
                    c.px.iter().for_each(|p| f.extend_from_slice(p));
                    std::fs::write(std::path::Path::new(&dir).join(format!("{}{}.ppm", name, s)), f).unwrap();
                }
            }
        }
    }
}
