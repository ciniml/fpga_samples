// How these panels work, for the booth: seven animated scenes (about 100 s
// in all) that explain the design of eda/ethernet_hub75.
//
// 0. the whole path: PC → LAN cable → FPGA (+ DDR2) → HUB75 panels
// 1. a frame cut into UDP packets of 1024 bytes, the ack back
// 2. inside the FPGA: PHY, MAC (CRC), UDP, the frame buffer's two pages
// 3. scanning: two rows lit at a time, sped up until the picture looks whole
// 4. BCM: LEDs are on or off, brightness is on-time weighted 32:16:...:1
// 5. the corner turn: pixel values → bit planes (the GMT block of GW3A)
// 6. the recap: the five steps again, each with a small moving picture
// 7. the specs
//
// Sound: a chime as each scene comes in. Packets leaving the PC blip, the
// ack answers with a two-note "got it", the MAC drops the broken packet
// with a buzz and the pages swap with a click. The scan and BCM scenes
// play their own timing: a click for every row lit (every bit plane
// switched) that runs faster with the animation until it turns into a
// tone, the way the blinking turns into a steady picture (held for a
// second at full speed, then quiet). The recap and
// the specs ring a bell for each line.
use crate::audio::{self, Bell, Burst, Hp, Keep, Param, Smooth, Tone, Voice};
use crate::fx::{mix, new_buf, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::jp::{self, Font};
use std::f32::consts::{PI, TAU};

const SCENES: [u64; 8] = [720, 900, 900, 1000, 1100, 900, 780, 720];
const FADE: u64 = 20;
const WHITE: Col = [0.95, 0.95, 1.0];
const CYAN: Col = [0.3, 0.85, 1.0];
const GOLD: Col = [1.0, 0.85, 0.2];
const DIM: Col = [0.55, 0.6, 0.7];
const BCM_VALUES: [u32; 4] = [63, 45, 20, 7];
const BCM_COLOR: Col = [1.0, 0.3, 0.15];
const BCM_MAX: f32 = 128.0; // BCM scene: top speed, units of the LSB a tick

fn hue(h: f32) -> Col {
    let c = |o: f32| 0.5 + 0.5 * (TAU * (h - o)).cos();
    [c(0.0), c(1.0 / 3.0), c(2.0 / 3.0)]
}

/// the picture the scenes send around: a heart on rainbow stripes (u, v in 0..1)
fn pic(u: f32, v: f32, ph: f32) -> Col {
    let bg = hue(u * 0.6 + v * 0.4 + ph);
    let (x, y) = ((u - 0.5) * 2.8, (0.42 - v) * 2.8);
    let a = x * x + y * y - 1.0;
    if a * a * a - x * x * y * y * y <= 0.0 {
        let hl = smooth(0.5, 0.0, ((x + 0.45).powi(2) + (y - 0.35).powi(2)).sqrt());
        mix([1.0, 0.15, 0.35], [1.0, 0.85, 0.9], hl * 0.8)
    } else {
        [bg[0] * 0.3, bg[1] * 0.3, bg[2] * 0.3]
    }
}

fn put(buf: &mut [Col], x: i32, y: i32, c: Col) {
    if x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
        buf[y as usize * W + x as usize] = c;
    }
}

fn fill(buf: &mut [Col], x: i32, y: i32, w: i32, h: i32, c: Col) {
    for yy in y..y + h {
        for xx in x..x + w {
            put(buf, xx, yy, c);
        }
    }
}

fn frame(buf: &mut [Col], x: i32, y: i32, w: i32, h: i32, c: Col) {
    fill(buf, x, y, w, 1, c);
    fill(buf, x, y + h - 1, w, 1, c);
    fill(buf, x, y, 1, h, c);
    fill(buf, x + w - 1, y, 1, h, c);
}

fn disc(buf: &mut [Col], cx: f32, cy: f32, r: f32, c: Col) {
    for y in (cy - r - 1.0) as i32..=(cy + r + 1.0) as i32 {
        for x in (cx - r - 1.0) as i32..=(cx + r + 1.0) as i32 {
            let d = ((x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2)).sqrt();
            let a = (r + 0.5 - d).clamp(0.0, 1.0);
            if a > 0.0 && x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
                let p = &mut buf[y as usize * W + x as usize];
                *p = mix(*p, c, a);
            }
        }
    }
}

/// the picture scaled into a box
fn thumb(buf: &mut [Col], x0: i32, y0: i32, w: i32, h: i32, ph: f32) {
    for y in 0..h {
        for x in 0..w {
            put(buf, x0 + x, y0 + y, pic((x as f32 + 0.5) / w as f32, (y as f32 + 0.5) / h as f32, ph));
        }
    }
}

fn header(buf: &mut [Col], s: &str) {
    fill(buf, 0, 0, W as i32, 23, [0.04, 0.06, 0.15]);
    fill(buf, 0, 23, W as i32, 1, [0.2, 0.4, 0.8]);
    jp::draw_centre(buf, Font::B16, s, 2, GOLD);
}

/// a line of text that fades in from tick `at` of the scene
fn line_in(buf: &mut [Col], t: u64, at: u64, f: Font, s: &str, y: i32, c: Col) {
    let k = smooth(at as f32, at as f32 + 20.0, t as f32);
    if k > 0.0 {
        jp::draw_centre(buf, f, s, y, [c[0] * k, c[1] * k, c[2] * k]);
    }
}

pub struct Explain {
    tick: u64,
    scene: usize,
    t: u64,
    row: f32,       // scan scene: the row being lit (0..32, wraps)
    speed: f32,     // rows a tick
    eye: [f32; 32], // how bright each scan row still looks (persistence)
    bu: f32,        // BCM scene: where in the cycle (0..63 LSB units)
    bspeed: f32,    // LSB units a tick
    beye: [f32; 4], // how bright each LED looks
    keep: Keep,
    click_rate: Param,  // the scan / BCM clicks a second
    click_level: Param,
    at_top: u32, // ticks at full speed (scan / BCM)
}

impl Explain {
    pub fn new(_seed: u64, _hi: u64) -> Explain {
        Explain {
            tick: 0,
            scene: 0,
            t: 0,
            row: 0.0,
            speed: 0.0,
            eye: [0.0; 32],
            bu: 0.0,
            bspeed: 0.0,
            beye: [0.0; 4],
            keep: Keep::default(),
            click_rate: Param::default(),
            click_level: Param::default(),
            at_top: 0,
        }
    }

    fn sound(&mut self) {
        if self.keep.start() {
            audio::play(Clicks::new(&self.click_rate, &self.click_level));
        }
        let t = self.t;
        let seed = (self.tick as u32).wrapping_mul(2654435761);
        if t == 1 {
            audio::play(Bell::new(1046.5, 0.06, 0.6));
            audio::play(Bell::new(1568.0, 0.045, 0.6).after(0.1));
        }
        let len = SCENES[self.scene];
        let fade = (t.min(len - t) as f32 / FADE as f32).min(1.0);
        // rows lit a second (scan), bit planes switched a second (BCM: 6 a cycle of 63 units)
        // at full speed the tone holds about a second, then fades out
        let top = match self.scene {
            3 => self.speed >= 64.0,
            4 => self.bspeed >= BCM_MAX,
            _ => false,
        };
        self.at_top = if top { self.at_top + 1 } else { 0 };
        let hold = 1.0 - ((self.at_top as f32 - 60.0) / 15.0).clamp(0.0, 1.0);
        let (rate, level) = match self.scene {
            3 => (self.speed * 60.0, fade * hold),
            4 => (self.bspeed * 60.0 * 6.0 / 63.0, fade * hold),
            _ => (0.0, 0.0),
        };
        self.click_rate.set(rate);
        self.click_level.set(level);
        match self.scene {
            1 => {
                let ft = t % 300;
                if ft % 4 == 0 && ft < 48 * 4 {
                    audio::play(Tone::new(1000.0 + ft as f32 * 4.0, 0.03, 10.0).len(0.03));
                }
                if ft == 48 * 4 + 30 {
                    audio::play(Tone::new(1318.5, 0.06, 10.0).harm(0.4).len(0.08));
                    audio::play(Tone::new(1760.0, 0.06, 0.15).harm(0.4).after(0.09).len(0.3));
                }
            }
            2 => {
                let ft = t % 280;
                if ft % 4 == 0 && ft < 48 * 4 {
                    audio::play(Burst::new(seed, 3000.0, 3.0, 0.06, 0.003));
                }
                if ft == 100 + 14 {
                    audio::play(Tone::new(140.0, 0.07, 10.0).square().len(0.25));
                }
                if ft == 230 {
                    audio::play(Burst::new(seed, 1200.0, 2.0, 0.25, 0.02));
                    audio::play(Tone::new(1318.5, 0.05, 10.0).harm(0.4).after(0.1).len(0.08));
                    audio::play(Tone::new(1760.0, 0.05, 0.15).harm(0.4).after(0.19).len(0.3));
                }
            }
            6 => {
                const NOTES: [f32; 5] = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0];
                for (k, f) in NOTES.iter().enumerate() {
                    if t == 30 + k as u64 * 70 {
                        audio::play(Bell::new(*f, 0.06, 0.6));
                    }
                }
            }
            7 => {
                const NOTES: [f32; 5] = [784.0, 880.0, 1046.5, 1174.7, 1318.5];
                for (k, f) in NOTES.iter().enumerate() {
                    if t == 45 + k as u64 * 60 {
                        audio::play(Bell::new(*f, 0.06, 0.6));
                    }
                }
            }
            _ => {}
        }
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
            self.row = 0.0;
            self.eye = [0.0; 32];
            self.bu = 0.0;
            self.beye = [0.0; 4];
        }
        self.sound();
        if self.scene == 4 {
            // a cycle every 200 ticks for 6 s, then doubling every 50 ticks
            // up to two cycles a tick; each LED looks as bright as the share
            // of the tick it was on, smoothed (the eye)
            let t = self.t as f32;
            self.bspeed = if t < 360.0 { 63.0 / 200.0 } else { (63.0 / 200.0 * 2f32.powf((t - 360.0) / 50.0)).min(BCM_MAX) };
            let n = ((self.bspeed * 4.0).ceil() as usize).clamp(1, 512);
            for (k, &v) in BCM_VALUES.iter().enumerate() {
                let mut on = 0;
                for i in 0..n {
                    let u = (self.bu + self.bspeed * i as f32 / n as f32) % 63.0;
                    // MSB first: bit 5 covers 0..32, bit 4 32..48, ...
                    let mut start = 0.0;
                    for b in (0..6).rev() {
                        let len = (1 << b) as f32;
                        if u < start + len {
                            on += (v >> b & 1) as usize;
                            break;
                        }
                        start += len;
                    }
                }
                let frac = on as f32 / n as f32;
                self.beye[k] = self.beye[k] * 0.55 + frac * 0.45;
            }
            self.bu = (self.bu + self.bspeed) % 63.0;
        }
        if self.scene == 3 {
            // a row every 12 ticks for 4 s, then doubling every 55 ticks up
            // to two whole scans a tick
            let t = self.t as f32;
            self.speed = if t < 240.0 { 0.08 } else { (0.08 * 2f32.powf((t - 240.0) / 55.0)).min(64.0) };
            let a = self.row.floor() as i32;
            self.row += self.speed;
            let b = (self.row.floor() as i32).min(a + 32);
            for e in &mut self.eye {
                *e *= 0.72;
            }
            for r in a..=b {
                self.eye[r.rem_euclid(32) as usize] = 1.0;
            }
            self.row %= 32.0;
        }
    }

    fn overview(&self, buf: &mut [Col]) {
        header(buf, "しくみ解説");
        let t = self.t;
        let tk = self.tick as f32;
        // PC: a monitor showing the picture
        frame(buf, 8, 30, 32, 22, [0.6, 0.6, 0.65]);
        thumb(buf, 9, 31, 30, 20, tk * 0.004);
        fill(buf, 21, 52, 6, 3, [0.4, 0.4, 0.45]);
        fill(buf, 15, 55, 18, 2, [0.4, 0.4, 0.45]);
        // the FPGA: a chip with pins, the DDR2 beside it
        let (cx, cy) = (10, 92);
        for k in 0..6 {
            let p = 3 + k * 4;
            fill(buf, cx + p, cy - 3, 2, 3, [0.7, 0.7, 0.7]);
            fill(buf, cx + p, cy + 28, 2, 3, [0.7, 0.7, 0.7]);
            fill(buf, cx - 3, cy + p, 3, 2, [0.7, 0.7, 0.7]);
            fill(buf, cx + 28, cy + p, 3, 2, [0.7, 0.7, 0.7]);
        }
        fill(buf, cx, cy, 28, 28, [0.12, 0.12, 0.14]);
        jp::draw(buf, Font::S12, "GW3A", cx + 2, cy + 8, WHITE);
        // the panels: 2 x 3 of them
        for p in 0..6 {
            let (px, py) = (13 + (p % 2) * 11, 146 + (p / 2) * 11);
            for y in 0..10 {
                for x in 0..10 {
                    let (u, v) = (((p % 2) * 10 + x) as f32 / 20.0, ((p / 2) * 10 + y) as f32 / 30.0);
                    put(buf, px + x, py + y, pic(u, v, tk * 0.004));
                }
            }
        }
        // cables with data running down them
        for (y0, y1, sp, c) in [(58, 86, 0.6, CYAN), (124, 143, 1.5, [1.0, 0.5, 0.9])] {
            fill(buf, 23, y0, 2, y1 - y0, [0.2, 0.22, 0.3]);
            let n = y1 - y0;
            for k in 0..3 {
                let y = y0 + ((tk * sp) as i32 + k * n / 3) % n;
                fill(buf, 22, y, 4, 3, c);
            }
        }
        // labels, a stage at a time
        let lab = |buf: &mut [Col], at: u64, y: i32, a: &str, b: &str| {
            let k = smooth(at as f32, at as f32 + 20.0, t as f32);
            if k > 0.0 {
                jp::draw(buf, Font::S12, a, 48, y, [GOLD[0] * k, GOLD[1] * k, GOLD[2] * k]);
                jp::draw(buf, Font::S12, b, 48, y + 13, [WHITE[0] * k, WHITE[1] * k, WHITE[2] * k]);
            }
        };
        lab(buf, 20, 32, "PC", "絵を作る");
        lab(buf, 100, 64, "LANケーブル", "1000BASE-T");
        lab(buf, 180, 96, "FPGA", "受信して変換");
        lab(buf, 260, 122, "HUB75信号", "行ごとに送る");
        lab(buf, 340, 152, "LEDパネル", "64×64×6枚");
        line_in(buf, t, 440, Font::S12, "この画面も同じ道", 180, CYAN);
    }

    fn packets(&self, buf: &mut [Col]) {
        header(buf, "① 映像を送る");
        const CYC: u64 = 300;
        let (n, ft) = (self.t / CYC, (self.t % CYC) as i32);
        let ph = n as f32 * 0.21;
        let (lx, rx, y0) = (8, 88, 42);
        jp::draw(buf, Font::S12, "PC", lx + 10, 27, GOLD);
        jp::draw(buf, Font::S12, "FPGA", rx + 4, 27, GOLD);
        frame(buf, lx - 1, y0 - 1, 34, 50, [0.3, 0.3, 0.35]);
        frame(buf, rx - 1, y0 - 1, 34, 50, [0.3, 0.3, 0.35]);
        let row = |buf: &mut [Col], j: i32, x: i32, y: i32| {
            for i in 0..32 {
                put(buf, x + i, y, pic((i as f32 + 0.5) / 32.0, (j as f32 + 0.5) / 48.0, ph));
            }
        };
        for j in 0..48 {
            row(buf, j, lx, y0 + j);
        }
        // a packet leaves every 4 ticks and takes 30 to arrive; the old
        // frame stays on the right until its rows are replaced
        let mut flying = Vec::new();
        for j in 0..48 {
            let dep = j * 4;
            if ft >= dep + 30 {
                row(buf, j, rx, y0 + j);
            } else {
                let old = (ph - 0.21, j);
                if n > 0 {
                    for i in 0..32 {
                        put(buf, rx + i, y0 + j, pic((i as f32 + 0.5) / 32.0, (old.1 as f32 + 0.5) / 48.0, old.0));
                    }
                }
                if ft >= dep {
                    flying.push((j, (ft - dep) as f32 / 30.0));
                }
            }
        }
        for (j, p) in flying {
            let x = lx as f32 + (rx - lx) as f32 * p;
            let y = (y0 + j) as f32 - 14.0 * (PI * p).sin();
            row(buf, j, x as i32, y as i32);
            fill(buf, x as i32 + 32, y as i32 - 1, 3, 3, GOLD); // the header
        }
        // the ack flies back
        let back = 48 * 4 + 30;
        if ft >= back && ft < back + 50 {
            let p = (ft - back) as f32 / 50.0;
            let x = rx as f32 + 20.0 - 90.0 * p;
            fill(buf, x as i32, 96, 5, 5, [1.0, 0.95, 0.4]);
            jp::draw(buf, Font::S12, "DEADBEEF", x as i32 + 7, 93, [1.0, 0.95, 0.4]);
        }
        let t = self.t;
        line_in(buf, t, 30, Font::S12, "絵を1024バイトずつ", 104, WHITE);
        line_in(buf, t, 60, Font::S12, "UDPパケットで送る", 118, WHITE);
        line_in(buf, t, 240, Font::S12, "全部届いたら", 132, CYAN);
        line_in(buf, t, 260, Font::S12, "FPGAが返事をする", 146, CYAN);
        // what is in a packet
        if t >= 330 {
            let k = smooth(330.0, 350.0, t as f32);
            let sc = |c: Col| [c[0] * k, c[1] * k, c[2] * k];
            fill(buf, 4, 171, 12, 8, sc([0.2, 0.35, 0.8]));
            fill(buf, 16, 171, 12, 8, sc([0.3, 0.5, 0.95]));
            fill(buf, 28, 171, 6, 8, sc([0.45, 0.65, 1.0]));
            fill(buf, 35, 171, 8, 8, sc([1.0, 0.55, 0.1]));
            for x in 44..124 {
                fill(buf, x, 171, 1, 8, sc(hue((x - 44) as f32 / 80.0)));
            }
            jp::draw(buf, Font::S12, "位置", 33, 158, sc([1.0, 0.6, 0.2]));
            jp::draw(buf, Font::S12, "ヘッダ", 1, 180, sc([0.5, 0.7, 1.0]));
            jp::draw(buf, Font::S12, "画素データ", 56, 180, sc(WHITE));
        }
    }

    fn receive(&self, buf: &mut [Col]) {
        header(buf, "② FPGAで受ける");
        const CYC: u64 = 280;
        let (n, ft) = (self.t / CYC, (self.t % CYC) as i32);
        let blocks = [("PHY", "信号→バイト", 28), ("MAC", "CRCで検査", 50), ("UDP", "宛先で振分け", 72), ("書込", "DDR2メモリへ", 94)];
        let lane = 116;
        // packets: one every 4 ticks, 2.5 px a tick from the cable to the pages
        let mut dots = Vec::new();
        for j in 0..48 {
            let dt = ft - j * 4;
            if dt >= 0 && dt < 40 {
                dots.push((24.0 + dt as f32 * 2.5, CYAN));
            }
        }
        // a broken one, dropped by the MAC
        let bad = ft - 100;
        let mut cross = false;
        if bad >= 0 && bad < 14 {
            dots.push((24.0 + bad as f32 * 2.5, [1.0, 0.2, 0.2]));
        } else if bad >= 14 && bad < 50 {
            cross = true;
        }
        for (name, note, y) in blocks {
            let busy = dots.iter().any(|d| d.0 >= y as f32 && d.0 < (y + 18) as f32);
            let edge = if busy { [0.4, 0.8, 1.0] } else { [0.2, 0.3, 0.5] };
            fill(buf, 6, y, 106, 18, [0.04, 0.06, 0.12]);
            frame(buf, 6, y, 106, 18, edge);
            jp::draw(buf, Font::S12, name, 10, y + 3, GOLD);
            jp::draw(buf, Font::S12, note, 38, y + 3, WHITE);
        }
        fill(buf, lane + 1, 24, 1, 98, [0.15, 0.18, 0.25]);
        for (y, c) in dots {
            fill(buf, lane, y as i32, 3, 3, c);
        }
        if cross {
            for k in -3..=3 {
                put(buf, lane + 1 + k, 58 + k, [1.0, 0.2, 0.2]);
                put(buf, lane + 1 + k, 58 - k, [1.0, 0.2, 0.2]);
            }
        }
        // the two pages: one being written, the other on the panels; they
        // swap when the last packet is in
        let swap = 230;
        let writing = (n % 2) as usize;
        let front = if ft >= swap { writing } else { 1 - writing };
        let got = ((ft - 40).max(0) / 4 + 1).min(48) as f32 / 48.0;
        for pg in 0..2 {
            let x = 8 + pg as i32 * 58;
            let mine = pg == writing;
            // page `writing` holds frame n (partly), the other frame n - 1
            let ph = if mine { n as f32 } else { n as f32 - 1.0 } * 0.21;
            let rows = if mine && ft < swap { (got * 36.0) as i32 } else { 36 };
            frame(buf, x - 1, 123, 50, 38, if pg == front { GOLD } else { [0.3, 0.3, 0.4] });
            for y in 0..36 {
                for xx in 0..48 {
                    let c = if y < rows && (n > 0 || mine) { pic((xx as f32 + 0.5) / 48.0, (y as f32 + 0.5) / 36.0, ph) } else { [0.02, 0.02, 0.03] };
                    put(buf, x + xx, 124 + y, c);
                }
            }
            let (s, c) = if pg == front { ("表示中", GOLD) } else { ("書込中", DIM) };
            jp::draw(buf, Font::S12, s, x + 6, 163, c);
        }
        // the ack climbs back up
        if ft >= swap && ft < swap + 40 {
            let y = 120 - (ft - swap) * 3;
            fill(buf, 122, y, 4, 4, [1.0, 0.95, 0.4]);
        }
        let msg = if ft >= swap { "切り替えてPCに返事" } else if cross { "壊れたものは捨てる" } else { "裏の面に書き込む" };
        jp::draw_centre(buf, Font::S12, msg, 178, CYAN);
    }

    fn scan(&self, buf: &mut [Col]) {
        header(buf, "③ 行ごとに点灯");
        let (x0, y0) = (32, 30);
        let cur = self.row as usize % 32;
        let slow = self.speed < 1.0;
        frame(buf, x0 - 1, y0 - 1, 66, 66, [0.25, 0.25, 0.3]);
        for y in 0..64 {
            let e = self.eye[y % 32];
            for x in 0..64 {
                let p = pic((x as f32 + 0.5) / 64.0, (y as f32 + 0.5) / 64.0, 0.0);
                let c = [0.03 + p[0] * 1.6 * e, 0.03 + p[1] * 1.6 * e, 0.035 + p[2] * 1.6 * e];
                put(buf, x0 + x, y0 + y as i32, c);
            }
        }
        // which rows: markers at the right, the row address A..E at the left
        if slow {
            for (r, name) in [(cur, "R1"), (cur + 32, "R2")] {
                let y = y0 + r as i32;
                for k in 0..4 {
                    fill(buf, 99 + k, y - k, 1, 2 * k + 1, GOLD);
                }
                jp::draw(buf, Font::S12, name, 106, y - 6, GOLD);
            }
        }
        for b in 0..5 {
            let y = y0 + 6 + b * 12;
            jp::draw(buf, Font::S12, ["A", "B", "C", "D", "E"][b as usize], 6, y - 5, DIM);
            let on = if slow { (cur >> b & 1) as f32 } else { 0.5 };
            disc(buf, 20.0, y as f32 + 1.0, 3.5, [0.1 + 0.9 * on, 0.1 + 0.6 * on, 0.05]);
        }
        let t = self.t;
        if t < 300 {
            line_in(buf, t, 30, Font::S12, "同時に光るのは", 102, WHITE);
            line_in(buf, t, 60, Font::S12, "上下の2行だけ", 116, WHITE);
        } else if self.speed < 64.0 {
            line_in(buf, t, 300, Font::S12, "切り替えを", 102, WHITE);
            line_in(buf, t, 320, Font::S12, "速くしていくと...", 116, WHITE);
        } else {
            line_in(buf, t, 780, Font::S12, "全体が見える!", 102, GOLD);
            line_in(buf, t, 800, Font::S12, "(目の残像)", 116, WHITE);
        }
        let hz = self.speed * 60.0 / 32.0;
        if self.speed < 64.0 {
            let s = format!("{:.1} 回/秒", hz);
            jp::draw_centre(buf, Font::B16, &s, 138, CYAN);
        } else {
            line_in(buf, t, 830, Font::S12, "本物は1秒に", 134, WHITE);
            line_in(buf, t, 850, Font::B16, "488回", 148, GOLD);
        }
        jp::draw_centre(buf, Font::S12, "1/32スキャン", 176, DIM);
    }

    fn bcm(&self, buf: &mut [Col]) {
        header(buf, "④ 明るさは時間");
        let t = self.t;
        let slow = self.bspeed < 2.0;
        jp::draw_centre(buf, Font::S12, "LEDは点くか消えるか", 28, WHITE);
        // the LEDs as the eye sees them, and their values
        for (k, &v) in BCM_VALUES.iter().enumerate() {
            let x = 20.0 + k as f32 * 29.0;
            let c = BCM_COLOR;
            let e = self.beye[k];
            disc(buf, x, 56.0, 11.0, [0.04 + c[0] * e, 0.04 + c[1] * e, 0.05 + c[2] * e]);
            let s = format!("{}", v);
            jp::draw(buf, Font::S12, &s, x as i32 - jp::width(Font::S12, &s) / 2, 70, DIM);
        }
        // a time line per LED: a segment per bit (MSB first) as long as its weight
        let sx = 114.0 / 63.0;
        for (k, &v) in BCM_VALUES.iter().enumerate() {
            let y = 88 + k as i32 * 10;
            let mut a = 0.0;
            for b in (0..6).rev() {
                let len = (1 << b) as f32;
                let (x1, x2) = ((7.0 + a * sx) as i32, (7.0 + (a + len) * sx) as i32 - 1);
                let set = v >> b & 1 != 0;
                fill(buf, x1, y, (x2 - x1).max(1), 7, if set { BCM_COLOR } else { [0.08, 0.08, 0.1] });
                a += len;
            }
        }
        for b in 0..6 {
            let a = 63 - (2 << b) + 1; // where bit b starts
            let w = format!("{}", 1 << b);
            if b >= 2 {
                let x = 7.0 + (a as f32 + (1 << b) as f32 / 2.0) * sx;
                jp::draw(buf, Font::S12, &w, x as i32 - jp::width(Font::S12, &w) / 2, 128, DIM);
            }
        }
        if slow {
            fill(buf, (7.0 + self.bu * sx) as i32, 85, 1, 42, WHITE);
        }
        let hz = self.bspeed * 60.0 / 63.0;
        if self.bspeed < BCM_MAX {
            let s = format!("{:.1} 周/秒", hz);
            jp::draw_centre(buf, Font::B16, &s, 142, CYAN);
        } else {
            line_in(buf, t, 860, Font::S12, "本物は1秒に488周", 146, GOLD);
        }
        if t < 360 {
            line_in(buf, t, 40, Font::S12, "重み32:16:8:4:2:1の", 164, WHITE);
            line_in(buf, t, 60, Font::S12, "時間だけ点ける", 178, WHITE);
        } else if self.bspeed < BCM_MAX {
            line_in(buf, t, 360, Font::S12, "1周を速くすると...", 164, WHITE);
        } else {
            line_in(buf, t, 830, Font::S12, "点滅が消えて", 164, GOLD);
            line_in(buf, t, 850, Font::S12, "明るさの違いに見える", 178, GOLD);
        }
    }

    fn transpose(&self, buf: &mut [Col]) {
        header(buf, "⑤ ビットの転置");
        const PX: [u32; 8] = [45, 12, 63, 30, 7, 50, 21, 38];
        let t = self.t as f32;
        let done = smooth(330.0, 340.0, t);
        // cell (pixel i, bit column c from the MSB) moves from row i / column c
        // to row c / column i
        for i in 0..8 {
            for c in 0..6 {
                let p = smooth(0.0, 1.0, (t - 180.0 - (i + c) as f32 * 8.0) / 60.0);
                let (bx, by) = (34.0 + c as f32 * 10.0, 46.0 + i as f32 * 10.0);
                let (ax, ay) = (24.0 + i as f32 * 10.0, 56.0 + c as f32 * 10.0);
                let lift = 8.0 * (PI * p).sin();
                let (x, y) = (bx + (ax - bx) * p - lift, by + (ay - by) * p - lift);
                let set = PX[i] >> (5 - c) & 1 != 0;
                let h = hue(i as f32 / 8.0);
                let col = if set { h } else { [h[0] * 0.1, h[1] * 0.1, h[2] * 0.1] };
                fill(buf, x as i32, y as i32, 9, 9, col);
            }
        }
        let before = 1.0 - smooth(150.0, 180.0, t);
        if before > 0.0 {
            jp::draw_centre(buf, Font::S12, "画素ごとの値(6bit)", 28, [before; 3]);
            for i in 0..8 {
                let h = hue(i as f32 / 8.0);
                let k = PX[i] as f32 / 63.0 * before;
                fill(buf, 100, 46 + i as i32 * 10, 9, 9, [h[0] * k, h[1] * k, h[2] * k]);
            }
            line_in(buf, self.t, 40, Font::S12, "パネルに送るのは", 136, WHITE);
            line_in(buf, self.t, 60, Font::S12, "桁ごとのビット列", 150, WHITE);
        }
        if done > 0.0 {
            let k = |c: Col| [c[0] * done, c[1] * done, c[2] * done];
            jp::draw_centre(buf, Font::S12, "ビットごとの面", 28, k(WHITE));
            for c in 0..6 {
                let w = format!("{}", 32 >> c);
                jp::draw(buf, Font::S12, &w, 18 - jp::width(Font::S12, &w), 55 + c * 10, k(DIM));
            }
            line_in(buf, self.t, 360, Font::S12, "1面=全画素の同じ桁", 124, WHITE);
            line_in(buf, self.t, 390, Font::S12, "そのまま送り出せる", 138, WHITE);
            line_in(buf, self.t, 470, Font::S12, "GW3Aの転置ハード", 160, CYAN);
            line_in(buf, self.t, 490, Font::S12, "GMTで32×32を一気に", 174, CYAN);
        }
    }

    fn recap(&self, buf: &mut [Col]) {
        header(buf, "まとめ");
        let steps = ["①", "②", "③", "④", "⑤"];
        let texts = ["絵をUDPで送る", "受けてDDR2に保存", "2行ずつ高速に点灯", "明るさ=点ける時間", "桁ごとに並べ替え"];
        let t = self.t as f32;
        let tk = self.tick as f32;
        // the steps light up in turn, a dot running down the line between them
        fill(buf, 11, 38, 1, 128, [0.15, 0.2, 0.3]);
        let dot = (t * 0.9) % 140.0;
        if t > 30.0 {
            fill(buf, 10, 36 + dot as i32, 3, 3, CYAN);
        }
        for k in 0..5 {
            let y = 28 + k as i32 * 31;
            let at = 30.0 + k as f32 * 70.0;
            let a = smooth(at, at + 20.0, t);
            let sc = |c: Col, f: f32| [c[0] * f, c[1] * f, c[2] * f];
            let lit = 0.3 + 0.7 * a;
            fill(buf, 2, y, 19, 19, [0.0; 3]);
            jp::draw(buf, Font::B16, steps[k], 3, y - 1, sc(GOLD, lit));
            jp::draw(buf, Font::S12, texts[k], 24, y + 1, sc(WHITE, lit));
            if a <= 0.0 {
                continue;
            }
            // a small picture of the step under its text (x 24..124, y + 15..y + 27)
            let (x0, y0) = (24, y + 15);
            match k {
                0 => {
                    // packets going right, the ack coming back
                    for j in 0..4 {
                        let x = ((tk * 1.2) as i32 + j * 22) % 88;
                        fill(buf, x0 + x, y0 + 3, 8, 3, sc(hue(j as f32 * 0.25), a));
                        fill(buf, x0 + x + 8, y0 + 3, 2, 3, sc(GOLD, a));
                    }
                    let x = 96 - ((tk * 1.5) as i32 % 100);
                    fill(buf, x0 + x, y0 + 8, 3, 3, sc([1.0, 0.95, 0.4], a));
                }
                1 => {
                    // two pages, swapping every second
                    let front = (self.tick / 60) % 2;
                    let fill_k = (self.tick % 60) as i32 * 10 / 60;
                    for pg in 0..2u64 {
                        let x = x0 + 20 + pg as i32 * 34;
                        frame(buf, x, y0, 26, 12, sc(if pg == front { GOLD } else { DIM }, a));
                        let rows = if pg == front { 10 } else { fill_k };
                        for yy in 0..rows {
                            for xx in 0..24 {
                                let c = pic((xx as f32 + 0.5) / 24.0, (yy as f32 + 0.5) / 10.0, 0.0);
                                put(buf, x + 1 + xx, y0 + 1 + yy, sc(c, a));
                            }
                        }
                    }
                    fill(buf, x0 + 4, y0 + 5, 12, 2, sc(CYAN, a));
                }
                2 => {
                    // a mini panel: one row pair at a time, fast
                    frame(buf, x0 + 30, y0, 42, 12, sc([0.25, 0.25, 0.3], a));
                    let r = (self.tick as i32 / 3) % 5;
                    for rr in [r, r + 5] {
                        for xx in 0..40 {
                            let c = pic((xx as f32 + 0.5) / 40.0, (rr as f32 + 0.5) / 10.0, 0.0);
                            put(buf, x0 + 31 + xx, y0 + 1 + rr, sc([c[0] * 2.0, c[1] * 2.0, c[2] * 2.0], a));
                        }
                    }
                }
                3 => {
                    // the weighted segments and a cursor
                    let v = 45;
                    let mut u = 0;
                    for b in (0..6).rev() {
                        let len = (1 << b) * 3 / 2;
                        let c = if v >> b & 1 != 0 { [1.0, 0.3, 0.2] } else { [0.08, 0.08, 0.1] };
                        fill(buf, x0 + u, y0 + 3, (len - 1).max(1), 6, sc(c, a));
                        u += len;
                    }
                    let cx = (tk * 0.8) as i32 % u;
                    fill(buf, x0 + cx, y0 + 1, 1, 10, sc(WHITE, a));
                }
                _ => {
                    // a 4 x 2 grid of bits turning into 2 x 4, back and forth
                    let p = smooth(0.0, 1.0, ((tk * 0.02).sin() * 1.5 + 0.5).clamp(0.0, 1.0));
                    for i in 0..4 {
                        for c in 0..2 {
                            let (bx, by) = (i as f32 * 5.0, c as f32 * 5.0 + 2.0);
                            let (ax, ay) = (c as f32 * 5.0 + 5.0, i as f32 * 3.0);
                            let x = x0 as f32 + 40.0 + bx + (ax - bx) * p;
                            let yy = y0 as f32 + by + (ay - by) * p;
                            let h = hue(i as f32 / 4.0);
                            fill(buf, x as i32, yy as i32, 4, if p > 0.5 { 2 } else { 4 }, sc(h, a));
                        }
                    }
                }
            }
        }
    }

    fn specs(&self, buf: &mut [Col]) {
        header(buf, "仕様");
        let rows = [
            ("パネルの書き換え", "488回/秒"),
            ("映像の入力", "1000BASE-T"),
            ("パネル", "最大16枚"),
            ("RTL (回路)", "すべてVeryl"),
            ("FPGA", "GW3A-LV20"),
        ];
        for (k, (a, b)) in rows.iter().enumerate() {
            let at = 30 + k as u64 * 60;
            let y = 28 + k as i32 * 32;
            line_in(buf, self.t, at, Font::S12, a, y, DIM);
            line_in(buf, self.t, at + 15, Font::B16, b, y + 12, if k % 2 == 0 { GOLD } else { CYAN });
        }
    }
}

impl crate::Game for Explain {
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
            0 => self.overview(&mut buf),
            1 => self.packets(&mut buf),
            2 => self.receive(&mut buf),
            3 => self.scan(&mut buf),
            4 => self.bcm(&mut buf),
            5 => self.transpose(&mut buf),
            6 => self.recap(&mut buf),
            _ => self.specs(&mut buf),
        }
        let len = SCENES[self.scene];
        let fade = (self.t.min(len - self.t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.4);
    }
    fn status(&self) -> String {
        let names = ["overview", "packets", "receive", "scan", "bcm", "transpose", "recap", "specs"];
        format!("scene {}", names[self.scene])
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

/// a click `rate` times a second (a Param), as loud as `level`: slow, the
/// clicks are heard one by one; fast, they run together into a tone
struct Clicks {
    rate: Smooth,
    level: Smooth,
    ph: f32,
    click: f32,
    hp: Hp,
}

impl Clicks {
    fn new(rate: &Param, level: &Param) -> Clicks {
        Clicks { rate: Smooth::new(rate), level: Smooth::new(level), ph: 0.0, click: 0.0, hp: Hp::new(300.0) }
    }
}

impl Voice for Clicks {
    fn next(&mut self) -> Option<f32> {
        let rate = self.rate.next().min(4000.0);
        let level = self.level.next();
        self.ph += rate / audio::RATE;
        if self.ph >= 1.0 {
            self.ph -= self.ph.floor();
            self.click = 1.0;
        }
        self.click *= 0.95; // about 0.4 ms
        // many clicks a second add up: keep the sum about as loud
        let amp = 0.35 / (1.0 + rate / 150.0).sqrt();
        Some(self.hp.run(self.click) * amp * level)
    }
}
