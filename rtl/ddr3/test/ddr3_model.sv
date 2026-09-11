// Copied from ~/repos/riscv-veryl/sim/ddr3/ddr3_model.sv (commit 78e2537) - behavioural DDR3 model for Verilator.
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
// Behavioural DDR3 SDRAM model for the slot-vector PHY interface of
// `Ddr3Ctrl` (see src/ddr3_ctrl.veryl and doc/ddr3_controller.md).
//
// The model is synchronous to pclk (= CK/2). Each pclk cycle carries eight
// *slots* (quarter CK each): the DQ/DQS/DM buses are sampled/driven once
// per slot, commands are sampled at the first CK edge of the cycle
// (slot 2), so the "pin level" waveform is the same one the Gowin
// OSER8/IDES8 based PHY produces, quantised to fclk half periods. This is
// enough to check the controller's command sequencing, the DDR3 timing
// (in units of CK), the write DQS/DQ relationship (DQ must be stable on
// both sides of every DQS edge, preamble/postamble present) and the read
// capture (data appears CL after the command plus a configurable delay,
// undriven slots return pseudo-random garbage).
//
// Modelled: init sequence (RESET#/CKE timing, MRS x4 with value checks,
// ZQCL), ACT / RD / WR (with and without auto precharge) / PRE / PREA /
// REF, per-bank open rows, tRCD tRP tRC tRAS tRTP tWR tRFC tMRD tMOD
// tZQinit tXPR checks, refresh starvation (9 x tREFI), fixed CL = CWL = 6
// (the DLL-off configuration), BL8 sequential bursts only.
//
// Storage: four byte-lane arrays indexed by 32-bit word, exactly like
// `Memory` (mem0 = byte 0 of the word), so the same `$readmemh` lane files
// can preload it. Device byte address = {row, bank, col, 1'b0}.
module ddr3_model #(
    parameter int ROW_BITS  = 13,
    parameter int COL_BITS  = 10,
    parameter int BANK_BITS = 3,
    parameter int CK_PS     = 6667,
    // DDR3 timing in ps (DDR3-1600, 1 Gb)
    parameter int T_RCD_PS    = 13_750,
    parameter int T_RP_PS     = 13_750,
    parameter int T_RC_PS     = 48_750,
    parameter int T_RAS_PS    = 35_000,
    parameter int T_WR_PS     = 15_000,
    parameter int T_RTP_PS    = 7_500,   // max(4 CK, 7.5 ns)
    parameter int T_RFC_PS    = 110_000,
    parameter int T_REFI_PS   = 7_800_000,
    parameter int T_XPR_PS    = 120_000, // tRFC + 10 ns
    parameter int T_RESET_PS  = 200_000_000,
    parameter int T_CKE_PS    = 500_000_000,
    parameter bit VERBOSE     = 0
) (
    input  logic         clk,        // pclk
    input  logic         rst,
    // extra read output delay (tDQSCK + flight time) in slots, 0..7
    input  logic [2:0]   rd_delay_slots,
    // duty-cycle distortion of the read data: odd beats start one slot
    // late (even beats last 3 slots, odd beats 1), as seen on the board
    input  logic         rd_odd_shift,

    input  logic         reset_n,
    input  logic         cke,
    input  logic         cs_n,
    input  logic         ras_n,
    input  logic         cas_n,
    input  logic         we_n,
    input  logic [2:0]   ba,
    input  logic [13:0]  a,
    input  logic [127:0] dq_out,
    input  logic [3:0]   dq_oe,
    input  logic [15:0]  dm_out,
    input  logic [15:0]  dqs_out,
    input  logic [3:0]   dqs_oe,
    output logic [127:0] dq_in,
    output logic [15:0]  dqs_in,

    output int           errors,
    output int           ref_count,
    output logic         init_done
);
    localparam int ADDR_BITS = ROW_BITS + BANK_BITS + COL_BITS + 1; // bytes
    localparam int WORDS     = 1 << (ADDR_BITS - 2);
    localparam int NBANKS    = 1 << BANK_BITS;

    logic [7:0] mem0 [0:WORDS-1];
    logic [7:0] mem1 [0:WORDS-1];
    logic [7:0] mem2 [0:WORDS-1];
    logic [7:0] mem3 [0:WORDS-1];

    // Timing in slots (1 slot = CK/4)
    function automatic longint ck_of(input longint ps);
        return (ps + CK_PS - 1) / CK_PS;
    endfunction
    localparam longint S_RCD   = 4 * ((T_RCD_PS + CK_PS - 1) / CK_PS);
    localparam longint S_RP    = 4 * ((T_RP_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_RC    = 4 * ((T_RC_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_RAS   = 4 * ((T_RAS_PS + CK_PS - 1) / CK_PS);
    localparam longint S_WR    = 4 * ((T_WR_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_RTP   = 4 * ((((T_RTP_PS + CK_PS - 1) / CK_PS) > 4) ? ((T_RTP_PS + CK_PS - 1) / CK_PS) : 4);
    localparam longint S_RFC   = 4 * ((T_RFC_PS + CK_PS - 1) / CK_PS);
    localparam longint S_REFI  = 4 * (T_REFI_PS / CK_PS);
    localparam longint S_XPR   = 4 * ((T_XPR_PS + CK_PS - 1) / CK_PS);
    localparam longint S_RESET = 4 * (T_RESET_PS / CK_PS);
    localparam longint S_CKE   = 4 * (T_CKE_PS / CK_PS);
    localparam longint S_MRD   = 4 * 4;
    localparam longint S_MOD   = 4 * 12;
    localparam longint S_ZQ    = 4 * 512;
    localparam int     CL      = 6;
    localparam int     CWL     = 6;
    localparam longint S_CL    = 4 * CL;
    localparam longint S_CWL   = 4 * CWL;

    longint cycle;          // pclk cycles since reset
    longint now;            // slot of CK0's rising edge this cycle (8*cycle + 2)

    // ---- init tracking ----
    longint t_reset_low, t_reset_high, t_cke_high, t_last_mrs, t_zqcl, t_last_ref;
    logic   reset_n_q, cke_q;
    logic   mr_set [0:3];
    logic [13:0] mr [0:3];
    logic   zq_done;
    logic   reset_ok, cke_ok;

    // ---- bank state ----
    logic   bank_open [0:NBANKS-1];
    logic [ROW_BITS-1:0] bank_row [0:NBANKS-1];
    longint t_act      [0:NBANKS-1]; // last ACT
    longint t_pre_done [0:NBANKS-1]; // earliest next ACT (tRP satisfied)
    longint t_pre_ok   [0:NBANKS-1]; // earliest explicit PRE (tRAS / tRTP / tWR)
    longint t_ap       [0:NBANKS-1]; // scheduled auto-precharge start, -1 if none

    // ---- data transfers ----
    typedef struct {
        logic   valid;
        longint t0;          // first DQS rising edge slot (first beat)
        logic [ROW_BITS-1:0] row;
        logic [BANK_BITS-1:0] bank;
        logic [COL_BITS-1:0] col;
        int     beats;       // beats captured so far (writes)
    } xfer_t;
    xfer_t wr_q [0:3];
    xfer_t rd_q [0:3];

    // previous-slot pin values for edge / stability checks
    logic [15:0] p_dq;
    logic        p_dq_oe;
    logic [1:0]  p_dm;
    logic [1:0]  p_dqs;
    logic        p_dqs_oe;

    logic [31:0] lfsr;

    function automatic longint byte_addr(input logic [ROW_BITS-1:0] row, input logic [BANK_BITS-1:0] bank, input logic [COL_BITS-1:0] col);
        return ((longint'(row) << (BANK_BITS + COL_BITS)) | (longint'(bank) << COL_BITS) | longint'(col)) << 1;
    endfunction

    function automatic logic [15:0] read_beat(input longint addr);
        longint w = addr >> 2;
        return addr[1] ? {mem3[w], mem2[w]} : {mem1[w], mem0[w]};
    endfunction

    task automatic write_beat(input longint addr, input logic [15:0] data, input logic [1:0] mask);
        longint w = addr >> 2;
        if (addr[1]) begin
            if (!mask[0]) mem2[w] = data[7:0];
            if (!mask[1]) mem3[w] = data[15:8];
        end else begin
            if (!mask[0]) mem0[w] = data[7:0];
            if (!mask[1]) mem1[w] = data[15:8];
        end
    endtask

    task automatic err(input string msg);
        errors++;
        $error("[ddr3_model] cycle %0d: %s", cycle, msg);
    endtask

    task automatic reset_state();
        ref_count = 0; init_done = 0;
        zq_done = 0; reset_ok = 0; cke_ok = 0;
        t_reset_low = 0; t_reset_high = -1; t_cke_high = -1; t_last_mrs = -1; t_zqcl = -1; t_last_ref = -1;
        reset_n_q = 1; cke_q = 0;
        for (int i = 0; i < 4; i++) begin mr_set[i] = 0; mr[i] = 0; wr_q[i].valid = 0; rd_q[i].valid = 0; end
        for (int b = 0; b < NBANKS; b++) begin
            bank_open[b] = 0; bank_row[b] = 0; t_act[b] = -100000; t_pre_done[b] = 0; t_pre_ok[b] = 0; t_ap[b] = -1;
        end
        p_dq = 0; p_dq_oe = 0; p_dm = 2'b11; p_dqs = 0; p_dqs_oe = 0;
    endtask

    initial begin
        errors = 0;
        lfsr = 32'hACE1_2357;
        cycle = 0; dq_in = 0; dqs_in = 0;
        reset_state();
    end

    // ------------------------------------------------------------------
    // Command / control processing (once per pclk, at CK0's rising edge)
    // ------------------------------------------------------------------
    task automatic do_auto_precharge(input longint t);
        // Apply scheduled auto-precharges whose start time has passed.
        for (int b = 0; b < NBANKS; b++) begin
            if (t_ap[b] >= 0 && t_ap[b] <= t) begin
                bank_open[b]  = 0;
                t_pre_done[b] = t_ap[b] + S_RP;
                t_ap[b]       = -1;
            end
        end
    endtask

    function automatic logic all_idle();
        for (int b = 0; b < NBANKS; b++) if (bank_open[b] || t_ap[b] >= 0) return 0;
        return 1;
    endfunction

    task automatic push_xfer(ref xfer_t q [0:3], input xfer_t x);
        for (int i = 0; i < 4; i++) begin
            if (!q[i].valid) begin q[i] = x; return; end
        end
        err("transfer queue overflow");
    endtask

    task automatic process_command();
        logic [2:0] c;
        int b;
        c = {ras_n, cas_n, we_n};
        b = int'(ba);

        // RESET# / CKE bookkeeping
        if (reset_n_q && !reset_n) t_reset_low = now;
        if (!reset_n_q && reset_n) begin
            t_reset_high = now;
            if (now - t_reset_low < S_RESET) err($sformatf("RESET# low for only %0d slots (need %0d)", now - t_reset_low, S_RESET));
            else reset_ok = 1;
        end
        if (!cke_q && cke) begin
            t_cke_high = now;
            if (!reset_n) err("CKE raised while RESET# low");
            else if (t_reset_high < 0 || now - t_reset_high < S_CKE) err($sformatf("CKE raised %0d slots after RESET# (need %0d)", now - t_reset_high, S_CKE));
            else cke_ok = 1;
        end
        reset_n_q = reset_n;
        cke_q     = cke;
        if (!reset_n) begin
            // asynchronous reset of the DRAM state
            for (int i = 0; i < 4; i++) mr_set[i] = 0;
            zq_done = 0; init_done = 0;
            for (int k = 0; k < NBANKS; k++) begin bank_open[k] = 0; t_ap[k] = -1; end
            return;
        end
        if (!cke || cs_n) return;
        if (c == 3'b111) return; // NOP

        if (t_cke_high < 0 || now - t_cke_high < S_XPR) err("command before tXPR after CKE high");
        if (t_last_ref >= 0 && now - t_last_ref < S_RFC) err("command within tRFC after REFRESH");
        if (t_last_mrs >= 0 && c != 3'b000 && now - t_last_mrs < S_MOD) err("command within tMOD after MRS");
        if (t_zqcl >= 0 && now - t_zqcl < S_ZQ && c != 3'b000) err("command within tZQinit after ZQCL");

        do_auto_precharge(now);

        case (c)
            3'b000: begin // MRS
                if (t_last_mrs >= 0 && now - t_last_mrs < S_MRD) err("MRS within tMRD");
                if (!all_idle()) err("MRS with a bank open");
                if (b > 3) err("MRS to BA > 3");
                else begin
                    mr[b] = a; mr_set[b] = 1;
                    case (b)
                        0: begin
                            if (a[1:0] != 2'b00) err($sformatf("MR0 BL must be fixed BL8 (got %b)", a[1:0]));
                            if ({a[6:4], a[2]} != 4'b0100) err($sformatf("MR0 CL must be 6 (A6:4=%b A2=%b)", a[6:4], a[2]));
                            if (a[3]) err("MR0 burst type must be sequential");
                        end
                        1: begin
                            if (!a[0]) err("MR1 A0 must be 1 (DLL off) at this clock rate");
                            if (a[4:3] != 2'b00) err("MR1 AL must be 0");
                            if (a[7]) err("MR1 write levelling not supported");
                        end
                        2: begin
                            if (a[5:3] != 3'b001) err($sformatf("MR2 CWL must be 6 (A5:3=%b)", a[5:3]));
                        end
                        default: ;
                    endcase
                end
                t_last_mrs = now;
            end
            3'b110: begin // ZQ calibration
                if (!a[10]) err("ZQCS not supported (use ZQCL)");
                if (!(mr_set[0] && mr_set[1] && mr_set[2] && mr_set[3])) err("ZQCL before all mode registers are set");
                if (!all_idle()) err("ZQCL with a bank open");
                t_zqcl  = now;
                zq_done = 1;
                // refresh starvation is measured from here until the first REF
                t_last_ref = now;
                init_done  = 1;
                if (VERBOSE) $display("[ddr3_model] initialised (ZQCL) at cycle %0d", cycle);
            end
            3'b001: begin // REFRESH
                if (!all_idle()) err("REFRESH with a bank open");
                if (!zq_done) err("REFRESH before ZQCL");
                if (t_last_ref >= 0 && now - t_last_ref > 9 * S_REFI) err($sformatf("refresh starved: %0d slots since last REF", now - t_last_ref));
                t_last_ref = now;
                ref_count++;
            end
            3'b010: begin // PRECHARGE
                if (a[10]) begin
                    for (int k = 0; k < NBANKS; k++) begin
                        if (bank_open[k]) begin
                            if (now < t_pre_ok[k]) err($sformatf("PREA bank %0d before tRAS/tRTP/tWR", k));
                            bank_open[k] = 0; t_pre_done[k] = now + S_RP;
                        end
                    end
                end else if (bank_open[b]) begin
                    if (now < t_pre_ok[b]) err($sformatf("PRE bank %0d before tRAS/tRTP/tWR", b));
                    bank_open[b] = 0; t_pre_done[b] = now + S_RP;
                end
            end
            3'b011: begin // ACTIVATE
                if (!zq_done) err("ACT before ZQCL / init");
                if (t_last_ref >= 0 && now - t_last_ref > 9 * S_REFI) err($sformatf("refresh starved: %0d slots since last REF", now - t_last_ref));
                if (bank_open[b] || t_ap[b] >= 0) err($sformatf("ACT to open bank %0d", b));
                if (now < t_pre_done[b]) err($sformatf("ACT bank %0d before tRP", b));
                if (now - t_act[b] < S_RC) err($sformatf("ACT bank %0d before tRC", b));
                bank_open[b] = 1;
                bank_row[b]  = a[ROW_BITS-1:0];
                t_act[b]     = now;
                t_pre_ok[b]  = now + S_RAS;
            end
            3'b101, 3'b100: begin // READ / WRITE
                xfer_t x;
                if (!bank_open[b]) err($sformatf("%s to closed bank %0d", c[0] ? "RD" : "WR", b));
                if (now - t_act[b] < S_RCD) err($sformatf("%s bank %0d before tRCD", c[0] ? "RD" : "WR", b));
                if (a[2:0] != 3'b000) err("burst start column must be 8-aligned in this model");
                x.valid = 1; x.row = bank_row[b]; x.bank = ba[BANK_BITS-1:0]; x.col = a[COL_BITS-1:0]; x.beats = 0;
                if (c[0]) begin // READ
                    x.t0 = now + S_CL + longint'(rd_delay_slots);
                    push_xfer(rd_q, x);
                    if (t_pre_ok[b] < now + S_RTP) t_pre_ok[b] = now + S_RTP;
                    if (a[10]) t_ap[b] = (t_pre_ok[b] > now + S_RTP) ? t_pre_ok[b] : now + S_RTP;
                end else begin // WRITE
                    x.t0 = now + S_CWL;
                    push_xfer(wr_q, x);
                    if (t_pre_ok[b] < now + S_CWL + 16 + S_WR) t_pre_ok[b] = now + S_CWL + 16 + S_WR;
                    if (a[10]) t_ap[b] = t_pre_ok[b];
                end
            end
            default: ;
        endcase
    endtask

    // ------------------------------------------------------------------
    // Slot-level data path
    // ------------------------------------------------------------------
    logic [127:0] dq_next;
    logic [15:0]  dqs_next;

    task automatic process_slots();
        logic [15:0] dq_s, dq_prev;
        logic        oe_s, oe_prev;
        logic [1:0]  dm_s;
        logic [1:0]  dqs_s, dqs_prev;
        logic        dqs_oe_s, dqs_oe_prev;
        longint g;
        dq_next  = 0;
        dqs_next = 0;
        for (int s = 0; s < 8; s++) begin
            g        = 8 * cycle + s;
            dq_s     = dq_out[16*s +: 16];
            oe_s     = dq_oe[s/2];
            dm_s     = dm_out[2*s +: 2];
            dqs_s    = dqs_out[2*s +: 2];
            dqs_oe_s = dqs_oe[s/2];
            if (s == 0) begin
                dq_prev = p_dq; oe_prev = p_dq_oe; dqs_prev = p_dqs; dqs_oe_prev = p_dqs_oe;
            end else begin
                dq_prev     = dq_out[16*(s-1) +: 16];
                oe_prev     = dq_oe[(s-1)/2];
                dqs_prev    = dqs_out[2*(s-1) +: 2];
                dqs_oe_prev = dqs_oe[(s-1)/2];
            end

            // ---- write capture on DQS edges ----
            if (dqs_oe_s && dqs_oe_prev && dqs_s[0] != dqs_prev[0]) begin
                int found = -1;
                if (dqs_s[1] != dqs_s[0]) err("DQSU / DQSL differ");
                for (int i = 0; i < 4; i++) begin
                    if (wr_q[i].valid && wr_q[i].beats < 8) begin
                        longint exp_t = wr_q[i].t0 + 2 * wr_q[i].beats;
                        if (g >= exp_t - 1 && g <= exp_t + 1) begin found = i; break; end
                    end
                end
                if (found < 0) err($sformatf("unexpected DQS edge at slot %0d", g));
                else begin
                    int k = wr_q[found].beats;
                    if (k == 0 && (dqs_prev[0] != 0 || dqs_s[0] != 1)) err("first DQS edge is not rising");
                    if (!oe_s || !oe_prev) err($sformatf("DQ not driven around DQS edge (beat %0d)", k));
                    if (dq_s != dq_prev) err($sformatf("DQ changes at the DQS edge (beat %0d): %h -> %h", k, dq_prev, dq_s));
                    if (k == 0) begin
                        // preamble: DQS driven low for the 3 slots before the edge
                        if (!(dqs_oe_prev && dqs_prev[0] == 0)) err("missing write preamble");
                    end
                    write_beat(byte_addr(wr_q[found].row, wr_q[found].bank, wr_q[found].col + k[COL_BITS-1:0]), dq_s, dm_s);
                    wr_q[found].beats++;
                    if (wr_q[found].beats == 8) begin
                        wr_q[found].valid = 0;
                        if (VERBOSE) $display("[ddr3_model] write burst done row=%h bank=%0d col=%h", wr_q[found].row, wr_q[found].bank, wr_q[found].col);
                    end
                end
            end
            // postamble check: after the last falling edge DQS must stay driven low for a slot
            if (dqs_oe_prev && !dqs_oe_s && dqs_prev[0] != 0) err("DQS released while high (no postamble)");

            // ---- read data ----
            begin
                logic drive_dq = 0, drive_dqs = 0;
                logic [15:0] v = 0;
                logic dqs_v = 0;
                for (int i = 0; i < 4; i++) begin
                    if (rd_q[i].valid) begin
                        longint rel = g - rd_q[i].t0;
                        if (rel >= -4 && rel < 18) begin
                            drive_dqs = 1;
                            dqs_v = (rel >= 0 && rel < 16) ? ((rel % 4) < 2) : 1'b0;
                        end
                        if (rel >= 0 && rel < 16) begin
                            int k = int'(rel / 2);
                            // odd shift: the odd beat starts one slot late, so beat pairs
                            // become {3 slots even, 1 slot odd} (the board's failure mode:
                            // a sample 2 slots after the even beat still sees the even beat)
                            if (rd_odd_shift && (rel % 2) == 0 && (k % 2) == 1) k = k - 1;
                            drive_dq = 1;
                            v = read_beat(byte_addr(rd_q[i].row, rd_q[i].bank, rd_q[i].col + k[COL_BITS-1:0]));
                        end
                        if (rel >= 18) rd_q[i].valid = 0;
                    end
                end
                if (drive_dq && oe_s) err("bus contention: controller drives DQ during read data");
                // The PHY's input path sees the pin: the controller's own
                // drive while it writes (like a real IOBUF), the DRAM's data
                // during a read, garbage otherwise.
                lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                dq_next[16*s +: 16] = oe_s ? dq_s : (drive_dq ? v : lfsr[15:0]);
                dqs_next[2*s +: 2]  = dqs_oe_s ? dqs_s : (drive_dqs ? {dqs_v, dqs_v} : lfsr[17:16]);
            end
        end
        p_dq = dq_out[127:112]; p_dq_oe = dq_oe[3]; p_dm = dm_out[15:14]; p_dqs = dqs_out[15:14]; p_dqs_oe = dqs_oe[3];
    endtask

    // `rst` re-arms the model (a fresh power-up: contents are kept, all
    // timing / init bookkeeping is cleared).
    always @(posedge clk) begin
        if (rst) begin
            reset_state();
            cycle  <= 0;
            dq_in  <= 0;
            dqs_in <= 0;
        end else begin
            now = 8 * cycle + 2;
            process_command();
            process_slots();
            // samples presented one pclk after the slots they belong to
            dq_in  <= dq_next;
            dqs_in <= dqs_next;
            cycle  <= cycle + 1;
        end
    end
endmodule
