// Games for the HUB75 panels of eda/ethernet_hub75 (DK_LED-RXCARD): each
// runs here at 60 ticks a second, draws 128x192 (2 x 3 panels of 64x64)
// and sends it over UDP into the top-left corner of the display (256x256
// for the 16-panel build, --frame 128x192 for the 6-panel build). Keys come
// from the terminal (input.rs); --auto lets a bot play (attract mode).
pub mod aquarium;
pub mod aurora;
pub mod blocks;
pub mod bricks;
pub mod clock;
pub mod fireworks;
pub mod fountain;
pub mod fractal;
pub mod explain;
pub mod expo;
pub mod fireflies;
pub mod flame;
pub mod fx;
pub mod gfx;
pub mod hourglass;
pub mod input;
pub mod lavalamp;
pub mod invaders;
pub mod jp;
pub mod jpfont;
pub mod life;
pub mod matrix;
pub mod net;
pub mod showcase;
pub mod stg;
pub mod storm;
pub mod waterfall;

/// xorshift64 (games need no more)
pub struct Rng(pub u64);
impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(seed | 1)
    }
    pub fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    /// 0 <= f < 1
    pub fn f(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
    pub fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f()
    }
    pub fn chance(&mut self, p: f32) -> bool {
        self.f() < p
    }
}

/// play time of the timed games (blocks, bricks): 3 minutes of ticks; the
/// shooters are paced to about the same length by their stage counts
pub const TIME_LIMIT: i32 = 180 * 60;

/// ticks (60 a second) as "m:ss", rounded up
pub fn mmss(ticks: i32) -> String {
    let s = (ticks.max(0) + 59) / 60;
    format!("{}:{:02}", s / 60, s % 60)
}

use clap::Parser;
use std::io::{IsTerminal, Write};
use std::time::{Duration, Instant};

pub trait Game {
    /// one tick; `inp` is None when the bot plays
    fn step(&mut self, inp: Option<&mut input::Input>);
    fn draw(&self, c: &mut gfx::Canvas);
    /// one line for the terminal
    fn status(&self) -> String;
    fn hi(&self) -> u64;
    /// false for the demos (they run without a terminal, no --auto needed)
    fn needs_keys(&self) -> bool {
        true
    }
}

#[derive(Parser)]
pub struct Cli {
    /// board address
    #[arg(long, default_value = "192.168.10.2:10004")]
    dest: String,
    /// local address (the PC's port on the panel network)
    #[arg(long, default_value = "192.168.10.1:0")]
    bind: String,
    /// display size WxH: 256x256 (16-panel build) or 128x192 (6 panels)
    #[arg(long, default_value = "256x256")]
    frame: String,
    /// frames (and game ticks) per second
    #[arg(long, default_value_t = 60)]
    fps: u32,
    /// the bot plays (attract mode; keys other than Q are ignored)
    #[arg(long)]
    auto: bool,
    /// debug: no panel / terminal, the bot plays TICKS ticks and every
    /// EVERY-th frame goes to DIR/frameNNNNN.ppm
    #[arg(long, value_names = ["DIR"])]
    snapshots: Option<std::path::PathBuf>,
    #[arg(long, default_value_t = 3600)]
    ticks: u64,
    #[arg(long, default_value_t = 300)]
    every: u64,
}

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn snapshots<G: Game>(mut game: G, dir: &std::path::Path, ticks: u64, every: u64) -> Result<()> {
    std::fs::create_dir_all(dir)?;
    let mut canvas = gfx::Canvas::new();
    for t in 0..ticks {
        game.step(None);
        if t % every == every - 1 {
            game.draw(&mut canvas);
            let mut f = Vec::from(format!("P6\n{} {}\n255\n", gfx::W, gfx::H).as_bytes());
            canvas.px.iter().for_each(|p| f.extend_from_slice(p));
            std::fs::write(dir.join(format!("frame{:05}.ppm", t + 1)), f)?;
            println!("tick {:5}: {}", t + 1, game.status());
        }
    }
    Ok(())
}

/// runs a game: `name` for the high score file (~/.hub75_<name>_hi),
/// `make(seed, hi)` builds it, `keys` is the help line
pub fn run<G: Game>(name: &str, keys: &str, make: impl FnOnce(u64, u64) -> G) -> Result<()> {
    let cli = Cli::parse();
    if let Some(dir) = &cli.snapshots {
        return snapshots(make(12345, 0), dir, cli.ticks, cli.every);
    }
    let (fw, fh) = cli
        .frame
        .split_once('x')
        .and_then(|(a, b)| Some((a.parse::<usize>().ok()?, b.parse::<usize>().ok()?)))
        .ok_or("--frame: WxH")?;
    let mut panel = net::Panel::new(&cli.bind, &cli.dest, fw, fh)?;
    let hi_path = std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_default()
        .join(format!(".hub75_{}_hi", name));
    let hi = std::fs::read_to_string(&hi_path).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos() as u64;
    let mut game = make(seed, hi);
    let mut canvas = gfx::Canvas::new();

    // without a terminal (e.g. started in the background) only --auto works
    let mut inp = if std::io::stdin().is_terminal() {
        Some(input::Input::new()?)
    } else if cli.auto || !game.needs_keys() {
        None
    } else {
        return Err("no terminal for the keys (use --auto for the attract mode)".into());
    };
    print!(
        "hub75 {} -> {} ({}x{} frame)\r\nkeys: {}\r\n{}\r\n",
        name,
        cli.dest,
        fw,
        fh,
        keys,
        match &inp {
            Some(i) if i.releases => "key releases: reported by the terminal",
            Some(_) => "key releases: not reported (held = auto-repeat)",
            None => "no terminal: attract mode only",
        }
    );
    std::io::stdout().flush()?;

    let period = Duration::from_secs_f64(1.0 / cli.fps as f64);
    let mut next = Instant::now();
    let mut stat_t = Instant::now();
    let (mut frames, mut acks0) = (0u64, 0u64);
    loop {
        if let Some(i) = inp.as_mut() {
            i.poll()?;
            if i.take(input::Key::Quit) {
                break;
            }
        }
        match inp.as_mut() {
            Some(i) if !cli.auto => game.step(Some(i)),
            _ => game.step(None),
        }
        game.draw(&mut canvas);
        panel.send(&canvas)?;
        frames += 1;
        if stat_t.elapsed() >= Duration::from_secs(1) {
            print!("\r {}  {} fps  {} acks   ", game.status(), frames, panel.acks - acks0);
            std::io::stdout().flush()?;
            frames = 0;
            acks0 = panel.acks;
            stat_t = Instant::now();
        }
        next += period;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now;
        }
    }
    drop(inp);
    println!();
    if game.hi() > hi && !cli.auto {
        let _ = std::fs::write(&hi_path, game.hi().to_string());
    }
    Ok(())
}
