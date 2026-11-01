// A Mandelbrot zoom on 128x192 (a demo, no game).
//
// It dives into one interesting spot after another (seahorse valley, the
// elephants, spirals, a dendrite), each for about 30 s down to a zoom of
// 1e4..1e6, then fades and starts the next. Colours come from the square
// root of the smooth iteration count (bands at every zoom) through a
// cosine palette that keeps cycling.
// The iteration limit grows with the zoom. Rows are spread over threads;
// points in the main cardioid / bulb or with a periodic orbit stop early.
use crate::fx::{new_buf, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use std::f64::consts::TAU;

const DIVE: u64 = 30 * 60; // ticks per spot
const FADE: u64 = 40;

/// (centre x, centre y, final zoom, palette phase)
const SPOTS: [(f64, f64, f64, f64); 5] = [
    (-0.743_643_887_037_151, 0.131_825_904_205_330, 2.0e6, 0.0), // seahorse valley
    (0.285_000_0, 0.011_000_0, 2.0e4, 0.3),                       // elephant valley
    (-0.775_683_77, 0.136_467_37, 1.0e6, 0.6),                    // a deep spiral
    (-0.101_096_363_845_648, 0.956_286_510_809_142, 1.0e6, 0.15), // spirals
    (-0.774_680_8, 0.137_416_9, 3.0e5, 0.45),                     // double spirals
];

pub struct Fractal {
    tick: u64,
    spot: usize,
    t: u64,
}

impl Fractal {
    pub fn new(seed: u64, _hi: u64) -> Fractal {
        Fractal { tick: 0, spot: (seed % SPOTS.len() as u64) as usize, t: 0 }
    }

    fn view(&self) -> (f64, f64, f64, u32) {
        let (cx, cy, zmax, _) = SPOTS[self.spot];
        let f = self.t as f64 / DIVE as f64;
        // zoom grows exponentially, eased at the start and end
        let e = f * f * (3.0 - 2.0 * f);
        let zoom = zmax.powf(e);
        let iters = (80.0 + 70.0 * zoom.log2()) as u32;
        (cx, cy, zoom, iters.min(1500))
    }

    fn render(&self, buf: &mut [Col]) {
        let (cx, cy, zoom, iters) = self.view();
        let scale = 3.2 / (zoom * H as f64); // the whole set fits the height at zoom 1
        let phase = SPOTS[self.spot].3 + self.tick as f64 * 0.0015;
        let threads = std::thread::available_parallelism().map_or(4, |n| n.get()).min(24);
        // thread k takes rows k, k + threads, ... (the costly rows are spread out)
        let rows: Vec<Vec<(usize, Vec<Col>)>> = std::thread::scope(|s| {
            let jobs: Vec<_> = (0..threads)
                .map(|k| {
                    s.spawn(move || {
                        (k..H)
                            .step_by(threads)
                            .map(|y| {
                                let row = (0..W)
                                    .map(|x| {
                                        let c_re = cx + (x as f64 + 0.5 - W as f64 / 2.0) * scale;
                                        let c_im = cy + (y as f64 + 0.5 - H as f64 / 2.0) * scale;
                                        pixel(c_re, c_im, iters, phase)
                                    })
                                    .collect();
                                (y, row)
                            })
                            .collect()
                    })
                })
                .collect();
            jobs.into_iter().map(|j| j.join().unwrap()).collect()
        });
        for (y, row) in rows.into_iter().flatten() {
            buf[y * W..(y + 1) * W].copy_from_slice(&row);
        }
    }
}

/// colour of the point c (black inside the set)
fn pixel(c_re: f64, c_im: f64, iters: u32, phase: f64) -> Col {
    // inside the main cardioid or the period-2 bulb: no need to iterate
    let q = (c_re - 0.25).powi(2) + c_im * c_im;
    if q * (q + (c_re - 0.25)) <= 0.25 * c_im * c_im || (c_re + 1.0).powi(2) + c_im * c_im <= 0.0625 {
        return [0.0; 3];
    }
    let (mut zr, mut zi, mut n) = (0.0f64, 0.0f64, 0u32);
    // periodicity check: an orbit that comes back to a saved point is inside
    let (mut sr, mut si, mut period) = (0.0f64, 0.0f64, 8u32);
    while n < iters && zr * zr + zi * zi < 256.0 {
        let t = zr * zr - zi * zi + c_re;
        zi = 2.0 * zr * zi + c_im;
        zr = t;
        n += 1;
        if (zr - sr).abs() < 1e-12 && (zi - si).abs() < 1e-12 {
            return [0.0; 3];
        }
        if n == period {
            (sr, si) = (zr, zi);
            period *= 2;
        }
    }
    if n >= iters {
        return [0.0; 3];
    }
    // smooth count, then a cosine palette
    let mu = n as f64 + 1.0 - ((zr * zr + zi * zi).ln() * 0.5).ln() / std::f64::consts::LN_2;
    let v = mu.sqrt() * 0.22 + phase;
    [
        (0.5 + 0.5 * (TAU * v).cos()) as f32,
        (0.45 + 0.45 * (TAU * (v + 0.12)).cos()) as f32,
        (0.5 + 0.5 * (TAU * (v + 0.3)).cos()) as f32,
    ]
}

impl crate::Game for Fractal {
    fn step(&mut self, inp: Option<&mut Input>) {
        self.tick += 1;
        let skip = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        if skip && self.t < DIVE - FADE {
            self.t = DIVE - FADE;
        }
        self.t += 1;
        if self.t >= DIVE {
            self.t = 0;
            self.spot = (self.spot + 1) % SPOTS.len();
        }
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        let fade = (self.t.min(DIVE - self.t) as f32 / FADE as f32).min(1.0);
        to_canvas(&buf, c, fade, 1.3);
    }
    fn status(&self) -> String {
        let (_, _, zoom, iters) = self.view();
        format!("spot {}  zoom {:.1e}  iters {}", self.spot, zoom, iters)
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
