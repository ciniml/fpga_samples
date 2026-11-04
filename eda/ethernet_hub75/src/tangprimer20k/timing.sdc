// Tang Primer 20K: ethernet_hub75 timing constraints.
create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]

report_timing -setup -max_paths 50 -max_common_paths 5
