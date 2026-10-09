// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// PIPE-level USB 3.2 Gen1 host model for `veryl test`.
//
// Emulates the device-side PHY behaviour visible on the PIPE pins
// (PhyStatus handshakes, receiver detection, LFPS via RxElecIdle) and a
// host MAC: LTSSM (Rx.Detect, Polling, U0, Recovery), link layer (HSN,
// credits, LGOOD/LCRD, LBAD/LRTY) and helpers for header packets / DPPs.
// Everything the device transmits is descrambled and parsed into event
// queues the test can inspect. The scrambler and CRCs are implemented
// bit-serially here, independently of the RTL package.
`timescale 1ns/1ps
module usb3_host_bfm (
    input  logic        clk,
    input  logic        rst,
    // from the device
    input  logic [31:0] d_tx_data,
    input  logic [3:0]  d_tx_k,
    input  logic        d_tx_elecidle,
    input  logic        d_tx_detectrx,
    input  logic [1:0]  d_power_down,
    input  logic        d_rx_polarity,
    input  logic        d_rx_termination,
    // to the device
    output logic [31:0] d_rx_data,
    output logic [3:0]  d_rx_k,
    output logic        d_rx_valid,
    output logic [2:0]  d_rx_status,
    output logic        d_rx_elecidle,
    output logic        d_phy_status,
    output logic        d_power_present
);
    localparam COM = 8'hBC, SKP = 8'h3C, SDP = 8'h5C, EDB = 8'h7C, SHP = 8'hFB, END = 8'hFD,
               SLC = 8'hFE, EPF = 8'hF7, D10_2 = 8'h4A, D5_2 = 8'h45;

    // ---------------------------------------------------------------- bit-serial helpers
    function automatic logic [15:0] lfsr_adv8_serial(logic [15:0] l);
        for (int i = 0; i < 8; i++) begin
            logic fb = l[15];
            l = {l[14:0], 1'b0} ^ (fb ? 16'h0039 : 16'h0);
        end
        return l;
    endfunction
    function automatic logic [7:0] lfsr_mask_serial(logic [15:0] l);
        logic [7:0] m;
        for (int i = 0; i < 8; i++) m[i] = l[15 - i];
        return m;
    endfunction
    // CRCs as the spec draws them: non-reflected register, data bit 0 first,
    // remainder complemented and bit-reversed into the field.
    function automatic logic [15:0] crc16_spec(logic [7:0] b[$]);
        logic [15:0] r = 16'hFFFF, f;
        for (int i = 0; i < b.size(); i++)
            for (int j = 0; j < 8; j++) begin
                logic fb = r[15] ^ b[i][j];
                r = {r[14:0], 1'b0} ^ (fb ? 16'h100B : 16'h0);
            end
        for (int i = 0; i < 16; i++) f[15 - i] = ~r[i];
        return f;
    endfunction
    function automatic logic [31:0] crc32_spec(logic [7:0] b[$]);
        logic [31:0] r = 32'hFFFFFFFF, f;
        for (int i = 0; i < b.size(); i++)
            for (int j = 0; j < 8; j++) begin
                logic fb = r[31] ^ b[i][j];
                r = {r[30:0], 1'b0} ^ (fb ? 32'h04C11DB7 : 32'h0);
            end
        for (int i = 0; i < 32; i++) f[31 - i] = ~r[i];
        return f;
    endfunction
    function automatic logic [4:0] crc5_spec(logic [10:0] v);
        logic [4:0] r = 5'h1F, f;
        for (int j = 0; j < 11; j++) begin
            logic fb = r[4] ^ v[j];
            r = {r[3:0], 1'b0} ^ (fb ? 5'h05 : 5'h0);
        end
        for (int i = 0; i < 5; i++) f[4 - i] = ~r[i]; // MSb of remainder -> bit 11 (f[0])
        return f;
    endfunction
    function automatic logic [15:0] lcw16(logic [10:0] v);
        return {crc5_spec(v), v};
    endfunction

    // ---------------------------------------------------------------- PHY emulation
    logic [1:0] pd_q;
    int         phy_delay = 0;
    logic       det_pending = 0;
    logic       host_present = 1;    // far-end termination for Rx.Detect
    logic       dev_lfps;            // device is transmitting LFPS
    assign dev_lfps = (d_power_down == 2'b00) ? (d_tx_elecidle && d_tx_detectrx) : !d_tx_elecidle;
    logic       dev_data_on;         // device is transmitting SuperSpeed data
    assign dev_data_on = d_power_down == 2'b00 && !d_tx_elecidle && !d_tx_detectrx;

    initial begin
        d_phy_status = 0; d_rx_status = 0; d_power_present = 1; d_rx_elecidle = 1;
        d_rx_data = 0; d_rx_k = 0; d_rx_valid = 0;
    end
    always @(posedge clk) begin
        d_phy_status <= 0;
        d_rx_status  <= 0;
        pd_q <= d_power_down;
        if (pd_q != d_power_down) phy_delay <= 8;
        if (d_power_down != 2'b00 && d_tx_detectrx && !det_pending) begin det_pending <= 1; phy_delay <= 20; end
        if (phy_delay > 0) begin
            phy_delay <= phy_delay - 1;
            if (phy_delay == 1) begin
                d_phy_status <= 1;
                if (det_pending) begin d_rx_status <= host_present ? 3'b011 : 3'b000; det_pending <= 0; end
            end
        end
    end

    // ---------------------------------------------------------------- LFPS
    // device bursts
    int   lfps_len = 0;            // clocks of the current device burst
    int   dev_bursts = 0;          // bursts ended
    int   dev_last_burst_len = 0;
    int   dev_lfps_on_clks = 0;    // current burst length while ongoing
    always @(posedge clk) begin
        if (dev_lfps) begin lfps_len <= lfps_len + 1; dev_lfps_on_clks <= lfps_len + 1; end
        else if (lfps_len != 0) begin dev_bursts <= dev_bursts + 1; dev_last_burst_len <= lfps_len; lfps_len <= 0; end
    end
    task automatic host_lfps(int ns);
        d_rx_elecidle = 0;
        #(ns);
        d_rx_elecidle = 1;
    endtask

    // ---------------------------------------------------------------- host transmit
    // tx mode when the symbol queue is empty
    typedef enum int { HM_ELEC_IDLE, HM_TSEQ, HM_TS1, HM_TS2, HM_IDLE } hmode_t;
    hmode_t hmode = HM_ELEC_IDLE;
    logic [7:0] ts1_cfg = 0, ts2_cfg = 0;
    logic [8:0] txq[$];           // {k, byte}, unscrambled
    logic [15:0] tx_lfsr = 16'hFFFF;
    int ts_sent = 0;              // ordered sets (TS1/TS2) sent by the host
    int host_skp_cnt = 0;

    task automatic push_sym(logic k, logic [7:0] b); txq.push_back({k, b}); endtask
    task automatic push_ts(int ts2, logic [7:0] cfg);
        repeat (4) push_sym(1, COM);
        push_sym(0, 8'h00); push_sym(0, cfg);
        repeat (10) push_sym(0, ts2 ? D5_2 : D10_2);
    endtask
    task automatic push_tseq();
        logic [7:0] t[16] = '{COM, 8'hFF, 8'h17, 8'hC0, 8'h14, 8'hB2, 8'hE7, 8'h02, 8'h82, 8'h72, 8'h6E, 8'h28, 8'hA6, 8'hBE, 8'h6D, 8'hBF};
        for (int i = 0; i < 16; i++) push_sym(i == 0, t[i]);
        repeat (16) push_sym(0, D10_2);
    endtask
    task automatic push_lc(logic [10:0] w);
        logic [15:0] v = lcw16(w);
`ifdef USB3_DBG
        $display("t=%0t host: send LC %03x", $time, w);
`endif
        push_sym(1, SLC); push_sym(1, SLC); push_sym(1, SLC); push_sym(1, EPF);
        push_sym(0, v[7:0]); push_sym(0, v[15:8]); push_sym(0, v[7:0]); push_sym(0, v[15:8]);
    endtask
    // header packet: hdr = 12 bytes little-endian in a 96-bit vector, lcw_info = 11 bits
    task automatic push_hp(logic [95:0] hdr, logic [10:0] lcw_info);
        logic [7:0] b[$]; logic [15:0] c, l;
`ifdef USB3_DBG
        $display("t=%0t host: send HP %024x hsn %0d", $time, hdr, lcw_info[2:0]);
`endif
        b.delete();   // block-local queues persist between calls in the simulator
        for (int i = 0; i < 12; i++) b.push_back(hdr[8*i +: 8]);
        c = crc16_spec(b); l = lcw16(lcw_info);
        push_sym(1, SHP); push_sym(1, SHP); push_sym(1, SHP); push_sym(1, EPF);
        for (int i = 0; i < 12; i++) push_sym(0, b[i]);
        push_sym(0, c[7:0]); push_sym(0, c[15:8]); push_sym(0, l[7:0]); push_sym(0, l[15:8]);
    endtask
    task automatic push_dpp(logic [7:0] data[$], logic corrupt = 0);
        logic [31:0] c = crc32_spec(data);
        push_sym(1, SDP); push_sym(1, SDP); push_sym(1, SDP); push_sym(1, EPF);
        for (int i = 0; i < data.size(); i++) push_sym(0, data[i] ^ ((corrupt && i == 0) ? 8'h01 : 8'h00));
        push_sym(0, c[7:0]); push_sym(0, c[15:8]); push_sym(0, c[23:16]); push_sym(0, c[31:24]);
        push_sym(1, END); push_sym(1, END); push_sym(1, END); push_sym(1, EPF);
    endtask
    task automatic push_skp(); push_sym(1, SKP); push_sym(1, SKP); endtask

    // one symbol out of the queue (or the mode filler), scrambled
    function automatic logic [8:0] next_tx_sym();
        logic [8:0] s;
        if (txq.size() == 0) begin
            case (hmode)
                HM_TSEQ: push_tseq();
                HM_TS1:  begin push_ts(0, ts1_cfg); ts_sent++; if (host_skp_cnt >= 708) begin push_skp(); push_skp(); host_skp_cnt = 0; end end
                HM_TS2:  begin push_ts(1, ts2_cfg); ts_sent++; if (host_skp_cnt >= 708) begin push_skp(); push_skp(); host_skp_cnt = 0; end end
                HM_IDLE: begin push_sym(0, 8'h00); if (host_skp_cnt >= 354) begin push_skp(); host_skp_cnt = 0; end end
                default: push_sym(0, 8'h00);
            endcase
        end
        s = txq.pop_front();
        host_skp_cnt++;
        if (s[8] && s[7:0] == COM) tx_lfsr = 16'hFFFF;
        else if (s[8] && s[7:0] == SKP) ;
        else begin
            if (!s[8] && !(hmode == HM_TSEQ || hmode == HM_TS1 || hmode == HM_TS2 || ts_raw)) s[7:0] ^= lfsr_mask_serial(tx_lfsr);
            tx_lfsr = lfsr_adv8_serial(tx_lfsr);
        end
        return s;
    endfunction
    logic ts_raw = 0; // symbols currently queued are training sets (never scrambled)

    always @(posedge clk) begin
        if (hmode == HM_ELEC_IDLE && txq.size() == 0) begin
            d_rx_valid <= 0; d_rx_data <= 0; d_rx_k <= 0;
        end else begin
            logic [31:0] w; logic [3:0] k;
            for (int i = 0; i < 4; i++) begin
                logic [8:0] s = next_tx_sym();
                w[8*i +: 8] = s[7:0]; k[i] = s[8];
            end
            d_rx_valid <= 1; d_rx_data <= w; d_rx_k <= k;
        end
    end

    // ---------------------------------------------------------------- host receive
    logic [15:0] rx_lfsr = 16'hFFFF;
    logic [8:0]  rxq[$];       // {k, descrambled byte}
    logic [7:0]  rxraw[$];
    always @(posedge clk) begin
        if (dev_data_on) begin
            for (int i = 0; i < 4; i++) begin
                logic k = d_tx_k[i]; logic [7:0] b = d_tx_data[8*i +: 8]; logic [7:0] d = b;
                if (k && b == COM) rx_lfsr = 16'hFFFF;
                else if (k && b == SKP) ;
                else begin
                    if (!k) d = b ^ lfsr_mask_serial(rx_lfsr);
                    rx_lfsr = lfsr_adv8_serial(rx_lfsr);
                end
                if (!(k && b == SKP)) begin rxq.push_back({k, d}); rxraw.push_back(b); end
            end
        end
    end

    // parser: runs on the queue; events
    typedef struct { logic [95:0] hdr; logic [15:0] lcw; logic crc_ok; } hp_t;
    logic [10:0] ev_lc[$];
    hp_t         ev_hp[$];
    logic [7:0]  ev_dpp[$];     // last DPP payload
    int          ev_dpp_len = -1;
    int          ev_dpp_ok = 0;
    int          ev_dpp_count = 0;
    int          ts1_rx = 0, ts2_rx = 0, ts_rx_consec = 0, tseq_rx = 0;
    logic [7:0]  ts_rx_cfg = 0;
    int          idle_rx = 0;    // consecutive descrambled idle symbols received
    int          lc_count = 0, hp_count = 0, bad_lc = 0;

    // consume one unit (ordered set / link command / header packet + DPP /
    // one idle symbol); progress = 0 when nothing could be consumed
    task automatic parse_step(output logic progress);
        logic [8:0] s;
        progress = 0;
        if (rxq.size() < 4) return;
        s = rxq[0];
        // TS1/TS2: COM x4
        if (rxq[0] == {1'b1, COM} && rxq[1] == {1'b1, COM} && rxq[2] == {1'b1, COM} && rxq[3] == {1'b1, COM}) begin
            logic [7:0] f;
            if (rxq.size() < 16) return;
            f = rxraw[6];
            ts_rx_cfg = rxraw[5];
            if (f == D10_2) begin ts1_rx++; ts_rx_consec++; end
            else if (f == D5_2) begin ts2_rx++; ts_rx_consec++; end
            else ts_rx_consec = 0;
            repeat (16) begin void'(rxq.pop_front()); void'(rxraw.pop_front()); end
            idle_rx = 0;
            progress = 1;
            return;
        end
        // TSEQ: COM then FF 17 C0
        if (rxq[0] == {1'b1, COM} && rxraw[1] == 8'hFF && rxraw[2] == 8'h17) begin
            if (rxq.size() < 32) return;
            tseq_rx++;
            repeat (32) begin void'(rxq.pop_front()); void'(rxraw.pop_front()); end
            progress = 1;
            return;
        end
        // link command
        if (rxq[0] == {1'b1, SLC} && rxq[1] == {1'b1, SLC} && rxq[2] == {1'b1, SLC} && rxq[3] == {1'b1, EPF}) begin
            logic [15:0] w0, w1;
            if (rxq.size() < 8) return;
            w0 = {rxq[5][7:0], rxq[4][7:0]}; w1 = {rxq[7][7:0], rxq[6][7:0]};
            repeat (8) begin void'(rxq.pop_front()); void'(rxraw.pop_front()); end
            if (w0 == w1 && w0[15:11] == crc5_spec(w0[10:0])) begin ev_lc.push_back(w0[10:0]); lc_count++; on_lc(w0[10:0]); end
            else bad_lc++;
            idle_rx = 0;
            progress = 1;
            return;
        end
        // header packet
        if (rxq[0] == {1'b1, SHP} && rxq[1] == {1'b1, SHP} && rxq[2] == {1'b1, SHP} && rxq[3] == {1'b1, EPF}) begin
            hp_t h; logic [7:0] b[$]; logic [15:0] c;
            int n;
            if (rxq.size() < 20) return;
            n = (rxq[4][7:0] & 8'h1F) == 5'b01000 ? {rxq[11][7:0], rxq[10][7:0]} : -1;   // DP: data length
            if (n >= 0 && rxq.size() < 20 + n + 12) return;   // wait for the whole DPP
            b.delete();
            for (int i = 0; i < 12; i++) begin b.push_back(rxq[4 + i][7:0]); h.hdr[8*i +: 8] = rxq[4 + i][7:0]; end
            c = {rxq[17][7:0], rxq[16][7:0]}; last_crc = c; last_crc_exp = crc16_spec(b);
            h.lcw = {rxq[19][7:0], rxq[18][7:0]};
            h.crc_ok = (c == crc16_spec(b)) && (h.lcw[15:11] == crc5_spec(h.lcw[10:0]));
            repeat (20) begin void'(rxq.pop_front()); void'(rxraw.pop_front()); end
            ev_hp.push_back(h); hp_count++;
            on_hp(h);
            idle_rx = 0;
            // DPP follows a DP header
            if (h.hdr[4:0] == 5'b01000) begin
                logic [31:0] cc;
                ev_dpp.delete();
                ev_dpp_ok = 0;
                if (rxq[0] == {1'b1, SDP} && rxq[1] == {1'b1, SDP} && rxq[2] == {1'b1, SDP} && rxq[3] == {1'b1, EPF}) begin
                    for (int i = 0; i < n; i++) ev_dpp.push_back(rxq[4 + i][7:0]);
                    cc = {rxq[4 + n + 3][7:0], rxq[4 + n + 2][7:0], rxq[4 + n + 1][7:0], rxq[4 + n][7:0]};
                    ev_dpp_ok = (cc == crc32_spec(ev_dpp)) && rxq[8 + n] == {1'b1, END} && rxq[9 + n] == {1'b1, END}
                                && rxq[10 + n] == {1'b1, END} && rxq[11 + n] == {1'b1, EPF};
                    repeat (n + 12) begin void'(rxq.pop_front()); void'(rxraw.pop_front()); end
                end
                ev_dpp_len = n;
                ev_dpp_count++;
            end
            progress = 1;
            return;
        end
        // idle / other
        if (s[8] == 0 && s[7:0] == 8'h00) idle_rx++; else idle_rx = 0;
        void'(rxq.pop_front()); void'(rxraw.pop_front());
        progress = 1;
    endtask
    always @(posedge clk) begin
        logic p;
        for (int i = 0; i < 64; i++) begin
            parse_step(p);
            if (!p) break;
        end
    end

    // ---------------------------------------------------------------- host link layer
    logic [2:0] h_tx_hsn = 0;        // next HSN we assign
    logic [2:0] h_ack_hsn = 0;       // next LGOOD we expect from the device
    logic [2:0] h_rx_hsn = 0;        // HSN expected in the next device HP
    int         h_credits = 0;       // credits granted by the device
    logic [1:0] h_cred_tx = 0;       // next LCRD letter we send
    logic [1:0] h_cred_rx = 0;       // next LCRD letter we expect
    logic       dev_adv_rx = 0;      // device's LGOOD advertisement seen
    int         dev_lcrd_rx = 0;     // LCRD count since U0 entry
    logic       auto_ack = 1;        // LGOOD/LCRD every device HP automatically
    logic       corrupt_next_hp = 0; // test hook: send the next HP with a bad CRC-16
    int         lgood_err = 0, lcrd_err = 0, hsn_err = 0;
    logic [95:0] last_hp_hdr;
    logic [15:0] last_crc, last_crc_exp;
    int         lbad_rx = 0, lrty_rx = 0, lxu_rx = 0, lau_rx = 0, lup_rx = 0;
    logic [95:0] rx_tp[$];           // device TPs/DPs (non-LMP headers) for the test

    task automatic on_lc(logic [10:0] w);
`ifdef USB3_DBG
        $display("t=%0t host: LC %03x from device", $time, w);
`endif
        if (w[10:3] == 0) begin
            if (!dev_adv_rx) begin dev_adv_rx = 1; h_ack_hsn = w[2:0] + 1; end
            else if (w[2:0] == h_ack_hsn) h_ack_hsn++;
            else lgood_err++;
        end else if (w[10:2] == 9'h020) begin
            if (w[1:0] == h_cred_rx) begin h_cred_rx++; h_credits++; dev_lcrd_rx++; end
            else lcrd_err++;
        end else if (w == 11'h180) lbad_rx++;
        else if (w == 11'h100) lrty_rx++;
        else if (w == 11'h300) lxu_rx++;
        else if (w == 11'h280) lau_rx++;
        else if (w == 11'h400) lup_rx++;
    endtask
    task automatic on_hp(hp_t h);
`ifdef USB3_DBG
        $display("t=%0t host: HP %024x lcw %04x ok=%0d from device (exp hsn %0d) crc_rx %04x exp %04x", $time, h.hdr, h.lcw, h.crc_ok, h_rx_hsn, last_crc, last_crc_exp);
`endif
        last_hp_hdr = h.hdr;
        if (!h.crc_ok) begin if (auto_ack) push_lc(11'h180); return; end
        if (h.lcw[2:0] != h_rx_hsn) begin hsn_err++; return; end
        if (auto_ack) begin
            push_lc({8'h0, h_rx_hsn});          // LGOOD_n
            push_lc({9'h020, h_cred_tx});       // LCRD_x
            h_cred_tx++;
        end
        h_rx_hsn++;
        if (h.hdr[4:0] == 5'b00000) begin
            // LMP: answer Port Capability with ours, Port Configuration handled by the test
            if (h.hdr[8:5] == 4'b0100 && lmp_auto) begin
                send_hp({32'h0, 32'h0001_0004, 32'h0000_0280});          // host Port Capability (DFP)
                send_hp({32'h0, 32'h0, 32'h0000_02A0});                  // Port Configuration, Gen1
            end
        end else rx_tp.push_back(h.hdr);
    endtask
    logic lmp_auto = 1;
    int   port_cfg_rsp = 0;
    always @(posedge clk) if (ev_hp.size() != 0) begin
        hp_t h = ev_hp.pop_front();
        if (h.crc_ok && h.hdr[4:0] == 0 && h.hdr[8:5] == 4'b0110) port_cfg_rsp++;
    end

    // send a header packet using the next HSN (blocks while the device has no credits)
    task automatic send_hp(logic [95:0] hdr, logic dl = 0);
        while (h_credits <= 0) @(posedge clk);
        h_credits--;
        push_hp(hdr, {1'b0, dl, 6'h0, h_tx_hsn} ^ (corrupt_next_hp ? 11'h000 : 11'h000));
        if (corrupt_next_hp) begin
            // flip a bit in the last-pushed header byte (CRC then mismatches)
            txq[$ - 5][0] = ~txq[$ - 5][0];
            corrupt_next_hp = 0;
        end
        h_tx_hsn++;
    endtask
    task automatic send_dp(logic [95:0] hdr, logic [7:0] data[$], logic corrupt = 0);
        send_hp(hdr);
        push_dpp(data, corrupt);
    endtask
    task automatic wait_tx_empty();
        while (txq.size() != 0) @(posedge clk);
        @(posedge clk);
    endtask

    // ---------------------------------------------------------------- host LTSSM helper
    int link_stage = 0;
    task automatic link_up(int tseq_sets = 64);
        // Rx.Detect: wait for the device's detection request handled by the PHY model
        link_stage = 1;
        while (!dev_lfps) @(posedge clk);
        // Polling.LFPS: answer every device burst with a burst of our own, 16 times
        link_stage = 2;
        repeat (20) begin
            while (dev_lfps) @(posedge clk);
            #2000;                       // 2 us after the device burst
            host_lfps(1000);
            while (!dev_lfps && link_stage == 2) begin
                @(posedge clk);
                if (dev_data_on) link_stage = 3;
            end
            if (link_stage == 3) break;
        end
        link_stage = 3;
        // Polling.RxEQ: host sends TSEQ while the device sends its own
        ts_raw = 1; hmode = HM_TSEQ;
        repeat (tseq_sets * 8) @(posedge clk);
        // Polling.Active: TS1 until the device's TS1/TS2 are seen 8 times in a row
        link_stage = 4;
        hmode = HM_TS1; ts1_cfg = 0; ts_rx_consec = 0;
        while (ts_rx_consec < 8) @(posedge clk);
        // Polling.Configuration: TS2
        link_stage = 5;
        hmode = HM_TS2; ts2_cfg = 0; ts_rx_consec = 0; ts2_rx = 0;
        while (ts2_rx < 8) @(posedge clk);
        ts_sent = 0;
        while (ts_sent < 16) @(posedge clk);
        // Polling.Idle
        link_stage = 6;
        txq.delete(); ts_raw = 0; hmode = HM_IDLE; idle_rx = 0;
        while (idle_rx < 8) @(posedge clk);
        repeat (8) @(posedge clk);
        // U0: advertise
        link_stage = 7;
        h_tx_hsn = 0; h_rx_hsn = 0; h_credits = 0; h_cred_tx = 0; h_cred_rx = 0; dev_adv_rx = 0; dev_lcrd_rx = 0;
        push_lc(11'h007);
        push_lc(11'h080); push_lc(11'h081); push_lc(11'h082); push_lc(11'h083);
        while (!dev_adv_rx || dev_lcrd_rx < 4) @(posedge clk);
        link_stage = 8;
    endtask
    // LDN keep-alive every 10 us while in U0 (hmode == HM_IDLE)
    always begin
        #10000;
        if (hmode == HM_IDLE && link_stage >= 8 && txq.size() == 0) push_lc(11'h580);
    end
endmodule
