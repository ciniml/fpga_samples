// Replay hardware-captured receiver samples (usb_device capture: 6 bytes per
// 60 MHz word: dp, dn, dd raw, ...) through usb_hs_cdr and count USB packets
// whose PID check passes (PID[3:0] == ~PID[7:4]) after NRZI decoding.
// The SE0 filter mirrors usb_phy_gowin (24-sample majority, 2-word delay).
`timescale 1ns/1ps
module hs_cdr_replay #(parameter string FILE = "cap.hex", parameter int N = 2048, parameter int IIR = 2, parameter int HYST = 2);
    logic clk = 0, rst = 1;
    always #(16.6667 / 2) clk = ~clk;
    logic [47:0] mem [0:N-1];
    initial $readmemh(FILE, mem);

    int idx = 0;
    logic [7:0] dp_raw, dn_raw, dd_raw;
    logic [7:0] dd_d1, dd_d2, dp_d1, dp_d2, dn_d1, dn_d2;
    logic [3:0] c0, c1, c2;
    function automatic logic [3:0] pop8(input logic [7:0] v); pop8 = 0; for (int k = 0; k < 8; k++) pop8 += v[k]; endfunction
    wire [7:0] se0_raw = ~dp_raw & ~dn_raw;
    always @(posedge clk) begin
        if (idx < N) begin dp_raw <= mem[idx][7:0]; dn_raw <= mem[idx][15:8]; dd_raw <= mem[idx][23:16]; end
        else begin dp_raw <= 0; dn_raw <= 0; dd_raw <= 1'b1; end
        idx <= idx + 1;
        dd_d1 <= dd_raw; dd_d2 <= dd_d1; dp_d1 <= dp_raw; dp_d2 <= dp_d1; dn_d1 <= dn_raw; dn_d2 <= dn_d1;
        c0 <= pop8(se0_raw); c1 <= c0; c2 <= c1;
    end
    wire se0_f = ({1'b0, c0} + {1'b0, c1} + {1'b0, c2}) >= 5'd12;

    logic [7:0] o_byte, o_dp, o_dn; logic o_valid, o_lock;
    usb_hs_cdr #(.CDR_IIR(IIR), .CDR_HYST(HYST)) dut(.clk_i(clk), .rst_i(rst), .i_track_en(1'b0), .i_dly_base(8'd0), .o_dly_dd(), .o_dly_dp(), .o_dly_dn(),
        .i_dd(dd_d2), .i_dp(dp_d2), .i_dn(dn_d2), .i_se0(se0_f),
        .o_byte(o_byte), .o_valid(o_valid), .o_dp(o_dp), .o_dn(o_dn), .o_lock(o_lock));

    // bit stream -> NRZI decode -> SYNC (KJKJ...KK: levels 0101...00) -> PID
    logic lv[$]; int lv_clk[$]; int ck = 0;
    int h_dsel[$], h_nbits[$], h_slip[$], h_lock[$], h_se0[$]; logic [23:0] h_s[$];
    always @(posedge clk) begin
        if (!rst && o_valid) for (int b = 0; b < 8; b++) begin lv.push_back(o_byte[b]); lv_clk.push_back(ck); end
        h_dsel.push_back(dut.u_cdr.dsel); h_nbits.push_back(dut.u_cdr.o_nbits); h_slip.push_back(dut.u_cdr.o_slip);
        h_lock.push_back(dut.u_cdr.lock); h_se0.push_back(se0_f); h_s.push_back(dut.s24_m); ck++;
    end
    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (N + 30) @(posedge clk);
        begin
            int pk = 0, good = 0, bad = 0;
            for (int i = 0; i + 40 < lv.size(); i++) begin
                // SYNC end: ... K J K K  (levels 0 1 0 0) preceded by at least 6 alternations
                bit s = 1;
                for (int j = 0; j < 8; j++) if (lv[i + j] != (j % 2 == 1)) begin s = 0; break; end  // 0101 0101
                if (s && lv[i + 8] == 0 && lv[i + 9] == 1 && lv[i + 10] == 0 && lv[i + 11] == 0) begin
                    // NRZI: bit = (level == previous level); PID follows the last SYNC bit (level 0)
                    logic [7:0] pid; logic prev = 0;
                    for (int b = 0; b < 8; b++) begin pid[b] = (lv[i + 12 + b] == prev); prev = lv[i + 12 + b]; end
                    pk++;
                    if (pid[3:0] == ~pid[7:4]) good++; else bad++;
                    $display("  packet %0d at bit %0d: PID %02x %s", pk, i, pid, (pid[3:0] == ~pid[7:4]) ? "ok" : "BAD");
                    if (pid[3:0] != ~pid[7:4]) begin
                        int c = lv_clk[i];
                        for (int w = c - 6; w <= c + 4; w++) if (w >= 0 && w < h_dsel.size())
                            $display("      clk %0d: se0=%0d dsel=%0d nbits=%0d slip=%0d lock=%0d s24=%b", w, h_se0[w], h_dsel[w], h_nbits[w], h_slip[w], h_lock[w], h_s[w]);
                        begin string r = ""; for (int j = i - 8; j < i + 40; j++) r = {r, lv[j] ? "1" : "0"}; $display("      levels: %s", r); end
                    end
                    i += 40;
                end
            end
            $display("REPLAY %s IIR=%0d HYST=%0d: %0d packets, %0d PID ok, %0d bad, %0d bits", FILE, IIR, HYST, pk, good, bad, lv.size());
        end
        $finish;
    end
endmodule
