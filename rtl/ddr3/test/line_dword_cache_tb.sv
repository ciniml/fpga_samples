// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// LineDwordCache + Ddr3Ctrl + behavioural DDR3 model: the NVMe core's
// dword RAM contract (request held until o_ready, data the cycle after)
// driven with block-sequential and random traffic against a reference
// array. Prints cycles per line miss for the README.
`default_nettype none
module line_dword_cache_tb;
    localparam int ADDR_BITS  = 25;
    localparam int LINE_BYTES = 512;
    localparam int LINE_DW    = LINE_BYTES / 4;

    logic clk  = 0;   // "50MHz" user / controller CPU clock
    logic pclk = 0;   // DDR3 pclk (CK / 2)
    logic rst  = 1;
    logic prst = 1;
    always #10 clk  = ~clk;
    always #7  pclk = ~pclk;

    LineBusIf line();
    BusIf     ctl();

    // ---- cache user side ----
    logic [ADDR_BITS-1:0] addr;
    logic                 wen, ren, ready;
    logic [31:0]          wdata, rdata;
    logic [2:0]           dbg;

    LineDwordCache #(.ADDR_BITS(ADDR_BITS), .LINE_BYTES(LINE_BYTES)) cache (
        .i_clk(clk), .i_rst(rst),
        .i_addr(addr), .i_wen(wen), .i_wdata(wdata), .i_ren(ren),
        .o_rdata(rdata), .o_ready(ready), .o_dbg(dbg),
        .line(line)
    );

    // ---- controller + DRAM model (as in riscv-veryl tb_ddr3) ----
    logic         reset_n, cke, odt, cs_n, ras_n, cas_n, we_n;
    logic [2:0]   ba;
    logic [13:0]  a;
    logic [127:0] dq_out, dq_in;
    logic [3:0]   dq_oe, dqs_oe;
    logic [15:0]  dm_out, dqs_out, dqs_in;
    logic         init_done, model_init_done;
    int           model_errors, ref_count;

    Ddr3Ctrl ctrl (
        .i_clk_cpu(clk), .i_rst_cpu(rst),
        .i_clk_mem(pclk), .i_rst_mem(prst),
        .bus(line), .ctl(ctl),
        .o_reset_n(reset_n), .o_cke(cke), .o_odt(odt),
        .o_cs_n(cs_n), .o_ras_n(ras_n), .o_cas_n(cas_n), .o_we_n(we_n),
        .o_ba(ba), .o_a(a),
        .o_dq_out(dq_out), .o_dq_oe(dq_oe), .o_dm_out(dm_out),
        .o_dqs_out(dqs_out), .o_dqs_oe(dqs_oe),
        .i_dq_in(dq_in), .i_dqs_in(dqs_in),
        .o_init_done(init_done)
    );

    ddr3_model model (
        .clk(pclk), .rst(prst), .rd_delay_slots(3'd0), .rd_odd_shift(1'b0),
        .reset_n(reset_n), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .ba(ba), .a(a),
        .dq_out(dq_out), .dq_oe(dq_oe), .dm_out(dm_out), .dqs_out(dqs_out), .dqs_oe(dqs_oe),
        .dq_in(dq_in), .dqs_in(dqs_in),
        .errors(model_errors), .ref_count(ref_count), .init_done(model_init_done)
    );

    initial begin
        ctl.valid = 0; ctl.addr = 0; ctl.we = 0; ctl.wstrb = 0; ctl.wdata = 0;
    end

    // ---- NVMe-core-like requester: hold the request until ready ----
    logic                 op_valid = 0, op_we = 0, op_done = 0, pend_rd = 0;
    logic [ADDR_BITS-1:0] op_addr = 0;
    logic [31:0]          op_wdata = 0, op_rdata = 0;
    assign wen   = op_valid && op_we;
    assign ren   = op_valid && !op_we;
    assign addr  = op_addr;
    assign wdata = op_wdata;

    always @(posedge clk) begin
        op_done <= 0;
        if (pend_rd) begin
            pend_rd  <= 0;
            op_rdata <= rdata;   // valid the cycle after the accepted read
            op_done  <= 1;
        end
        if (op_valid && ready) begin
            op_valid <= 0;
            if (op_we) op_done <= 1;
            else       pend_rd <= 1;
        end
    end

    task automatic access(input logic we, input logic [ADDR_BITS-1:0] a_, input logic [31:0] d, output logic [31:0] r);
        @(posedge clk);
        op_we <= we; op_addr <= a_; op_wdata <= d; op_valid <= 1;
        wait (op_done);
        r = op_rdata;
        @(posedge clk);
    endtask

    // ---- profiling ----
    longint cyc = 0, busy_cyc = 0, misses = 0;
    logic   busy_q = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        busy_q <= dbg[0];
        if (dbg[0]) busy_cyc <= busy_cyc + 1;
        if (dbg[0] && !busy_q) misses <= misses + 1;
    end

    // ---- reference ----
    logic [31:0] ref_mem [int];
    int errors = 0;

    function automatic logic [31:0] pat(input int blk, input int i, input int seed);
        return (blk * 32'h0101_0101) ^ (i * 32'h0001_0003) ^ (seed * 32'h9E37_79B9);
    endfunction

    task automatic write_block(input int blk, input int seed);
        logic [31:0] r;
        for (int i = 0; i < LINE_DW; i++) begin
            access(1, blk * LINE_DW + i, pat(blk, i, seed), r);
            ref_mem[blk * LINE_DW + i] = pat(blk, i, seed);
        end
    endtask

    task automatic check_block(input int blk);
        logic [31:0] r;
        for (int i = 0; i < LINE_DW; i++) begin
            access(0, blk * LINE_DW + i, 0, r);
            if (r !== ref_mem[blk * LINE_DW + i]) begin
                errors++;
                if (errors < 10)
                    $display("MISMATCH blk=%0d i=%0d got=%08x exp=%08x", blk, i, r, ref_mem[blk * LINE_DW + i]);
            end
        end
    endtask

    int top_blk;
    initial begin
        top_blk = (1 << (ADDR_BITS - 7)) - 2; // second-to-last block (last 16B is the cal scratch)
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge pclk);
        prst = 0;
        // DRAM initialisation (700us of reset/CKE timing + MRS + ZQ + calibration)
        for (int t = 0; t < 5_000_000; t++) begin
            @(posedge clk);
            if (init_done) break;
        end
        if (!init_done) $fatal(1, "DDR3 init timeout");
        $display("DDR3 init done at %0t (model errors=%0d)", $time, model_errors);
        repeat (20) @(posedge clk);

        // phase A: block-sequential, like the NVMe core
        $display("phase A: sequential blocks");
        for (int b = 0; b < 8; b++) write_block(b, 1);
        write_block(top_blk, 1);
        for (int b = 0; b < 8; b++) check_block(b);
        check_block(top_blk);
        // overwrite (dirty write-back) and re-check
        for (int b = 0; b < 8; b += 2) write_block(b, 2);
        for (int b = 0; b < 8; b++) check_block(b);
        check_block(top_blk);

        // phase B: random dwords across four lines (thrash)
        $display("phase B: random dwords");
        for (int n = 0; n < 400; n++) begin
            int blk = $urandom_range(0, 3);
            int i   = $urandom_range(0, LINE_DW - 1);
            logic [31:0] r;
            if ($urandom_range(0, 1)) begin
                access(1, blk * LINE_DW + i, $urandom, r);
                ref_mem[blk * LINE_DW + i] = op_wdata;
            end else begin
                access(0, blk * LINE_DW + i, 0, r);
                if (r !== ref_mem[blk * LINE_DW + i]) begin
                    errors++;
                    if (errors < 10) $display("MISMATCH(rand) blk=%0d i=%0d got=%08x exp=%08x", blk, i, r, ref_mem[blk * LINE_DW + i]);
                end
            end
        end
        for (int b = 0; b < 4; b++) check_block(b);

        $display("PROF line=%0dB misses=%0d busy_cycles=%0d (%.1f cyc/miss) model_errors=%0d",
                 LINE_BYTES, misses, busy_cyc, misses ? real'(busy_cyc) / real'(misses) : 0.0, model_errors);
        if (errors != 0 || model_errors != 0) $fatal(1, "FAIL: %0d data errors, %0d model errors", errors, model_errors);
        $display("PASS: line_dword_cache");
        $finish;
    end
endmodule
`default_nettype wire
