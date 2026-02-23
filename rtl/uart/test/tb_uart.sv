// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2024.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file  tb_uart.sv
 * @brief Test bench for uart rx and tx
 */

`timescale 1ns/1ps

module tb #(
    parameter int NUMBER_OF_TESTS = 1000,
    parameter int VALID_RATE = 8,
    parameter int READY_RATE = 8,
    parameter int BAUD_DIVIDER = 8
)();
    logic         clock = 0;     // クロック /*verilator clocker*/
    logic         reset = 1;     // リセット (正論理)
    
    logic         tx_valid;
    logic         tx_ready;
    logic [7:0]   tx_bits;

    logic         tx;
    logic         rx;
    logic         overrun;

    logic         rx_valid;
    logic         rx_ready;
    logic [7:0]   rx_bits;
    
    // Instantiate DUT
    uart_rx #(
        .BAUD_DIVIDER(BAUD_DIVIDER)
    ) dut_rx (
        .data_valid(rx_valid),
        .data_ready(rx_ready),
        .data_bits(rx_bits),
        .*
    );
    uart_tx #(
        .BAUD_DIVIDER(BAUD_DIVIDER)
    ) dut_tx (
        .data_valid(tx_valid),
        .data_ready(tx_ready),
        .data_bits(tx_bits),
        .*
    );
    assign rx = tx;

    localparam int TIMEOUT_CYCLES = NUMBER_OF_TESTS * 20 * BAUD_DIVIDER;

    int input_test_index = 0;
    int output_test_index = 0;
    int timeout_counter = 0;
    bit [7:0] test_data[NUMBER_OF_TESTS];
    
    // Sample the input stream ready signal
    logic tx_ready_reg;
    always @(posedge clock) begin
        if( reset ) begin
            tx_ready_reg <= 0;
        end
        else begin
            tx_ready_reg <= tx_ready;
        end
    end
    // Generate input signal
    always @(negedge clock) begin
        if( reset ) begin
            input_test_index <= 0;
            tx_valid <= 0;
            tx_bits <= 0;
        end
        else begin
            if( tx_valid && tx_ready_reg ) begin
                tx_valid <= 0;
            end
            if( !tx_valid || tx_ready_reg ) begin
                if( input_test_index < NUMBER_OF_TESTS && $urandom_range(0, 10) < VALID_RATE) begin
                    tx_valid <= 1;
                    tx_bits <= test_data[input_test_index];
                    input_test_index <= input_test_index + 1;
                end
            end
        end
    end

    // Generate test sink ready signal
    always @(negedge clock) begin
        if( reset ) begin
            rx_ready <= 1'b0;
        end
        else begin
            rx_ready <= $urandom_range(0, 10) < READY_RATE;
        end
    end

    always @(posedge clock) begin   // Check the received data
        if( reset ) begin
            output_test_index <= 0;
        end
        else begin
            if( rx_valid && rx_ready ) begin
                logic [7:0] expected_bits;
                
                expected_bits = test_data[output_test_index];
                
                if( rx_bits != expected_bits ) $error("#%04d mismatch tdata: expected %02h != actual %02h", output_test_index, expected_bits, rx_bits);
                output_test_index <= output_test_index + 1;
            end
        end
    end

    always @(posedge clock) begin   // Timeout counter
        timeout_counter <= timeout_counter + 1;
    end
    always #(5) begin // Generate clock (5[ns]*2 = 10[ns] period)
        clock = ~clock;
    end
    
    initial begin
        $dumpfile("trace.fst"); // Make a trace file
        $dumpvars(0, dut);      // Dump all signals

        // Reset - Release after 2 clock cycles
        reset = 1;
        // Generate test data
        for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
            test_data[i] = 8'($urandom_range(0, 256));
        end
        repeat(2) @(negedge clock);
        reset = 0;
        @(posedge clock);

        // Wait until the test is done or timeout
        while( output_test_index < NUMBER_OF_TESTS && timeout_counter < TIMEOUT_CYCLES ) @(posedge clock);
        if( timeout_counter >= TIMEOUT_CYCLES ) $error("timeout");
        $finish;
    end
endmodule

module tb_default();
    tb #() tb_inst();
endmodule

module tb_low_valid();
    tb #(.VALID_RATE(3)) tb_inst();
endmodule

module tb_low_ready();
    tb #(.READY_RATE(1)) tb_inst();
endmodule