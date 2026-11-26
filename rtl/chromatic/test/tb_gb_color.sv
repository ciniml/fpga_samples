// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// tb_gb_color: GbColorQuant against gb_color_ref.py (make color)
//   col_in.hex: frame count, then 14336 RGB565 values per frame; col_out.hex: RAM 0x0100-0x11BF per frame
`timescale 1ns/1ps
module tb_gb_color;
    localparam int FB = 128 * 112;
    localparam int MAXF = 8;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic [15:0] in_mem [0:1 + MAXF * FB - 1];
    logic [15:0] fb [0:16383];
    logic [7:0]  ram [0:8191];
    logic        start = 0, busy, we;
    logic [13:0] ra;
    logic [15:0] rq;
    logic [12:0] wa;
    logic [7:0]  wd;
    always @(posedge clk) rq <= fb[ra];
    always @(posedge clk) if (we) ram[wa] <= wd;
    GbColorQuant dut (.i_clk(clk), .i_rst(rst), .i_start(start), .o_busy(busy), .o_ra(ra), .i_rq(rq),
                      .o_we(we), .o_wa(wa), .o_wd(wd));

    int fo, nf, t0;
    initial begin
        $readmemh("col_in.hex", in_mem);
        nf = in_mem[0];
        fo = $fopen("col_out.hex", "w");
        repeat (5) @(posedge clk);
        rst <= 0;
        for (int f = 0; f < nf; f++) begin
            for (int i = 0; i < FB; i++) fb[i] = in_mem[1 + f * FB + i];
            for (int a = 0; a < 8192; a++) ram[a] = 8'h55;
            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;
            t0 = $time;
            @(posedge clk);
            while (busy) @(posedge clk);
            repeat (4) @(posedge clk);
            $display("frame %0d: %0d us", f, ($time - t0) / 1000);
            for (int a = 'h100; a < 'h11C0; a++) $fwrite(fo, "%02x\n", ram[a]);
        end
        $fclose(fo);
        $display("TB PASS");
        $finish;
    end
endmodule
