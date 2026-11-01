// All the demos in turn (src/showcase.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("showcase", "space / Enter next demo, Q quit", hub75_games::showcase::Showcase::new)
}
