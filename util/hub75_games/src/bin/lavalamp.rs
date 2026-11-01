// Lava lamp demo (src/lavalamp.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("lavalamp", "Q quit", hub75_games::lavalamp::LavaLamp::new)
}
