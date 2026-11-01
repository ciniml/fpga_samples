// Drawing on the 128x192 screen: RGB canvas, 5x7 font, ASCII-art sprites.

pub const W: usize = 128;
pub const H: usize = 192;

pub type Rgb = [u8; 3];

pub struct Canvas {
    pub px: Vec<Rgb>,
}

impl Canvas {
    pub fn new() -> Self {
        Canvas { px: vec![[0; 3]; W * H] }
    }

    pub fn clear(&mut self, c: Rgb) {
        self.px.fill(c);
    }

    pub fn pset(&mut self, x: i32, y: i32, c: Rgb) {
        if x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
            self.px[y as usize * W + x as usize] = c;
        }
    }

    /// adds c (saturating), for glows and flashes
    pub fn padd(&mut self, x: i32, y: i32, c: Rgb) {
        if x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
            let p = &mut self.px[y as usize * W + x as usize];
            for i in 0..3 {
                p[i] = p[i].saturating_add(c[i]);
            }
        }
    }

    pub fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, c: Rgb) {
        for yy in y..y + h {
            for xx in x..x + w {
                self.pset(xx, yy, c);
            }
        }
    }

    pub fn disc(&mut self, cx: f32, cy: f32, r: f32, c: Rgb) {
        let r2 = r * r;
        let (x0, x1) = ((cx - r).floor() as i32, (cx + r).ceil() as i32);
        let (y0, y1) = ((cy - r).floor() as i32, (cy + r).ceil() as i32);
        for y in y0..=y1 {
            for x in x0..=x1 {
                let (dx, dy) = (x as f32 + 0.5 - cx, y as f32 + 0.5 - cy);
                if dx * dx + dy * dy <= r2 {
                    self.pset(x, y, c);
                }
            }
        }
    }

    /// sprite centred on (cx, cy); tint replaces every colour (hit flash)
    pub fn sprite(&mut self, s: &Sprite, cx: f32, cy: f32, tint: Option<Rgb>) {
        let x0 = cx.round() as i32 - s.w as i32 / 2;
        let y0 = cy.round() as i32 - s.h as i32 / 2;
        for y in 0..s.h {
            for x in 0..s.w {
                if let Some(c) = s.px[y * s.w + x] {
                    self.pset(x0 + x as i32, y0 + y as i32, tint.unwrap_or(c));
                }
            }
        }
    }

    pub fn text(&mut self, s: &str, x: i32, y: i32, scale: i32, c: Rgb) {
        let mut x0 = x;
        for ch in s.chars() {
            let g = glyph(ch);
            for (ry, row) in g.iter().enumerate() {
                for rx in 0..5 {
                    if row & (0x10 >> rx) != 0 {
                        self.rect(x0 + rx * scale, y + ry as i32 * scale, scale, scale, c);
                    }
                }
            }
            x0 += 6 * scale;
        }
    }

    pub fn text_centre(&mut self, s: &str, y: i32, scale: i32, c: Rgb) {
        let w = s.chars().count() as i32 * 6 * scale - scale;
        self.text(s, (W as i32 - w) / 2, y, scale, c);
    }
}

pub fn scale(c: Rgb, k: f32) -> Rgb {
    let f = |v: u8| (v as f32 * k).clamp(0.0, 255.0) as u8;
    [f(c[0]), f(c[1]), f(c[2])]
}

pub struct Sprite {
    pub w: usize,
    pub h: usize,
    px: Vec<Option<Rgb>>,
}

fn palette(ch: char) -> Option<Rgb> {
    Some(match ch {
        'W' => [230, 230, 255],
        'C' => [0, 220, 255],
        'B' => [40, 90, 255],
        'R' => [255, 40, 40],
        'D' => [140, 0, 20],
        'O' => [255, 130, 0],
        'Y' => [255, 230, 0],
        'G' => [40, 230, 60],
        'g' => [0, 120, 40],
        'M' => [255, 40, 200],
        'P' => [150, 60, 255],
        'K' => [120, 120, 140],
        'k' => [60, 60, 80],
        _ => return None,
    })
}

impl Sprite {
    pub fn parse(rows: &[&str]) -> Sprite {
        let w = rows[0].len();
        let px = rows.iter().flat_map(|r| r.chars().map(palette)).collect();
        Sprite { w, h: rows.len(), px }
    }
}

fn glyph(ch: char) -> [u8; 7] {
    match ch.to_ascii_uppercase() {
        '0' => [0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e],
        '1' => [0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e],
        '2' => [0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f],
        '3' => [0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e],
        '4' => [0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02],
        '5' => [0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e],
        '6' => [0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e],
        '7' => [0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        '8' => [0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e],
        '9' => [0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c],
        'A' => [0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11],
        'B' => [0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e],
        'C' => [0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e],
        'D' => [0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e],
        'E' => [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f],
        'F' => [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10],
        'G' => [0x0e, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0f],
        'H' => [0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11],
        'I' => [0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e],
        'J' => [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0c],
        'K' => [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f],
        'M' => [0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11],
        'N' => [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
        'O' => [0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e],
        'P' => [0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10],
        'Q' => [0x0e, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0d],
        'R' => [0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11],
        'S' => [0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e],
        'T' => [0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        'U' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e],
        'V' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04],
        'W' => [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0a],
        'X' => [0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11],
        'Y' => [0x11, 0x11, 0x0a, 0x04, 0x04, 0x04, 0x04],
        'Z' => [0x1f, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1f],
        '.' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x0c],
        '-' => [0x00, 0x00, 0x00, 0x1f, 0x00, 0x00, 0x00],
        '!' => [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
        ':' => [0x00, 0x0c, 0x0c, 0x00, 0x0c, 0x0c, 0x00],
        '/' => [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10],
        _ => [0; 7],
    }
}
