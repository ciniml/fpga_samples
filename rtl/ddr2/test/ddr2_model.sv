/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//
// Behavioural DDR2 SDRAM model (one x16 device) for the slot-vector PHY
// interface of Ddr2Ctrl, after ddr3_model.sv of riscv-veryl.
//
// Synchronous to pclk (= CK / 2). Each pclk cycle carries eight slots
// (a quarter CK each): DQ / DQS are sampled / driven once per slot and the
// command is sampled at the first CK edge of the cycle (slot 2), so the
// waveform is the one the OSER8 / IDES8 PHY produces, quantised to fclk
// half periods.
//
// Checked: the JEDEC init sequence (CKE low >= T_INIT with the clock
// running, 400 ns before the first command, PREA, EMR2, EMR3, EMR1 with the
// DLL on, MR with DLL reset, PREA, >= 2 REF, MR without DLL reset, OCD
// default and exit; no access before that, no read within 200 CK of the
// DLL reset), the mode register values (BL8, sequential, CL, AL 0, DQS#
// on), ACT / RD / WR (with and without auto precharge) / PRE / PREA / REF,
// per-bank open rows, tRCD tRP tRC tRAS tRTP tWR tWTR tRFC tMRD, refresh
// starvation (9 x tREFI), the write DQS / DQ relation (DQ stable on both
// sides of every DQS edge, preamble, postamble, back-to-back bursts) and
// bus contention during reads. Read data appears CL after the command
// plus rd_delay_slots; undriven slots read as pseudo-random garbage, and
// the input path sees the controller's own drive (like an IOBUF).
//
// Storage: bytes, device byte address = {row, bank, col, 1'b0}.
module ddr2_model #(
    parameter int ROW_BITS  = 13,
    parameter int COL_BITS  = 9,
    parameter int BANK_BITS = 2,
    parameter int CK_PS     = 6000,
    parameter int CL        = 4,
    // timing in ps (DDR2-800, 256 Mb)
    parameter int T_RCD_PS  = 12_500,
    parameter int T_RP_PS   = 12_500,
    parameter int T_RAS_PS  = 45_000,
    parameter int T_RC_PS   = 57_500,
    parameter int T_WR_PS   = 15_000,
    parameter int T_WTR_PS  = 7_500,
    parameter int T_RTP_PS  = 7_500,
    parameter int T_RFC_PS  = 75_000,
    parameter int T_REFI_PS = 7_800_000,
    parameter int T_INIT_PS = 200_000_000,
    parameter bit VERBOSE   = 0
) (
    input  logic                 clk,        // pclk
    input  logic                 rst,
    input  logic [2:0]           rd_delay_slots, // extra read delay (tDQSCK + flight), 0..7
    input  logic                 rd_odd_shift,   // odd beats start a slot late (duty distortion)
    input  logic                 report,         // print the counters (and MODEL FAIL on errors)

    input  logic                 cke,
    input  logic                 cs_n,
    input  logic                 ras_n,
    input  logic                 cas_n,
    input  logic                 we_n,
    input  logic [BANK_BITS-1:0] ba,
    input  logic [ROW_BITS-1:0]  a,
    input  logic [127:0]         dq_out,
    input  logic [3:0]           dq_oe,
    input  logic [15:0]          dqs_out,
    input  logic [3:0]           dqs_oe,
    output logic [127:0]         dq_in,
    output logic [15:0]          dqs_in,

    output int                   errors,
    output int                   ref_count,
    output int                   wr_bursts,
    output int                   rd_bursts,
    output logic                 init_done
);
    localparam int  ADDR_BITS = ROW_BITS + BANK_BITS + COL_BITS + 1; // bytes
    localparam longint BYTES  = 64'd1 << ADDR_BITS;
    localparam int  NBANKS    = 1 << BANK_BITS;
    localparam int  WL        = CL - 1;

    logic [7:0] mem [0:BYTES-1];

    function automatic longint s_ck(input longint ps);
        return 4 * ((ps + CK_PS - 1) / CK_PS);
    endfunction
    localparam longint S_RCD  = 4 * ((T_RCD_PS + CK_PS - 1) / CK_PS);
    localparam longint S_RP   = 4 * ((T_RP_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_RC   = 4 * ((T_RC_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_RAS  = 4 * ((T_RAS_PS + CK_PS - 1) / CK_PS);
    localparam longint S_WR   = 4 * ((T_WR_PS  + CK_PS - 1) / CK_PS);
    localparam longint S_WTR  = 4 * ((T_WTR_PS + CK_PS - 1) / CK_PS);
    localparam longint S_RTP0 = 4 * ((T_RTP_PS + CK_PS - 1) / CK_PS);
    localparam longint S_RTP  = (S_RTP0 > 8) ? S_RTP0 : 8; // max(tRTP, 2 CK)
    localparam longint S_RFC  = 4 * ((T_RFC_PS + CK_PS - 1) / CK_PS);
    localparam longint S_REFI = 4 * (T_REFI_PS / CK_PS);
    localparam longint S_INIT = 4 * (T_INIT_PS / CK_PS);
    localparam longint S_CKE  = 4 * ((400_000 + CK_PS - 1) / CK_PS);
    localparam longint S_MRD  = 4 * 2;
    localparam longint S_DLL  = 4 * 200;
    localparam longint S_CL   = 4 * CL;
    localparam longint S_WL   = 4 * WL;
    localparam longint S_BL   = 16; // BL8 = 4 CK

    longint cycle;
    longint now;

    // ---- init tracking ----
    typedef enum int {I_PWR, I_PREA1, I_EMR2, I_EMR3, I_EMR1, I_MRDLL, I_PREA2, I_REF, I_MR, I_OCD, I_DONE} init_t;
    init_t  istate;
    int     init_refs;
    longint t_cke_high, t_last_mrs, t_last_ref, t_dll_reset, t_last_wr_end, t_last_rd;
    logic   cke_q;
    logic [ROW_BITS-1:0] mr [0:3];

    // ---- bank state ----
    logic   bank_open [0:NBANKS-1];
    logic [ROW_BITS-1:0] bank_row [0:NBANKS-1];
    longint t_act      [0:NBANKS-1];
    longint t_pre_done [0:NBANKS-1];
    longint t_pre_ok   [0:NBANKS-1];
    longint t_ap       [0:NBANKS-1];

    typedef struct {
        logic   valid;
        longint t0;
        logic [ROW_BITS-1:0]  row;
        logic [BANK_BITS-1:0] bank;
        logic [COL_BITS-1:0]  col;
        int     beats;
    } xfer_t;
    xfer_t wr_q [0:3];
    xfer_t rd_q [0:3];

    logic [15:0] p_dq;
    logic        p_dq_oe;
    logic [1:0]  p_dqs;
    logic        p_dqs_oe;
    logic [31:0] lfsr;

    function automatic longint byte_addr(input logic [ROW_BITS-1:0] row, input logic [BANK_BITS-1:0] bank, input logic [COL_BITS-1:0] col);
        return ((longint'(row) << (BANK_BITS + COL_BITS)) | (longint'(bank) << COL_BITS) | longint'(col)) << 1;
    endfunction

    // test bench access (byte address)
    function automatic logic [7:0] peek(input longint addr);
        return mem[addr];
    endfunction
    task automatic poke(input longint addr, input logic [7:0] v);
        mem[addr] = v;
    endtask

    task automatic err(input string msg);
        errors++;
        $error("[ddr2_model] cycle %0d: %s", cycle, msg);
    endtask

    task automatic reset_state();
        ref_count = 0; wr_bursts = 0; rd_bursts = 0; init_done = 0;
        istate = I_PWR; init_refs = 0;
        t_cke_high = -1; t_last_mrs = -1; t_last_ref = -1; t_dll_reset = -1; t_last_wr_end = -1000; t_last_rd = -1000;
        cke_q = 0;
        for (int i = 0; i < 4; i++) begin mr[i] = 0; wr_q[i].valid = 0; rd_q[i].valid = 0; end
        for (int b = 0; b < NBANKS; b++) begin
            bank_open[b] = 0; bank_row[b] = 0; t_act[b] = -100000; t_pre_done[b] = 0; t_pre_ok[b] = 0; t_ap[b] = -1;
        end
        p_dq = 0; p_dq_oe = 0; p_dqs = 0; p_dqs_oe = 0;
    endtask

    initial begin
        errors = 0;
        lfsr = 32'hACE1_2357;
        cycle = 0; dq_in = 0; dqs_in = 0;
        for (longint i = 0; i < BYTES; i++) mem[i] = 8'hA5 ^ i[7:0];
        reset_state();
    end

    task automatic do_auto_precharge(input longint t);
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

    task automatic precharge(input int b);
        if (now < t_pre_ok[b]) err($sformatf("PRE bank %0d before tRAS/tRTP/tWR", b));
        bank_open[b] = 0; t_pre_done[b] = now + S_RP;
    endtask

    task automatic process_command();
        logic [2:0] c;
        int b;
        c = {ras_n, cas_n, we_n};
        b = int'(ba);

        if (!cke_q && cke) begin
            t_cke_high = now;
            if (now < S_INIT) err($sformatf("CKE raised after %0d slots (need %0d)", now, S_INIT));
        end
        if (cke_q && !cke && istate != I_PWR) err("CKE dropped (power down is not modelled)");
        cke_q = cke;
        if (!cke || cs_n) return;
        if (c == 3'b111) return; // NOP

        if (t_cke_high < 0 || now - t_cke_high < S_CKE) err("command within 400 ns of CKE high");
        if (t_last_ref >= 0 && now - t_last_ref < S_RFC) err("command within tRFC after REFRESH");
        if (t_last_mrs >= 0 && now - t_last_mrs < S_MRD) err("command within tMRD after MRS");

        do_auto_precharge(now);

        case (c)
            3'b000: begin // MRS / EMRS
                if (!all_idle()) err("MRS with a bank open");
                mr[b] = a;
                case (b)
                    0: begin
                        if (a[2:0] != 3'b011) err($sformatf("MR BL must be 8 (A2:0=%b)", a[2:0]));
                        if (a[3]) err("MR burst type must be sequential");
                        if (a[6:4] != CL) err($sformatf("MR CL %0d, expected %0d", a[6:4], CL));
                        if (a[7]) err("MR test mode");
                        if (a[11:9] < 1 || a[11:9] > 5) err("MR WR out of range");
                        if (a[8]) begin
                            t_dll_reset = now;
                            if (istate != I_EMR1) err("MR with DLL reset out of sequence");
                            else istate = I_MRDLL;
                        end else begin
                            if (istate != I_REF || init_refs < 2) err("MR (no DLL reset) before PREA + 2 REF");
                            else istate = I_MR;
                        end
                    end
                    1: begin
                        if (a[0]) err("EMR1 DLL disabled");
                        if (a[5:3] != 3'b000) err("EMR1 AL must be 0");
                        if (a[10]) err("EMR1 DQS# disabled");
                        if (a[12] || a[11]) err("EMR1 Qoff / RDQS set");
                        if (a[9:7] == 3'b111) begin
                            if (istate != I_MR) err("OCD default out of sequence");
                            else istate = I_OCD;
                        end else if (a[9:7] == 3'b000) begin
                            if (istate == I_EMR3) istate = I_EMR1;
                            else if (istate == I_OCD) begin
                                istate = I_DONE; init_done = 1;
                                if (VERBOSE) $display("[ddr2_model] initialised at cycle %0d", cycle);
                            end else err("EMR1 out of sequence");
                        end else err("EMR1 OCD adjust mode not supported");
                    end
                    2: begin
                        if (istate != I_PREA1) err("EMR2 out of sequence"); else istate = I_EMR2;
                    end
                    3: begin
                        if (istate != I_EMR2) err("EMR3 out of sequence"); else istate = I_EMR3;
                    end
                    default: err("MRS to BA > 3");
                endcase
                t_last_mrs = now;
            end
            3'b001: begin // REFRESH
                if (!all_idle()) err("REFRESH with a bank open");
                for (int k = 0; k < NBANKS; k++) if (now < t_pre_done[k]) err("REFRESH before tRP");
                if (istate == I_DONE && t_last_ref >= 0 && now - t_last_ref > 9 * S_REFI)
                    err($sformatf("refresh starved: %0d slots since last REF", now - t_last_ref));
                if (istate == I_PREA2 || istate == I_REF) begin istate = I_REF; init_refs++; end
                else if (istate != I_DONE && istate != I_MR && istate != I_OCD) err("REFRESH out of sequence");
                t_last_ref = now;
                ref_count++;
            end
            3'b010: begin // PRECHARGE
                if (a[10]) begin
                    for (int k = 0; k < NBANKS; k++) if (bank_open[k]) precharge(k);
                    if (istate == I_PWR) istate = I_PREA1;
                    else if (istate == I_MRDLL) istate = I_PREA2;
                end else if (bank_open[b]) precharge(b);
            end
            3'b011: begin // ACTIVATE
                if (istate != I_DONE) err("ACT before the init is complete");
                if (t_last_ref >= 0 && now - t_last_ref > 9 * S_REFI) err($sformatf("refresh starved: %0d slots since last REF", now - t_last_ref));
                if (bank_open[b] || t_ap[b] >= 0) err($sformatf("ACT to open bank %0d", b));
                if (now < t_pre_done[b]) err($sformatf("ACT bank %0d before tRP", b));
                if (now - t_act[b] < S_RC) err($sformatf("ACT bank %0d before tRC", b));
                bank_open[b] = 1;
                bank_row[b]  = a;
                t_act[b]     = now;
                t_pre_ok[b]  = now + S_RAS;
            end
            3'b101, 3'b100: begin // READ / WRITE
                xfer_t x;
                if (!bank_open[b]) err($sformatf("%s to closed bank %0d", c[0] ? "RD" : "WR", b));
                if (now - t_act[b] < S_RCD) err($sformatf("%s bank %0d before tRCD", c[0] ? "RD" : "WR", b));
                if (a[2:0] != 3'b000) err("burst start column must be 8-aligned in this model");
                x.valid = 1; x.row = bank_row[b]; x.bank = ba; x.col = a[COL_BITS-1:0]; x.beats = 0;
                if (c[0]) begin // READ
                    if (t_dll_reset < 0 || now - t_dll_reset < S_DLL) err("READ within 200 CK of the DLL reset");
                    if (now < t_last_wr_end + S_WTR) err("READ before tWTR after a write");
                    x.t0 = now + S_CL + longint'(rd_delay_slots);
                    push_xfer(rd_q, x);
                    rd_bursts++;
                    t_last_rd = now;
                    if (t_pre_ok[b] < now + S_BL - 8 + S_RTP) t_pre_ok[b] = now + S_BL - 8 + S_RTP;
                    if (a[10]) t_ap[b] = t_pre_ok[b];
                end else begin // WRITE
                    x.t0 = now + S_WL;
                    push_xfer(wr_q, x);
                    wr_bursts++;
                    t_last_wr_end = now + S_WL + S_BL;
                    if (t_pre_ok[b] < now + S_WL + S_BL + S_WR) t_pre_ok[b] = now + S_WL + S_BL + S_WR;
                    if (a[10]) t_ap[b] = t_pre_ok[b];
                end
            end
            default: ;
        endcase
    endtask

    logic [127:0] dq_next;
    logic [15:0]  dqs_next;

    task automatic process_slots();
        logic [15:0] dq_s, dq_prev;
        logic        oe_s, oe_prev;
        logic [1:0]  dqs_s, dqs_prev;
        logic        dqs_oe_s, dqs_oe_prev;
        longint g;
        dq_next  = 0;
        dqs_next = 0;
        for (int s = 0; s < 8; s++) begin
            g        = 8 * cycle + s;
            dq_s     = dq_out[16*s +: 16];
            oe_s     = dq_oe[s/2];
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
                    if (k == 0 && !(dqs_oe_prev && dqs_prev[0] == 0)) err("missing write preamble");
                    begin
                        longint ad = byte_addr(wr_q[found].row, wr_q[found].bank, wr_q[found].col + k[COL_BITS-1:0]);
                        mem[ad]     = dq_s[7:0];
                        mem[ad + 1] = dq_s[15:8];
                    end
                    wr_q[found].beats++;
                    if (wr_q[found].beats == 8) wr_q[found].valid = 0;
                end
            end
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
                            longint ad;
                            if (rd_odd_shift && (rel % 2) == 0 && (k % 2) == 1) k = k - 1;
                            drive_dq = 1;
                            ad = byte_addr(rd_q[i].row, rd_q[i].bank, rd_q[i].col + k[COL_BITS-1:0]);
                            v = {mem[ad + 1], mem[ad]};
                        end
                        if (rel >= 18) rd_q[i].valid = 0;
                    end
                end
                if (drive_dq && oe_s) err("bus contention: controller drives DQ during read data");
                if (drive_dqs && dqs_oe_s) err("bus contention: controller drives DQS during a read");
                lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                dq_next[16*s +: 16] = oe_s ? dq_s : (drive_dq ? v : lfsr[15:0]);
                dqs_next[2*s +: 2]  = dqs_oe_s ? dqs_s : (drive_dqs ? {dqs_v, dqs_v} : lfsr[17:16]);
            end
        end
        p_dq = dq_out[127:112]; p_dq_oe = dq_oe[3]; p_dqs = dqs_out[15:14]; p_dqs_oe = dqs_oe[3];
    endtask

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
            dq_in  <= dq_next;
            dqs_in <= dqs_next;
            cycle  <= cycle + 1;
        end
        // reported from here: the test bench's timing processes do not
        // reliably see these counters fresh (Verilator)
        if (report) begin
            $display("  model: refreshes %0d, bursts wr %0d rd %0d, errors %0d", ref_count, wr_bursts, rd_bursts, errors);
            if (errors != 0) $display("MODEL FAIL");
        end
    end
endmodule
