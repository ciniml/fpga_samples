/**
 * @file top.sv
 * @brief Top module for WS2812 example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module top (
    input wire clock,

    output logic [7:0] led_out
);

localparam int CLOCK_HZ = 12_000_000;

blink #(
    .CLOCK_HZ(CLOCK_HZ),
    .NUMBER_OF_LEDS(8)
) blink_inst (
    .*
);

endmodule