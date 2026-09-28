// usb_hs_cdr test: HS packets (SYNC + random NRZI-ish bits + EOP-like tail)
// with idle gaps, sampled by three receivers at 0 / 1/3 / 2/3 UI with a
// frequency offset; the recovered byte stream must contain every packet's
// bit sequence in order.
`timescale 1ns/1ps
module hs_cdr_tb #(parameter real PPM = 500.0, parameter real PHASE0 = 0.2, parameter int NPKT = 40, parameter int PKT_BITS = 400, parameter int IIR = 2, parameter int HYST = 2);
    localparam real UI = 2.0833;
    logic clk = 0, rst = 1;
    always #(16.6667 / 2) clk = ~clk;

    // ---- line model: bit stream with idle gaps ----
    // level[n]: 1 = J, 0 = K during packets; idle = SE0 (dd noise, dp = dn = 0)
    logic       lvl[$];       // per bit index
    logic       act[$];       // 1 = packet bit, 0 = idle bit
    int         pkt_start[$];
    initial begin
        for (int p = 0; p < NPKT; p++) begin
            for (int g = 0; g < ((p % 9 == 8) ? 3000 : 40 + (p % 7) * 13); g++) begin lvl.push_back(1'b1); act.push_back(0); end   // idle gap (one long gap in 9)
            pkt_start.push_back(lvl.size());
            for (int i = 0; i < 32; i++) begin lvl.push_back(i[0]); act.push_back(1); end       // SYNC KJKJ... (K first = 0)
            // random NRZI levels with the USB bit-stuffing property: at most 7 consecutive equal levels
            begin
                logic cur = 1'b1; int run = 1;
                for (int i = 0; i < PKT_BITS; i++) begin
                    logic nxt = (run >= 7) ? ~cur : $urandom_range(1);
                    run = (nxt == cur) ? run + 1 : 1; cur = nxt;
                    lvl.push_back(cur); act.push_back(1);
                end
            end
            for (int i = 0; i < 8; i++) begin lvl.push_back(1'b1); act.push_back(1); end          // tail
        end
        for (int g = 0; g < 400; g++) begin lvl.push_back(1'b1); act.push_back(0); end
    end
    real ui_tx = UI * (1.0 + PPM / 1e6);
    real tnow = 0.0;
    function automatic int bit_at(input real t); return int'($floor(t / ui_tx)); endfunction
    logic [7:0] dd, dp, dn; logic se0;
    always @(posedge clk) begin
        int n; int nse0 = 0;
        for (int k = 0; k < 8; k++) begin
            n = bit_at(tnow + PHASE0 + UI * k);                 dd[k] <= (n < lvl.size() && act[n]) ? lvl[n] : $urandom_range(1);
            n = bit_at(tnow + PHASE0 + UI * k - UI / 3.0);      dp[k] <= (n < lvl.size() && act[n]) ? lvl[n] : 1'b0;   // sampled 1/3 UI "later" = earlier bit time
            n = bit_at(tnow + PHASE0 + UI * k - 2.0 * UI / 3.0); dn[k] <= (n < lvl.size() && act[n]) ? ~lvl[n] : 1'b0;
            n = bit_at(tnow + PHASE0 + UI * k);                 if (!(n < lvl.size() && act[n])) nse0++;
        end
        se0 <= (nse0 >= 5);
        tnow <= tnow + 16.6667;
    end
    // NOTE: the delayed comparator paths see the line 1/3 and 2/3 UI *earlier*
    // in bit time (an IODELAY delays the signal), so in time order the sample
    // triplet is [dd(t), dp(t+1/3), dn(t+2/3)] of the line at t-0, t-1/3... —
    // the interleave order in usb_hs_cdr assumes dp/dn lag dd, which is what
    // a delayed path gives: dp[k] shows the line at (t_k - 1/3 UI).

    logic [7:0] o_byte, o_dp, o_dn; logic o_valid, o_lock;
    usb_hs_cdr #(.CDR_IIR(IIR), .CDR_HYST(HYST)) dut(.clk_i(clk), .rst_i(rst), .i_dd(dd), .i_dp(dp), .i_dn(dn), .i_se0(se0),
                   .o_byte(o_byte), .o_valid(o_valid), .o_dp(o_dp), .o_dn(o_dn), .o_lock(o_lock));

    // ---- collect recovered bits ----
    logic rec[$]; int rec_clk[$]; int clkidx = 0;
    // CDR internals per clock (for diagnosis)
    int h_dsel[$], h_nbits[$], h_posu[$], h_slip[$], h_lock[$]; logic [23:0] h_s[$];
    always @(posedge clk) begin
        if (!rst && o_valid) for (int b = 0; b < 8; b++) begin rec.push_back(o_byte[b]); rec_clk.push_back(clkidx); end
        h_dsel.push_back(dut.u_cdr.dsel); h_nbits.push_back(dut.u_cdr.o_nbits); h_posu.push_back(dut.u_cdr.posu);
        h_slip.push_back(dut.u_cdr.o_slip); h_lock.push_back(dut.u_cdr.lock); h_s.push_back(dut.s24_m);
        clkidx++;
    end

    initial begin
        repeat (5) @(posedge clk); rst = 0;
        wait (tnow > (lvl.size() + 10) * ui_tx);
        repeat (50) @(posedge clk);
        begin
            int found = 0, pos = 0, lost_shown = 0;
            for (int p = 0; p < NPKT; p++) begin
                int s = pkt_start[p]; int len = 32 + PKT_BITS + 8; int hit = -1;
                // search the recovered stream (from pos) for this packet's bits (skip the first 16 SYNC bits: acquisition)
                for (int i = pos; i + len - 16 <= rec.size(); i++) begin
                    bit ok = 1;
                    for (int j = 16; j < len; j++) if (rec[i + j - 16] != lvl[s + j]) begin ok = 0; break; end
                    if (ok) begin hit = i; break; end
                end
                if (hit >= 0) begin found++; pos = hit + len - 16; end
                else begin
                    // diagnose: align on the first 24 bits after the skipped SYNC part and report the first mismatch
                    int best_i = -1, best_m = -1;
                    for (int i = pos; i + 48 <= rec.size() && i < pos + 4000; i++) begin
                        int m = 0;
                        for (int j = 16; j < 40; j++) if (rec[i + j - 16] == lvl[s + j]) m++;
                        if (m > best_m) begin best_m = m; best_i = i; end
                    end
                    if (best_i >= 0 && best_m >= 22) begin
                        int first = -1;
                        for (int j = 16; j < len && best_i + j - 16 < rec.size(); j++) if (rec[best_i + j - 16] != lvl[s + j]) begin first = j; break; end
                        if (first >= 0 && lost_shown < 4) begin
                            string e = "", r = "";
                            for (int j = first - 12; j < first + 12; j++) begin e = {e, lvl[s + j] ? "1" : "0"}; r = {r, rec[best_i + j - 16] ? "1" : "0"}; end
                            $display("packet %0d: first mismatch at bit %0d of %0d  expected ...%s...  got ...%s...", p, first, len, e, r);
                            begin
                                int c = rec_clk[best_i + first - 16];
                                for (int w = c - 7; w <= c + 1; w++) if (w >= 0 && w < h_dsel.size())
                                    $display("      clk %0d: dsel=%0d posu=%0d nbits=%0d slip=%0d lock=%0d samples(23..0)=%b", w, h_dsel[w], h_posu[w], h_nbits[w], h_slip[w], h_lock[w], h_s[w]);
                            end
                            lost_shown++;
                        end
                        pos = best_i + len - 16;
                    end
                    $display("packet %0d not found in the recovered stream (pos %0d, rec %0d bits)", p, pos, rec.size());
                    if (p < 2) begin
                        string e = "", r = "";
                        for (int j = 0; j < 72; j++) e = {e, lvl[s + j] ? "1" : "0"};
                        for (int j = pos; j < pos + 120 && j < rec.size(); j++) r = {r, rec[j] ? "1" : "0"};
                        $display("  expected: %s", e); $display("  recovered from pos: %s", r);
                    end
                end
            end
            $display("ppm=%0.0f phase0=%0.2f IIR=%0d HYST=%0d: %0d / %0d packets recovered, %0d bits out", PPM, PHASE0, IIR, HYST, found, NPKT, rec.size());
            if (found != NPKT) $fatal(1, "packets lost");
            $display("PASS");
        end
        $finish;
    end
endmodule
