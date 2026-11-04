// Game of Life demo (src/life.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("life", "space / Enter new board, Q quit", hub75_games::life::Life::new)
}
