// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023-2024.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tb_dds_core.sv
 * @brief Test bench for dds_core.
 */

`timescale 1ns/1ps

module tb #(
    parameter int NUMBER_OF_TESTS = 1<<14
)();
    logic clock /*verilator clocker*/;
    logic aresetn;

    localparam int unsigned CLOCK_HZ         = 32'd4_000_000; // Clock frequency
    localparam int unsigned PRECHARGE_CYCLES = 32'd10       ; // Number of precharge cycles
    localparam bit          DEBUG_OUT        = 0            ; // Enable debug output messages

    // DDS control input
    logic         saxis_data_tvalid;
    logic         saxis_data_tready;
    logic [8-1:0] saxis_data_tdata ;
    logic         saxis_data_tlast ;
    // AUX_CH output
    logic aux_ch_out       ;
    logic aux_ch_out_enable;
    
    displayport_aux_ch_tx #( .CLOCK_HZ(CLOCK_HZ)
               , .PRECHARGE_CYCLES(PRECHARGE_CYCLES)
               , .DEBUG_OUT(DEBUG_OUT)
    ) dut (
        .*
    );

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    initial begin
        $dumpfile("trace.fst");
        $dumpvars(0, dut);
        $info("Starting test");
        
        // reset
        aresetn = 0;
        saxis_data_tvalid = 0;
        saxis_data_tdata = 0;
        saxis_data_tlast = 0;
        repeat(4) @(posedge clock);
        aresetn = 1;
        @(posedge clock);
        saxis_data_tvalid = 1;
        saxis_data_tdata = 8'h5a;
        saxis_data_tlast = 1;
        @(posedge clock);

        fork
            begin
                for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
                    @(posedge clock);
                end
            end
            begin
                for(int i = 0; i < (NUMBER_OF_TESTS*10); i++) @(posedge clock);
                $error("Timeout");
            end
        join_any
        disable fork;

        $finish;
    end
endmodule

module tb_default();
    tb #() tb_inst();
endmodule
