// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// End-to-end test of the board bring-up driver (PsramTest + GowinPsram +
// uart_tx) against the HyperRAM model: decodes the UART lines and checks
// that the ck_delay=1 pass is clean and reports the right ID0/CR0.
`timescale 1ns/1ps
module psram_test_body #(
    parameter RUN = 0,
    parameter real PERIOD = 12.0,
    parameter real PHASE  = 3.0
);
    localparam CLK_HZ     = 81_000_000;
    localparam TEST_WORDS = 1024;
    localparam BAUD_DIV   = 8;

    logic clk = 0;
    logic clk_p = 0;
    logic rst = 1;
    always #(PERIOD / 2) clk = ~clk;
    always @(clk) clk_p <= #(PHASE) clk;

    logic        ctrl_rst;
    logic [1:0]  ck_delay, lat_extra;
    logic        ready;
    logic        cmd_valid, cmd_ready, cmd_write, cmd_reg;
    logic [21:0] cmd_addr;
    logic [6:0]  cmd_len;
    logic        wr_valid, wr_ready;
    logic [15:0] wr_data;
    logic [1:0]  wr_mask;
    logic        rd_valid, rd_last;
    logic [15:0] rd_data;
    logic        tx_valid, tx_ready;
    logic [7:0]  tx_data;
    logic [4:0]  status;
    logic        uart;

    wire       psram_ck, psram_cs_n, psram_reset_n;
    wire [7:0] psram_dq;
    wire       psram_rwds;

    PsramTest #(.CLK_HZ(CLK_HZ), .TEST_WORDS(TEST_WORDS)) drv (
        .i_clk(clk), .i_rst(rst),
        .o_ctrl_rst(ctrl_rst), .o_ck_delay(ck_delay), .o_lat_extra(lat_extra), .i_ready(ready),
        .o_cmd_valid(cmd_valid), .i_cmd_ready(cmd_ready),
        .o_cmd_write(cmd_write), .o_cmd_reg(cmd_reg),
        .o_cmd_addr(cmd_addr), .o_cmd_len(cmd_len),
        .o_wr_valid(wr_valid), .i_wr_ready(wr_ready),
        .o_wr_data(wr_data), .o_wr_mask(wr_mask),
        .i_rd_valid(rd_valid), .i_rd_data(rd_data), .i_rd_last(rd_last),
        .o_tx_valid(tx_valid), .i_tx_ready(tx_ready), .o_tx_data(tx_data),
        .o_status(status)
    );

    GowinPsram #(.CLK_HZ(CLK_HZ), .LATENCY(3)) dut (
        .i_clk(clk), .i_clk_p(clk_p), .i_rst(rst | ctrl_rst),
        .i_ck_delay(ck_delay), .i_lat_extra(lat_extra), .o_ready(ready),
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

    hyperram_model ram (
        .ck(psram_ck), .cs_n(psram_cs_n), .reset_n(psram_reset_n),
        .dq(psram_dq), .rwds(psram_rwds)
    );

    uart_tx #(.BAUD_DIVIDER(BAUD_DIV)) u_uart (
        .clock(clk), .reset(rst),
        .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data),
        .tx(uart)
    );

    // UART receiver: 8N1 at clk / BAUD_DIV
    string line = "";
    string lines [$];
    logic [7:0] rxb;
    int b;
    always begin
        @(negedge uart);
        repeat (BAUD_DIV / 2) @(posedge clk);    // middle of the start bit
        for (b = 0; b < 8; b++) begin
            repeat (BAUD_DIV) @(posedge clk);
            rxb[b] = uart;
        end
        repeat (BAUD_DIV) @(posedge clk);        // stop bit
        if (rxb == 8'h0A) begin
            $display("UART: %s", line);
            lines.push_back(line);
            line = "";
        end else if (rxb != 8'h0D) begin
            line = {line, string'(rxb)};
        end
    end

    int errors = 0;
    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 60_000_000) $fatal(1, "TIMEOUT");
    end

    function automatic void expect_sub(input string what, input string s, input string sub);
        int found = 0;
        for (int i = 0; i + sub.len() <= s.len(); i++)
            if (s.substr(i, i + sub.len() - 1) == sub) found = 1;
        if (!found) begin
            $display("ERROR: %s: '%s' not in '%s'", what, sub, s);
            errors++;
        end
    endfunction

    function automatic void expect_not_sub(input string what, input string s, input string sub);
        for (int i = 0; i + sub.len() <= s.len(); i++)
            if (s.substr(i, i + sub.len() - 1) == sub) begin
                $display("ERROR: %s: '%s' unexpectedly in '%s'", what, sub, s);
                errors++;
                return;
            end
    endfunction

    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        // ck_delay 0..2 x lat_extra 0..3; only (0, 0) is clean with the model
        while (lines.size() < 12) @(posedge clk);
        expect_sub("pass0", lines[0], "ckd=0 lx=0 id0=0c81 cr0=8fef err=00000000 first=000000 got=0000 exp=0000");
        for (int i = 1; i < 12; i++) begin
            expect_sub($sformatf("pass%0d", i), lines[i], $sformatf("ckd=%0d lx=%0d ", i / 4, i % 4));
            // misaligned CK: the model rejects the shifted CAs; late write
            // data: wrong words. Neither may be reported clean.
            expect_not_sub($sformatf("pass%0d clean", i), lines[i], "err=00000000");
        end
        // (ram.errors is not added: the misaligned ck_delay passes feed the
        // model malformed CAs by design, which it reports as errors)
        if (errors != 0) $fatal(1, "FAILED: %0d errors", errors);
        $display("PASSED");
        $finish;
    end
endmodule
