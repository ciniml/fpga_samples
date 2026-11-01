// Waterfall demo (src/waterfall.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("waterfall", "Q quit", hub75_games::waterfall::Waterfall::new)
}
