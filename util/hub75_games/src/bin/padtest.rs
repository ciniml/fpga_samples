// Prints what the game controller sends, as keys (a check of the controller
// and its udev permission): padtest [seconds]
use hub75_games::gamepad::Gamepad;
use std::time::{Duration, Instant};

fn main() {
    let secs: u64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(20);
    let mut g = Gamepad::new();
    println!("controller: {}", if g.connected() { g.name.as_str() } else { "not found (yet)" });
    let end = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < end {
        g.poll(|k, down| println!("{:?} {}", k, if down { "down" } else { "up" }), || {});
        std::thread::sleep(Duration::from_millis(10));
    }
}
