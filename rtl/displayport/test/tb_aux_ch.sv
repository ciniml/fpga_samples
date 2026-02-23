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
    parameter int NUMBER_OF_TESTS = 100
)();
    logic clock /*verilator clocker*/;
    logic aresetn;

    localparam int unsigned CLOCK_HZ         = 32'd8_000_000; // Clock frequency
    localparam int unsigned PRECHARGE_CYCLES = 32'd10       ; // Number of precharge cycles
    localparam bit          DEBUG_OUT        = 1            ; // Enable debug output messages

    // AXI stream input
    logic         saxis_data_tvalid;
    logic         saxis_data_tready;
    logic [8-1:0] saxis_data_tdata ;
    logic         saxis_data_tlast ;

    // AXI stream output
    logic         maxis_data_tvalid;
    logic         maxis_data_tready;
    logic [8-1:0] maxis_data_tdata ;
    logic         maxis_data_tlast ;

    // AUX_CH output
    logic aux_ch_out       ;
    logic aux_ch_out_enable;
    // AUX_CH input
    logic aux_ch_in       ;

    displayport_aux_ch_tx #( .CLOCK_HZ(CLOCK_HZ)
               , .PRECHARGE_CYCLES(PRECHARGE_CYCLES)
               , .DEBUG_OUT(DEBUG_OUT)
    ) dut_tx (
        .*
    );
    displayport_aux_ch_rx #( .CLOCK_HZ(CLOCK_HZ)
               , .DEBUG_OUT(DEBUG_OUT)
    ) dut_rx (
        .*
    );
    
    typedef struct packed {
        logic [8-1:0] data;
        logic last;
    } data_t;

    // Connect AUX_CH output to AUX_CH input
    assign aux_ch_in = aux_ch_out_enable ? aux_ch_out : 1'bz;

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    task automatic get_output_data(output data_t data, input int ready_deassert_factor);
        bit ready_value;
        do begin
            ready_value = $urandom() >= ready_deassert_factor;
            maxis_data_tready = ready_value;
            @(posedge clock);
        end while( !ready_value );
        while(maxis_data_tvalid == 0) @(posedge clock);
        data.data = maxis_data_tdata;
        data.last = maxis_data_tlast;
        maxis_data_tready = ready_value;
    endtask

    initial begin
        data_t test_data[NUMBER_OF_TESTS];

        $dumpfile("trace.fst");
        $dumpvars(0, dut);
        $info("Starting test");
        
        // Generate test data
        for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
            test_data[i].data = 8'($urandom_range(0, 256));
            test_data[i].last = 1'($urandom_range(0, 2));
        end

        // reset
        aresetn = 0;
        saxis_data_tvalid = 0;
        saxis_data_tdata = 0;
        saxis_data_tlast = 0;
        maxis_data_tready = 0;
        repeat(4) @(posedge clock);
        aresetn = 1;
        @(posedge clock);

        fork
            fork
                begin
                    for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
                        @(negedge clock);
                        while($urandom_range(0, 16) < 4) @(negedge clock);
                        saxis_data_tdata = test_data[i].data;
                        saxis_data_tlast = test_data[i].last;
                        saxis_data_tvalid = 1;
                        @(posedge clock);
                        while(!saxis_data_tready) @(posedge clock);
                        saxis_data_tvalid = 0;
                    end
                end
                begin
                    for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
                        data_t actual;
                        bit expected_last;
                        expected_last = i == (NUMBER_OF_TESTS - 1) ? 1 : test_data[i].last;
                        get_output_data(actual, 32'h80000000);
                        if( actual.data != test_data[i].data ) $error("%d: TDATA mismatch. Expected: %h, Actual: %h", i, test_data[i].data, actual.data);
                        if( actual.last != expected_last     ) $error("%d: TLAST mismatch. Expected: %h, Actual: %h", i, expected_last,     actual.last);
                    end
                end
            join
            begin
                for(int i = 0; i < (NUMBER_OF_TESTS*1000); i++) @(posedge clock);
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
