// Vertical scrolling shooter (src/stg.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("stg", "arrows / WASD move, X bomb, Enter start, P pause, Q quit", hub75_games::stg::Stg::new)
}
