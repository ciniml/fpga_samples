// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test body for GowinPsram against the behavioral HyperRAM model, using
// the Gowin ODDR/IDDR simulation primitives (test/gen/). RUN=0 by default.
`timescale 1ns/1ps
module gowin_psram_test_body #(
    parameter RUN = 0,
    parameter real PERIOD = 12.0,   // ~81MHz
    parameter real PHASE  = 3.0,    // CK clock shift (90 degrees)
    parameter real T_CKD  = 5.0     // RAM CK-to-data delay
);
    localparam CLK_HZ  = 81_000_000;
    localparam LATENCY = 3;

    logic clk = 0;
    logic clk_p = 0;
    logic rst = 1;
    always #(PERIOD / 2) clk = ~clk;
    always @(clk) clk_p <= #(PHASE) clk;

    logic [1:0]  ck_delay = 0;   // nominal (see GowinPsram header)
    logic        ready;
    logic        cmd_valid = 0, cmd_ready, cmd_write = 0, cmd_reg = 0;
    logic [21:0] cmd_addr = 0;
    logic [6:0]  cmd_len = 0;
    logic        wr_valid = 0, wr_ready;
    logic [15:0] wr_data = 0;
    logic [1:0]  wr_mask = 0;
    logic        rd_valid, rd_last;
    logic [15:0] rd_data;

    wire       psram_ck, psram_cs_n, psram_reset_n;
    wire [7:0] psram_dq;
    wire       psram_rwds;

    GowinPsram #(.CLK_HZ(CLK_HZ), .LATENCY(LATENCY)) dut (
        .i_clk(clk), .i_clk_p(clk_p), .i_rst(rst),
        .i_ck_delay(ck_delay), .i_lat_extra(2'd0), .o_ready(ready),
        .i_cmd_valid(cmd_valid), .o_cmd_ready(cmd_ready),
        .i_cmd_write(cmd_write), .i_cmd_reg(cmd_reg),
        .i_cmd_addr(cmd_addr), .i_cmd_len(cmd_len),
        .i_wr_valid(wr_valid), .o_wr_ready(wr_ready),
        .i_wr_data(wr_data), .i_wr_mask(wr_mask),
        .o_rd_valid(rd_valid), .o_rd_data(rd_data), .o_rd_last(rd_last),
        .o_psram_ck(psram_ck), .o_psram_cs_n(psram_cs_n),
        .o_psram_reset_n(psram_reset_n),
        .io_psram_dq(psram_dq), .io_psram_rwds(psram_rwds)
    );

    hyperram_model #(.T_CKD(T_CKD)) ram (
        .ck(psram_ck), .cs_n(psram_cs_n), .reset_n(psram_reset_n),
        .dq(psram_dq), .rwds(psram_rwds)
    );

    int errors = 0;
`ifdef PSRAM_TRACE
    always @(clk or clk_p or psram_ck or psram_cs_n or psram_dq)
        if ($realtime > 158660.0 && $realtime < 158780.0)
            $display("TRACE %0t clk=%b clkp=%b | st=%0d cnt=%0d cke=%b busy=%b oe=%b ris=%h | ck=%b cs_n=%b dq=%h", $realtime, clk, clk_p,
                     dut.state, dut.cnt, dut.ck_e_r, dut.busy_r, dut.dq_oe, dut.dq_ris, psram_ck, psram_cs_n, psram_dq);
`endif

    // write source: words are served from wbuf in order
    logic [15:0] wbuf [0:127];
    logic [1:0]  mbuf [0:127];
    int          widx = 0;
    always @(posedge clk) begin
        if (cmd_valid && cmd_ready) widx <= 0;
        else if (wr_ready)          widx <= widx + 1;
    end
    always_comb begin
        wr_data  = wbuf[widx[6:0]];
        wr_mask  = mbuf[widx[6:0]];
    end

    // read sink
    logic [15:0] rbuf [0:127];
    int          ridx = 0;
    int          rlast_at = -1;
    // (all bookkeeping lives in this one process: mixing writes from the
    // stimulus process and this block confused the simulator's ordering)
    always @(posedge clk) begin
        if (cmd_valid && cmd_ready) begin
            ridx     <= 0;
            rlast_at <= -1;
        end else if (rd_valid) begin
            if (ridx < 128) rbuf[ridx] <= rd_data;
            if (rd_last) rlast_at <= ridx;
            ridx <= ridx + 1;
        end
    end

    task automatic check16(input string what, input logic [15:0] got, input logic [15:0] exp);
        if (got !== exp) begin
            $display("ERROR: %s: got %h expected %h", what, got, exp);
            errors++;
        end
    endtask

    task automatic issue(input bit write, input bit regsp, input [21:0] addr, input [6:0] len);
        @(negedge clk);
        cmd_valid = 1; cmd_write = write; cmd_reg = regsp; cmd_addr = addr; cmd_len = len;
        forever begin
            @(posedge clk);
            if (cmd_ready) break;
        end
        @(negedge clk);
        cmd_valid = 0;
        // wait for completion
        forever begin
            @(posedge clk);
            if (cmd_ready) break;
        end
    endtask

    task automatic do_write(input [21:0] addr, input int n);
        wr_valid = 1;
        issue(1, 0, addr, n - 1);
        wr_valid = 0;
        if (widx != n) begin
            $display("ERROR: write %0d words: %0d consumed", n, widx);
            errors++;
        end
    endtask

    task automatic do_read(input string what, input [21:0] addr, input int n);
        issue(0, 0, addr, n - 1);
        if (ridx != n) begin
            $display("ERROR: %s: read %0d words, got %0d", what, n, ridx);
            errors++;
        end
        if (rlast_at != n - 1) begin
            $display("ERROR: %s: rd_last at %0d expected %0d (ridx=%0d, t=%0t)", what, rlast_at, n - 1, ridx, $realtime);
            errors++;
        end
    endtask

    function automatic logic [15:0] pat(input [21:0] addr, input int i, input int seed);
        pat = (addr[15:0] + i * 16'h0113 + seed * 16'h2B00) ^ 16'hA5C3;
    endfunction

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 40_000_000) $fatal(1, "TIMEOUT");
    end

    int i, t, n;
    logic [21:0] a;
    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;

        // ---- init: CR0 written by the controller ----
        forever begin
            @(posedge clk);
            if (ready) break;
        end
        check16("CR0 after init", ram.cr0, 16'h8FEF);   // latency 3, fixed
        $display("init done at %0t, CR0=%h", $time, ram.cr0);

        // ---- register reads: ID0, CR0 ----
        issue(0, 1, 22'h0000, 0);
        check16("ID0", rbuf[0], 16'h0C81);
        if (ridx != 1) begin $display("ERROR: ID0 read count %0d", ridx); errors++; end
        issue(0, 1, 22'h1000, 0);
        check16("CR0 readback", rbuf[0], 16'h8FEF);

        // ---- single word write / read ----
        wbuf[0] = 16'h1234; mbuf[0] = 2'b00;
        do_write(22'h00_0100, 1);
        check16("mem[0x80]", ram.mem[22'h80], 16'h1234);
        do_read("single", 22'h00_0100, 1);
        check16("single rd", rbuf[0], 16'h1234);

        // ---- byte masks ----
        wbuf[0] = 16'hAABB; mbuf[0] = 2'b10;   // only low byte
        do_write(22'h00_0100, 1);
        check16("mask lo", ram.mem[22'h80], 16'h12BB);
        wbuf[0] = 16'hCCDD; mbuf[0] = 2'b01;   // only high byte
        do_write(22'h00_0100, 1);
        check16("mask hi", ram.mem[22'h80], 16'hCCBB);
        do_read("masked", 22'h00_0100, 1);
        check16("masked rd", rbuf[0], 16'hCCBB);

        // ---- 64-word burst write and read back ----
        a = 22'h12_3450;
        for (i = 0; i < 64; i++) begin wbuf[i] = pat(a, i, 1); mbuf[i] = 2'b00; end
        do_write(a, 64);
        do_read("burst64", a, 64);
        for (i = 0; i < 64; i++) check16($sformatf("burst64[%0d]", i), rbuf[i], pat(a, i, 1));

        // ---- max burst (128 words) ----
        a = 22'h3F_FF00;   // crosses nothing special, near the top
        for (i = 0; i < 128; i++) begin wbuf[i] = pat(a, i, 2); mbuf[i] = 2'b00; end
        do_write(a, 128);
        do_read("burst128", a, 128);
        for (i = 0; i < 128; i++) check16($sformatf("burst128[%0d]", i), rbuf[i], pat(a, i, 2));

        // ---- wr_valid low -> word masked ----
        for (i = 0; i < 4; i++) begin wbuf[i] = 16'hFFFF; mbuf[i] = 2'b00; end
        wr_valid = 0;
        issue(1, 0, a, 3);     // all four words skipped
        do_read("skip", a, 4);
        for (i = 0; i < 4; i++) check16($sformatf("skip[%0d]", i), rbuf[i], pat(a, i, 2));

        // ---- random bursts ----
        for (t = 0; t < 40; t++) begin
            n = $urandom_range(1, 128);
            a = {$urandom_range(0, (1 << 21) - 1), 1'b0};
            if (a[21:1] + n > (1 << 21)) a = 0;
            for (i = 0; i < n; i++) begin wbuf[i] = pat(a, i, t + 10); mbuf[i] = 2'b00; end
            do_write(a, n);
            do_read($sformatf("rand%0d", t), a, n);
            for (i = 0; i < n; i++) check16($sformatf("rand%0d[%0d]", t, i), rbuf[i], pat(a, i, t + 10));
        end

        // ---- back-to-back commands (ready handshake) ----
        for (i = 0; i < 8; i++) begin wbuf[i] = pat(22'h100, i, 99); mbuf[i] = 2'b00; end
        do_write(22'h100, 8);
        do_read("b2b", 22'h100, 8);
        for (i = 0; i < 8; i++) check16($sformatf("b2b[%0d]", i), rbuf[i], pat(22'h100, i, 99));

        errors += ram.errors;
        $display("model: %0d reg writes, %0d read words, %0d written words, %0d masked",
                 ram.n_ca_writes, ram.n_reads, ram.n_writes, ram.n_masked);
        if (errors != 0) $fatal(1, "FAILED: %0d errors", errors);
        $display("PASSED");
        $finish;
    end
endmodule
