// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Framing loopback: Usb3TxFramer -> wire model (SKP insertion, arbitrary
// re-alignment with idle symbols, bit corruption) -> scrambler ->
// descrambler -> Usb3RxFifo -> Usb3RxParser. Checks link commands, header
// packets (CRC good/bad), DPPs of many lengths and TS1/TS2 detection.
`timescale 1ns/1ps
// RUN: Verilator runs every test body of include_files as an implicit top in every test, so the
// body only acts when instantiated with RUN = 1 (TbUsb3Prim's test wrappers); it ends with $finish
// on success, $fatal on failure (veryl test counts a $finish as success)
module usb3_frame_test_body #(parameter bit RUN = 0);
    import usb3_pkg::*;
    logic clk = 0;
    logic rst = 1;
    always #4 clk = ~clk;
    initial if (RUN) begin repeat (400_000) @(posedge clk); $fatal(1, "TIMEOUT"); end

    // ---------------------------------------------------------------- TX
    logic        lc_valid, lc_ready;
    logic [10:0] lc_word;
    logic        hp_valid, hp_ready, hp_dpp;
    logic [95:0] hp_hdr;
    logic [10:0] hp_lcw, hp_len;
    logic        dpp_rd;
    logic [12:0] dpp_addr;
    logic [31:0] dpp_data;
    logic [31:0] tx_data;
    logic [3:0]  tx_k;
    logic        tx_busy;
    logic        tx_enable = 0;

    logic [31:0] ram[256];
    always_ff @(posedge clk) if (dpp_rd) dpp_data <= ram[dpp_addr[7:0]];

    Usb3TxFramer txf(.i_clk(clk), .i_rst(rst), .i_enable(tx_enable),
        .i_lc_valid(lc_valid), .i_lc_word(lc_word), .o_lc_ready(lc_ready),
        .i_hp_valid(hp_valid), .i_hp_hdr(hp_hdr), .i_hp_lcw(hp_lcw), .i_hp_dpp(hp_dpp),
        .i_hp_dpp_len(hp_len), .i_hp_dpp_base(13'd0), .o_hp_ready(hp_ready),
        .o_dpp_rd(dpp_rd), .o_dpp_addr(dpp_addr), .i_dpp_data(dpp_data),
        .o_data(tx_data), .o_k(tx_k), .o_busy(tx_busy));

    // ---------------------------------------------------------------- wire model (raw symbols)
    // A symbol queue; the framer's words are appended every clock, extra
    // symbols are inserted between packets, and 4 symbols per clock are
    // handed to the scrambler. Symbols: {k, byte}.
    logic [8:0] q[$];
    int ins_mode = 0;       // 0 none, 1 SKP pairs, 2 odd idle shifts, 3 both
    int unsigned seed = 1;
    logic [8:0] raw_in[4];
    logic        raw_valid = 0;   // raw bypass (TS injection) when set the wire feeds ts_word
    logic [31:0] ts_word; logic [3:0] ts_k; logic ts_bypass;
    int corrupt_at = -1;     // countdown (symbols) once armed by the next SHP; -1 idle
    int corrupt_off = -1;    // arm: offset from the first SHP symbol of the next header packet
    int qcount = 0;

    logic [31:0] w_data; logic [3:0] w_k; logic w_bypass;
    always @(posedge clk) begin
        // append the framer output
        for (int i = 0; i < 4; i++) q.push_back({tx_k[i], tx_data[8*i +: 8]});
        qcount += 4;
        if (!tx_busy && tx_enable) begin
            if ((ins_mode & 1) && ($urandom(seed) % 23 == 0)) begin q.push_back({1'b1, K_SKP}); q.push_back({1'b1, K_SKP}); end
            if ((ins_mode & 2) && ($urandom(seed) % 17 == 0)) begin
                int n = $urandom(seed) % 4;
                repeat (n) q.push_back({1'b0, 8'h00});
            end
        end
    end
    // pop 4 per clock into the scrambler input (registered word)
    logic [31:0] s_data; logic [3:0] s_k; logic s_valid;
    always @(negedge clk) begin
        s_valid = 0;
        if (raw_valid) begin
            s_data = ts_word; s_k = ts_k; s_valid = 1; w_bypass = ts_bypass;
            repeat (4) if (q.size() > 0) void'(q.pop_front());   // keep the queue bounded
        end else if (q.size() >= 4) begin
            for (int i = 0; i < 4; i++) begin
                logic [8:0] e = q.pop_front();
                if (corrupt_off >= 0 && e == {1'b1, K_SHP}) begin corrupt_at = corrupt_off; corrupt_off = -1; end
                if (corrupt_at == 0) begin e[0] = ~e[0]; corrupt_at = -1; end
                else if (corrupt_at > 0) corrupt_at--;
                s_data[8*i +: 8] = e[7:0]; s_k[i] = e[8];
            end
            s_valid = 1; w_bypass = 0;
        end
    end

    logic [31:0] scr_out;
    logic [15:0] lfsr_tx, lfsr_rx;
    Usb3Scrambler scr(.i_clk(clk), .i_rst(rst), .i_valid(s_valid), .i_bypass(w_bypass),
                      .i_data(s_data), .i_k(s_k), .o_data(scr_out), .o_lfsr(lfsr_tx));
    // "wire": register
    logic [31:0] l_data; logic [3:0] l_k; logic l_valid;
    always_ff @(posedge clk) begin l_data <= scr_out; l_k <= s_k; l_valid <= s_valid && !rst; end

    // ---------------------------------------------------------------- RX
    logic [31:0] desc;
    Usb3Scrambler dscr(.i_clk(clk), .i_rst(rst), .i_valid(l_valid), .i_bypass(1'b0),
                       .i_data(l_data), .i_k(l_k), .o_data(desc), .o_lfsr(lfsr_rx));
    logic [31:0] cls;
    always_comb for (int i = 0; i < 4; i++) cls[8*i +: 8] = sym_class(l_k[i], l_data[8*i +: 8], desc[8*i +: 8]);

    logic [191:0] f_raw, f_desc, f_cls; logic [23:0] f_k; logic [4:0] f_fill; logic f_adv;
    Usb3RxFifo fifo(.i_clk(clk), .i_rst(rst), .i_flush(1'b0), .i_valid(l_valid),
        .i_raw(l_data), .i_desc(desc), .i_k(l_k), .i_cls(cls),
        .o_raw(f_raw), .o_desc(f_desc), .o_k(f_k), .o_cls(f_cls), .o_fill(f_fill), .o_adv(f_adv));

    logic ts_valid, ts_inv, pol_hint, idle8, rlc_valid, rhp_valid, rhp_ok;
    logic [1:0] ts_type; logic [7:0] ts_cfg; logic [10:0] rlc_word;
    logic [95:0] rhp_hdr; logic [15:0] rhp_lcw;
    logic dpp_start, dpp_valid, dpp_end, dpp_err; logic [31:0] dpp_w; logic [3:0] dpp_be;
    Usb3RxParser par(.i_clk(clk), .i_rst(rst), .i_enable(1'b1), .i_adv(f_adv),
        .i_raw(f_raw), .i_desc(f_desc), .i_k(f_k), .i_cls(f_cls), .i_fill(f_fill),
        .o_ts_valid(ts_valid), .o_ts_type(ts_type), .o_ts_cfg(ts_cfg), .o_ts_inv(ts_inv),
        .o_pol_inv_hint(pol_hint), .o_idle8(idle8),
        .o_lc_valid(rlc_valid), .o_lc_word(rlc_word),
        .o_hp_valid(rhp_valid), .o_hp_hdr(rhp_hdr), .o_hp_lcw(rhp_lcw), .o_hp_crc_ok(rhp_ok),
        .o_dpp_start(dpp_start), .o_dpp_valid(dpp_valid), .o_dpp_data(dpp_w), .o_dpp_be(dpp_be),
        .o_dpp_end(dpp_end), .o_dpp_err(dpp_err));

    // ---------------------------------------------------------------- RX event log
    typedef struct { int kind; logic [95:0] hdr; logic [15:0] lcw; logic ok; logic [10:0] lc; } ev_t;
    ev_t evq[$];
    logic [7:0] rxbuf[$];
    int dpp_ends = 0, dpp_errs = 0, dpp_starts = 0, ts_seen = 0, hints = 0;
    logic [10:0] tsq[$];   // {inv, type, cfg}
    always @(posedge clk) begin
        if (rlc_valid) begin ev_t e; e.kind = 1; e.lc = rlc_word; evq.push_back(e); end
        if (rhp_valid) begin ev_t e; e.kind = 2; e.hdr = rhp_hdr; e.lcw = rhp_lcw; e.ok = rhp_ok; evq.push_back(e); end
        if (dpp_start) dpp_starts++;
        if (dpp_valid) for (int i = 0; i < 4; i++) if (dpp_be[i]) rxbuf.push_back(dpp_w[8*i +: 8]);
        if (dpp_end) dpp_ends++;
        if (dpp_err) dpp_errs++;
        if (ts_valid) begin ts_seen++; tsq.push_back({ts_inv, ts_type, ts_cfg}); end
        if (pol_hint) hints++;
    end

`ifdef USB3_DBG
    initial if (RUN) begin
        #200;
        forever begin
            @(posedge clk);
            if (raw_valid || $time < 400000) $display("t=%0t tx=%08x k=%b busy=%b | s=%08x k=%b v=%b | l=%08x k=%b v=%b desc=%08x | fill=%0d pos=%0d pop=%0d st=%0d win=%016x k=%08b",
                $time, tx_data, tx_k, tx_busy, s_data, s_k, s_valid, l_data, l_k, l_valid, desc,
                f_fill, par.pos, par.pop, par.state, par.v_raw, par.v_k);
            if (par.state >= 3) $display("   remain=%0d crc32=%08x crc_rx=%08x txst=%0d txrem=%0d tail0=%024x k=%03x", par.remain, par.crc32, par.crc_rx, txf.state, txf.remain, txf.tail0, txf.tail0_k);
        end
    end
`endif

    int errors = 0;
    string stage = "init";

    task automatic fail(string m); $display("FAIL [%s] %s", stage, m); errors++; endtask

    // inputs change on the falling edge (no race with the DUT's clock edge)
    task automatic send_lc(logic [10:0] w);
        @(negedge clk); lc_word = w; lc_valid = 1;
        @(posedge clk); while (!lc_ready) @(posedge clk);
        @(negedge clk); lc_valid = 0;
    endtask
    task automatic send_hp(logic [95:0] h, logic [10:0] l, logic dpp, int len);
        @(negedge clk); hp_hdr = h; hp_lcw = l; hp_dpp = dpp; hp_len = len; hp_valid = 1;
        @(posedge clk); while (!hp_ready) @(posedge clk);
        @(negedge clk); hp_valid = 0;
    endtask
    task automatic wait_events(int n);
        int guard = 0;
        while (evq.size() < n && guard < 5000) begin @(posedge clk); guard++; end
        if (evq.size() < n) fail($sformatf("expected %0d events, got %0d", n, evq.size()));
    endtask
    task automatic settle(); repeat (40) @(posedge clk); endtask

    logic [95:0] h; ev_t e;
    int len;
    int lens[12] = '{0, 1, 2, 3, 4, 5, 7, 8, 13, 64, 511, 1024};
    initial if (RUN) begin
        lc_valid = 0; hp_valid = 0; raw_valid = 0; ts_bypass = 0;
        repeat (3) @(posedge clk); @(negedge clk); rst = 0; repeat (3) @(posedge clk);
        tx_enable = 1; settle();

        // ---- link commands
        stage = "lc";
        send_lc(LC_LGOOD + 3); send_lc(LC_LCRD + 1); send_lc(LC_LUP);
        wait_events(3);
        if (evq[0].kind != 1 || evq[0].lc != LC_LGOOD + 3) fail("lc0");
        if (evq[1].kind != 1 || evq[1].lc != LC_LCRD + 1) fail("lc1");
        if (evq[2].kind != 1 || evq[2].lc != LC_LUP) fail("lc2");
        evq.delete();

        // ---- bursts of link commands under every wire perturbation
        for (int mode = 0; mode < 4; mode++) begin
            ins_mode = mode;
            for (int rep = 0; rep < 20; rep++) begin
                stage = $sformatf("lc burst mode%0d rep%0d", mode, rep);
                for (int i = 0; i < 8; i++) send_lc(LC_LCRD + (i & 3) + ((i & 4) ? 11'h100 : 0));
                wait_events(8);
                for (int i = 0; i < 8 && i < evq.size(); i++)
                    if (evq[i].kind != 1 || evq[i].lc != (LC_LCRD + (i & 3) + ((i & 4) ? 11'h100 : 0))) begin fail($sformatf("lc %0d got %03x", i, evq[i].lc)); break; end
                evq.delete();
            end
        end
        ins_mode = 0;

        // ---- header packet without DPP (Port Capability LMP), HSN 5
        stage = "hp";
        h = {32'h0, 32'h0002_0004, 32'h0000_0280};
        send_hp(h, 11'd5, 0, 0);
        wait_events(1);
        if (evq[0].kind != 2 || evq[0].hdr != h || !evq[0].ok || evq[0].lcw[2:0] != 5) fail("hp0");
        evq.delete();

        // ---- DPPs of assorted lengths, all wire perturbations
        for (int mode = 0; mode < 4; mode++) begin
            ins_mode = mode;
            foreach (lens[j]) begin
                len = lens[j];
                stage = $sformatf("dpp mode%0d len%0d", mode, len);
                for (int i = 0; i < 256; i++) ram[i] = $urandom(seed);
                rxbuf.delete(); dpp_ends = 0; dpp_errs = 0; dpp_starts = 0;
                h = {32'h0, 16'(len), 16'h0180, 27'h0, PKT_DP};   // DW1[31:16] = length, EP1 IN-ish
                send_hp(h, 11'd1, 1, len);
                send_lc(LC_LGOOD + 1);            // something right after
                wait_events(2);
                if (evq[0].kind != 2 || !evq[0].ok || evq[0].hdr != h) fail($sformatf("dph: ev0 kind=%0d ok=%0d hdr=%024x lc=%03x (exp %024x) events=%0d", evq[0].kind, evq[0].ok, evq[0].hdr, evq[0].lc, h, evq.size()));
                if (evq[1].kind != 1 || evq[1].lc != LC_LGOOD + 1) fail("lc after dpp");
                evq.delete();
                if (dpp_starts != 1) fail($sformatf("starts=%0d", dpp_starts));
                if (dpp_ends != 1) fail($sformatf("ends=%0d errs=%0d", dpp_ends, dpp_errs));
                if (rxbuf.size() != len) fail($sformatf("rx len %0d", rxbuf.size()));
                for (int i = 0; i < len && i < rxbuf.size(); i++)
                    if (rxbuf[i] !== ram[i/4][8*(i%4) +: 8]) begin fail($sformatf("byte %0d", i)); break; end
            end
        end
        ins_mode = 0;

        // ---- corrupted header (one bit in byte 2 of the header): crc_ok must be 0
        stage = "hp corrupt";
        settle();
        corrupt_off = 4 + 2;   // HPSTART (4) then header byte 2
        h = {32'h1111_2222, 32'h3333_4444, 32'h5555_6660};
        send_hp(h, 11'd2, 0, 0);
        wait_events(1);
        if (evq[0].kind != 2 || evq[0].ok) fail("corrupt not detected");
        evq.delete();
        // corrupted DPP data: dpp_err, no dpp_end
        stage = "dpp corrupt";
        settle();
        corrupt_off = 4 + 16 + 4 + 3;   // HPSTART(4) hdr(16) DPPSTART(4) byte 3
        h = {32'h0, 16'd16, 16'h0180, 27'h0, PKT_DP};
        dpp_ends = 0; dpp_errs = 0;
        send_hp(h, 11'd3, 1, 16);
        wait_events(1); evq.delete(); settle();
        if (dpp_ends != 0 || dpp_errs != 1) fail($sformatf("ends=%0d errs=%0d", dpp_ends, dpp_errs));

        // ---- logical idle detection
        stage = "idle";
        settle();
        if (!idle8) fail("idle8 not set");

        // ---- TS1 / TS2 injected raw (scrambler bypass), misaligned by 2 via SKP pair
        stage = "ts";
        tx_enable = 0; settle();
        tsq.delete(); hints = 0;
        raw_valid = 1; ts_bypass = 1;
        ts_word = {K_SKP, K_SKP, 8'h00, 8'h00}; ts_k = 4'b1100; @(negedge clk); @(posedge clk);
        ts_word = {K_COM, K_COM, K_COM, K_COM}; ts_k = 4'b1111; @(posedge clk);
        ts_word = {D10_2, D10_2, 8'h08, 8'h00};  ts_k = 0; @(posedge clk);   // cfg = 0x08 (Disable Scrambling)
        ts_word = {D10_2, D10_2, D10_2, D10_2};  @(posedge clk);
        ts_word = {D10_2, D10_2, D10_2, D10_2};  @(posedge clk);
        ts_word = {K_COM, K_COM, K_COM, K_COM}; ts_k = 4'b1111; @(posedge clk);
        ts_word = {D5_2, D5_2, 8'h01, 8'h00};  ts_k = 0; @(posedge clk);      // TS2, Reset bit
        ts_word = {D5_2, D5_2, D5_2, D5_2};  @(posedge clk);
        ts_word = {D5_2, D5_2, D5_2, D5_2};  @(posedge clk);
        ts_word = {K_COM, K_COM, K_COM, K_COM}; ts_k = 4'b1111; @(posedge clk);
        ts_word = {D21_5, D21_5, 8'h00, 8'h00};  ts_k = 0; @(posedge clk);    // inverted TS1
        ts_word = {D21_5, D21_5, D21_5, D21_5};  @(posedge clk);
        ts_word = {D21_5, D21_5, D21_5, D21_5};  @(posedge clk);
        ts_word = {D21_5, D21_5, D21_5, D21_5};  @(posedge clk);              // polarity hint
        ts_word = 0; ts_k = 0;
        settle();
        if (tsq.size() != 3) fail($sformatf("ts events %0d", tsq.size()));
        else begin
            if (tsq[0] != {1'b0, 2'd1, 8'h08}) fail("ts1");
            if (tsq[1] != {1'b0, 2'd2, 8'h01}) fail("ts2");
            if (tsq[2] != {1'b1, 2'd1, 8'h00}) fail("ts1 inv");
        end
        settle();
        if (hints == 0) fail("no polarity hint");
        raw_valid = 0;

        if (errors == 0) begin $display("PASS usb3_frame"); $finish; end
        else $fatal(1, "FAIL usb3_frame: %0d errors", errors);
        $finish;
    end
endmodule
