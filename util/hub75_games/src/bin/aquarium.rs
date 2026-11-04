// Fish tank demo (src/aquarium.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("aquarium", "Q quit", hub75_games::aquarium::Aquarium::new)
}
