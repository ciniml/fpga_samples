// An hourglass with coloured sand on 128x192 (a demo, no game).
//
// The sand is a grid of grains: each tick, from the bottom row up, a grain
// falls if the cell below is free (two cells while it falls freely), else
// it slides down-left or down-right; that gives the stream through the
// neck and the cone that piles up below. The sand starts in coloured
// layers, so the cone shows them stacked the other way round. When the top
// bulb is empty and the sand has settled, the hourglass turns over (the
// whole picture rotates, shrinking a little so the corners fit) and runs
// again. The glass is symmetric under a half turn, so after the turn the
// grid is simply rotated by 180 degrees. Space / Enter: turn it now.
use crate::fx::{new_buf, noise, noise2, smooth, to_canvas, Col};
use crate::gfx::{Canvas, H, W};
use crate::input::{Input, Key};
use crate::Rng;
use std::f32::consts::PI;

const CX: f32 = 64.0; // centre (the grid is turned about it)
const CY: f32 = 96.0;
const HALF: f32 = 78.0; // glass: neck to end
const BULB: f32 = 30.0; // widest half width
const NECK: f32 = 1.0; // half width of the neck (2 px)
const FILL: f32 = 0.62; // of the top bulb
const TURN: u32 = 110; // ticks
const LAYERS: [Col; 6] = [
    [0.95, 0.25, 0.2],
    [1.0, 0.55, 0.1],
    [0.95, 0.85, 0.2],
    [0.25, 0.85, 0.3],
    [0.15, 0.6, 1.0],
    [0.65, 0.3, 0.95],
];

/// half width of the inside of the glass at row y (0 outside)
fn half_width(y: f32) -> f32 {
    let d = (y + 0.5 - CY).abs() / HALF; // 0 neck .. 1 end
    if d >= 1.0 {
        return 0.0;
    }
    let rise = (d / 0.6).min(1.0);
    let mut w = NECK + (BULB - NECK) * (rise * PI / 2.0).sin().powf(1.6);
    if d > 0.82 {
        let e = (d - 0.82) / 0.18;
        w *= (1.0 - e * e).max(0.0).sqrt();
    }
    w
}

fn inside(x: i32, y: i32) -> bool {
    x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H && ((x as f32 + 0.5 - CX).abs() < half_width(y as f32))
}

#[derive(PartialEq)]
enum State {
    Run,
    Wait(u32),
    Turn(u32),
}

pub struct Hourglass {
    rng: Rng,
    tick: u64,
    grid: Vec<u8>, // 0 empty, else 1 + layer * 4 + shade
    mask: Vec<bool>,
    state: State,
    still: u32, // ticks without a move
    turns: u32,
}

impl Hourglass {
    pub fn new(seed: u64, _hi: u64) -> Hourglass {
        let mut rng = Rng::new(seed);
        let mask: Vec<bool> = (0..W * H).map(|i| inside((i % W) as i32, (i / W) as i32)).collect();
        // fill the top bulb from the neck up, in layers
        let top: Vec<usize> = (0..W * H).filter(|&i| mask[i] && ((i / W) as f32) < CY - 1.0).collect();
        let total = top.len();
        let mut grid = vec![0u8; W * H];
        let n = (total as f32 * FILL) as usize;
        let mut rows: Vec<usize> = top.clone();
        rows.sort_by_key(|&i| std::cmp::Reverse(i / W)); // the lowest rows first
        for (k, &i) in rows.iter().take(n).enumerate() {
            let layer = (k * LAYERS.len() / n).min(LAYERS.len() - 1);
            grid[i] = 1 + (layer * 4) as u8 + (rng.next() % 4) as u8;
        }
        Hourglass { rng, tick: 0, grid, mask, state: State::Run, still: 0, turns: 0 }
    }

    fn free(&self, x: i32, y: i32) -> bool {
        x >= 0 && y >= 0 && (x as usize) < W && (y as usize) < H && self.mask[y as usize * W + x as usize] && self.grid[y as usize * W + x as usize] == 0
    }

    /// one step of the sand; the number of grains that moved
    fn settle(&mut self) -> u32 {
        let mut moved = 0;
        for y in (0..H as i32 - 1).rev() {
            let flip = self.rng.chance(0.5);
            for k in 0..W as i32 {
                let x = if flip { W as i32 - 1 - k } else { k };
                let i = y as usize * W + x as usize;
                let g = self.grid[i];
                if g == 0 {
                    continue;
                }
                let to = if self.free(x, y + 1) {
                    if self.free(x, y + 2) && self.rng.chance(0.8) {
                        Some((x, y + 2))
                    } else {
                        Some((x, y + 1))
                    }
                } else {
                    let (a, b) = if self.rng.chance(0.5) { (-1, 1) } else { (1, -1) };
                    if self.free(x + a, y + 1) {
                        Some((x + a, y + 1))
                    } else if self.free(x + b, y + 1) {
                        Some((x + b, y + 1))
                    } else {
                        None
                    }
                };
                if let Some((nx, ny)) = to {
                    self.grid[i] = 0;
                    self.grid[ny as usize * W + nx as usize] = g;
                    moved += 1;
                }
            }
        }
        moved
    }

    fn top_grains(&self) -> usize {
        self.grid[..(CY as usize - 1) * W].iter().filter(|&&g| g != 0).count()
    }

    fn update(&mut self, now: bool) {
        self.tick += 1;
        match self.state {
            State::Run => {
                let m = self.settle();
                self.still = if m == 0 { self.still + 1 } else { 0 };
                if now || (self.still > 30 && self.top_grains() == 0) {
                    self.state = State::Wait(if now { 0 } else { 90 });
                }
            }
            State::Wait(n) => {
                self.state = if n == 0 { State::Turn(0) } else { State::Wait(n - 1) };
            }
            State::Turn(n) => {
                if n + 1 >= TURN {
                    self.grid.reverse(); // the half turn
                    self.turns += 1;
                    self.still = 0;
                    self.state = State::Run;
                } else {
                    self.state = State::Turn(n + 1);
                }
            }
        }
    }

    /// the hourglass itself (frame, glass, sand); None where it is not
    fn object(&self) -> Vec<Option<Col>> {
        let mut o: Vec<Option<Col>> = vec![None; W * H];
        let top = (CY - HALF - 1.0) as i32;
        let bot = (CY + HALF + 1.0) as i32;
        let wood = |x: f32, y: f32| -> Col {
            let g = 0.5 + 0.5 * noise(x * 0.35 + 3.0 * noise(y * 0.15, 61), 62);
            [0.32 + 0.12 * g, 0.16 + 0.07 * g, 0.06 + 0.03 * g]
        };
        // plates top and bottom (symmetric under the half turn)
        for (y0, y1) in [(top - 8, top), (bot, bot + 8)] {
            for y in y0..y1 {
                let inset = if y == y0 || y == y1 - 1 { 2 } else { 0 };
                for x in 22 + inset..106 - inset {
                    let mut c = wood(x as f32, y as f32);
                    let edge = if y < (y0 + y1) / 2 { 1.25 } else { 0.8 };
                    for v in &mut c {
                        *v *= edge;
                    }
                    o[y as usize * W + x as usize] = Some(c);
                }
            }
        }
        // two turned pillars
        for y in top..bot {
            for px in [26, 98] {
                let fy = y as f32;
                let bulge = 2.2 + 0.8 * (fy * 0.25).sin().abs();
                for x in px - 3..px + 4 {
                    let dx = (x as f32 + 0.5 - (px as f32 + 0.5)) / bulge;
                    if dx.abs() < 1.0 {
                        let shade = (1.0 - dx * dx).sqrt() * 0.8 + 0.3 - 0.2 * dx;
                        let c = wood(x as f32, fy);
                        o[y as usize * W + x as usize] = Some([c[0] * shade, c[1] * shade, c[2] * shade]);
                    }
                }
            }
        }
        // glass: faint inside, a bright rim, highlights; then the sand
        for y in top..bot {
            let fy = y as f32;
            let w = half_width(fy);
            for x in 0..W as i32 {
                let dx = x as f32 + 0.5 - CX;
                let i = y as usize * W + x as usize;
                let g = self.grid[i];
                if g != 0 {
                    let layer = ((g - 1) / 4) as usize;
                    let shade = 0.8 + 0.07 * ((g - 1) % 4) as f32;
                    let c = LAYERS[layer];
                    o[i] = Some([c[0] * shade, c[1] * shade, c[2] * shade]);
                } else if dx.abs() < w {
                    let hl = smooth(0.0, 1.0, 1.0 - ((dx / w.max(1.0)) + 0.55).abs() * 4.0) * 0.12;
                    o[i] = Some([0.03 + hl, 0.045 + hl, 0.06 + hl * 1.2]);
                } else if dx.abs() < w + 1.2 && w > 0.0 {
                    o[i] = Some([0.25, 0.32, 0.38]);
                }
            }
        }
        o
    }

    fn render(&self, buf: &mut [Col]) {
        // background: a dark wall with a soft light behind the glass
        for y in 0..H {
            for x in 0..W {
                let (dx, dy) = ((x as f32 - CX) / 70.0, (y as f32 - CY) / 110.0);
                let l = 0.06 / (1.0 + 3.0 * (dx * dx + dy * dy));
                let n = 0.004 * noise2(x as f32 * 0.2, y as f32 * 0.2, 999, 63);
                buf[y * W + x] = [0.015 + l * 0.6 + n, 0.012 + l * 0.5 + n, 0.03 + l + n];
            }
        }
        let obj = self.object();
        let (ang, scale) = match self.state {
            State::Turn(n) => {
                let f = n as f32 / TURN as f32;
                let e = f * f * (3.0 - 2.0 * f);
                (e * PI, 1.0 - 0.28 * (e * PI).sin())
            }
            _ => (0.0, 1.0),
        };
        let (s, c) = ang.sin_cos();
        for y in 0..H {
            for x in 0..W {
                // where this pixel was before the turn
                let (px, py) = ((x as f32 + 0.5 - CX) / scale, (y as f32 + 0.5 - CY) / scale);
                let (ox, oy) = (px * c + py * s + CX, -px * s + py * c + CY);
                let (ix, iy) = (ox.floor() as i32, oy.floor() as i32);
                if ix >= 0 && iy >= 0 && (ix as usize) < W && (iy as usize) < H {
                    if let Some(col) = obj[iy as usize * W + ix as usize] {
                        buf[y * W + x] = col;
                    }
                }
            }
        }
    }
}

impl crate::Game for Hourglass {
    fn step(&mut self, inp: Option<&mut Input>) {
        let now = match inp {
            Some(i) => i.take(Key::Space) | i.take(Key::Start),
            None => false,
        };
        self.update(now && self.state == State::Run);
    }
    fn draw(&self, c: &mut Canvas) {
        let mut buf = new_buf();
        self.render(&mut buf);
        to_canvas(&buf, c, 1.0, 1.5);
    }
    fn status(&self) -> String {
        format!("turns {}  top {}", self.turns, self.top_grains())
    }
    fn hi(&self) -> u64 {
        0
    }
    fn needs_keys(&self) -> bool {
        false
    }
}
