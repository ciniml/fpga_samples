/**
 * @file blink_all.sv
 * @brief simple LED blink example.
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module blink #(
    parameter longint CLOCK_HZ = 24_000_000,
    parameter NUMBER_OF_LEDS = 8
) (
    input  logic clock,
    output logic [NUMBER_OF_LEDS-1:0] led_out
);

localparam longint COUNT_HALF = CLOCK_HZ/2;
localparam int COUNTER_BITS = $clog2(COUNT_HALF);

logic [COUNTER_BITS-1:0] counter = 0;
logic led_out_internal = 0;

always_comb begin
    led_out = {NUMBER_OF_LEDS {led_out_internal}};
end

always_ff @(posedge clock) begin
    if( counter < COUNT_HALF - 1 ) begin
        counter <= counter + 1;
    end
    else begin
        counter <= 0;
        led_out_internal ^= 1;
    end    
end

endmodule
    
