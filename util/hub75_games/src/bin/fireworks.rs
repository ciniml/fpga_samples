// Fireworks demo (src/fireworks.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("fireworks", "space / Enter finale, Q quit", hub75_games::fireworks::Fireworks::new)
}
