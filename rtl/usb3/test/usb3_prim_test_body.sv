// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Unit tests for usb3_pkg helpers and Usb3Scrambler. Expected values come
// from test/usb3_ref.py (checked against the USB 3.2 Appendix B tables,
// zlib.crc32 and the spec residuals).
`timescale 1ns/1ps
// RUN: Verilator runs every test body of include_files as an implicit top in every test, so the
// body only acts when instantiated with RUN = 1 (TbUsb3Prim's test wrappers); it ends with $finish
// on success, $fatal on failure (veryl test counts a $finish as success)
module usb3_prim_test_body #(parameter bit RUN = 0);
    import usb3_pkg::*;
    logic clk = 0;
    logic rst = 1;
    always #4 clk = ~clk;

    logic        s_valid, s_bypass;
    logic [31:0] s_in, s_out;
    logic [3:0]  s_k;
    logic [15:0] s_lfsr;
    Usb3Scrambler dut(.i_clk(clk), .i_rst(rst), .i_valid(s_valid), .i_bypass(s_bypass),
                      .i_data(s_in), .i_k(s_k), .o_data(s_out), .o_lfsr(s_lfsr));

    int errors = 0;
    task automatic check(string what, logic [31:0] got, logic [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %s: got %08x exp %08x", what, got, exp);
            errors++;
        end
    endtask

    logic [15:0] c16;
    logic [31:0] c32;
    logic [7:0]  hdr[12];
    initial if (RUN) begin
        // ---- LFSR table (Appendix B): FFFF -> E817 -> 0328 -> 284B
        check("adv1", lfsr_adv8(16'hFFFF), 16'hE817);
        check("adv2", lfsr_adv8(16'hE817), 16'h0328);
        check("adv3", lfsr_adv8(16'h0328), 16'h284B);
        check("mask", lfsr_mask(16'hFFFF), 8'hFF);
        check("mask2", lfsr_mask(16'hE817), 8'h17);   // bits 15..8 reversed: E8 -> 17

        // ---- CRC-16 over 12 header bytes 10h..1Bh -> 0EC5h
        c16 = 16'hFFFF;
        for (int i = 0; i < 12; i++) c16 = crc16_byte(c16, 8'h10 + i);
        check("crc16", {16'h0, ~c16}, 16'h0EC5);
        // residual: feed the field bytes too -> ~reg == 0 is not the rule; check
        // against the reference by recomputing: reg after field = reflected F6AA.
        c16 = crc16_byte(c16, 8'hC5); c16 = crc16_byte(c16, 8'h0E);
        check("crc16 residual", c16, 16'h556F);   // bitrev16(F6AA)
        c16 = 16'hFFFF; c16 = crc16_byte(c16, 8'h04);
        for (int i = 0; i < 11; i++) c16 = crc16_byte(c16, 8'h00);
        check("crc16 b", {16'h0, ~c16}, 16'h533F);

        // ---- CRC-32: empty -> 0, "abc" -> 352441C2, 0..36 -> 8222EFE9
        check("crc32 empty", ~32'hFFFFFFFF, 32'h00000000);
        c32 = 32'hFFFFFFFF;
        c32 = crc32_byte(c32, "a"); c32 = crc32_byte(c32, "b"); c32 = crc32_byte(c32, "c");
        check("crc32 abc", ~c32, 32'h352441C2);
        c32 = 32'hFFFFFFFF;
        for (int i = 0; i < 37; i++) c32 = crc32_byte(c32, i);
        check("crc32 0..36", ~c32, 32'h8222EFE9);
        // residual after the little-endian field: reflected C704DD7B = DEBB20E3
        c32 = crc32_byte(c32, 8'hE9); c32 = crc32_byte(c32, 8'hEF);
        c32 = crc32_byte(c32, 8'h22); c32 = crc32_byte(c32, 8'h82);
        check("crc32 residual", c32, 32'hDEBB20E3);

        // ---- CRC-5 / link control words: seq0 -> 1000h, seq1 -> E801h, seq7 -> 6807h
        check("lcw0", lcw_make(11'h000), 16'h1000);
        check("lcw1", lcw_make(11'h001), 16'hE801);
        check("lcw7", lcw_make(11'h007), 16'h6807);
        check("lcw_ok", {31'h0, lcw_ok(16'hE801)}, 1);
        check("lcw_bad", {31'h0, lcw_ok(16'hE800)}, 0);

        // ---- scrambler: COM resets; zeros -> FF 17 C0 14; SKP SKP pass and do
        // not advance; then B2, E7 02; SHP (K) advances (eats 82); 0x55 ^ 72 -> 0x27
        s_valid = 0; s_bypass = 0; s_in = 0; s_k = 0;
        repeat (2) @(posedge clk); @(negedge clk); rst = 0; @(posedge clk);
        s_in = {8'h00, 8'h00, 8'h00, K_COM}; s_k = 4'b0001; s_valid = 1; #1;
        check("scr w0", s_out, {8'hC0, 8'h17, 8'hFF, K_COM});
        @(posedge clk); #1;
        s_in = {8'h00, K_SKP, K_SKP, 8'h00}; s_k = 4'b0110; #1;
        check("scr w1", s_out, {8'hB2, K_SKP, K_SKP, 8'h14});
        @(posedge clk); #1;
        s_in = {8'h55, K_SHP, 8'h00, 8'h00}; s_k = 4'b0100; #1;
        check("scr w2", s_out, {8'h27, K_SHP, 8'h02, 8'hE7});
        @(posedge clk); #1;
        // bypass: D-codes pass through, LFSR still advances
        s_bypass = 1; s_in = 32'h11223344; s_k = 0; #1;
        check("scr bypass", s_out, 32'h11223344);
        @(posedge clk); #1;
        s_bypass = 0; s_valid = 0;
        // descrambling the scrambled zeros with a second COM-synced run gives zeros
        s_in = {8'hC0, 8'h17, 8'hFF, K_COM}; s_k = 4'b0001; s_valid = 1; #1;
        check("descr", s_out, {24'h0, K_COM});
        @(posedge clk);

        if (errors == 0) begin $display("PASS usb3_prim"); $finish; end
        else $fatal(1, "FAIL usb3_prim: %0d errors", errors);
        $finish;
    end
endmodule
