// Invaders-style shooter (src/invaders.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run(
        "invaders",
        "left / right (A / D) move, space / Z / up fire, Enter start, P pause, Q quit",
        hub75_games::invaders::Invaders::new,
    )
}
