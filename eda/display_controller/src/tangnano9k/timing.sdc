// timing.sdc
// Copyright 2025 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


create_clock -name clock -period 37.037 -waveform {0 18.518} [get_ports {clock}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/SET}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/D}]
set_false_path -from [get_pins {reset_seq_dvi/reset_seq_0_s0/Q}] -to [get_pins {oser_dvi_*/RESET}]

create_clock -name spi_sck -period 12.5 -waveform {0 6.25} [get_ports {spi_sck}]
create_generated_clock -name clock_dvi -source [get_ports {clock}] -divide_by 20 -multiply_by 55  [get_nets {clock_dvi}]

set_clock_groups -asynchronous -group [get_clocks {spi_sck}]
set_input_delay  -clock spi_sck -max 0.5 -min 0.2  [get_ports {spi_mosi}]
set_input_delay  -clock spi_sck -max 0.5 -min 0.2  [get_ports {spi_cs}]
# set_output_delay -clock spi_sck -max 3.0 -min 0.2  [get_ports {spi_miso}]