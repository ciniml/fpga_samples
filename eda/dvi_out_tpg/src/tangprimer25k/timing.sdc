// timing.sdc
// Copyright 2024 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]
set_false_path -from [get_pins {reset_seq_dvi/reset_seq_0_s0/Q}] -to [get_pins {oser_dvi_*/RESET}]