// Mandelbrot zoom demo (src/fractal.rs).
fn main() -> hub75_games::Result<()> {
    hub75_games::run("fractal", "space / Enter next spot, Q quit", hub75_games::fractal::Fractal::new)
}
