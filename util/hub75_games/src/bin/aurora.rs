// Aurora demo (src/aurora.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("aurora", "Q quit", hub75_games::aurora::Aurora::new)
}
