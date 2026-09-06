// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// PsramDwordCache + GowinPsram + HyperRAM model: the user side runs at
// 50MHz, the PSRAM side at 81MHz. Sequential line traffic (the NVMe
// pattern) plus random dword accesses thrashing a few lines, checked
// against a reference array.
`timescale 1ns/1ps
module psram_cache_test_body #(
    parameter RUN = 0,
    parameter LINE_BYTES = 512
);
    localparam CLK_HZ = 81_000_000;
    localparam ADDR_BITS = 20;

    logic clk = 0;      // user, 50MHz
    logic pclk = 0;     // psram, 81MHz
    logic pclk_p = 0;
    logic rst = 1, prst = 1;
    always #10 clk = ~clk;
    always #6 pclk = ~pclk;
    always @(pclk) pclk_p <= #3 pclk;

    logic [ADDR_BITS-1:0] addr = 0;
    logic        wen = 0, ren = 0;
    logic [31:0] wdata = 0, rdata;
    logic        ready;

    logic        pready;
    logic        cmd_valid, cmd_ready, cmd_write;
    logic [21:0] cmd_addr;
    logic [5:0]  cmd_len;
    logic        wr_valid, wr_ready;
    logic [15:0] wr_data;
    logic [1:0]  wr_mask;
    logic        rd_valid, rd_last;
    logic [15:0] rd_data;

    wire       psram_ck, psram_cs_n, psram_reset_n;
    wire [7:0] psram_dq;
    wire       psram_rwds;

    PsramDwordCache #(.ADDR_BITS(ADDR_BITS), .LINE_BYTES(LINE_BYTES)) cache (
        .i_clk(clk), .i_rst(rst),
        .i_addr(addr), .i_wen(wen), .i_wdata(wdata), .i_ren(ren),
        .o_rdata(rdata), .o_ready(ready), .o_dbg(),
        .i_pclk(pclk), .i_prst(prst), .i_pready(pready),
        .o_cmd_valid(cmd_valid), .i_cmd_ready(cmd_ready), .o_cmd_write(cmd_write),
        .o_cmd_addr(cmd_addr), .o_cmd_len(cmd_len),
        .o_wr_valid(wr_valid), .i_wr_ready(wr_ready), .o_wr_data(wr_data), .o_wr_mask(wr_mask),
        .i_rd_valid(rd_valid), .i_rd_data(rd_data), .i_rd_last(rd_last)
    );

    GowinPsram #(.CLK_HZ(CLK_HZ), .LATENCY(3)) dut (
        .i_clk(pclk), .i_clk_p(pclk_p), .i_rst(prst), .o_ready(pready),
        .i_cmd_valid(cmd_valid), .o_cmd_ready(cmd_ready),
        .i_cmd_write(cmd_write), .i_cmd_reg(1'b0),
        .i_cmd_addr(cmd_addr), .i_cmd_len(cmd_len),
        .i_wr_valid(wr_valid), .o_wr_ready(wr_ready),
        .i_wr_data(wr_data), .i_wr_mask(wr_mask),
        .o_rd_valid(rd_valid), .o_rd_data(rd_data), .o_rd_last(rd_last),
        .o_psram_ck(psram_ck), .o_psram_cs_n(psram_cs_n),
        .o_psram_reset_n(psram_reset_n),
        .io_psram_dq(psram_dq), .io_psram_rwds(psram_rwds)
    );

    hyperram_model ram (
        .ck(psram_ck), .cs_n(psram_cs_n), .reset_n(psram_reset_n),
        .dq(psram_dq), .rwds(psram_rwds)
    );

    int errors = 0;
    // profiling: stall cycles (request up but not ready) and miss events
    longint stall_cycles = 0, req_cycles = 0, misses = 0;
    logic prev_busy = 0;
    always @(posedge clk) if (RUN) begin
        if (wen || ren) begin
            req_cycles++;
            if (!ready) stall_cycles++;
        end
        if (cache.busy && !prev_busy) misses++;
        prev_busy <= cache.busy;
    end
    logic [31:0] refmem [0:(1 << ADDR_BITS) - 1];
    bit          written [0:(1 << ADDR_BITS) - 1];

    // sync-RAM-with-ready protocol: hold the request until ready
    task automatic mem_write(input [ADDR_BITS-1:0] a, input [31:0] d);
        @(negedge clk);
        addr = a; wdata = d; wen = 1;
        forever begin
            @(posedge clk);
            if (ready) break;
        end
        @(negedge clk);
        wen = 0;
        refmem[a] = d; written[a] = 1;
    endtask

    task automatic mem_read(input string what, input [ADDR_BITS-1:0] a);
        @(negedge clk);
        addr = a; ren = 1;
        forever begin
            @(posedge clk);
            if (ready) break;
        end
        @(negedge clk);
        ren = 0;
        @(posedge clk);   // data one cycle after the accepted read
        #1;
        if (rdata !== refmem[a]) begin
            $display("ERROR: %s: [%h] got %h expected %h", what, a, rdata, refmem[a]);
            errors++;
        end
    endtask

    function automatic logic [31:0] pat(input [ADDR_BITS-1:0] a, input int s);
        pat = {a, 12'h0} ^ (a * 32'h9E37_79B1) ^ (s * 32'h0101_0101) ^ 32'hDEAD_BEEF;
    endfunction

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 30_000_000) $fatal(1, "TIMEOUT");
    end

    int i, l, t;
    logic [ADDR_BITS-1:0] a;
    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge pclk);
        prst = 0;

        // ---- sequential lines, like NVMe writes ----
        for (l = 0; l < 4; l++)
            for (i = 0; i < 128; i++) mem_write(l * 128 + i, pat(l * 128 + i, 1));
        // ---- read back in a different order (each switch evicts a dirty line) ----
        for (l = 3; l >= 0; l--)
            for (i = 0; i < 128; i++) mem_read("seq", l * 128 + i);
        $display("sequential lines ok at %0t", $time);

        // ---- partial line update then full read ----
        for (i = 40; i < 50; i++) mem_write(2 * 128 + i, pat(2 * 128 + i, 2));
        for (i = 0; i < 128; i++) mem_read("partial", 0 * 128 + i);   // evicts line 2 (dirty)
        for (i = 0; i < 128; i++) mem_read("partial2", 2 * 128 + i);

        // ---- random dword traffic over 8 lines near the top of the die ----
        for (t = 0; t < 300; t++) begin
            a = 20'hFFC00 + $urandom_range(0, 8 * 128 - 1);
            if ($urandom_range(0, 1) || !written[a]) mem_write(a, pat(a, t + 3));
            else mem_read("rand", a);
        end
        for (i = 0; i < 8 * 128; i++) if (written[20'hFFC00 + i]) mem_read("final", 20'hFFC00 + i);

        errors += ram.errors;
        $display("PROF line=%0dB misses=%0d req_cycles=%0d stall_cycles=%0d (%.1f cyc/miss)",
                 LINE_BYTES, misses, req_cycles, stall_cycles, misses ? real'(stall_cycles) / real'(misses) : 0.0);
        if (errors != 0) $fatal(1, "FAILED: %0d errors", errors);
        $display("PASSED");
        $finish;
    end
endmodule
