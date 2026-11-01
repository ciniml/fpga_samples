// Thunderstorm demo (src/storm.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("storm", "space / Enter lightning now, Q quit", hub75_games::storm::Storm::new)
}
