// timing.sdc
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


create_clock -name clock -period 5.000 -waveform {0 2.500} [get_ports {clock}]
report_timing -setup -max_paths 100 -max_common_paths 5
