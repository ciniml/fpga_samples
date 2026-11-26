// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// tb_gb_scale: IspGbScale with a synthetic 1280x720 RAW10 frame (run_gb_scale.sh checks it with gb_scale_ref.py)
//   frame 0: black 16, gain 1.0, white balance 1.0; frame 1: black 0, gain 1.5, automatic white balance
//   (from frame 0), mirrored and flipped (CFA 3, BGGR). out/gb_scale.hex: per frame 14336 luma bytes,
//   then 14336 RGB565 words
`timescale 1ns/1ps
module tb_gb_scale;
    logic clk = 0, rst = 1;
    always #4 clk = ~clk;

    logic        we = 0;
    logic [8:0]  waddr = 0;
    logic [39:0] wdata = 0;
    logic [11:0] row = 0;
    logic [9:0]  black = 16;
    logic [15:0] gain = 16'h100;
    logic        mirror = 0, flip = 0, awb = 0;
    logic        o_we, o_frame;
    logic [13:0] o_wa;
    logic [7:0]  o_wd;
    logic [15:0] o_cwd, wb_r, wb_b;
    IspGbScale dut (
        .i_clk(clk), .i_rst(rst), .i_we(we), .i_waddr(waddr), .i_wdata(wdata), .i_row(row),
        .i_black(black), .i_cfa(2'd3), .i_gain(gain),
        .i_awb(awb), .i_wb_r(16'h0100), .i_wb_b(16'h0100), .i_mirror(mirror), .i_flip(flip),
        .o_we(o_we), .o_wa(o_wa), .o_wd(o_wd), .o_cwd(o_cwd), .o_frame(o_frame), .o_wb_r(wb_r), .o_wb_b(wb_b));

    function automatic logic [9:0] pix(input int x, input int y);
        return 10'(((x * 7 + y * 13) ^ (x * y)) & 10'h3FF);
    endfunction

    logic [7:0] fb [0:16383];
    logic [15:0] cfb [0:16383];
    int nwr = 0;
    always @(posedge clk) if (o_we) begin
        fb[o_wa] <= o_wd;
        cfb[o_wa] <= o_cwd;
        nwr <= nwr + 1;
    end

    int fo, errs = 0;
    logic frame_q;
    initial begin
        fo = $fopen("out/gb_scale.hex", "w");
        repeat (5) @(posedge clk);
        rst <= 0;
        for (int f = 0; f < 2; f++) begin
            if (f == 1) begin black <= 0; gain <= 16'h180; mirror <= 1; flip <= 1; awb <= 1; end
            for (int a = 0; a < 16384; a++) fb[a] = 8'h00;
            nwr = 0;
            frame_q = o_frame;
            for (int y = 0; y < 720; y++) begin
                for (int w = 0; w < 320; w++) begin
                    @(posedge clk);
                    we <= 1; waddr <= 9'(w); row <= 12'(y);
                    wdata <= {pix(w*4+3, y), pix(w*4+2, y), pix(w*4+1, y), pix(w*4, y)};
                    @(posedge clk); we <= 0;
                    if (w % 2) @(posedge clk);   // 2 or 3 clocks a word, as 2 bytes a clock give
                end
                repeat (20) @(posedge clk);
            end
            repeat (400) @(posedge clk);
            $display("frame %0d: %0d writes, frame toggle %0d, white balance R %04x B %04x", f, nwr, o_frame != frame_q, wb_r, wb_b);
            if (nwr != 14336 || o_frame == frame_q) errs++;
            for (int a = 0; a < 14336; a++) $fwrite(fo, "%02x\n", fb[a]);
            for (int a = 0; a < 14336; a++) $fwrite(fo, "%04x\n", cfb[a]);
        end
        $fclose(fo);
        if (errs) $display("TB FAIL (%0d)", errs);
        else $display("TB PASS");
        $finish;
    end
endmodule
