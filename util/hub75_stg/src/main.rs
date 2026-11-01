// hub75_stg: a vertical scrolling shooter for the HUB75 panels of
// eda/ethernet_hub75 (DK_LED-RXCARD). The game runs here at 60 ticks a
// second; every frame is drawn on 128x192 (2 x 3 panels of 64x64) and sent
// over UDP into the top-left corner of the display (256x256 for the
// 16-panel build, --frame 128x192 for the 6-panel build).
// Keys from this terminal (works over ssh / tmux), see input.rs.
mod game;
mod gfx;
mod input;
mod net;

use clap::Parser;
use std::io::{IsTerminal, Write};
use std::time::{Duration, Instant};

#[derive(Parser)]
struct Cli {
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
    /// 300th frame goes to DIR/frameNNNNN.ppm
    #[arg(long, value_names = ["DIR"])]
    snapshots: Option<std::path::PathBuf>,
    #[arg(long, default_value_t = 3600)]
    ticks: u64,
}

fn ctl_from(inp: &mut input::Input) -> game::Ctl {
    use input::Key;
    let axis = |a: Key, b: Key| inp.held(b) as i32 as f32 - inp.held(a) as i32 as f32;
    let (dx, dy) = (axis(Key::Left, Key::Right), axis(Key::Up, Key::Down));
    game::Ctl {
        dx,
        dy,
        bomb: inp.take(Key::Bomb),
        start: inp.take(Key::Start) | inp.take(Key::Shot),
        pause: inp.take(Key::Pause),
    }
}

fn snapshots(dir: &std::path::Path, ticks: u64) -> anyhow_free::Result<()> {
    std::fs::create_dir_all(dir)?;
    let mut game = game::Game::new(12345, 0);
    let mut canvas = gfx::Canvas::new();
    for t in 0..ticks {
        let ctl = game.bot();
        game.update(&ctl);
        if t % 300 == 299 {
            game.draw(&mut canvas);
            let mut f = Vec::from(format!("P6\n{} {}\n255\n", gfx::W, gfx::H).as_bytes());
            canvas.px.iter().for_each(|p| f.extend_from_slice(p));
            std::fs::write(dir.join(format!("frame{:05}.ppm", t + 1)), f)?;
            println!("tick {:5}: stage {} score {:7}", t + 1, game.stage, game.score);
        }
    }
    Ok(())
}

fn hi_path() -> std::path::PathBuf {
    std::env::var_os("HOME").map(std::path::PathBuf::from).unwrap_or_default().join(".hub75_stg_hi")
}

fn main() -> anyhow_free::Result<()> {
    let cli = Cli::parse();
    if let Some(dir) = &cli.snapshots {
        return snapshots(dir, cli.ticks);
    }
    let (fw, fh) = cli
        .frame
        .split_once('x')
        .and_then(|(a, b)| Some((a.parse::<usize>().ok()?, b.parse::<usize>().ok()?)))
        .ok_or("--frame: WxH")?;
    let mut panel = net::Panel::new(&cli.bind, &cli.dest, fw, fh)?;
    let hi = std::fs::read_to_string(hi_path()).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos() as u64;
    let mut game = game::Game::new(seed, hi);
    let mut canvas = gfx::Canvas::new();

    // without a terminal (e.g. started in the background) only --auto works
    let mut inp = if std::io::stdin().is_terminal() {
        Some(input::Input::new()?)
    } else if cli.auto {
        None
    } else {
        return Err("no terminal for the keys (use --auto for the attract mode)".into());
    };
    print!(
        "hub75_stg -> {} ({}x{} frame)\r\nkeys: arrows / WASD move, X bomb, Enter start, P pause, Q quit\r\n{}\r\n",
        cli.dest,
        fw,
        fh,
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
        let ctl = match inp.as_mut() {
            Some(i) if !cli.auto => ctl_from(i),
            _ => game.bot(),
        };
        game.update(&ctl);
        game.draw(&mut canvas);
        panel.send(&canvas)?;
        frames += 1;
        if stat_t.elapsed() >= Duration::from_secs(1) {
            print!(
                "\r stage {}  score {:07}  {} fps  {} acks   ",
                game.stage,
                game.score,
                frames,
                panel.acks - acks0
            );
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
    if game.hi > hi && !cli.auto {
        let _ = std::fs::write(hi_path(), game.hi.to_string());
    }
    Ok(())
}

mod anyhow_free {
    pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
}
