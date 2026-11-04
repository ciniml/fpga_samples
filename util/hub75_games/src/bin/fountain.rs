// Fountain demo (src/fountain.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("fountain", "space / Enter next scene, Q quit", hub75_games::fountain::Fountain::new)
}
