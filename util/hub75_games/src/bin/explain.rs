// How the panels work (src/explain.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("explain", "space / Enter next scene, Q quit", hub75_games::explain::Explain::new)
}
