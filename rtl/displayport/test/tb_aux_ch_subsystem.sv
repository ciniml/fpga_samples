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

    parameter  int unsigned CLOCK_HZ            = 32'd27_000_000; // Clock frequency (default = 27MHz)
    parameter  int unsigned MANCHESTER_CLOCK_HZ = 32'd1_000_000  ; // Manchester clock frequency (default = 2MHz)
    parameter  int unsigned PRECHARGE_CYCLES    = 32'd16         ; // Number of precharge cycles
    parameter  int unsigned BUFFER_SIZE         = 256            ; // Buffer size
    parameter  bit          DEBUG_OUT           = 0              ; // Enable debug output messages
    parameter  int unsigned PROCESSOR_ID        = 32'h01234567   ; // Processor ID
    parameter  int unsigned PROCESSOR_ROM_SIZE  = 16384          ; // Processor ROM size (default = 16kB)
    parameter  int unsigned PROCESSOR_RAM_SIZE  = 8192           ; // Processor RAM size (default = 8kB)
    localparam int unsigned REGISTER_COUNT      = 32             ; // Number of registers

    // AUX_CH output
    logic aux_ch_out       [1:0];
    logic aux_ch_out_enable[1:0];
    // AUX_CH input
    logic aux_ch_in        [1:0];

    // CPU OUT
    logic [31:0] cpu_out   [1:0];

    // Connect AUX_CH output to AUX_CH input
    generate
        for(genvar i = 0; i < 2; i++) begin: aux_ch_gen
            assign aux_ch_in[!i[0]] = aux_ch_out_enable[i[0]] ? aux_ch_out[i[0]] : 1'b0;

            logic         maxis_serial_out_tvalid;
            logic         maxis_serial_out_tready;
            logic [8-1:0] maxis_serial_out_tdata ;

            displayport_aux_ch_subsystem #(
                .CLOCK_HZ(CLOCK_HZ),
                .MANCHESTER_CLOCK_HZ(MANCHESTER_CLOCK_HZ),
                .PRECHARGE_CYCLES(PRECHARGE_CYCLES),
                .BUFFER_SIZE(BUFFER_SIZE),
                .DEBUG_OUT(DEBUG_OUT),
                .PROCESSOR_ID(i),
                .PROCESSOR_ROM_SIZE(PROCESSOR_ROM_SIZE),
                .PROCESSOR_RAM_SIZE(PROCESSOR_RAM_SIZE)
            ) dut (
                .clock  (clock),
                .aresetn(aresetn),
                .aux_ch_in(aux_ch_in[i[0]]),
                .aux_ch_out(aux_ch_out[i[0]]),
                .aux_ch_out_enable(aux_ch_out_enable[i[0]]),
                .cpu_io_out(cpu_out[i[0]]),
                .maxis_serial_out_tvalid(maxis_serial_out_tvalid),
                .maxis_serial_out_tready(maxis_serial_out_tready),
                .maxis_serial_out_tdata(maxis_serial_out_tdata),
                .saxis_serial_in_tvalid(1'b0),
                .saxis_serial_in_tready(),
                .saxis_serial_in_tdata (8'h0)
            );
            assign maxis_serial_out_tready = aresetn;
            string line_buffer;
            always_ff @(posedge clock) begin
                if( !aresetn ) begin
                end else begin
                    if( maxis_serial_out_tvalid && maxis_serial_out_tready ) begin
                        //$display("[%d] %c %s", i, maxis_serial_out_tdata, line_buffer);
                        if( maxis_serial_out_tdata == 8'h0a ) begin
                            $display("[%1d] %s", i, line_buffer);
                            $fflush(1);
                            line_buffer = "";
                        end else begin
                            line_buffer = {line_buffer, maxis_serial_out_tdata};
                        end
                    end
                end
            end
        end
    endgenerate

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    initial begin
        $dumpfile("trace.fst");
        $dumpvars(0, aux_ch_gen[0].dut);
        $dumpvars(0, aux_ch_gen[1].dut);

        $readmemh("../sw-rs/bootrom-rs.hex", aux_ch_gen[0].dut.processor_rom);
        $readmemh("../sw-rs/bootrom-rs.hex", aux_ch_gen[1].dut.processor_rom);

        $info("Starting test");
        
        // reset
        aresetn = 0;
        repeat(4) @(posedge clock);
        aresetn = 1;
        @(posedge clock);

        while( cpu_out[0][0] == 0 || cpu_out[1][0] == 0 ) begin
            @(posedge clock);
        end

        $finish;
    end
endmodule

module tb_default();
    tb #() tb_inst();
endmodule
