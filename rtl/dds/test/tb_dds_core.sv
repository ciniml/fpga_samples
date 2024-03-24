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
    parameter int NUMBER_OF_TESTS = 1<<14,
    parameter int PHASE_COUNTER_BITS = 14,
    parameter bit USE_SINE = 0 
)();
    logic clock /*verilator clocker*/;
    logic aresetn;

    localparam int unsigned SAMPLE_BITS        = 16;
    localparam int unsigned TABLE_LENGTH_BITS  = 8; 
    localparam int unsigned TABLE_READ_LATENCY = 1;  // table memory access latency.
    localparam int unsigned MULTIPLYER_LATENCY = 1; 
    
    // Table access
    logic [TABLE_LENGTH_BITS-1:0] table_addr    [0:2-1];
    logic                         table_read_en [0:2-1];
    logic [SAMPLE_BITS-1:0]       table_data    [0:2-1];

    // DDS control input
    logic                              saxis_control_tvalid;
    logic                              saxis_control_tready;
    logic [PHASE_COUNTER_BITS + 1-1:0] saxis_control_tdata ;

    // DDS output
    logic                   maxis_wave_tvalid;
    logic                   maxis_wave_tready;
    logic [SAMPLE_BITS-1:0] maxis_wave_tdata;
    
    dds_dds_core #( .SAMPLE_BITS(SAMPLE_BITS)
                  , .TABLE_LENGTH_BITS(TABLE_LENGTH_BITS)
                  , .TABLE_READ_LATENCY(TABLE_READ_LATENCY)
                  , .PHASE_COUNTER_BITS(PHASE_COUNTER_BITS)
                  , .MULTIPLYER_LATENCY(MULTIPLYER_LATENCY)
    ) dut (
        .*
    );

    // waveform table
    localparam int TABLE_LENGTH = 1 << TABLE_LENGTH_BITS;
    bit [SAMPLE_BITS-1:0] wave_table [0:TABLE_LENGTH-1];

    initial begin
        for(int i = 0; i < TABLE_LENGTH; i++) begin
            if( USE_SINE ) begin
                wave_table[i] = SAMPLE_BITS'(signed'( $rtoi($sin(2.0 * $itor(i) * 3.14159265358979323846 / $itor(TABLE_LENGTH)) * $itor((1 << (SAMPLE_BITS - 1)) - 1) ) ));
            end
            else begin
                wave_table[i] = SAMPLE_BITS'(i << (SAMPLE_BITS - TABLE_LENGTH_BITS));
            end
        end
    end

    always @(posedge clock) begin
        if( !aresetn ) begin
            
        end
        else begin
            for(int i = 0; i < 2; i++) begin
                if( table_read_en[i] ) begin
                    table_data[i] <= wave_table[table_addr[i]];
                end
            end
        end
    end

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    initial begin
        int fd;

        $dumpfile("trace.fst");
        $dumpvars(0, dut);
        $info("Starting test");
        
        // waveform output
        fd = $fopen("waveform.csv", "w");
        
        // reset
        aresetn = 0;
        table_data = {0, 0};
        saxis_control_tvalid = 0;
        saxis_control_tdata = 0;
        maxis_wave_tready = 0;

        repeat(4) @(posedge clock);
        aresetn = 1;
        @(posedge clock);

        saxis_control_tdata = 1;
        saxis_control_tvalid = 1;
        @(posedge clock);
        saxis_control_tvalid = 0;
        
        fork
            begin
                maxis_wave_tready = 1;
                for(int i = 0; i < NUMBER_OF_TESTS; i++) begin
                    while( !maxis_wave_tvalid  ) @(posedge clock);
                    $fwrite(fd, "%d\n", maxis_wave_tdata);
                    @(posedge clock);
                end
            end
            begin
                for(int i = 0; i < (NUMBER_OF_TESTS*10); i++) @(posedge clock);
                $error("Timeout");
            end
        join_any
        disable fork;

        $fclose(fd);

        $finish;
    end
endmodule

module tb_default();
    tb #() tb_inst();
endmodule

module tb_sine();
    tb #(
        .NUMBER_OF_TESTS(1024),
        .PHASE_COUNTER_BITS(10),
        .USE_SINE(1)
    ) tb_inst();
endmodule