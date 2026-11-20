// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// N T1sPhy nodes on one behavioural mixing segment (t1s_bus), each on its
// own 100 MHz clock (+-ppm), with a MAC model each.
//   PLCA = 1: node 0 is the coordinator (node count N), every node sends
//             NFRAMES frames at the same time; there must be no physical
//             collision and every node must receive all frames of the others.
//   PLCA = 0: CSMA without collision detection, so the nodes send one after
//             the other (node 0 first, then node 1 ...).
`timescale 1ns/1ps
module t1s_link_body #(
    parameter int  N          = 2,
    parameter bit  PLCA       = 0,
    parameter bit  LEFT_FIRST = 1,
    parameter bit  RX_LEFT    = 1,     // receivers' configured order (with AUTO = 0)
    parameter bit  AUTO       = 0,
    parameter real PPM0       = 0.0,
    parameter real PPM1       = 0.0,
    parameter real PPM2       = 0.0,
    parameter real TAU        = 7.0,
    parameter real ATT        = 1.0,
    parameter real NOISE      = 0.0,
    parameter real TH         = 0.1,
    parameter int  TO         = 32,
    parameter int  NFRAMES    = 6,
    parameter bit  RUN        = 0,
    parameter bit  DEBUG      = 0
) ();
    localparam int SPC = 4;
    real ppm [3] = '{PPM0, PPM1, PPM2};

    logic [N-1:0] clk, tx_p, tx_n, tx_en;
    logic         rst = 1;
    logic [SPC-1:0] h [N];
    logic [SPC-1:0] l [N];
    int collisions;

    for (genvar i = 0; i < N; i++) begin : g_clk
        initial clk[i] = 0;
        always #(5.0 * (1.0 + ppm[i] / 1e6)) clk[i] = ~clk[i];
    end

    t1s_bus #(.N(N), .TAU(TAU), .ATT(ATT), .NOISE(NOISE), .TH(TH), .SPC(SPC)) bus (
        .tx_p(tx_p), .tx_n(tx_n), .tx_en(tx_en), .rx_clk(clk), .h(h), .l(l), .collisions(collisions));

    logic start = 0;
    int   nfr [N];
    int   sent [N], rx_good [N], rx_bad [N], rx_own [N];
    int   rx_from [N][8];
    logic [N-1:0] sync, bcn;
    logic [1:0] order [N];

    for (genvar i = 0; i < N; i++) begin : g_node
        logic       pending, tx_go, tx_req, m_tx_en, rx_valid, rx_er, rx_sof, rx_eof, rx_bad_w, rx_dv, rx_own_w;
        logic [3:0] txd, rx_data;
        T1sPhy #(.HALF(4), .SPC(SPC)) phy (
            .i_clk(clk[i]), .i_rst(rst),
            .i_h(h[i]), .i_l(l[i]), .o_tx_p(tx_p[i]), .o_tx_n(tx_n[i]), .o_tx_en(tx_en[i]), .o_pwm(),
            .i_th(10'd512), .i_left_first(i == 0 ? LEFT_FIRST : (AUTO ? LEFT_FIRST : RX_LEFT)),
            .i_auto(AUTO), .i_test(2'd0),
            .i_plca_en(PLCA), .i_plca_id(8'(i)), .i_plca_cnt(8'(N)), .i_plca_to(8'(TO)),
            .i_pending(pending), .o_tx_go(tx_go), .o_tx_req(tx_req), .i_tx_en(m_tx_en), .i_tx_er(1'b0),
            .i_txd(txd), .o_rx_valid(rx_valid), .o_rx_data(rx_data), .o_rx_er(rx_er), .o_rx_sof(rx_sof),
            .o_rx_eof(rx_eof), .o_rx_bad(rx_bad_w), .o_rx_dv(rx_dv), .o_rx_own(rx_own_w),
            .o_crs(), .o_tx_active(), .o_beacon_rx(), .o_beacon_end(), .o_commit(), .o_order(order[i]),
            .o_viol_pma(), .o_viol_pcs(), .o_plca_cur(), .o_plca_state(), .o_plca_sync(sync[i]),
            .o_plca_bcn(bcn[i]));
        t1s_mac_model #(.ID(i), .SEED(i + 1)) mac (
            .clk(clk[i]), .rst(rst), .nframes(nfr[i]), .start(start), .pending(pending), .tx_go(tx_go),
            .tx_req(tx_req), .tx_en(m_tx_en), .txd(txd), .rx_valid(rx_valid), .rx_data(rx_data), .rx_er(rx_er),
            .rx_sof(rx_sof), .rx_eof(rx_eof), .rx_bad(rx_bad_w), .rx_own(rx_own_w), .sent(sent[i]),
            .rx_good(rx_good[i]), .rx_badcnt(rx_bad[i]), .rx_owncnt(rx_own[i]), .rx_from(rx_from[i]));
        if (DEBUG) begin : g_dbg
            logic [2:0] st_d;
            logic [7:0] cur_d;
            logic       act_d, crs_d;
            always @(posedge clk[i]) begin
                st_d <= phy.o_plca_state; cur_d <= phy.o_plca_cur; act_d <= phy.o_tx_active; crs_d <= phy.o_crs;
                if (phy.o_plca_state != st_d || phy.o_plca_cur != cur_d)
                    $display("%t n%0d plca st %0d cur %0d pend %0d crs %0d act %0d", $realtime, i, phy.o_plca_state,
                             phy.o_plca_cur, pending, phy.o_crs, phy.o_tx_active);
                if (tx_go) $display("%t n%0d TX_GO", $realtime, i);
                if (phy.o_tx_active != act_d) $display("%t n%0d tx_active %0d", $realtime, i, phy.o_tx_active);
                if (phy.o_crs != crs_d) $display("%t n%0d crs %0d", $realtime, i, phy.o_crs);
                if (phy.u_pma_tx.o_sym_req && (phy.u_pma_tx.i_sym != 5'b11111 || phy.o_tx_active))
                    $display("%t n%0d sym %b pma_st %0d txen %0d", $realtime, i, phy.u_pma_tx.i_sym, phy.u_pma_tx.state, m_tx_en);
            end
        end
    end

    int errors = 0;
    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end else $display("ok: %s", what);
    endtask

    initial if (RUN) begin
        for (int i = 0; i < N; i++) nfr[i] = 0;
        repeat (10) @(posedge clk[0]);
        rst = 0;
        if (PLCA) begin
            // wait until the followers have seen a BEACON
            fork
                begin wait (&sync); end
                begin #200us; end
            join_any
            disable fork;
            check("PLCA synchronised", &sync);
            for (int i = 0; i < N; i++) nfr[i] = NFRAMES;
            @(posedge clk[0]); start = 1; repeat (2) @(posedge clk[0]); start = 0;
            fork
                begin
                    wait (rx_good[0] + rx_bad[0] >= (N - 1) * NFRAMES);
                    for (int i = 1; i < N; i++) wait (rx_good[i] + rx_bad[i] >= (N - 1) * NFRAMES);
                end
                begin #(NFRAMES * N * 200us + 1ms); end
            join_any
            disable fork;
        end else begin
            #20us;
            for (int s = 0; s < N; s++) begin
                for (int i = 0; i < N; i++) nfr[i] = (i == s) ? NFRAMES : 0;
                @(posedge clk[0]); start = 1; repeat (2) @(posedge clk[0]); start = 0;
                fork
                    begin wait (sent[s] >= NFRAMES); end
                    begin #(NFRAMES * 300us); end
                join_any
                disable fork;
                #50us;
            end
        end
        #50us;
        for (int i = 0; i < N; i++) begin
            $display("node %0d: sent %0d good %0d bad %0d own %0d order %b", i, sent[i], rx_good[i], rx_bad[i],
                     rx_own[i], order[i]);
            check($sformatf("node %0d sent all", i), sent[i] == NFRAMES);
            check($sformatf("node %0d no bad frames", i), rx_bad[i] == 0);
            for (int j = 0; j < N; j++) if (j != i)
                check($sformatf("node %0d got %0d frames from node %0d", i, rx_from[i][j], j),
                      rx_from[i][j] == NFRAMES);
        end
        $display("physical collisions: %0d", collisions);
        if (PLCA) check("no physical collision", collisions == 0);
        if (errors != 0) $fatal(1, "%0d errors", errors);
        $display("PASS");
        $finish;
    end
endmodule
