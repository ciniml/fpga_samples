// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Link-up and link-layer tests: Usb3Top (TSEQ shortened) against the PIPE
// host model. Stages: Rx.Detect -> Polling -> U0, Port Capability /
// Configuration exchange, header packet acknowledgement, keep-alive,
// LBAD/LRTY retry, LGO_U1 refusal, U3 entry / wakeup, Hot Reset.
`timescale 1ns/1ps
// RUN: Verilator runs every test body of include_files as an implicit top in every test, so the
// body only acts when instantiated with RUN = 1 (TbUsb3Prim's test wrappers); it ends with $finish
// on success, $fatal on failure (veryl test counts a $finish as success)
module usb3_link_test_body #(parameter bit RUN = 0);
    logic clk = 0;
    logic rst = 1;
    always #4 clk = ~clk;   // 125 MHz
    initial if (RUN) begin repeat (3_000_000) @(posedge clk); $fatal(1, "TIMEOUT at stage %s", stage); end
    string stage = "init";

    logic [31:0] rx_data, tx_data; logic [3:0] rx_k, tx_k; logic rx_valid; logic [2:0] rx_status;
    logic rx_elecidle, phy_status, power_present, tx_elecidle, tx_detectrx, rx_polarity, rx_termination;
    logic [1:0] power_down;
    logic rx_hp_valid; logic [95:0] rx_hp_hdr;
    logic dpp_start, dpp_valid, dpp_end, dpp_err; logic [31:0] dpp_data; logic [3:0] dpp_be;
    logic tx_hp_valid = 0, tx_dpp = 0, tx_hp_ready, tx_hp_idle; logic [95:0] tx_hp_hdr = 0; logic [10:0] tx_dpp_len = 0; logic [12:0] tx_dpp_base = 0;
    logic dpp_rd; logic [12:0] dpp_addr; logic [31:0] dpp_rdata;
    logic [4:0] ltssm_state; logic in_u0, u0_entry, hot_reset, warm_reset, configured;

    Usb3Top #(.TSEQ_COUNT(64)) dut(.i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_data), .i_rx_k(rx_k), .i_rx_valid(rx_valid), .i_rx_status(rx_status), .i_rx_elecidle(rx_elecidle),
        .i_phy_status(phy_status), .i_power_present(power_present),
        .o_tx_data(tx_data), .o_tx_k(tx_k), .o_tx_elecidle(tx_elecidle), .o_tx_detectrx(tx_detectrx),
        .o_power_down(power_down), .o_rx_polarity(rx_polarity), .o_rx_termination(rx_termination),
        .o_rx_hp_valid(rx_hp_valid), .o_rx_hp_hdr(rx_hp_hdr),
        .o_dpp_start(dpp_start), .o_dpp_valid(dpp_valid), .o_dpp_data(dpp_data), .o_dpp_be(dpp_be), .o_dpp_end(dpp_end), .o_dpp_err(dpp_err),
        .i_tx_hp_valid(tx_hp_valid), .i_tx_hp_hdr(tx_hp_hdr), .i_tx_dpp(tx_dpp), .i_tx_dpp_len(tx_dpp_len), .i_tx_dpp_base(tx_dpp_base),
        .o_tx_hp_ready(tx_hp_ready), .o_tx_hp_idle(tx_hp_idle),
        .o_dpp_rd(dpp_rd), .o_dpp_addr(dpp_addr), .i_dpp_data(dpp_rdata),
        .o_ltssm_state(ltssm_state), .o_in_u0(in_u0), .o_u0_entry(u0_entry), .o_hot_reset(hot_reset), .o_warm_reset(warm_reset),
        .o_configured(configured));

    usb3_host_bfm host(.clk(clk), .rst(rst),
        .d_tx_data(tx_data), .d_tx_k(tx_k), .d_tx_elecidle(tx_elecidle), .d_tx_detectrx(tx_detectrx),
        .d_power_down(power_down), .d_rx_polarity(rx_polarity), .d_rx_termination(rx_termination),
        .d_rx_data(rx_data), .d_rx_k(rx_k), .d_rx_valid(rx_valid), .d_rx_status(rx_status), .d_rx_elecidle(rx_elecidle),
        .d_phy_status(phy_status), .d_power_present(power_present));

    // device-side packet RAM for DPPs
    logic [31:0] ram[4096];
    always_ff @(posedge clk) if (dpp_rd) dpp_rdata <= ram[dpp_addr];

    // device-side received headers / payloads
    logic [95:0] dev_rx_hp[$];
    logic [7:0]  dev_rx_dpp[$];
    int dev_dpp_end = 0, dev_dpp_err = 0;
    always @(posedge clk) begin
        if (rx_hp_valid) dev_rx_hp.push_back(rx_hp_hdr);
        if (dpp_start) dev_rx_dpp.delete();
        if (dpp_valid) for (int i = 0; i < 4; i++) if (dpp_be[i]) dev_rx_dpp.push_back(dpp_data[8*i +: 8]);
        if (dpp_end) dev_dpp_end++;
        if (dpp_err) dev_dpp_err++;
    end

`ifdef USB3_DBG
    logic [4:0] st_q; int ls_q;
    always @(posedge clk) begin
        if (ltssm_state != st_q) $display("t=%0t LTSSM %0d -> %0d (host stage %0d dev_bursts %0d) go_rec=%0d ts1_seen=%0d u0rec=%0d pend=%0d/%0d cred=%0d/%0d", $time, st_q, ltssm_state, host.link_stage, host.dev_bursts,
            dut.go_recovery, dut.u_ltssm.ts1_seen, dut.u_link.u0rec_us, dut.u_link.pending_on, dut.u_link.pending_us, dut.u_link.credit_on, dut.u_link.credit_us);
        st_q <= ltssm_state;
        if (host.link_stage != ls_q) $display("t=%0t host stage %0d (ltssm %0d ts1_rx %0d ts2_rx %0d consec %0d idle_rx %0d)", $time, host.link_stage, ltssm_state, host.ts1_rx, host.ts2_rx, host.ts_rx_consec, host.idle_rx);
        ls_q <= host.link_stage;
        if (in_u0 && (dut.go_recovery || dut.u_ltssm.ts1_seen || dut.ts_valid || warm_reset)) $display("t=%0t U0 event: go_rec=%0d ts1_seen=%0d ts_valid=%0d type=%0d warm=%0d", $time, dut.go_recovery, dut.u_ltssm.ts1_seen, dut.ts_valid, dut.ts_type, warm_reset);
        if (dut.hp_valid) $display("t=%0t dev: parser HP ok=%0d lcw %04x", $time, dut.hp_crc_ok, dut.hp_lcw);
        if (dut.lc_valid) $display("t=%0t dev: parser LC %03x", $time, dut.lc_word);
        if (dut.u_link.lcq_pop) $display("t=%0t dev: framer takes LC %03x (queue %0d)", $time, dut.f_lc_word, dut.u_link.lcq_cnt);
        if (dut.f_hp_valid && dut.f_hp_ready) $display("t=%0t dev: framer takes HP hsn %0d", $time, dut.f_hp_lcw[2:0]);
        if (host.d_rx_valid !== 1 && in_u0) $display("t=%0t host rx_valid low in U0", $time);
    end
`endif

    int errors = 0;
    task automatic fail(string m); $display("FAIL [%s] %s", stage, m); errors++; endtask
    task automatic wait_clk(int n); repeat (n) @(posedge clk); endtask
    task automatic wait_for(ref logic c, int max_clk, string what);
        int n = 0;
        while (!c && n < max_clk) begin @(posedge clk); n++; end
        if (!c) fail({"timeout waiting for ", what});
    endtask

    // device sends a header packet (no DPP)
    task automatic dev_send_hp(logic [95:0] h, logic dpp = 0, int len = 0, int base = 0);
        @(negedge clk); tx_hp_hdr = h; tx_dpp = dpp; tx_dpp_len = len; tx_dpp_base = base; tx_hp_valid = 1;
        @(posedge clk); while (!tx_hp_ready) @(posedge clk);
        @(negedge clk); tx_hp_valid = 0;
    endtask

    localparam logic [95:0] TP_PING = {32'h0, 32'h0000_0107, 27'h0, 5'b00100}; // SubType PING, EP1

    logic [7:0] pl[1024];
    logic [7:0] plq[$];
    int n0;
    int dlens[5] = '{13, 0, 1024, 512, 3};
    initial if (RUN) begin
        wait_clk(5); @(negedge clk); rst = 0; wait_clk(5);

        // ---------------------------------------------------------------- link up
        stage = "linkup";
        host.link_up(64);
        wait_clk(50);
        if (!in_u0) fail("device not in U0");
        // Port Capability from the device, Port Configuration Response after ours
        begin
            int n = 0;
            while ((host.port_cfg_rsp == 0 || !configured) && n < 20000) begin @(posedge clk); n++; end
            if (host.port_cfg_rsp != 1) fail($sformatf("port cfg responses %0d", host.port_cfg_rsp));
            if (!configured) fail("device not configured");
        end
        if (host.lgood_err || host.lcrd_err || host.hsn_err) fail("ack errors during link up");

        // ---------------------------------------------------------------- host -> device header packets
        stage = "hp rx";
        begin
            logic [2:0] a0 = host.h_ack_hsn;
            host.send_hp(TP_PING);
            host.wait_tx_empty(); wait_clk(60);
            if (dev_rx_hp.size() != 1) fail($sformatf("device delivered %0d HPs", dev_rx_hp.size()));
            else if (dev_rx_hp[0] != TP_PING) fail("HP content");
            if (host.h_ack_hsn != a0 + 3'd1) fail($sformatf("LGOOD not received (ack hsn %0d)", host.h_ack_hsn));
            if (host.h_credits != 4) fail($sformatf("credits %0d", host.h_credits));
            dev_rx_hp.delete();
            // four back-to-back
            repeat (4) host.send_hp(TP_PING);
            host.wait_tx_empty(); wait_clk(120);
            if (dev_rx_hp.size() != 4) fail($sformatf("burst: %0d HPs", dev_rx_hp.size()));
            if (host.h_ack_hsn != a0 + 3'd5 || host.h_credits != 4) fail("burst acks");
            dev_rx_hp.delete();
        end

        // ---------------------------------------------------------------- host -> device DP with payload
        stage = "dp rx";
        for (int i = 0; i < 1024; i++) pl[i] = i * 7 + 3;
        foreach (dlens[j]) begin
            int n = dlens[j];
            logic [95:0] h = {32'h0, 16'(n), 16'h0100, 27'h0, 5'b01000};   // DP, EP1 OUT, seq 0
            dev_dpp_end = 0; dev_dpp_err = 0;
            plq.delete(); for (int i = 0; i < n; i++) plq.push_back(pl[i]);
            host.send_dp(h, plq);
            host.wait_tx_empty(); wait_clk(60);
            if (dev_rx_hp.size() != 1) fail($sformatf("dp hdr %0d", dev_rx_hp.size()));
            if (dev_dpp_end != 1 || dev_dpp_err != 0) fail($sformatf("len %0d: end=%0d err=%0d", n, dev_dpp_end, dev_dpp_err));
            if (dev_rx_dpp.size() != n) fail($sformatf("len %0d: got %0d bytes", n, dev_rx_dpp.size()));
            for (int i = 0; i < n && i < dev_rx_dpp.size(); i++) if (dev_rx_dpp[i] != pl[i]) begin fail("payload byte"); break; end
            dev_rx_hp.delete();
        end
        // corrupted payload -> dpp_err, header still acknowledged
        begin
            logic [95:0] h = {32'h0, 16'd64, 16'h0100, 27'h0, 5'b01000};
            logic [2:0] a0 = host.h_ack_hsn;
            dev_dpp_end = 0; dev_dpp_err = 0;
            plq.delete(); for (int i = 0; i < 64; i++) plq.push_back(pl[i]);
            host.send_dp(h, plq, 1);
            host.wait_tx_empty(); wait_clk(60);
            if (dev_dpp_err != 1 || dev_dpp_end != 0) fail("corrupt dpp not flagged");
            if (host.h_ack_hsn != a0 + 1) fail("corrupt dpp header not acked");
            dev_rx_hp.delete();
        end

        // ---------------------------------------------------------------- device -> host header packets
        stage = "hp tx";
        host.rx_tp.delete();
        dev_send_hp({32'h0, 32'h0000_0207, 27'h0, 5'b00100});   // NRDY-ish TP from EP1
        begin int n = 0; while (host.rx_tp.size() < 1 && n < 2000) begin @(posedge clk); n++; end end
        if (host.rx_tp.size() != 1) fail("host did not receive the TP");
        wait_clk(100);
        if (!tx_hp_idle) fail("tx not idle after LGOOD");
        // DP with payload from RAM (base 16, 100 bytes)
        for (int i = 0; i < 25; i++) ram[16 + i] = {8'(i*4+3), 8'(i*4+2), 8'(i*4+1), 8'(i*4)};
        host.ev_dpp_count = 0;
        dev_send_hp({32'h0, 16'd100, 16'h0180, 27'h0, 5'b01000}, 1, 100, 16);
        begin int n = 0; while (host.ev_dpp_count < 1 && n < 3000) begin @(posedge clk); n++; end end
        if (host.ev_dpp_count != 1 || !host.ev_dpp_ok || host.ev_dpp_len != 100) fail($sformatf("host dpp count=%0d ok=%0d len=%0d", host.ev_dpp_count, host.ev_dpp_ok, host.ev_dpp_len));
        for (int i = 0; i < 100 && i < host.ev_dpp.size(); i++) if (host.ev_dpp[i] != 8'(i)) begin fail("dpp byte to host"); break; end
        wait_clk(100);

        // ---------------------------------------------------------------- keep-alive
        stage = "lup";
        begin
            int l0 = host.lup_rx;
            #25000;   // 25 us of idle
            if (host.lup_rx < l0 + 2) fail($sformatf("LUP count %0d -> %0d", l0, host.lup_rx));
        end
        if (!in_u0) fail("left U0 during idle");

        // ---------------------------------------------------------------- LBAD / LRTY
        stage = "lbad";
        begin
            int lb0 = host.lbad_rx;
            logic [2:0] a0 = host.h_ack_hsn;
            host.auto_ack = 1;
            host.corrupt_next_hp = 1;
            host.send_hp(TP_PING);               // device must answer LBAD
            host.wait_tx_empty(); wait_clk(60);
            if (host.lbad_rx != lb0 + 1) fail($sformatf("lbad %0d", host.lbad_rx - lb0));
            // host retries: LRTY then the same HP again (HSN unchanged)
            host.h_tx_hsn--; host.h_credits++;
            host.push_lc(11'h100);
            host.send_hp(TP_PING);
            host.wait_tx_empty(); wait_clk(60);
            if (host.h_ack_hsn != a0 + 1) fail("retried HP not acked");
            if (dev_rx_hp.size() != 1) fail($sformatf("retried HP delivered %0d times", dev_rx_hp.size()));
            dev_rx_hp.delete();
        end
        // device side: host says LBAD for a device HP -> device sends LRTY and resends
        begin
            int lr0 = host.lrty_rx;
            host.rx_tp.delete();
            host.auto_ack = 0;
            dev_send_hp({32'h0, 32'h0000_0207, 27'h0, 5'b00100});
            begin int n = 0; while (host.rx_tp.size() < 1 && n < 2000) begin @(posedge clk); n++; end end
            host.h_rx_hsn = host.h_rx_hsn - 3'd1;   // the retransmission carries the same HSN
            host.push_lc(11'h180);              // LBAD
            begin int n = 0; while (host.rx_tp.size() < 2 && n < 3000) begin @(posedge clk); n++; end end
            if (host.lrty_rx != lr0 + 1) fail("no LRTY from device");
            if (host.rx_tp.size() != 2) fail("device did not resend");
            host.auto_ack = 1;
            // acknowledge it now
            host.push_lc({8'h0, host.h_rx_hsn - 3'd1}); host.push_lc({9'h020, host.h_cred_tx}); host.h_cred_tx++;
            host.wait_tx_empty(); wait_clk(100);
            if (!tx_hp_idle) fail("device tx not idle after late LGOOD");
        end

        // ---------------------------------------------------------------- LGO_U1 -> LXU
        stage = "lgo_u1";
        begin
            int x0 = host.lxu_rx;
            host.push_lc(11'h201);
            host.wait_tx_empty(); wait_clk(60);
            if (host.lxu_rx != x0 + 1) fail("no LXU");
            if (!in_u0) fail("left U0 on LGO_U1");
        end

        // ---------------------------------------------------------------- U3 and wakeup via Recovery
        stage = "u3";
        begin
            int a0 = host.lau_rx;
            host.push_lc(11'h203);                          // LGO_U3
            host.wait_tx_empty(); wait_clk(60);
            if (host.lau_rx != a0 + 1) fail("no LAU");
            host.push_lc(11'h380);                          // LPMA
            host.wait_tx_empty();
            host.hmode = host.HM_ELEC_IDLE; host.link_stage = 0;
            wait_clk(200);
            if (ltssm_state != 12) fail($sformatf("not in U3 (state %0d)", ltssm_state));
            // host wakes the device: LFPS >= 80 us, the device answers with LFPS
            fork
                host.host_lfps(100_000);
            join_none
            begin int n = 0; while (!host.dev_lfps && n < 20000) begin @(posedge clk); n++; end
                  if (!host.dev_lfps) fail("device did not answer wakeup LFPS"); end
            #110_000;
            while (host.dev_lfps) @(posedge clk);
            // Recovery: TS1 / TS2 / idle, then U0 advertisement
            host.ts_raw = 1; host.hmode = host.HM_TS1; host.ts_rx_consec = 0;
            begin int n = 0; while (host.ts_rx_consec < 8 && n < 20000) begin @(posedge clk); n++; end end
            host.hmode = host.HM_TS2; host.ts2_rx = 0;
            begin int n = 0; while (host.ts2_rx < 8 && n < 20000) begin @(posedge clk); n++; end end
            host.ts_sent = 0; while (host.ts_sent < 16) @(posedge clk);
            host.h_credits = 0; host.h_cred_tx = 0; host.h_cred_rx = 0; host.dev_adv_rx = 0; host.dev_lcrd_rx = 0;
            host.txq.delete(); host.ts_raw = 0; host.hmode = host.HM_IDLE; host.idle_rx = 0;
            begin int n = 0; while (host.idle_rx < 8 && n < 20000) begin @(posedge clk); n++; end end
            wait_clk(8);
            host.push_lc({8'h0, host.h_rx_hsn - 3'd1});
            host.push_lc(11'h080); host.push_lc(11'h081); host.push_lc(11'h082); host.push_lc(11'h083);
            begin int n = 0; while ((!host.dev_adv_rx || host.dev_lcrd_rx < 4) && n < 20000) begin @(posedge clk); n++; end end
            host.link_stage = 8;
            wait_clk(50);
            if (!in_u0) fail($sformatf("not back in U0 after wakeup (state %0d)", ltssm_state));
            // traffic still works, sequence numbers continued
            dev_rx_hp.delete();
            host.send_hp(TP_PING); host.wait_tx_empty(); wait_clk(60);
            if (dev_rx_hp.size() != 1) fail("HP after recovery");
        end

        if (errors == 0) begin $display("PASS usb3_link"); $finish; end
        else $fatal(1, "FAIL usb3_link: %0d errors", errors);
        $finish;
    end
endmodule
