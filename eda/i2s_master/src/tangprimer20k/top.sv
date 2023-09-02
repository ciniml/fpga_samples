/**
 * @file top.sv
 * @brief Top module for ethernet ICMP echo reply system.
 */
// Copyright 2023 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,

    output logic out_bclk_dbg,
    output logic out_data_dbg,
    output logic out_ws_dbg,

    output logic out_bclk,
    output logic out_data,
    output logic out_ws,
    output logic out_pa_en
);

logic main_clock;
logic main_clock_lock;

rpll_main your_instance_name(
    .clkout(main_clock), //output clkout
    .lock(main_clock_lock), //output lock
    .clkin(clock) //input clkin
);

logic reset;
reset_seq reset_seq_ext(
  .clock(main_clock),
  .reset_in(!main_clock_lock),
  .reset_out(reset)
);

assign out_pa_en = !reset;

always_comb begin
  out_bclk_dbg = out_bclk;
  out_data_dbg = out_data;
  out_ws_dbg = out_ws;
end

I2sMasterSystem system (
  .clock(main_clock),
  .*
);

endmodule
`default_nettype wire