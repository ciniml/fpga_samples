// Falling-block puzzle (src/blocks.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run(
        "blocks",
        "left / right move, down soft drop, space hard drop, up / X rotate, Z rotate back, C hold, Enter start, P pause, Q quit",
        hub75_games::blocks::Blocks::new,
    )
}
