// Japanese (and ASCII) text from the glyphs in jpfont.rs (made by
// tools/gen_jpfont.py; only the characters listed there exist, others are
// skipped). `pixels` gives the lit pixels so a demo can paint them as it
// likes (gradients, glows); `draw` paints them in one colour.
use crate::fx::Col;
use crate::gfx::{H, W};
use crate::jpfont::{Glyph, B16, B16_H, B24, B24_H, S12, S12_H};

#[derive(Clone, Copy)]
pub enum Font {
    S12, // IPAGothic 12 px
    B16, // Noto Sans CJK JP Bold 16 px
    B24, // Noto Sans CJK JP Bold 24 px
}

fn table(f: Font) -> (&'static [Glyph], i32) {
    match f {
        Font::S12 => (S12, S12_H),
        Font::B16 => (B16, B16_H),
        Font::B24 => (B24, B24_H),
    }
}

fn glyph(t: &'static [Glyph], ch: char) -> Option<&'static Glyph> {
    t.binary_search_by(|g| g.ch.cmp(&ch)).ok().map(|i| &t[i])
}

pub fn height(f: Font) -> i32 {
    table(f).1
}

pub fn width(f: Font, s: &str) -> i32 {
    let (t, _) = table(f);
    s.chars().filter_map(|c| glyph(t, c)).map(|g| g.adv as i32).sum()
}

/// the lit pixels of s with its top left corner at (x, y)
pub fn pixels(f: Font, s: &str, x: i32, y: i32) -> Vec<(i32, i32)> {
    let (t, _) = table(f);
    let mut v = Vec::new();
    let mut x0 = x;
    for c in s.chars() {
        if let Some(g) = glyph(t, c) {
            for (ry, row) in g.rows.iter().enumerate() {
                for rx in 0..g.w as i32 {
                    if row >> (g.w as i32 - 1 - rx) & 1 != 0 {
                        v.push((x0 + rx, y + ry as i32));
                    }
                }
            }
            x0 += g.adv as i32;
        }
    }
    v
}

/// x that centres s on the screen
pub fn centre_x(f: Font, s: &str) -> i32 {
    (W as i32 - width(f, s)) / 2
}

pub fn draw(buf: &mut [Col], f: Font, s: &str, x: i32, y: i32, col: Col) {
    for (px, py) in pixels(f, s, x, y) {
        if px >= 0 && py >= 0 && (px as usize) < W && (py as usize) < H {
            buf[py as usize * W + px as usize] = col;
        }
    }
}

pub fn draw_centre(buf: &mut [Col], f: Font, s: &str, y: i32, col: Col) {
    draw(buf, f, s, centre_x(f, s), y, col);
}
