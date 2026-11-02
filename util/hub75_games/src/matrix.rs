// "Digital rain" on 128x192 (a demo, no game): 32 columns x 32 rows of
// 3x5 glyphs in 4x6 cells. Streams fall down the columns at their own
// speeds; the head glyph is white-green, the cells it passed glow green and
// fade. Glyphs change now and then, faster near the heads. The glyphs are
// made up at random (symmetric 3x5 bitmaps), which reads like a code
// nobody knows. Now and then a word shows up in the rain.
//
// Sound: some of the streams blip as their head comes in at the top, a note
// of a minor pentatonic scale by the column (low on the left, high on the
// right); a word arrives with a rising arpeggio of soft bells.
use crate::audio::{self, Bell, Tone};
use crate::fx::{new_buf, to_canvas, Col};
use crate::gfx::{Canvas, W};
use crate::input::Input;
use crate::Rng;

const CW: usize = 4;
const CHH: usize = 6;
const COLS: usize = W / CW; // 32
const ROWS: usize = 192 / CHH; // 32
const NGLYPH: usize = 96;
const WORDS: [&str; 4] = ["HUB75", "VERYL", "GOWIN", "UDP"];

struct Stream {
    col: usize,
    y: f32, // head row
    v: f32,
    len: f32, // trail length in rows
}

pub struct Matrix {
    rng: Rng,
    tick: u64,
    glyphs: Vec<[u8; 5]>, // rows of 3 bits
    cell: Vec<(u8, f32, bool)>, // glyph, glow, head
    streams: Vec<Stream>,
    word: Option<(usize, usize, &'static str, i32)>, // col, row, text, ticks
}

/// 3x5 glyphs for the words (A-Z subset used by WORDS, digits)
fn letter(ch: char) -> [u8; 5] {
    match ch {
        'H' => [0b101, 0b101, 0b111, 0b101, 0b101],
        'U' => [0b101, 0b101, 0b101, 0b101, 0b111],
        'B' => [0b110, 0b101, 0b110, 0b101, 0b110],
        '7' => [0b111, 0b001, 0b010, 0b010, 0b010],
        '5' => [0b111, 0b100, 0b110, 0b001, 0b110],
        'V' => [0b101, 0b101, 0b101, 0b101, 0b010],
        'E' => [0b111, 0b100, 0b110, 0b100, 0b111],
        'R' => [0b110, 0b101, 0b110, 0b101, 0b101],
        'Y' => [0b101, 0b101, 0b010, 0b010, 0b010],
        'L' => [0b100, 0b100, 0b100, 0b100, 0b111],
        'G' => [0b011, 0b100, 0b101, 0b101, 0b011],
        'O' => [0b010, 0b101, 0b101, 0b101, 0b010],
        'W' => [0b101, 0b101, 0b101, 0b111, 0b101],
        'I' => [0b111, 0b010, 0b010, 0b010, 0b111],
        'N' => [0b101, 0b111, 0b111, 0b101, 0b101],
        'D' => [0b110, 0b101, 0b101, 0b101, 0b110],
        'P' => [0b110, 0b101, 0b110, 0b100, 0b100],
        _ => [0; 5],
    }
}

impl Matrix {
    pub fn new(seed: u64, _hi: u64) -> Matrix {
        let mut rng = Rng::new(seed);
        let glyphs = (0..NGLYPH)
            .map(|_| {
                let mut g = [0u8; 5];
                loop {
                    for r in &mut g {
                        let bits = (rng.next() & 7) as u8;
                        // mirror the left column now and then: looks more like a script
                        *r = if rng.chance(0.4) { (bits & 0b110) | (bits >> 2) } else { bits };
                    }
                    let n: u32 = g.iter().map(|r| r.count_ones()).sum();
                    if (5..=11).contains(&n) {
                        break;
                    }
                }
                g
            })
            .collect();
        let cell = (0..COLS * ROWS).map(|_| ((rng.next() % NGLYPH as u64) as u8, 0.0, false)).collect();
        let mut m = Matrix { rng, tick: 0, glyphs, cell, streams: Vec::new(), word: None };
        for c in 0..COLS {
            let y = m.rng.range(-40.0, ROWS as f32);
            m.add_stream(c, y);
        }
        m
    }

    fn add_stream(&mut self, col: usize, y: f32) {
        let v = self.rng.range(0.12, 0.5);
        let len = self.rng.range(6.0, 22.0);
        self.streams.push(Stream { col, y, v, len });
    }

    fn update(&mut self) {
        self.tick += 1;
        for c in &mut self.cell {
            c.2 = false;
        }
        let mut done = Vec::new();
        for (k, s) in self.streams.iter_mut().enumerate() {
            let before = s.y as i32;
            s.y += s.v;
            if before < 0 && s.y as i32 >= 0 && self.rng.chance(0.6) {
                // A minor pentatonic from A4, two octaves over the columns
                const STEPS: [f32; 5] = [0.0, 3.0, 5.0, 7.0, 10.0];
                let k = s.col * 10 / COLS;
                let f = 440.0 * 2f32.powf((12.0 * (k / 5) as f32 + STEPS[k % 5]) / 12.0);
                audio::play(Tone::new(f, 0.08, 0.07).harm(0.6));
            }
            for r in before + 1..=s.y as i32 {
                if r >= 0 && (r as usize) < ROWS {
                    let i = r as usize * COLS + s.col;
                    self.cell[i].1 = 1.0;
                    self.cell[i].0 = (self.rng.next() % NGLYPH as u64) as u8;
                }
            }
            let r = s.y as i32;
            if r >= 0 && (r as usize) < ROWS {
                self.cell[r as usize * COLS + s.col].2 = true;
            }
            if s.y - s.len > ROWS as f32 {
                done.push(k);
            }
        }
        for &k in done.iter().rev() {
            let col = self.streams.swap_remove(k).col;
            let y = self.rng.range(-20.0, -1.0);
            self.add_stream(col, y);
        }
        // a second stream in a column now and then
        if self.rng.chance(0.02) && self.streams.len() < COLS * 2 {
            let col = (self.rng.next() % COLS as u64) as usize;
            if self.streams.iter().filter(|s| s.col == col).all(|s| s.y - s.len > 4.0) {
                self.add_stream(col, -1.0);
            }
        }
        // the glow fades by each stream's trail length and speed
        let mut fade = vec![0.93f32; COLS];
        for s in &self.streams {
            fade[s.col] = 0.05f32.powf(s.v / s.len); // 5 % left `len` rows behind the head
        }
        for (i, c) in self.cell.iter_mut().enumerate() {
            c.1 *= fade[i % COLS];
        }
        for _ in 0..12 {
            let i = (self.rng.next() % (COLS * ROWS) as u64) as usize;
            if self.cell[i].1 > 0.05 {
                self.cell[i].0 = (self.rng.next() % NGLYPH as u64) as u8;
            }
        }
        // a word, for a few seconds
        match &mut self.word {
            Some(w) => {
                w.3 -= 1;
                if w.3 <= 0 {
                    self.word = None;
                }
            }
            None if self.rng.chance(1.0 / 600.0) => {
                let s = WORDS[(self.rng.next() % WORDS.len() as u64) as usize];
                let col = (self.rng.next() % (COLS - 1) as u64) as usize;
                let row = (self.rng.next() % (ROWS - s.len()) as u64) as usize;
                self.word = Some((col, row, s, 240));
                for (i, f) in [880.0, 1046.5, 1318.5, 1760.0].iter().enumerate() {
                    audio::play(Bell::new(*f, 0.07, 0.5).after(i as f32 * 0.12));
                }
            }
            None => {}
        }
    }

    fn render(&self, buf: &mut [Col]) {
        for r in 0..ROWS {
            for c in 0..COLS {
                let (g, glow, head) = self.cell[r * COLS + c];
                let mut bits = self.glyphs[g as usize];
                let mut col: Col = if head {
                    [0.75, 1.0, 0.8]
                } else {
                    let v = glow.powf(1.3);
                    [0.1 * v, v, 0.25 * v]
                };
                if let Some((wc, wr, s, t)) = self.word {
                    if c == wc && r >= wr && r < wr + s.len() {
                        bits = letter(s.as_bytes()[r - wr] as char);
                        let k = (t.min(240 - t).min(40) as f32 / 40.0).min(1.0);
                        col = [col[0].max(0.8 * k), col[1].max(k), col[2].max(0.8 * k)];
                    }
                }
                for (gy, row) in bits.iter().enumerate() {
                    for gx in 0..3 {
                        if row & (4 >> gx) != 0 {
                            buf[(r * CHH + gy) * W + c * CW + gx] = col;
                        }
                    }
                }
            }
        }
    }
}

impl crate::Game for Matrix {
    fn step(&mut self, _inp: Option<&mut Input>) {
        self.update();
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.4);
    }
    fn status(&self) -> String {
        format!("streams {}", self.streams.len())
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
