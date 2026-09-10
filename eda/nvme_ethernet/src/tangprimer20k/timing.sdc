// Tang Primer 20K: everything but the PHY reset sequencer runs on the
// 50MHz RMII reference clock; the 27MHz crystal only clocks that sequencer.
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
create_clock -name clock      -period 37.037 -waveform {0 18.518} [get_ports {clock}]
set_clock_groups -asynchronous -group [get_clocks {rmii_txclk}] -group [get_clocks {clock}]
