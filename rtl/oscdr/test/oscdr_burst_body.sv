// OsCdr burst test: packets (32-bit alternating SYNC + random data + EOP)
// separated by idle (constant level) with a random phase per packet, as on a
// USB HS link. i_reacq follows the idle detector with a 12-word lag (as in
// usb_hs_os32: the DLY-delayed extraction must have finished the previous
// packet before a jump may happen). Every packet's levels from SYNC
// bit 8 on must appear verbatim in the extracted bit stream: no bit
// duplicated or dropped by the acquisition inside the SYNC (the first bits,
// extracted before the acquisition from a partial word, may be garbled: the
// USB SYNC detector only needs a few clean alternations before the final 1).
`timescale 1ns/1ps
module oscdr_burst_body #(
    parameter real PPM    = 0.0,
    parameter real JITTER = 0.0,
    parameter int  NB     = 40,
    parameter int  DLY    = 9,
    parameter bit  RUN    = 0
) ();
    localparam int  SAMPLES = 32, OSR = 8;
    localparam real UI_NS = 2.0833;
    localparam real CLK_NS = UI_NS * SAMPLES / OSR;
    localparam real SP_NS  = UI_NS / OSR;
    localparam int  NBITS  = 32 + 64 + 8;
    logic clk = 0, rst = 1;
    always #(CLK_NS / 2) clk = ~clk;

    real  ui_tx = UI_NS * (1.0 + PPM / 1e6);
    real  bstart [NB];
    logic pat [NB][NBITS];
    initial begin
        real t = 300.0;
        for (int k = 0; k < NB; k++) begin
            int run = 0; logic lv = 1;
            bstart[k] = t + ($urandom() / 4294967296.0) * ui_tx;
            for (int i = 0; i < 32; i++) pat[k][i] = i % 2;          // SYNC: K J K J ... (ends on J = 1)
            for (int i = 32; i < 96; i++) begin                      // data: random levels, runs <= 6
                logic nb = $urandom() % 2;
                if (nb == lv) begin run++; if (run > 6) begin nb = ~lv; run = 1; end end else run = 1;
                lv = nb; pat[k][i] = nb;
            end
            pat[k][96] = ~lv;                                        // EOP: one transition then 7 flat
            for (int i = 97; i < NBITS; i++) pat[k][i] = ~lv;
            t = bstart[k] + NBITS * ui_tx + 300.0 + ($urandom() % 1200);
        end
    end
    function automatic logic in_burst(input real t, output int k, output int n);
        for (k = 0; k < NB; k++) begin
            if (t >= bstart[k] && t < bstart[k] + NBITS * ui_tx) begin
                real rel = t - bstart[k];
                n = int'($floor(rel / ui_tx));
                if (JITTER != 0.0) begin
                    real edge_shift = JITTER * ui_tx * (2.0 * ($urandom() / 4294967296.0) - 1.0);
                    if (rel < n * ui_tx + edge_shift && n > 0) n = n - 1;
                end
                return 1;
            end
        end
        return 0;
    endfunction
    function automatic logic sample_at(input real t);
        int k, n;
        if (in_burst(t, k, n)) return pat[k][n];
        return 1;
    endfunction

    real tnow = 0.0;
    logic [SAMPLES-1:0] samples;
    logic idle_now; logic [11:0] idle_sh; logic reacq;
    always @(posedge clk) begin
        int k, n;
        for (int j = 0; j < SAMPLES; j++) samples[j] <= sample_at(tnow + SP_NS * j);
        idle_now <= !in_burst(tnow, k, n);
        idle_sh  <= {idle_sh[10:0], idle_now};
        reacq    <= idle_sh[11];
        tnow     <= tnow + CLK_NS;
    end

    logic [4:0] bits; logic [3:0] nbits; logic lock, slip; logic [2:0] phase;
    OsCdr #(.SAMPLES(SAMPLES), .OSR(OSR), .IIR(2), .HYST(2), .ACT_MIN(1), .DLY(DLY)) cdr (
        .i_clk(clk), .i_rst(rst), .i_samples(samples), .i_freeze(1'b0), .i_reacq(reacq), .i_phase_force(1'b0), .i_phase_val('0), .i_phase_ofs(1'b0), .o_cnt(), .o_acq(),
        .o_bits(bits), .o_nbits(nbits), .o_phase(phase), .o_lock(lock), .o_slip(slip),
        .o_acc_first(), .o_acc_last());

    string rx = "";
    always @(posedge clk) if (!rst) for (int j = 0; j < nbits; j++) rx = {rx, bits[j] ? "1" : "0"};

    // phase centring: at the end of each packet's SYNC, o_phase should sit
    // about half a UI after the edge class (edge class = the sample index
    // just after a transition, mod OSR)
    int worst_dev = 0;
    always @(posedge clk) if (!rst) begin
        int k, n;
        real tw = tnow - CLK_NS * (DLY + 1);      // word whose bits are being extracted now (DLY words behind)
        if (in_burst(tw, k, n) && n == 40) begin   // in the data, right after the SYNC
            real tedge = bstart[k] + (n + 1) * ui_tx;               // next edge time
            int  ec   = int'($ceil((tedge - tw) / SP_NS)) % OSR;    // class of the first sample after it
            int  want = (ec + OSR / 2) % OSR;
            int  dev  = (int'(phase) - want + OSR + OSR / 2) % OSR - OSR / 2;
            if (dev < 0) dev = -dev;
            if (dev > worst_dev) worst_dev = dev;
        end
    end

    initial begin
        int found = 0;
        if (!RUN) begin #1; $finish; end
        idle_sh = '1; reacq = 1; idle_now = 1;
        repeat (4) @(posedge clk); rst = 0;
        #(bstart[NB-1] + NBITS * ui_tx + 2000.0);
        for (int k = 0; k < NB; k++) begin
            string want = "";
            int hit = -1;
            for (int i = 8; i < NBITS; i++) want = {want, pat[k][i] ? "1" : "0"};
            for (int p = 0; p + want.len() <= rx.len(); p++) begin
                if (rx.substr(p, p + want.len() - 1) == want) begin hit = p; break; end
            end
            if (hit >= 0) found++;
            else begin
                int q = -1;
                string head = want.substr(16, 55);   // 40 bits from inside the SYNC / start of data
                for (int p = 0; p + 40 <= rx.len(); p++) if (rx.substr(p, p + 39) == head) begin q = p; break; end
                $display("burst %0d NOT found (starts %.1f ns)", k, bstart[k]);
                if (q >= 0) begin
                    $display("  want: %s", want.substr(0, NBITS - 9));
                    $display("  got : %s", rx.substr(q - 16, q - 16 + NBITS - 9));
                end else $display("  (head not found either)");
            end
        end
        $display("oscdr_burst: %0d / %0d packets recovered intact, worst phase deviation from eye centre %0d/%0d UI (PPM=%0.0f JITTER=%0.2f DLY=%0d)", found, NB, worst_dev, OSR, PPM, JITTER, DLY);
        if (found != NB) $error("oscdr_burst: %0d packets corrupted", NB - found);
        if (worst_dev > 2) $error("oscdr_burst: sample phase %0d/%0d UI off centre", worst_dev, OSR);
        $finish;
    end
endmodule
