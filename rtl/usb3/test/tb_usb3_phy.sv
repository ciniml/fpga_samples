// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Test of the soft USB 3.0 PHY datapath (test/run_phy.sh, Verilator --binary):
//  1. 8b/10b: every data byte and control symbol, both running disparities, through enc8b10b and
//     dec8b10b; known K28.5 forms; ones count of every symbol.
//  2. Loopback: Usb3PhyTx in the remote clock (the recovered clock rclk) -> a bit slip of SLIP bits
//     (and an inversion, undone by RxPolarity) -> Usb3PhyRx -> Usb3PhyEb -> pclk. The symbol stream
//     (counter bytes, COM every 64 symbols, a SKP pair every 40) must come out unchanged apart from
//     SKP pairs, with no decode / disparity error, with rclk faster (RPPM > 0) and slower than pclk.
`timescale 1ns / 1ps
module tb_usb3_phy;
    import usb3_phy_pkg::*;

    parameter int SLIP = 13;
    parameter int INV = 1;
    parameter int RPPM = 1000;   // remote clock offset against pclk, ppm (+: faster)

    // ------------------------------------------------------------------ 8b/10b
    task automatic check_codec();
        logic [10:0] e;
        logic [11:0] d;
        int nk, ones;
        logic [7:0] ks [12] = '{8'h1C, 8'h3C, 8'h5C, 8'h7C, 8'h9C, 8'hBC, 8'hDC, 8'hFC, 8'hF7, 8'hFB, 8'hFD, 8'hFE};
        for (int rd = 0; rd < 2; rd++) begin
            for (int v = 0; v < 256 + 12; v++) begin
                logic k; logic [7:0] b;
                k = v >= 256;
                b = k ? ks[v - 256] : v[7:0];
                e = enc8b10b(k, b, rd[0]);
                ones = $countones(e[9:0]);
                if (!(ones == 5 || (ones == 6 && rd == 0) || (ones == 4 && rd == 1)))
                    $fatal(1, "enc %s%02x rd%0d: %010b has %0d ones", k ? "K" : "D", b, rd, e[9:0], ones);
                if (e[10] != (ones == 5 ? rd[0] : !rd[0]))
                    $fatal(1, "enc %s%02x rd%0d: rd out %0d", k ? "K" : "D", b, rd, e[10]);
                d = dec8b10b(e[9:0], rd[0]);
                if (d[7:0] != b || d[8] != k || d[9] || d[10] || d[11] != e[10])
                    $fatal(1, "dec %s%02x rd%0d: sym %03x -> %03x", k ? "K" : "D", b, rd, e[9:0], d);
            end
        end
        // K28.5 (bit 0 = a): RD- 001111 1010, RD+ 110000 0101
        e = enc8b10b(1'b1, 8'hBC, 1'b0);
        if (e[9:0] != 10'h17C) $fatal(1, "K28.5 RD- = %03x", e[9:0]);
        e = enc8b10b(1'b1, 8'hBC, 1'b1);
        if (e[9:0] != 10'h283) $fatal(1, "K28.5 RD+ = %03x", e[9:0]);
        // D10.2 = 0101010101 -> 0x2AA
        e = enc8b10b(1'b0, 8'h4A, 1'b0);
        if (e[9:0] != 10'h2AA) $fatal(1, "D10.2 = %03x", e[9:0]);
        // an invalid code
        d = dec8b10b(10'h000, 1'b0);
        if (!d[9]) $fatal(1, "000 not a code error");
        $display("codec: ok");
    endtask

    // ------------------------------------------------------------------ loopback
    logic rclk = 0, pclk = 0, rst = 1;
    real rper = 8.0 * 1e6 / (1e6 + RPPM);
    always #(rper / 2) rclk = ~rclk;
    always #4 pclk = ~pclk;

    // remote transmitter (rclk): symbol stream generator
    int sidx = 0;
    logic [31:0] tdata;
    logic [3:0] tk;
    // payload symbol p: COM when p % 64 == 0, else data (p % 64) * 3 + 1 (period 64)
    function automatic logic [8:0] payload(int p);
        if (p % 64 == 0) return {1'b1, 8'hBC};
        return {1'b0, 8'((p % 64) * 3 + 1)};
    endfunction
    // line symbol n: 38 payload symbols then a SKP pair, repeated
    function automatic logic [8:0] gen_sym(int n);   // {k, byte}
        int m;
        m = n % 40;
        if (m == 38 || m == 39) return {1'b1, 8'h3C};
        return payload((n / 40) * 38 + m);
    endfunction
    always_comb
        for (int i = 0; i < 4; i++) {tk[i], tdata[i * 8 +: 8]} = gen_sym(sidx + i);
    always @(posedge rclk) if (!rst) sidx <= sidx + 4;

    logic [39:0] txd;
    Usb3PhyTx u_tx (.i_clk(rclk), .i_rst(rst), .i_data(tdata), .i_k(tk), .i_elecidle(1'b0), .i_detectrx(1'b0),
        .i_power_down(2'd0), .o_txdata(txd), .o_drive(), .o_lfps());
    // channel: slip by SLIP bits, optional inversion
    logic [79:0] ch = '0;
    always @(posedge rclk) ch <= {txd, ch[79:40]};
    wire [39:0] rxraw = ch[SLIP +: 40] ^ {40{INV[0]}};

    logic whigh, rv, rxv, locked;
    logic [31:0] rxd; logic [3:0] rxk; logic [2:0] rxst;
    logic [38:0] rdata;
    Usb3PhyRx u_rx (.i_clk(rclk), .i_rst(rst), .i_rxdata(rxraw), .i_valid(1'b1), .i_polarity(INV[0]), .i_drop(whigh),
        .o_valid(rxv), .o_data(rxd), .o_k(rxk), .o_status(rxst), .o_locked(locked));
    Usb3PhyEb u_eb (.i_wclk(rclk), .i_wrst(rst), .i_wv(rxv), .i_wdata({rxst, rxk, rxd}), .o_whigh(whigh),
        .i_rclk(pclk), .i_rrst(rst), .i_run(1'b1), .o_rv(rv), .o_rdata(rdata));

    // checker (pclk): the payload without SKPs, synchronised on the first COM
    int exp_p = -1, got = 0, gaps = 0, drops = 0, errs = 0;
    always @(posedge pclk) begin
        if (rv) begin
            if (exp_p >= 0 && (rdata[38:36] == 3'd4 || rdata[38:36] == 3'd7)) errs++;   // (before: RD unknown)
            if (rdata[38:36] == 3'd2) drops++;
            for (int i = 0; i < 4; i++) begin
                logic [8:0] s;
                s = {rdata[32 + i], rdata[i * 8 +: 8]};
                if (s == {1'b1, 8'h3C}) continue;
                if (exp_p < 0) begin
                    if (s == {1'b1, 8'hBC}) exp_p = 1;
                    continue;
                end
                if (s != payload(exp_p))
                    $fatal(1, "symbol %0d: got %03x, expected %03x (payload %0d)", got, s, payload(exp_p), exp_p);
                exp_p++;
                got++;
            end
        end else if (exp_p >= 0) gaps++;
    end

    initial begin
        check_codec();
        repeat (10) @(negedge pclk);
        rst = 0;
        repeat (40000) @(negedge pclk);
        $display("RPPM=%0d: got %0d, errs %0d, drops %0d, gaps %0d", RPPM, got, errs, drops, gaps);
        if (got < 100000) $fatal(1, "only %0d symbols checked", got);
        if (errs) $fatal(1, "%0d words with code / disparity errors", errs);
        if (RPPM > 0 && drops == 0) $fatal(1, "rclk faster but no SKP pair removed");
        if (RPPM < 0 && gaps == 0) $fatal(1, "rclk slower but no gap inserted");
        $display("loopback SLIP=%0d INV=%0d RPPM=%0d: %0d symbols ok, %0d SKP pairs removed, %0d gap clocks",
                 SLIP, INV, RPPM, got, drops, gaps);
        $finish;
    end
endmodule
