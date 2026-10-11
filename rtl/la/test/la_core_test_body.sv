// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// (acts only with RUN = 1; ends with $finish on success, $fatal on failure)
// LaCore end to end: registers -> capture -> host stream, checked sample by sample against a model
// of the test patterns (PRBS15 / PRBS17 with the test clock) and of pin patterns driven here.
`timescale 1ns/1ps
module la_core_test_body #(parameter RUN = 0) ();
    logic uclk = 0, sclk = 0, urst = 1, srst = 1;
    always #4 uclk = ~uclk;           // 125 MHz
    always #5 sclk = ~sclk;           // 100 MHz

    logic reg_wr = 0; logic [7:0] reg_addr = 0; logic [15:0] reg_wdata = 0; logic [31:0] reg_rdata;
    logic tvalid, tlast, tready = 0; logic [31:0] tdata;
    logic pwm, active;
    logic [63:0] raw_a = 0, raw_b = 0; logic [7:0] ck_a = 0, ck_b = 0;

    LaCore #(.FIFO_AW(6), .BLK(16), .TIMEOUT(300)) dut (
        .i_uclk(uclk), .i_urst(urst), .i_reg_wr(reg_wr), .i_reg_addr(reg_addr), .i_reg_wdata(reg_wdata),
        .o_reg_rdata(reg_rdata), .o_tvalid(tvalid), .o_tdata(tdata), .o_tlast(tlast), .i_tready(tready),
        .o_pwm(pwm), .o_active(active), .i_salive(1'b1),
        .i_sclk(sclk), .i_srst(srst), .i_raw_a(raw_a), .i_raw_b(raw_b), .i_ck_a(ck_a), .i_ck_b(ck_b));

    int errors = 0;
    string stage = "";
    task automatic fail(string m);
        errors++;
        $display("FAIL [%s] %s", stage, m);
    endtask

    // ---------------------------------------------------------------- host side
    task automatic wr(input [7:0] a, input [15:0] d);
        @(posedge uclk); reg_wr <= 1; reg_addr <= a; reg_wdata <= d;
        @(posedge uclk); reg_wr <= 0;
    endtask
    task automatic rd(input [7:0] a, output [31:0] d);
        @(posedge uclk); reg_addr <= a; @(posedge uclk); #1 d = reg_rdata;
    endtask

    // stream sink with random backpressure (ready_pct %)
    int ready_pct = 100;
    string dumpdir = ""; int ncap = 0;
    initial void'($value$plusargs("dump=%s", dumpdir));
    logic [31:0] rxq[$];
    always @(posedge uclk) begin
        if (tvalid && tready) rxq.push_back(tdata);
        tready <= ($urandom % 100) < ready_pct;
    end

    // ---------------------------------------------------------------- pin patterns (sclk)
    // pin mode: every sample of a group is a running counter (CH0..7 = counter bits); the clock
    // input of each group is a square wave of half period ck_half (low first) on the same counter
    int unsigned pin_k = 0;
    int ck_half_a = 8, ck_half_b = 4;   // (at most one used edge per word)
    always @(posedge sclk) begin
        for (int i = 0; i < 8; i++) begin
            int unsigned k = pin_k + i;
            raw_a[i*8 +: 8] <= 8'(k);
            raw_b[i*8 +: 8] <= 8'(k * 3);
            ck_a[i] <= (k / ck_half_a) & 1;
            ck_b[i] <= (k / ck_half_b) & 1;
        end
        pin_k <= pin_k + 8;
    end

    // ---------------------------------------------------------------- model of the test patterns
    byte unsigned tab15[32767], tab17[131071];
    function automatic void make_tabs();
        logic [14:0] s15 = '1; logic [16:0] s17 = '1;
        for (int i = 0; i < 32767; i++) begin
            byte unsigned v = 0;
            for (int b = 0; b < 8; b++) begin logic nb = s15[14] ^ s15[13]; v[b] = nb; s15 = {s15[13:0], nb}; end
            tab15[i] = v;
        end
        for (int i = 0; i < 131071; i++) begin
            byte unsigned v = 0;
            for (int b = 0; b < 8; b++) begin logic nb = s17[16] ^ s17[13]; v[b] = nb; s17 = {s17[15:0], nb}; end
            tab17[i] = v;
        end
    endfunction

    // the raw sample positions a group takes, in order (positions count from word 0 of the capture)
    typedef struct { int cmode; int wlog; int skew; int test; int div; int thalf; int ck_sel; } cfg_t;
    function automatic longint next_pos(cfg_t c, int half, ref longint k, input longint j);
        // internal: 8 + j div; edges: the k-th sample where the clock (k / half) & 1 changes as asked
        if (c.cmode == 0) return 8 + j * c.div;
        forever begin
            int lv = (k / half) & 1, lp = ((k - 1) / half) & 1;
            longint kk = k; k++;
            if ((c.cmode == 1 && lv && !lp) || (c.cmode == 2 && !lv && lp) || (c.cmode == 3 && lv != lp))
                return kk - c.skew;
        end
    endfunction

    // ---------------------------------------------------------------- stream parsing
    // (module-level state: Verilator takes only plain variables as ref arguments)
    logic [31:0] sw[2][$];
    int s_started[2], s_ended[2], s_nseq[2], s_seqerr[2];
    logic [63:0] s_sbeat[2], s_ebeat[2];
    function automatic void parse(input int capid);
        int i = 0;
        for (int g = 0; g < 2; g++) begin
            sw[g].delete(); s_started[g] = 0; s_ended[g] = 0; s_nseq[g] = 0; s_seqerr[g] = 0; s_sbeat[g] = 0; s_ebeat[g] = 0;
        end
        while (i < rxq.size()) begin
            logic [31:0] h = rxq[i]; int ty = h[31:28], s = h[26], len = h[15:0];
            if (h[27] || h[25:24] != 0 || i + len >= rxq.size() + 1) begin
                fail($sformatf("bad header %08x at %0d of %0d", h, i, rxq.size())); return;
            end
            if (ty == 4 || ty == 5) begin
                logic [63:0] b = {rxq[i+2], rxq[i+1]};
                if (len != 2) fail($sformatf("event len %0d", len));
                if (h[23:16] != capid) fail($sformatf("capture id %0d", h[23:16]));
                if (ty == 4) begin s_started[s]++; s_sbeat[s] = b; s_nseq[s] = 0; end
                else begin s_ended[s]++; s_ebeat[s] = b; end
            end else if (ty == 1) begin
                if (!s_started[s] || s_ended[s]) fail("data outside START..END");
                if (h[23:16] != 8'(s_nseq[s])) s_seqerr[s]++;
                s_nseq[s]++;
                for (int k = 1; k <= len; k++) sw[s].push_back(rxq[i + k]);
            end else fail($sformatf("header type %0d", ty));
            i += len + 1;
        end
    endfunction

    // the sample j of a stream from its payload words
    function automatic int get_sample(input int g, input longint j, input int wlog);
        longint bit0 = j << wlog; int W = 1 << wlog;
        return (sw[g][bit0 / 32] >> (bit0 % 32)) & ((1 << W) - 1);
    endfunction

    // checks one stream: START / END, sizes and every sample against the model
    //   mode 0: test patterns, 1: pin counter pattern
    task automatic check_stream(input int g, input cfg_t c, input int mode, input int exp_ovf);
        // (edge clocks: data from sample 8 on, i.e. edges from 8 + skew)
        longint cnt, nw, kpos = 8 + (c.cmode != 0 ? c.skew : 0); int W = 1 << c.wlog, half, step = g ? 3 : 1;
        if (s_started[g] != 1 || s_ended[g] != 1) begin
            fail($sformatf("group %0d: %0d START %0d END", g, s_started[g], s_ended[g]));
            for (int i = (rxq.size() > 12 ? rxq.size() - 12 : 0); i < rxq.size(); i++) $display("      rx[%0d] %08x", i, rxq[i]);
            return;
        end
        if (s_seqerr[g]) fail($sformatf("group %0d: %0d block sequence errors", g, s_seqerr[g]));
        if (s_sbeat[g][1:0] != c.wlog) fail($sformatf("group %0d: START cfg %h", g, s_sbeat[g]));
        cnt = s_ebeat[g][47:0];
        if (s_ebeat[g][57:56] != exp_ovf) fail($sformatf("group %0d: END flags %0d", g, s_ebeat[g][57:56]));
        // payload: the samples rounded up to 8, then to a 64-bit word
        nw = ((((cnt + 7) / 8) * 8 * W) + 63) / 64 * 2;
        if (sw[g].size() != nw) fail($sformatf("group %0d: %0d samples but %0d words (expected %0d)", g, cnt, sw[g].size(), nw));
        if (cnt < 16 && exp_ovf == 0) fail($sformatf("group %0d: only %0d samples", g, cnt));
        half = c.test ? c.thalf : ((c.ck_sel ? !g : g) ? ck_half_b : ck_half_a);
        begin
            int bad = 0, prev = 0;
            longint dk = (c.cmode == 0) ? c.div : (c.cmode == 3 ? half : 2 * half);
            for (longint j = 0; j < cnt && bad < 5; j++) begin
                longint k = next_pos(c, half, kpos, j);
                int got = get_sample(g, j, c.wlog), exp;
                if (mode == 0) begin
                    exp = (g == 0 ? tab15[k % 32767] : tab17[k % 131071]) & ((1 << W) - 1);
                    if (got != exp) begin bad++; fail($sformatf("group %0d sample %0d (pos %0d): %02x, expected %02x", g, j, k, got, exp)); end
                end else begin
                    // pin counter (8 channels): consecutive samples step by the sample distance
                    if (j > 0) begin
                        exp = (prev + step * dk) & 255;
                        if (got != exp) begin bad++; fail($sformatf("group %0d pin sample %0d: %02x, expected %02x", g, j, got, exp)); end
                    end
                    prev = got;
                    if (c.cmode != 0) begin
                        // taken `skew` samples before a clock edge: (counter + skew) is an edge position
                        int pos = (g ? (got * 171) & 255 : got) + c.skew;   // 171 = 3^-1 mod 256
                        int lv = (pos / half) & 1, lp = ((pos - 1) / half) & 1;
                        // (only below the counter wrap, where the clock phase follows the 8-bit value: 256 % (2 half) may be nonzero)
                        if (pin_wrap_ok(half) && pos >= half && pos < 256 &&
                            !((c.cmode == 1 && lv && !lp) || (c.cmode == 2 && !lv && lp) || (c.cmode == 3 && lv != lp)))
                            begin bad++; fail($sformatf("group %0d pin sample %0d: %02x not at a clock edge", g, j, got)); end
                    end
                end
            end
            // the padding is zero
            for (longint b = cnt << c.wlog; b < longint'(sw[g].size()) * 32; b++)
                if ((sw[g][b / 32] >> (b % 32)) & 1) begin fail($sformatf("group %0d: padding bit %0d set", g, b)); break; end
        end
    endtask
    function automatic int pin_wrap_ok(int half); return (256 % (2 * half)) == 0; endfunction

    // one capture: configure, run `clocks` sclk, stop, read everything out, check
    task automatic capture(input string name, input int groups, input cfg_t ca, input cfg_t cb, input int clocks,
                           input int mode, input int ovf_a = 0, input int ovf_b = 0, input int capid = 5);
        stage = name;
        rxq.delete();
        wr(8'h01, 16'(groups));
        wr(8'h02, 16'({ca.ck_sel[0], ca.skew[2:0], ca.test[0], ca.cmode[1:0], ca.wlog[1:0]}));
        wr(8'h03, ca.div[15:0]); wr(8'h04, 16'(ca.div[23:16])); wr(8'h05, 16'(ca.thalf));
        wr(8'h0A, 16'({cb.ck_sel[0], cb.skew[2:0], cb.test[0], cb.cmode[1:0], cb.wlog[1:0]}));
        wr(8'h0B, cb.div[15:0]); wr(8'h0C, 16'(cb.div[23:16])); wr(8'h0D, 16'(cb.thalf));
        repeat (4) @(posedge uclk);
        wr(8'h00, 16'(capid << 8) | 16'h1);
        repeat (clocks) @(posedge sclk);
        wr(8'h00, 16'(capid << 8));
        // until both ENDs are out and the stream is quiet
        begin
            int quiet = 0;
            while (quiet < 2000) begin
                int n = rxq.size();
                @(posedge uclk);
                quiet = (rxq.size() == n) ? quiet + 1 : 0;
            end
        end
        // (+dump=DIR: the stream of each capture to DIR/capNN.bin, for host/la_stream -f)
        if (dumpdir != "") begin
            int fd = $fopen($sformatf("%s/cap%02d.bin", dumpdir, ncap), "wb");
            foreach (rxq[i]) $fwrite(fd, "%c%c%c%c", rxq[i][7:0], rxq[i][15:8], rxq[i][23:16], rxq[i][31:24]);
            $fclose(fd);
        end
        ncap++;
        parse(capid);
        $display("    state: fe %0d/%0d pk %0d/%0d wempty %b level %0d/%0d qv %b framer %0d tmo %0d/%0d",
                 dut.u_fe_a.state, dut.u_fe_b.state, dut.g_grp[0].u_pk.state, dut.g_grp[1].u_pk.state,
                 dut.wempty, dut.q_level[0], dut.q_level[1], dut.q_tvalid, dut.u_framer.state, dut.u_framer.tmo[0], dut.u_framer.tmo[1]);
        for (int g = 0; g < 2; g++) begin
            if (groups & (1 << g)) check_stream(g, g ? cb : ca, mode, g ? ovf_b : ovf_a);
            else if (s_started[g] || sw[g].size()) fail($sformatf("group %0d disabled but sent data", g));
        end
        $display("  %-28s A %0d samples, B %0d samples, %0d words, errors so far %0d", name,
                 s_ebeat[0][47:0], s_ebeat[1][47:0], rxq.size(), errors);
    endtask

    initial if (RUN) begin
        cfg_t a, b; logic [31:0] v;
        make_tabs();
        repeat (5) @(posedge uclk); urst = 0;
        repeat (5) @(posedge sclk); srst = 0;
        repeat (5) @(posedge uclk);
        stage = "id"; rd(8'h00, v); if (v != 32'h01004C41) fail($sformatf("id %08x", v));

        // test patterns, internal clock
        a = '{cmode: 0, wlog: 2, skew: 0, test: 1, div: 1, thalf: 4, ck_sel: 0};
        b = '{cmode: 0, wlog: 3, skew: 0, test: 1, div: 2, thalf: 4, ck_sel: 0};
        capture("A 4ch div1", 1, a, b, 300, 0);
        a.wlog = 3; a.div = 2;
        capture("A 8ch div2", 1, a, b, 300, 0, 0, 0, 6);
        a.wlog = 2; b.wlog = 2;
        capture("A+B 4ch div2", 3, a, b, 300, 0);
        a.wlog = 0; a.div = 4; b.wlog = 1; b.div = 8;
        capture("A 1ch div4, B 2ch div8", 3, a, b, 400, 0);
        a.wlog = 3; a.div = 9; b.wlog = 0; b.div = 13;
        capture("A 8ch div9, B 1ch div13", 3, a, b, 600, 0);
        a.div = 3; b.div = 8;
        capture("A div3: not supported", 3, a, b, 300, 0, 2, 0);
        a.wlog = 3; a.div = 100; b.wlog = 2; b.div = 37;
        capture("slow (timeout blocks)", 3, a, b, 3000, 0);
        // test clock
        a = '{cmode: 1, wlog: 3, skew: 2, test: 1, div: 1, thalf: 4, ck_sel: 0};
        b = '{cmode: 3, wlog: 2, skew: 0, test: 1, div: 1, thalf: 8, ck_sel: 0};
        capture("ext rise 100M / both 50M", 3, a, b, 400, 0);
        a.cmode = 2; a.thalf = 4; a.skew = 7; a.wlog = 2; b.cmode = 1; b.thalf = 16; b.skew = 4; b.wlog = 3;
        capture("ext fall 100M / rise 25M", 3, a, b, 400, 0);
        // overflow: 8 channels at 800 MS/s (800 MB/s) into a 500 MB/s stream with a slow reader
        ready_pct = 50;
        a = '{cmode: 0, wlog: 3, skew: 0, test: 1, div: 1, thalf: 4, ck_sel: 0};
        capture("overflow", 1, a, b, 2000, 0, 1, 0);
        // an edge clock faster than 4 samples per word: END flag bit 1 (B keeps going)
        a = '{cmode: 3, wlog: 2, skew: 0, test: 1, div: 1, thalf: 1, ck_sel: 0};
        b = '{cmode: 1, wlog: 2, skew: 0, test: 1, div: 1, thalf: 4, ck_sel: 0};
        capture("edge clock too fast", 3, a, b, 300, 0, 2, 0);
        ready_pct = 70;
        // pin patterns
        a = '{cmode: 0, wlog: 3, skew: 0, test: 0, div: 4, thalf: 1, ck_sel: 0};
        b = '{cmode: 1, wlog: 3, skew: 2, test: 0, div: 1, thalf: 1, ck_sel: 0};
        capture("pins div4 / ext rise", 3, a, b, 400, 1);
        a.cmode = 3; a.skew = 1; b.ck_sel = 1; b.cmode = 2; b.skew = 0;
        capture("pins both / B on A's clock", 3, a, b, 400, 1);
        ready_pct = 100;
        a = '{cmode: 0, wlog: 1, skew: 0, test: 1, div: 1, thalf: 4, ck_sel: 0};
        capture("again (new capture id)", 1, a, b, 200, 0, 0, 0, 9);

        if (errors == 0) begin $display("la_core: PASS"); $finish; end
        else $fatal(1, "la_core: FAIL (%0d errors)", errors);
    end
    initial if (RUN) begin #20ms; $fatal(1, "la_core: FAIL (timeout in %s)", stage); end
endmodule
