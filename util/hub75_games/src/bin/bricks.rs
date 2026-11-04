// Brick breaker (src/bricks.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run(
        "bricks",
        "left / right (A / D) move, space / up launch, Enter start, P pause, Q quit",
        hub75_games::bricks::Bricks::new,
    )
}
