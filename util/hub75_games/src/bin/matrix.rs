// Digital rain demo (src/matrix.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("matrix", "Q quit", hub75_games::matrix::Matrix::new)
}
