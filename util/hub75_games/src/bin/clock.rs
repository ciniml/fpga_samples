// Clock demo (src/clock.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("clock", "space / Enter next face, Q quit", hub75_games::clock::Clock::new)
}
