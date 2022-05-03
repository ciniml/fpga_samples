/**
 * @file top.sv
 * @brief Top module for LED blink example
 */
// Copyright 2021-2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module top (
    input wire clock,

    output logic [5:0] led
);

localparam int CLOCK_HZ = 27_000_000;

logic [5:0] led_out;

blink #(
    .CLOCK_HZ(CLOCK_HZ),
    .NUMBER_OF_LEDS(6)
) blink_inst (
    .*
);

always_comb begin
    led <= led_out;
end

endmodule