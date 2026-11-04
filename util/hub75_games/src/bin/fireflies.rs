// Fireflies demo (src/fireflies.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("fireflies", "Q quit", hub75_games::fireflies::Fireflies::new)
}
