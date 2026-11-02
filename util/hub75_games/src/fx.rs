// Helpers for the demos: smooth noise, blending, and a float frame buffer
// that goes to the canvas through a gamma curve (LEDs look washed out
// with linear values). Most of the curve is the board's colour table
// (--board-gamma, 8-bit steps there instead of RGB565's 5 bits here); a
// demo asks for its overall gamma and gamma() leaves the rest.
use crate::gfx::{Canvas, H, W};
use std::sync::atomic::{AtomicU32, Ordering};

static BOARD_GAMMA: AtomicU32 = AtomicU32::new(0x3f80_0000); // 1.0

pub fn set_board_gamma(g: f32) {
    BOARD_GAMMA.store(g.to_bits(), Ordering::Relaxed);
}

pub fn board_gamma() -> f32 {
    f32::from_bits(BOARD_GAMMA.load(Ordering::Relaxed))
}

/// the exponent to apply here for an overall gamma g (the board does the rest)
pub fn gamma(g: f32) -> f32 {
    g / board_gamma()
}

pub type Col = [f32; 3];

/// smooth value noise, -1..1
pub fn noise(x: f32, seed: u32) -> f32 {
    let h = |i: i32| {
        let mut v = (i as u32).wrapping_mul(0x9e37_79b9) ^ seed.wrapping_mul(0x85eb_ca6b);
        v ^= v >> 15;
        v = v.wrapping_mul(0x2c1b_3c6d);
        v ^= v >> 12;
        (v & 0xffff) as f32 / 32767.5 - 1.0
    };
    let i = x.floor();
    let f = x - i;
    let f = f * f * (3.0 - 2.0 * f);
    h(i as i32) * (1.0 - f) + h(i as i32 + 1) * f
}

/// smooth 2-D value noise, -1..1, wrapping every `wx` cells in x
pub fn noise2(x: f32, y: f32, wx: i32, seed: u32) -> f32 {
    let (xi, yi) = (x.floor(), y.floor());
    let (fx, fy) = (x - xi, y - yi);
    let (fx, fy) = (fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy));
    let (xi, yi) = (xi as i32, yi as i32);
    let at = |i: i32, j: i32| noise((j * 1013 + i.rem_euclid(wx)) as f32, seed);
    let a = at(xi, yi) * (1.0 - fx) + at(xi + 1, yi) * fx;
    let b = at(xi, yi + 1) * (1.0 - fx) + at(xi + 1, yi + 1) * fx;
    a * (1.0 - fy) + b * fy
}

pub fn smooth(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

pub fn mix(a: Col, b: Col, t: f32) -> Col {
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

/// a frame of 0..1 colours (more is clipped), overall gamma g
pub fn to_canvas(buf: &[Col], c: &mut Canvas, gain: f32, g: f32) {
    let e = gamma(g);
    for (p, b) in c.px.iter_mut().zip(buf) {
        for i in 0..3 {
            p[i] = ((b[i] * gain).clamp(0.0, 1.0).powf(e) * 255.0) as u8;
        }
    }
}

pub fn new_buf() -> Vec<Col> {
    vec![[0.0; 3]; W * H]
}

/// adds col at (x, y) if it is on the screen
pub fn add(buf: &mut [Col], x: i32, y: i32, col: Col) {
    if x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H {
        let p = &mut buf[y as usize * W + x as usize];
        for i in 0..3 {
            p[i] += col[i];
        }
    }
}

/// distance from (px, py) to the segment a-b
pub fn seg_dist(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let (vx, vy) = (bx - ax, by - ay);
    let l2 = vx * vx + vy * vy;
    let u = if l2 > 0.0 { (((px - ax) * vx + (py - ay) * vy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    let (dx, dy) = (ax + vx * u - px, ay + vy * u - py);
    (dx * dx + dy * dy).sqrt()
}

/// a thick anti-aliased line blended over the buffer
pub fn line(buf: &mut [Col], ax: f32, ay: f32, bx: f32, by: f32, width: f32, col: Col) {
    let r = width / 2.0 + 1.0;
    let (x0, x1) = ((ax.min(bx) - r).floor() as i32, (ax.max(bx) + r).ceil() as i32);
    let (y0, y1) = ((ay.min(by) - r).floor() as i32, (ay.max(by) + r).ceil() as i32);
    for y in y0.max(0)..=y1.min(H as i32 - 1) {
        for x in x0.max(0)..=x1.min(W as i32 - 1) {
            let d = seg_dist(x as f32 + 0.5, y as f32 + 0.5, ax, ay, bx, by);
            let a = (width / 2.0 + 0.5 - d).clamp(0.0, 1.0);
            if a > 0.0 {
                let p = &mut buf[y as usize * W + x as usize];
                *p = mix(*p, col, a);
            }
        }
    }
}

/// a soft halo around a mask: two box blurs
pub fn blur(mask: &[f32], r: i32) -> Vec<f32> {
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
