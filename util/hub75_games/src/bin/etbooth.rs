// The EdgeTech+ 2026 booth guide (src/etbooth.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("etbooth", "space / Enter next page, Q quit", hub75_games::etbooth::EtBooth::new)
}
