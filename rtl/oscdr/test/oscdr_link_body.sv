// OsCdr + BitGearbox loopback with a behavioural OSIDES32-style sampler.
//   TX: PRBS7 at UI_TX = 1.0ns * (1 + PPM/1e6), optional edge jitter
//   RX: 32 samples per 8ns clock, 0.25ns apart, starting at PHASE0 [ns]
//   Check: 16-bit words -> self-syncing PRBS7 checker (exact error count)
// SCAN=1: freeze the CDR after lock and sweep the sample offset over one
// UI, printing the error count per step (behavioural eye scan).
`timescale 1ns/1ps
module oscdr_link_body #(
    parameter real PPM    = 0.0,
    parameter real JITTER = 0.0,      // peak edge jitter [UI], uniform
    parameter real PHASE0 = 0.11,     // initial sampling offset [ns]
    parameter int  NWORDS = 20000,    // clocks to run after lock
    parameter bit  SCAN   = 0,
    parameter bit  RUN    = 0
) ();
    logic clk = 0, rst = 1;
    always #4 clk = ~clk;   // 125MHz

    // ---- TX bit source: PRBS7 as a function of bit index ----
    logic [6:0] lfsr = 7'h5a;
    logic       prbs_bits[$];
    function automatic logic prbs_bit(input longint n);
        while (prbs_bits.size() <= n + 1) begin
            logic b = lfsr[6] ^ lfsr[5];
            prbs_bits.push_back(lfsr[6]);
            lfsr = {lfsr[5:0], b};
        end
        return prbs_bits[n];
    endfunction

    // ---- sampler ----
    real ui_tx = 1.0 * (1.0 + PPM / 1e6);
    real tnow  = 0.0;               // time of sample 0 of the current word
    real scan_off = 0.0;            // extra sample offset (eye scan)
    logic [31:0] samples;
    function automatic logic sample_at(input real t);
        // bit index whose interval contains t, with per-edge jitter on the boundary
        longint n = longint'($floor(t / ui_tx));
        real    nr = n;
        real    edge_shift = JITTER * ui_tx * (2.0 * ($urandom() / 4294967296.0) - 1.0);
        real    boundary = (nr * ui_tx) + edge_shift;   // jittered position of the edge before bit n
        // if t is before the jittered edge, we're still in bit n-1
        if (t < boundary && n > 0) return prbs_bit(n - 1);
        return prbs_bit(n);
    endfunction
    always @(posedge clk) begin
        for (int k = 0; k < 32; k++) samples[k] <= sample_at(tnow + PHASE0 + scan_off + 0.25 * k);
        tnow <= tnow + 8.0;
    end

    // ---- DUT ----
    logic       freeze = 0, lock, slip;
    logic [8:0] bits;
    logic [3:0] nbits;
    logic [1:0] phase;
    OsCdr #(.SAMPLES(32), .OSR(4)) cdr (
        .i_clk(clk), .i_rst(rst), .i_samples(samples), .i_freeze(freeze),
        .o_bits(bits), .o_nbits(nbits), .o_phase(phase), .o_lock(lock), .o_slip(slip));
    logic        w_valid;
    logic [15:0] w_data;
    BitGearbox #(.IN_MAX(9), .OUT_W(16)) gb (
        .i_clk(clk), .i_rst(rst), .i_bits(bits), .i_nbits(nbits), .o_valid(w_valid), .o_word(w_data));

    // ---- PRBS7 checker (self-sync history, then free-run compare) ----
    logic [30:0] hist = 0;
    int          synced = 0;        // bits seen since (re)sync
    longint      nbits_chk = 0, nerr = 0;
    int          slips = 0;
    always @(posedge clk) begin
        if (slip) slips++;
        if (w_valid) begin
            for (int i = 0; i < 16; i++) begin
                logic b = w_data[i];
                logic pred = hist[6] ^ hist[5];
                if (synced >= 64) begin
                    nbits_chk++;
                    if (pred != b) begin nerr++; hist = {hist[29:0], b}; end   // resync on error
                    else hist = {hist[29:0], pred};
                end else begin
                    hist = {hist[29:0], b}; synced++;
                end
            end
        end
    end

    // debug: trace the last few words before an error
    int dbg_printed = 0;
    logic [3:0] hist_posu[$]; logic [3:0] hist_nb[$]; logic hist_slip[$]; logic [31:0] hist_s[$];
    always @(posedge clk) begin
        hist_posu.push_back(cdr.posu); hist_nb.push_back(nbits); hist_slip.push_back(slip); hist_s.push_back(samples);
        if (hist_posu.size() > 6) begin void'(hist_posu.pop_front()); void'(hist_nb.pop_front()); void'(hist_slip.pop_front()); void'(hist_s.pop_front()); end
    end
    longint nerr_q = 0;
    always @(posedge clk) begin
        if (nerr != nerr_q && dbg_printed < 4) begin
            $display("  [%0t] error #%0d: posu/nbits/slip history (oldest first):", $time, nerr);
            for (int i = 0; i < hist_posu.size(); i++) $display("      posu=%0d nbits=%0d slip=%0d samples(bit31..0)=%b", hist_posu[i], hist_nb[i], hist_slip[i], hist_s[i]);
            dbg_printed++;
        end
        nerr_q = nerr;
    end

    int errors = 0;
    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end else $display("ok: %s", what);
    endtask

    initial if (RUN) begin
        repeat (4) @(posedge clk); rst = 0;
        // acquisition
        repeat (200) @(posedge clk);
        check("lock", lock);
        // settle checker, clear
        repeat (200) @(posedge clk);
        nbits_chk = 0; nerr = 0; slips = 0;
        repeat (NWORDS) @(posedge clk);
        $display("ppm=%0.0f jitter=%0.2fUI: bits=%0d errs=%0d slips=%0d lock=%0d phase=%0d",
                 PPM, JITTER, nbits_chk, nerr, slips, lock, phase);
        check("still locked", lock);
        check("zero errors", nerr == 0);
        begin
            // expected slips ~ |ppm| * bits / 1e6 / (1/OSR) = |ppm|*bits*4/1e6
            real exp_slips = (PPM < 0 ? -PPM : PPM) * nbits_chk * 4.0 / 1e6;
            check($sformatf("slip count plausible (exp ~%0.0f)", exp_slips),
                  (PPM == 0.0) ? slips <= 2 : (slips > exp_slips * 0.7 && slips < exp_slips * 1.3 + 2));
        end

        if (SCAN) begin
            // behavioural eye scan: freeze, sweep offset -0.5..+0.5 UI in 1/16 UI steps
            freeze = 1;
            for (int s = -8; s <= 8; s++) begin
                scan_off = s / 16.0;
                repeat (50) @(posedge clk);
                nbits_chk = 0; nerr = 0;
                repeat (2000) @(posedge clk);
                $display("scan %0.3f UI: errs=%0d / %0d", s / 16.0, nerr, nbits_chk);
            end
            scan_off = 0; freeze = 0;
        end

        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end
endmodule
