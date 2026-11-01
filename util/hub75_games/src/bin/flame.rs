// Flame demo (src/flame.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("flame", "space / Enter next scene, Q quit", hub75_games::flame::Flame::new)
}
