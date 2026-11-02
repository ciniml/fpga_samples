// The booth's arcade: the demos until a controller button, then the games (src/arcade.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("arcade", "controller: any button = menu, Q quit", hub75_games::arcade::Arcade::new)
}
