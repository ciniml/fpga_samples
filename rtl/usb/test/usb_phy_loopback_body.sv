// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Shared PHY loopback test body (see tb_usb_phy.veryl / tb_ulpi.veryl).
// ULPI=0: host BFM <-> UsbPhy (UTMI). ULPI=1: UTMI -> UlpiLink -> UlpiPhy.
`timescale 1ns/1ps
module usb_phy_loopback_body #(parameter HS = 0, parameter LS = 0, parameter ULPI = 0, parameter W = 8, parameter RUN = 0);
    logic clk = 0;
    logic rst = 1;
    always #8.333 clk = ~clk;
    // W = 4: the PHY runs on clk2 (120 MHz, 4 line samples per clock) behind UsbPhyBridge; the
    // BFM keeps its 8-sample / 60 MHz view, the adapters below split / merge the samples.
    // clk2 rises 50 ps after every clk edge and again half a clk period later, so the BFM's
    // clk-edge view of the adapter outputs is race-free and the phase never drifts.
    logic clk2 = 0;
    always @(clk) begin #0.05 clk2 = 1; #4.1 clk2 = 0; end

    logic [7:0] utmi_data_out, utmi_data_in;
    logic utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror;
    logic [1:0] utmi_linestate, utmi_opmode, utmi_xcvr;
    logic utmi_termsel;
    logic [7:0] rx_dp, rx_dn, tx_dp, tx_dn;
    logic tx_oe;
    logic pu_dp, pu_dn, term_dp, term_dn;

    generate if (ULPI == 0 && W == 4) begin : g_utmi_w4
        // ph = 1 in the clk2 cycle that ends on a clk edge: a clk2 toggle captured by the clk edge
        // (both paths are full-cycle, no same-edge race; the same scheme is used on the FPGA)
        logic ph, tp = 0, tp_c = 0;
        always @(posedge clk2) tp <= ~tp;
        always @(posedge clk) tp_c <= tp;
        assign ph = tp == tp_c;
        logic [3:0] rx4_dp, rx4_dn, tx4_dp, tx4_dn; logic tx4_oe;
        // The BFM word changes on the clk edge, 50 ps before the clk2 edge that ends the ph cycle:
        // latch it there so both clk2 cycles of the next word see the same word.
        logic [7:0] rx_w_dp, rx_w_dn;
        always @(posedge clk2) if (ph) begin rx_w_dp <= rx_dp; rx_w_dn <= rx_dn; end
        assign rx4_dp = ph ? rx_w_dp[7:4] : rx_w_dp[3:0];
        assign rx4_dn = ph ? rx_w_dn[7:4] : rx_w_dn[3:0];
        // The BFM sees 8-sample words with one enable: when the PHY's enable rises or falls in the
        // middle of such a word, fill the undriven half with the bus idle level (SE0 in HS, J in FS/LS)
        // and report the word as driven, as the terminated bus would look.
        logic [3:0] lo_dp, lo_dn, idle_dp, idle_dn; logic lo_oe, oe4;
        assign oe4 = tx4_oe;
        assign idle_dp = (utmi_xcvr == 2'b00) ? 4'h0 : (utmi_xcvr == 2'b10 ? 4'h0 : 4'hF);   // HS: SE0, LS: J = D- high, FS: J = D+ high
        assign idle_dn = (utmi_xcvr == 2'b00) ? 4'h0 : (utmi_xcvr == 2'b10 ? 4'hF : 4'h0);
        always @(posedge clk2) if (!ph) begin lo_dp <= oe4 ? tx4_dp : idle_dp; lo_dn <= oe4 ? tx4_dn : idle_dn; lo_oe <= oe4; end
        assign tx_dp = {oe4 ? tx4_dp : idle_dp, lo_dp};   // sampled by the BFM on the clk edge (ph = 1 cycle end)
        assign tx_dn = {oe4 ? tx4_dn : idle_dn, lo_dn};
        assign tx_oe = oe4 | lo_oe;
        logic [7:0] p_data_out, p_data_in; logic p_txvalid, p_txready, p_rxactive, p_rxvalid, p_rxerror; logic [1:0] p_linestate;
        UsbPhy #(.W(4), .FS_CLOCKS_PER_BIT(10), .LS_CLOCKS_PER_BIT(80)) dut (
            .i_clk(clk2), .i_rst(rst),
            .i_utmi_data_out(p_data_out), .i_utmi_txvalid(p_txvalid), .o_utmi_txready(p_txready),
            .o_utmi_data_in(p_data_in), .o_utmi_rxactive(p_rxactive), .o_utmi_rxvalid(p_rxvalid),
            .o_utmi_rxerror(p_rxerror), .o_utmi_linestate(p_linestate),
            .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvr), .i_utmi_termselect(utmi_termsel),
            .i_rx_dp(rx4_dp), .i_rx_dn(rx4_dn), .i_rx_dd(rx4_dp), .i_rx_dd_valid(1'b1), .o_tx_dp(tx4_dp), .o_tx_dn(tx4_dn), .o_tx_oe(tx4_oe),
            .o_pullup_dp_en(pu_dp), .o_pullup_dn_en(pu_dn), .o_term_dp_en(term_dp), .o_term_dn_en(term_dn)
        );
        UsbPhyBridge bridge (
            .i_clk(clk2), .i_rst(rst), .i_ph(ph),
            .o_p_txvalid(p_txvalid), .o_p_data_out(p_data_out), .i_p_txready(p_txready),
            .i_p_data_in(p_data_in), .i_p_rxactive(p_rxactive), .i_p_rxvalid(p_rxvalid), .i_p_rxerror(p_rxerror), .i_p_linestate(p_linestate),
            .i_l_data_out(utmi_data_out), .i_l_txvalid(utmi_txvalid), .o_l_txready(utmi_txready),
            .o_l_data_in(utmi_data_in), .o_l_rxactive(utmi_rxactive), .o_l_rxvalid(utmi_rxvalid), .o_l_rxerror(utmi_rxerror), .o_l_linestate(utmi_linestate)
        );
    end else if (ULPI == 0) begin : g_utmi
        UsbPhy dut (
            .i_clk(clk), .i_rst(rst),
            .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
            .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
            .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
            .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvr), .i_utmi_termselect(utmi_termsel),
            .i_rx_dp(rx_dp), .i_rx_dn(rx_dn), .i_rx_dd(rx_dp), .i_rx_dd_valid(1'b1), .o_tx_dp(tx_dp), .o_tx_dn(tx_dn), .o_tx_oe(tx_oe),
            .o_pullup_dp_en(pu_dp), .o_pullup_dn_en(pu_dn), .o_term_dp_en(term_dp), .o_term_dn_en(term_dn)
        );
    end else begin : g_ulpi
        // UTMI -> ULPI link adapter -> ULPI PHY (the Gowin "Interface = ULPI" shape)
        logic [7:0] ulpi_l2p, ulpi_p2l, ulpi_bus;
        logic ulpi_dir, ulpi_nxt, ulpi_stp, ulpi_l_oe;
        assign ulpi_bus = ulpi_dir ? ulpi_p2l : (ulpi_l_oe ? ulpi_l2p : 8'hzz);
        UlpiLink link (
            .i_clk(clk), .i_rst(rst),
            .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
            .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
            .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
            .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvr), .i_utmi_termselect(utmi_termsel),
            .i_ulpi_data(ulpi_bus), .o_ulpi_data(ulpi_l2p), .o_ulpi_data_oe(ulpi_l_oe),
            .i_ulpi_dir(ulpi_dir), .i_ulpi_nxt(ulpi_nxt), .o_ulpi_stp(ulpi_stp)
        );
        UlpiPhy dut (
            .i_clk(clk), .i_rst(rst),
            .i_ulpi_data(ulpi_bus), .o_ulpi_data(ulpi_p2l), .o_ulpi_dir(ulpi_dir), .o_ulpi_nxt(ulpi_nxt), .i_ulpi_stp(ulpi_stp),
            .i_vbus_valid(1'b1),
            .i_rx_dp(rx_dp), .i_rx_dn(rx_dn), .i_rx_dd(rx_dp), .o_tx_dp(tx_dp), .o_tx_dn(tx_dn), .o_tx_oe(tx_oe),
            .o_pullup_dp_en(pu_dp), .o_pullup_dn_en(pu_dn), .o_term_dp_en(term_dp), .o_term_dn_en(term_dn),
            .o_dp_pulldown(), .o_dm_pulldown()
        );
    end endgenerate

    logic host_drive;
    usb_host_bfm host (
        .clk(clk), .hs(HS), .ls(LS),
        .dp_o(rx_dp), .dn_o(rx_dn), .drive(host_drive),
        .dp_i(tx_dp), .dn_i(tx_dn), .oe_i(tx_oe)
    );

    // UTMI RX capture
    byte cap[0:1023];
    int  cap_len;
    int  cap_err;
    int  cap_active_edges;
    logic rxactive_d;
    always @(posedge clk) begin
        rxactive_d <= utmi_rxactive;
        if (utmi_rxactive && !rxactive_d) begin cap_len <= 0; cap_active_edges <= cap_active_edges + 1; end
        if (utmi_rxvalid) begin cap[cap_len] <= utmi_data_in; cap_len <= cap_len + 1; end
        if (utmi_rxerror) cap_err <= cap_err + 1;
    end

    int errors = 0;
    string stage = "init";
    initial if (RUN) begin repeat (3_000_000) @(posedge clk); $fatal(1, "TIMEOUT at stage %s", stage); end

    task automatic fill(input int n, input int pattern);
        for (int i = 0; i < n; i++)
            host.tx_buf[i] = (pattern == 0) ? byte'(i * 7 + 3) : (pattern == 1) ? 8'hFF : 8'h00;
        host.tx_len = n;
    endtask

    task automatic host_to_phy(input int n, input int pattern, input string what);
        stage = what;
        fill(n, pattern);
        cap_len = 0; cap_err = 0;
        host.send_packet();
        repeat (LS ? 400 : 60) @(posedge clk);
        if (cap_len != n) begin
            $display("ERROR: %s: RX got %0d bytes, expected %0d", what, cap_len, n); errors++;
        end else begin
            for (int i = 0; i < n; i++)
                if (cap[i] != host.tx_buf[i]) begin
                    $display("ERROR: %s: RX byte %0d = %h, expected %h", what, i, cap[i], host.tx_buf[i]); errors++;
                end
        end
        if (cap_err != 0) begin $display("ERROR: %s: RxError asserted", what); errors++; end
        if (utmi_rxactive) begin $display("ERROR: %s: RxActive stuck", what); errors++; end
    endtask

    // Drive the UTMI TX side with n bytes; BFM decodes.
    byte txd[0:1023];
    task automatic phy_to_host(input int n, input int pattern, input string what);
        int k;
        stage = what;
        for (int i = 0; i < n; i++)
            txd[i] = (pattern == 0) ? byte'(i * 13 + 1) : (pattern == 1) ? 8'hFF : 8'h00;
        // Over ULPI the first byte is a PID carried in the Transmit
        // command and re-encoded as {~pid, pid}; 0x00 would mean NOPID.
        if (ULPI) txd[0] = 8'hC3; // DATA0
        fork
            begin
                bit r;
                k = 0;
                @(negedge clk);
                utmi_txvalid  = 1;
                utmi_data_out = txd[0];
                while (k < n) begin
                    r = utmi_txready;   // value sampled at the coming posedge
                    @(posedge clk);
                    if (r) k++;
                    @(negedge clk);
                    utmi_data_out = txd[k];
                end
                utmi_txvalid = 0;
            end
            host.recv_packet(LS ? 20000 : 3000);
        join
        if (host.rx_timeout || !host.rx_ok) begin
            $display("ERROR: %s: BFM timeout=%0d ok=%0d", what, host.rx_timeout, host.rx_ok); errors++;
        end else if (host.rx_len != n) begin
            $display("ERROR: %s: BFM got %0d bytes, expected %0d", what, host.rx_len, n); errors++;
        end else begin
            for (int i = 0; i < n; i++)
                if (host.rx_buf[i] != txd[i]) begin
                    $display("ERROR: %s: TX byte %0d = %h, expected %h", what, i, host.rx_buf[i], txd[i]); errors++;
                end
        end
        repeat (LS ? 400 : 60) @(posedge clk);
        if (tx_oe) begin $display("ERROR: %s: TX still driving", what); errors++; end
    endtask

    // RUN = 0 keeps an uninstantiated copy (a Verilator implicit top) inert.
    initial if (RUN) begin
        utmi_data_out = 0; utmi_txvalid = 0; utmi_opmode = 2'b00;
        utmi_xcvr = HS ? 2'b00 : (LS ? 2'b10 : 2'b01); utmi_termsel = HS ? 0 : 1;
        cap_len = 0; cap_err = 0; cap_active_edges = 0;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (ULPI ? 60 : 20) @(posedge clk);

        if (!HS && !LS && (utmi_linestate != 2'b01)) begin $display("ERROR: idle linestate %b", utmi_linestate); errors++; end
        if (HS && (utmi_linestate != 2'b00)) begin $display("ERROR: HS idle linestate %b", utmi_linestate); errors++; end
        if (LS && (utmi_linestate != 2'b10)) begin $display("ERROR: LS idle linestate %b", utmi_linestate); errors++; end
        if (HS && (pu_dp || !term_dp)) begin $display("ERROR: HS termination outputs"); errors++; end
        if (!HS && !LS && (!pu_dp || pu_dn || term_dp)) begin $display("ERROR: FS termination outputs"); errors++; end
        if (LS && (pu_dp || !pu_dn)) begin $display("ERROR: LS termination outputs"); errors++; end

        // ---- host -> PHY ----
        host_to_phy(3, 0, "rx token");
        host_to_phy(1, 0, "rx handshake");
        host_to_phy(11, 0, "rx data 11");
        host_to_phy(16, 1, "rx data all-ones (stuffing)");
        host_to_phy(16, 2, "rx data all-zeros");
        host_to_phy(LS ? 11 : 67, 0, "rx data max");
        if (!LS) host_to_phy(67, 1, "rx data max all-ones");

        // ---- PHY -> host ----
        phy_to_host(1, 0, "tx handshake");
        phy_to_host(3, 0, "tx token");
        phy_to_host(11, 0, "tx data 11");
        phy_to_host(16, 1, "tx data all-ones (stuffing)");
        phy_to_host(16, 2, "tx data all-zeros");
        phy_to_host(LS ? 11 : 67, 0, "tx data max");
        if (!LS) phy_to_host(67, 1, "tx data max all-ones");

        // ---- back-to-back: host packet immediately followed by TX ----
        host_to_phy(3, 0, "rx token 2");
        phy_to_host(1, 0, "tx handshake 2");

        // ---- bit-stuff violation -> RxError ----
        begin
            fill(4, 1);
            host.encode_packet();
            // Remove the first stuffed zero: bit index after SYNC + 6 ones.
            // SYNC = 8 (FS) or 32 (HS) bits; its final one counts, so the
            // stuffed zero follows the 5th data one.
            for (int i = (HS ? 32 : 8) + 5; i < host.nbits - 1; i++) begin
                host.lv[i] = ~host.lv[i+1]; host.se[i] = host.se[i+1]; // NRZI: drop level, keep later transitions
            end
            host.nbits = host.nbits - 1;
            cap_err = 0;
            host.drive_bits();
            repeat (LS ? 400 : 60) @(posedge clk);
            if (cap_err == 0) begin $display("ERROR: stuff violation did not raise RxError"); errors++; end
            if (utmi_rxactive) begin $display("ERROR: RxActive stuck after error"); errors++; end
        end
        // Recovery after the error
        host_to_phy(3, 0, "rx token after error");

        // ---- Chirp K via OpMode RAW ----
        if (HS) begin
            utmi_termsel = 1;
            utmi_opmode  = 2'b10;
            utmi_data_out = 8'h00;
            @(posedge clk);
            utmi_txvalid = 1;
            repeat (ULPI ? 40 : 20) @(posedge clk);
            if (!tx_oe || tx_dp != 8'h00 || tx_dn != 8'hFF) begin
                $display("ERROR: chirp K not driven (oe=%0d dp=%h dn=%h)", tx_oe, tx_dp, tx_dn); errors++;
            end
            utmi_txvalid = 0;
            repeat (8) @(posedge clk);
            if (tx_oe) begin $display("ERROR: chirp K not released"); errors++; end
            utmi_opmode = 2'b00;
            utmi_termsel = 0;
        end

        errors += host.errors;
        if (errors == 0) $display("PASS: usb_phy loopback HS=%0d LS=%0d ULPI=%0d", HS, LS, ULPI);
        else $fatal(1, "FAIL: usb_phy loopback HS=%0d LS=%0d errors=%0d", HS, LS, errors);
        $finish;
    end
endmodule
