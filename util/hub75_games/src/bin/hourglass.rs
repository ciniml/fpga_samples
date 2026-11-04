// Hourglass demo (src/hourglass.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("hourglass", "space / Enter turn it over, Q quit", hub75_games::hourglass::Hourglass::new)
}
