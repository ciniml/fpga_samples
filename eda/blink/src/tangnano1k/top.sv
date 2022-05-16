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

    output logic led_r,
    output logic led_g,
    output logic led_b
);

localparam int CLOCK_HZ = 27_000_000;

logic [2:0] led_out;

blink #(
    .CLOCK_HZ(CLOCK_HZ),
    .NUMBER_OF_LEDS(3)
) blink_inst (
    .*
);

always_comb begin
    led_r <= led_out[0];
    led_g <= led_out[1];
    led_b <= led_out[2];
end

endmodule