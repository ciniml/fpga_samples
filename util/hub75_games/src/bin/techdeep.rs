// The technical explanation for EdgeTech+ (src/techdeep.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("techdeep", "space / Enter next slide, Q quit", hub75_games::techdeep::TechDeep::new)
}
