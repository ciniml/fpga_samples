// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tb_hub75_crop.sv
 * @brief Video -> crop_to_hub75 -> async FIFO -> Hub75 -> HUB75 panel model.
 *
 *   The panel model shifts R1G1B1 / R2G2B2 on CLK rising edges into
 *   CHAIN_LEN-long registers, latches them on LAT, and while OE is low
 *   adds (bit x OE cycles) to the row given by A..E (R1 lane: electrical
 *   row r, R2 lane: r + 32). Over one full refresh the sum divided by the
 *   LSB-plane OE length is the displayed 5-bit component.
 *
 *   Electrical -> display: ex = shift position (first pixel shifted = 0),
 *   the second 64-row band sits to the right in the chain:
 *     x = ex % DISP_W, y = (ex / DISP_W) * 64 + ey.
 *
 *   Checks every displayed pixel against the source's top-left
 *   DISP_W x DISP_H, then switches the source picture and checks that the
 *   panel shows the new picture completely (double buffer, no mixing).
 */
`timescale 1ns/1ps
`default_nettype none
module tb_hub75_crop;
`ifndef DISP_W
`define DISP_W 128
`endif
`ifndef DISP_H
`define DISP_H 128
`endif
    localparam int DISP_W = `DISP_W;
    localparam int DISP_H = `DISP_H;
    localparam int CB     = 5;
    localparam int CHAIN_LEN = DISP_W * DISP_H / 64;
    localparam int X_BITS    = $clog2(CHAIN_LEN);
    localparam int ADDR_BITS = 1 + 5 + X_BITS;
    localparam int CMD_BITS  = 1 + ADDR_BITS + 3 * CB;
    localparam int BASE_OE   = 16;
    localparam int LSB_OE    = 2 * BASE_OE;

    // Source raster (small; the crop only needs >= DISP_W x DISP_H)
    localparam int H_ACT = 160, H_TOT = 200, V_ACT = 140, V_TOT = 150;

    logic pclk = 0, clock = 0;
    always #6.7 pclk = ~pclk;      // ~74.6 MHz
    always #10  clock = ~clock;    // 50 MHz
    logic reset = 1;

    // ---------------- source ----------------
    logic [11:0] hc = 0, vc = 0;
    logic        pattern = 0;       // 0: picture A, 1: picture B
    logic [23:0] vdata;
    logic        vde, vvs;
    function automatic logic [14:0] pic(input logic sel, input int x, input int y);
        logic [4:0] r, g, b;
        if (!sel) begin
            r = 5'(x) ^ 5'(y >> 2);
            g = 5'(y) + 5'(x >> 5);
            b = 5'(x + y);
        end else begin
            r = ~(5'(x * 3) ^ 5'(y));
            g = 5'(x >> 2) ^ 5'(y * 7);
            b = 5'(y >> 2) + 5'(x);
        end
        return {r, g, b};
    endfunction
    always_ff @(posedge pclk) begin
        logic [14:0] p;
        hc <= (hc == H_TOT - 1) ? 12'd0 : hc + 1'd1;
        if (hc == H_TOT - 1) vc <= (vc == V_TOT - 1) ? 12'd0 : vc + 1'd1;
        vde  <= hc < H_ACT && vc < V_ACT;
        vvs  <= vc >= V_TOT - 2;
        p     = pic(pattern, hc, vc);
        // 8-bit channels whose top 5 bits are the picture (low bits noise)
        vdata <= {p[14:10], 3'(hc), p[9:5], 3'(vc), p[4:0], 3'(hc ^ vc)};
    end

    // ---------------- DUT chain ----------------
    logic                cmd_wen, skipped;
    logic [CMD_BITS-1:0] cmd;
    logic                flip_pending;
    logic       lut_init = 0, lut_we = 0, lut_busy;
    logic [2:0] lut_mask = 0;
    logic [7:0] lut_addr = 0, lut_data = 0;
    crop_to_hub75 #(.DISP_W(DISP_W), .DISP_H(DISP_H), .COMPONENT_BITS(CB)) u_crop (
        .i_pclk(pclk), .i_reset(reset), .i_valid(1'b1), .i_de(vde), .i_vsync(vvs),
        .i_data(vdata), .i_flip_pending(flip_pending),
        .o_cmd_wen(cmd_wen), .o_cmd(cmd), .o_frame_skipped(skipped),
        .i_clk(clock), .i_rst(reset), .i_lut_init(lut_init), .i_lut_we(lut_we),
        .i_lut_mask(lut_mask), .i_lut_addr(lut_addr), .i_lut_data(lut_data), .o_lut_busy(lut_busy));

    // ---------------- colour tables (reference copy) ----------------
    logic [7:0] ref_lut [0:2][0:255];     // [R, G, B]
    task automatic set_identity();
        for (int c = 0; c < 3; c++) for (int i = 0; i < 256; i++) ref_lut[c][i] = 8'(i);
    endtask
    task automatic lut_write_all(input int c);  // copy ref_lut[c] into the hardware
        for (int i = 0; i < 256; i++) begin
            @(negedge clock);
            lut_we = 1; lut_mask = 3'(1 << c); lut_addr = 8'(i); lut_data = ref_lut[c][i];
        end
        @(negedge clock) lut_we = 0;
    endtask
    // the 8-bit source channel of pixel (x, y) (the picture's 5 bits + noise)
    function automatic logic [7:0] src8(input logic sel, input int x, input int y, input int c);
        logic [14:0] p;
        p = pic(sel, x, y);
        case (c)
            0: return {p[14:10], 3'(x)};
            1: return {p[9:5], 3'(y)};
            default: return {p[4:0], 3'(x ^ y)};
        endcase
    endfunction

    logic                rd_empty, rd_valid = 0, full;
    logic [CMD_BITS-1:0] rd_cmd;
    wire                 rd_en = !rd_empty;
    async_fifo #(.WIDTH(CMD_BITS), .DEPTH_BITS(6)) u_fifo (
        .i_wr_clk(pclk), .i_wr_rst(reset), .i_wr_en(cmd_wen), .i_wr_data(cmd), .o_wr_full(full),
        .i_rd_clk(clock), .i_rd_rst(reset), .i_rd_en(rd_en), .o_rd_data(rd_cmd), .o_rd_empty(rd_empty));
    always_ff @(posedge clock) rd_valid <= rd_en;
    int overflow = 0;
    always_ff @(posedge pclk) if (cmd_wen && full) overflow <= overflow + 1;

    logic ra, rb, rc, rd, re, r0, g0, b0, r1, g1, b1, oe, lat, hclk;
    Hub75 #(.PANEL_WIDTH(64), .PANEL_HEIGHT(64), .NUM_CHAINED(CHAIN_LEN / 64),
            .CLOCK_DIVIDER(1), .COMPONENT_BITS(CB), .BASE_OE_CYCLES(BASE_OE)) u_hub75 (
        .i_clk(clock), .i_rst(reset),
        .i_px_wen(rd_valid && !rd_cmd[CMD_BITS-1]),
        .i_px_addr(rd_cmd[CMD_BITS-2 -: ADDR_BITS]),
        .i_px_data(rd_cmd[3*CB-1:0]),
        .i_flip_req(rd_valid && rd_cmd[CMD_BITS-1]),
        .o_flip_pending(flip_pending),
        .o_row_a(ra), .o_row_b(rb), .o_row_c(rc), .o_row_d(rd), .o_row_e(re),
        .o_r0(r0), .o_g0(g0), .o_b0(b0), .o_r1(r1), .o_g1(g1), .o_b1(b1),
        .o_oe(oe), .o_lat(lat), .o_clk(hclk));

    // ---------------- panel model ----------------
    logic [5:0] sr    [0:CHAIN_LEN-1];   // {r0,g0,b0,r1,g1,b1} per shift position
    logic [5:0] latch [0:CHAIN_LEN-1];
    int unsigned acc [0:63][0:CHAIN_LEN-1][0:2];   // [ey][ex][rgb]
    bit   collecting = 0;
    int   oe_len = 0;
    logic [4:0] row;
    always @(posedge hclk) begin
        for (int i = CHAIN_LEN - 1; i > 0; i--) sr[i] = sr[i - 1];
        sr[0] = {r0, g0, b0, r1, g1, b1};
    end
    // Timing rules that make edge-triggered and transparent (LAT-high)
    // latches behave the same: no shift clock while LAT is high, and
    // neither LAT nor the shift clock while OE is active.
    int rule_errors = 0;
    // (not during the FM6126A init sequences, which clock with LAT high
    //  on purpose to write the driver's registers)
    wire scanning = !reset && u_hub75.state >= 3;
    always @(posedge hclk) if (scanning && (lat || !oe)) rule_errors++;
    always @(posedge lat)  if (scanning && !oe) rule_errors++;
    always @(posedge lat) begin
        // ex = position counted from the first shifted pixel
        for (int ex = 0; ex < CHAIN_LEN; ex++) latch[ex] = sr[CHAIN_LEN - 1 - ex];
    end
    always @(posedge clock) begin
        if (!oe) begin
            oe_len <= oe_len + 1;
            row    <= {re, rd, rc, rb, ra};
        end else if (oe_len != 0) begin
            if (collecting) begin
                for (int ex = 0; ex < CHAIN_LEN; ex++) begin
                    for (int c = 0; c < 3; c++) begin
                        acc[row][ex][c]      += latch[ex][5 - c] ? oe_len : 0;
                        acc[row + 32][ex][c] += latch[ex][2 - c] ? oe_len : 0;
                    end
                end
            end
            oe_len <= 0;
        end
    end

    // Refresh boundaries: row address returning to 0 after 31.
    int refreshes = 0;
    logic [4:0] last_row = 0;
    always @(posedge clock) begin
        if (!oe) begin
            if (last_row == 31 && {re, rd, rc, rb, ra} == 0) refreshes <= refreshes + 1;
            last_row <= {re, rd, rc, rb, ra};
        end
    end

    task automatic wait_refreshes(input int n);
        int start;
        start = refreshes;
        while (refreshes < start + n) @(posedge clock);
    endtask

    int errors = 0;
    task automatic check_picture(input logic sel, input string what);
        int bad;
        bad = 0;
        // one complete refresh
        for (int y = 0; y < 64; y++)
            for (int x = 0; x < CHAIN_LEN; x++)
                for (int c = 0; c < 3; c++) acc[y][x][c] = 0;
        wait_refreshes(1);
        collecting = 1;
        wait_refreshes(1);
        collecting = 0;
        for (int ey = 0; ey < 64; ey++) begin
            for (int ex = 0; ex < CHAIN_LEN; ex++) begin
                int x, y;

                x = ex % DISP_W;
                y = (ex / DISP_W) * 64 + ey;
                for (int c = 0; c < 3; c++) begin
                    int got, want;
                    got  = acc[ey][ex][c] / LSB_OE;
                    want = ref_lut[c][src8(sel, x, y, c)] >> (8 - CB);
                    if (acc[ey][ex][c] % LSB_OE != 0 || got != want) begin
                        bad++;
                        if (bad <= 8)
                            $display("[tb_hub75] %s: (x=%0d,y=%0d) ch%0d got %0d (acc %0d) want %0d",
                                     what, x, y, c, got, acc[ey][ex][c], want);
                    end
                end
            end
        end
        if (bad != 0) begin
            errors += bad;
            $display("[tb_hub75] %s: %0d wrong components", what, bad);
        end else begin
            $display("[tb_hub75] %s: all %0d pixels correct", what, DISP_W * DISP_H);
        end
    endtask

    int skips = 0;
    always @(posedge pclk) if (skipped) skips++;

    initial begin
        set_identity();
        repeat (20) @(posedge clock);
        reset = 0;
        // first picture: wait until a frame has been written and flipped in
        wait_refreshes(3);
        check_picture(0, "picture A");
        // switch the source; the panel must end up showing only picture B
        @(posedge pclk) pattern = 1;
        wait_refreshes(3);
        check_picture(1, "picture B");

        // colour tables: R inverted, G gamma 2.2, B identity (all 8 input
        // bits matter, not only the top 5)
        for (int i = 0; i < 256; i++) begin
            ref_lut[0][i] = 8'(255 - i);
            ref_lut[1][i] = 8'($rtoi(255.0 * ((real'(i) / 255.0) ** 2.2) + 0.5));
        end
        lut_write_all(0);
        lut_write_all(1);
        wait_refreshes(3);
        check_picture(1, "picture B, tables R inv / G gamma 2.2");

        // back to identity
        @(negedge clock) lut_init = 1;
        @(negedge clock) lut_init = 0;
        set_identity();
        wait (!lut_busy);
        wait_refreshes(3);
        check_picture(1, "picture B, tables reset to identity");
        if (rule_errors != 0) begin
            errors++;
            $display("[tb_hub75] %0d CLK/LAT/OE timing-rule violations", rule_errors);
        end
        if (overflow != 0) begin
            errors++;
            $display("[tb_hub75] FIFO overflow x%0d", overflow);
        end
        $display("[tb_hub75] %0dx%0d chain %0d: %0d skipped source frames (flip still pending)",
                 DISP_W, DISP_H, CHAIN_LEN, skips);
        if (errors != 0) $fatal(1, "[tb_hub75] FAIL (%0d errors)", errors);
        $display("[tb_hub75] PASS");
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "[tb_hub75] timeout");
    end
endmodule
`default_nettype wire
