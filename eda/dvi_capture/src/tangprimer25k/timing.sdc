// timing.sdc — DVI receiver smoke-test constraints.

// Board reference clock (50 MHz).
create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]

// PLL outputs are auto-detected by the Gowin tool from the gowin_pll /
// gowin_pll_27 primitives (CLKOUT0 = 162 MHz pclk, CLKOUT1 = 810 MHz fclk).
// Once the IP is regenerated for the real cable F_pixel, add explicit
// create_generated_clock entries if the auto-detection drifts.
