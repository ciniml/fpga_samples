/**
 * @file stmemu.sv
 * @brief linear move stepper motor actuator emulator.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module stp_emu #(
    parameter longint CLOCK_HZ = 24_000_000,
    parameter int FULL_STROKE_PULSES = 1000,
    parameter int LIMIT_SW_NEAR_PULSES = 20,
    parameter int LIMIT_SW_FAR_PULSES = 20,
    localparam int COUNTER_LIMIT = LIMIT_SW_NEAR_PULSES + FULL_STROKE_PULSES + LIMIT_SW_FAR_PULSES,
    localparam int COUNTER_BITS = $clog2(COUNTER_LIMIT)
) (
    input  wire  clock,
    
    input  wire  stp_en_in,
    input  wire  stp_pa_in,
    input  wire  stp_pb_in,
    
    output logic limit_sw_near_out,
    output logic limit_sw_far_out,

    output logic [COUNTER_BITS-1:0] counter_out
);

logic [COUNTER_BITS-1:0] counter = 0;
assign counter_out = counter;

// Synchronize input signals.
logic [1:0] stp_en_sync = 0;
logic [1:0] stp_pa_sync = 0;
logic [1:0] stp_pb_sync = 0;
logic stp_en;
logic stp_pa;
logic stp_pb;

always_comb begin
    stp_en = stp_en_sync[0];
    stp_pa = stp_pa_sync[0];
    stp_pb = stp_pb_sync[0];
end

always_ff @(posedge clock) begin
    stp_en_sync <= {stp_en_in, stp_en_sync[1]};
    stp_pa_sync <= {stp_pa_in, stp_pa_sync[1]};
    stp_pb_sync <= {stp_pb_in, stp_pb_sync[1]};
end

logic stp_pa_prev = 0;
logic stp_pb_prev = 0;
logic [COUNTER_BITS-1:0] next_counter;

// next counter condition.
always_comb begin
    next_counter = counter;
    if( stp_en ) begin
        if( (!stp_pa_prev && stp_pa && !stp_pb) || (!stp_pb_prev && stp_pb && stp_pa) || (stp_pa_prev && !stp_pa && stp_pb) || (stp_pb_prev && !stp_pb && !stp_pa) ) begin  // CW condition
            next_counter = counter < COUNTER_LIMIT ? counter + 1 : counter;
        end
        else if( (!stp_pa_prev && stp_pa && stp_pb) || (!stp_pb_prev && stp_pb && !stp_pa) || (stp_pa_prev && !stp_pa && !stp_pb) || (stp_pb_prev && !stp_pb && stp_pa) ) begin // CCW condition
            next_counter = counter > 0 ? counter - 1 : counter;
        end
    end
end

// Initialize limit switch output.
initial begin
    limit_sw_near_out <= 0;
    limit_sw_far_out <= 0;
end

always_ff @(posedge clock) begin
    stp_pa_prev <= stp_pa;   
    stp_pb_prev <= stp_pb;

    counter <= next_counter;

    // Update limit switches output.
    limit_sw_near_out <= counter < LIMIT_SW_NEAR_PULSES;
    limit_sw_far_out <= counter >= LIMIT_SW_NEAR_PULSES + FULL_STROKE_PULSES;
end

endmodule
    
