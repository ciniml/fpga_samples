// timing.sdc
// Copyright 2023 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


create_clock -name clock -period 37.037 -waveform {0 18.518} [get_ports {clock}]
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
create_generated_clock -name clock_main -source [get_ports {rmii_txclk}] -master_clock rmii_txclk -divide_by 5 -multiply_by 2 [get_nets {clock_main}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/SET}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/D}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_main/reset_seq*/SET}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_main/reset_seq*/D}]
set_false_path -from [get_pins {ethernet_system_inst/txAsyncFifo/index*/Q}] -to [get_pins {ethernet_system_inst/txAsyncFifo/wIndexGrayReg*/D}]
set_false_path -from [get_pins {ethernet_system_inst/rxAsyncFifo/index*/Q}] -to [get_pins {ethernet_system_inst/rxAsyncFifo/wIndexGrayReg*/D}]
set_false_path -from [get_pins {ethernet_system_inst/txAsyncFifo/index*/Q}] -to [get_pins {ethernet_system_inst/txAsyncFifo/rIndexGrayReg*/D}]
set_false_path -from [get_pins {ethernet_system_inst/rxAsyncFifo/index*/Q}] -to [get_pins {ethernet_system_inst/rxAsyncFifo/rIndexGrayReg*/D}]