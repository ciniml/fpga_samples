// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Two T1sPhy + T1sBringup nodes (PLCA off, periodic test frames) on t1s_bus.
// CLK_HZ is scaled down so that the 1 s send period and the 0.5 s status
// line come every few hundred microseconds. Node A's UART line is decoded
// and printed; both nodes must count the other's frames as good.
`timescale 1ns/1ps
module t1s_bringup_body #(
    parameter bit RUN = 0
) ();
    localparam int SPC    = 4;
    localparam int CLK_HZ = 400_000;     // scaled: tick_half every 200k clocks = 2 ms
    localparam int BAUD   = 20_000;      // DIV 20
    logic [1:0] clk;
    logic       rst = 1, rst_b = 1;    // B starts 1 ms later: the periodic frames do not overlap (CSMA, no CD)
    initial clk = 0;
    always #5.0 clk[0] = ~clk[0];
    always #5.0003 clk[1] = ~clk[1];

    logic [1:0] tx_p, tx_n, tx_en;
    logic [SPC-1:0] h [2];
    logic [SPC-1:0] l [2];
    int collisions;
    t1s_bus #(.N(2), .SPC(SPC)) bus (.tx_p(tx_p), .tx_n(tx_n), .tx_en(tx_en), .rx_clk(clk), .h(h), .l(l),
                                     .collisions(collisions));

    logic [1:0] utx;
    for (genvar i = 0; i < 2; i++) begin : g
        logic [9:0] th; logic lf, au, pe, pend, go, req, ten, rv, rer, rsof, reof, rbad, rown, crs, bcn, viol;
        logic [1:0] tm, order; logic [7:0] id, cnt, to; logic [3:0] txd, rd; logic [2:0] pst;
        T1sPhy #(.HALF(4), .SPC(SPC)) phy (
            .i_clk(clk[i]), .i_rst(i == 0 ? rst : rst_b), .i_h(h[i]), .i_l(l[i]), .o_tx_p(tx_p[i]), .o_tx_n(tx_n[i]),
            .o_tx_en(tx_en[i]), .o_pwm(), .i_th(th), .i_left_first(lf), .i_auto(au), .i_test(tm),
            .i_plca_en(pe), .i_plca_id(id), .i_plca_cnt(cnt), .i_plca_to(to), .i_pending(pend), .o_tx_go(go),
            .o_tx_req(req), .i_tx_en(ten), .i_tx_er(1'b0), .i_txd(txd), .o_rx_valid(rv), .o_rx_data(rd),
            .o_rx_er(rer), .o_rx_sof(rsof), .o_rx_eof(reof), .o_rx_bad(rbad), .o_rx_dv(), .o_rx_own(rown),
            .o_crs(crs), .o_tx_active(), .o_beacon_rx(), .o_beacon_end(), .o_commit(), .o_order(order),
            .o_viol_pma(viol), .o_viol_pcs(), .o_plca_cur(), .o_plca_state(pst), .o_plca_sync(), .o_plca_bcn(bcn));
        T1sBringup #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) bu (
            .i_clk(clk[i]), .i_rst(i == 0 ? rst : rst_b), .o_th(th), .o_left_first(lf), .o_auto(au), .o_test(tm), .o_plca_en(pe),
            .o_plca_id(id), .o_plca_cnt(cnt), .o_plca_to(to), .o_pending(pend), .i_tx_go(go), .i_tx_req(req),
            .o_tx_en(ten), .o_txd(txd), .i_rx_valid(rv), .i_rx_data(rd), .i_rx_er(rer), .i_rx_sof(rsof),
            .i_rx_eof(reof), .i_rx_bad(rbad), .i_rx_own(rown), .i_crs(crs), .i_beacon(bcn), .i_viol(viol),
            .i_order(order), .i_plca_state(pst), .o_led_rx(), .o_txd_u(utx[i]), .i_rxd_u(1'b1));
    end

    // UART decoder for node A (DIV clocks per bit)
    string line = "";
    int    nlines = 0;
    initial begin
        forever begin
            byte c;
            @(negedge utx[0]);
            repeat (10) @(posedge clk[0]);          // middle of the start bit
            for (int b = 0; b < 8; b++) begin
                repeat (20) @(posedge clk[0]);
                c[b] = utx[0];
            end
            repeat (20) @(posedge clk[0]);
            if (c == 8'h0a) begin
                $display("A uart: %s", line);
                line = "";
                nlines++;
            end else if (c != 8'h0d) line = {line, string'(c)};
        end
    end

    initial if (RUN) begin
        repeat (10) @(posedge clk[0]);
        rst = 0;
        #1ms;
        rst_b = 0;
        #14ms;
        $display("A good %0d bad %0d own %0d sent %0d / B good %0d bad %0d sent %0d", g[0].bu.rx_good, g[0].bu.rx_bad,
                 g[0].bu.rx_own, g[0].bu.tx_count, g[1].bu.rx_good, g[1].bu.rx_bad, g[1].bu.tx_count);
        if (!(g[1].bu.rx_good >= 3 && g[0].bu.rx_good >= 3 && g[0].bu.rx_bad == 0 && g[1].bu.rx_bad == 0
              && nlines >= 3))
            $fatal(1, "bring-up test failed");
        $display("PASS");
        $finish;
    end
endmodule
