// Helpers for the demos: smooth noise, blending, and a float frame buffer
// that goes to the canvas through a gamma curve (LEDs look washed out
// with linear values).
use crate::gfx::{Canvas, H, W};

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

/// a frame of 0..1 colours (more is clipped)
pub fn to_canvas(buf: &[Col], c: &mut Canvas, gain: f32, gamma: f32) {
    for (p, b) in c.px.iter_mut().zip(buf) {
        for i in 0..3 {
            p[i] = ((b[i] * gain).clamp(0.0, 1.0).powf(gamma) * 255.0) as u8;
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
