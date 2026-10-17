// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file csi_stats.sv
 * @brief Bring-up instrumentation for the CSI-2 receiver (pclk domain),
 *        read out from the system clock domain.
 *
 *  - counters: free-running 32-bit, copied to a snapshot on request
 *    (toggle handshake); the host computes rates from differences.
 *    Index map: see CNT_* below and host/csictl.py STAT_NAMES.
 *  - event log: one 64-bit record per packet (short packets at the
 *    header, long packets at their CRC), 1024 deep, armed by the host,
 *    optionally starting at the next frame start. Record:
 *      [63:40] time (pclk / 256 = 2.048 us)  [39:36] kind  [35:32] flags
 *      [31:24] DI (VC, DT)  [23:8] WC  [7:0] 0
 *      kind 1 short (flag0 = ECC corrected), 2 long (flag0 = CRC ok,
 *      flag1 = ECC corrected), 3 header ECC error, 4 abort
 *  - raw capture: the oversampled lanes, 1024 words x 96 bits
 *    {d1, d0, clk}, ring buffer that stops POST words after a trigger:
 *      0 immediate, 1 clock activity after >= 64 quiet words,
 *      2 a sync byte on any lane, 3 an error (ECC, CRC, abort), 4 FS
 *    (the receiver events lag the samples by ~10 words; 256 words of
 *    pre-trigger history cover that)
 * Reading the capture / log memories is only meaningful while they are
 * not being written (capture done / log full or the record index below
 * the snapshot count).
 */
`default_nettype none
module csi_stats (
    input  wire        pclk,
    input  wire        prst,
    // receiver events (Csi2Rx)
    input  wire        i_hdr,
    input  wire        i_short,
    input  wire [1:0]  i_vc,
    input  wire [5:0]  i_dt,
    input  wire [15:0] i_wc,
    input  wire        i_end,
    input  wire        i_crc_ok,
    input  wire        i_ecc_corr,
    input  wire        i_ecc_err,
    input  wire        i_abort,
    input  wire [3:0]  i_nbits,
    input  wire        i_ovf,
    input  wire [1:0]  i_sync,
    input  wire        i_drop,
    input  wire [1:0]  i_active,
    // raw samples
    input  wire [31:0] i_s_clk,
    input  wire [31:0] i_s_d0,
    input  wire [31:0] i_s_d1,

    // system side
    input  wire        clk,
    input  wire        i_snap_tgl,     // toggle: take a snapshot
    output logic       o_snap_ack,     // follows i_snap_tgl when done (clk domain)
    input  wire [4:0]  i_snap_idx,
    output logic [31:0] o_snap_data,   // registered
    input  wire        i_cap_tgl,      // toggle: arm the capture
    input  wire [2:0]  i_cap_mode,     // quasi-static
    input  wire [9:0]  i_cap_raddr,
    output logic [95:0] o_cap_rdata,   // registered
    input  wire        i_log_tgl,      // toggle: arm the event log
    input  wire        i_log_at_fs,    // quasi-static: start at the next FS
    input  wire [9:0]  i_log_raddr,
    output logic [63:0] o_log_rdata    // registered
);
    localparam int NCNT = 25;
    localparam int CNT_LINES = 20, CNT_LAST = 21, CNT_FPER = 22, CNT_FNUM = 23, CNT_STAT = 24;

    // ---------------- counters ----------------
    logic [31:0] cnt [0:NCNT-1];
    logic [31:0] lines_cur, fper_cur;
    logic        in_frame;
    logic [7:0]  long_di;
    logic [15:0] long_wc;
    logic        long_cor;

    wire crc_bad = i_end && !i_crc_ok;
    wire is_fs   = i_hdr && i_short && i_dt == 6'h00;
    wire is_fe   = i_hdr && i_short && i_dt == 6'h01;

    // capture / log status (below)
    logic        cap_done;
    logic [9:0]  cap_wp;
    logic        log_full;
    logic [10:0] log_cnt;

    always_ff @(posedge pclk) begin
        if (prst) begin
            for (int i = 0; i < NCNT; i++) cnt[i] <= '0;
            lines_cur <= '0;
            fper_cur  <= '0;
            in_frame  <= 1'b0;
            long_di   <= '0;
            long_wc   <= '0;
            long_cor  <= 1'b0;
        end else begin
            cnt[0] <= cnt[0] + 1'b1;
            cnt[1] <= cnt[1] + i_nbits;
            if (|i_active) begin
                cnt[2] <= cnt[2] + 1'b1;
                cnt[3] <= cnt[3] + i_nbits;
            end
            if (i_ovf)      cnt[4]  <= cnt[4] + 1'b1;
            if (i_sync[0])  cnt[5]  <= cnt[5] + 1'b1;
            if (i_sync[1])  cnt[6]  <= cnt[6] + 1'b1;
            if (i_hdr)      cnt[7]  <= cnt[7] + 1'b1;
            if (is_fs)      cnt[8]  <= cnt[8] + 1'b1;
            if (is_fe)      cnt[9]  <= cnt[9] + 1'b1;
            if (i_hdr && i_short && i_dt[5:1] != 5'd0) cnt[10] <= cnt[10] + 1'b1;
            if (i_end) begin
                if (long_di[5:0] == 6'h12)      cnt[12] <= cnt[12] + 1'b1;
                else if (long_di[5:4] == 2'b10) cnt[11] <= cnt[11] + 1'b1;   // 0x20..0x2F: RGB / RAW
                else                            cnt[13] <= cnt[13] + 1'b1;
            end
            if (i_end && i_crc_ok) cnt[14] <= cnt[14] + 1'b1;
            if (crc_bad)    cnt[15] <= cnt[15] + 1'b1;
            if (i_ecc_corr) cnt[16] <= cnt[16] + 1'b1;
            if (i_ecc_err)  cnt[17] <= cnt[17] + 1'b1;
            if (i_abort)    cnt[18] <= cnt[18] + 1'b1;
            if (i_drop)     cnt[19] <= cnt[19] + 1'b1;
            // frame structure
            if (i_hdr && !i_short) begin
                long_di  <= {i_vc, i_dt};
                long_wc  <= i_wc;
                long_cor <= i_ecc_corr;
            end
            if (i_end && long_di[5:4] == 2'b10) begin
                lines_cur <= lines_cur + 1'b1;
                cnt[CNT_LAST] <= {8'd0, long_di, long_wc};
            end
            fper_cur <= fper_cur + 1'b1;
            if (is_fs) begin
                if (in_frame || fper_cur != '0) cnt[CNT_FPER] <= fper_cur;
                fper_cur      <= 32'd1;
                lines_cur     <= '0;
                in_frame      <= 1'b1;
                cnt[CNT_FNUM] <= {16'd0, i_wc};
            end
            if (is_fe) begin
                cnt[CNT_LINES] <= lines_cur;
                in_frame       <= 1'b0;
            end
            cnt[CNT_STAT] <= {cap_done, 5'd0, cap_wp, log_full, 4'd0, log_cnt};
        end
    end

    // ---------------- snapshot ----------------
    logic [2:0]  snap_s;
    logic        snap_p;
    logic [31:0] snap [0:NCNT-1];
    always_ff @(posedge pclk) begin
        snap_s <= {snap_s[1:0], i_snap_tgl};
        if (snap_s[2] != snap_s[1]) begin
            for (int i = 0; i < NCNT; i++) snap[i] <= cnt[i];
        end
        snap_p <= snap_s[2];
    end
    logic [2:0] ack_s;
    always_ff @(posedge clk) begin
        ack_s       <= {ack_s[1:0], snap_p};
        o_snap_ack  <= ack_s[2];
        o_snap_data <= (i_snap_idx < NCNT) ? snap[i_snap_idx] : 32'd0;
    end

    // ---------------- raw capture ----------------
    localparam int POST = 768;
    logic [2:0]  cap_s;
    logic [1:0]  cap_st;     // 0 idle, 1 armed (writing), 2 post-trigger, 3 done
    logic [9:0]  post_cnt;
    logic [6:0]  quiet;
    logic        cap_trig, cap_trig_r;
    (* syn_ramstyle = "block_ram" *) logic [95:0] cap_mem [0:1023];
    always_comb begin
        case (i_cap_mode)
            3'd0:    cap_trig = 1'b1;
            3'd1:    cap_trig = quiet[6] && i_nbits != 4'd0;
            3'd2:    cap_trig = |i_sync;
            3'd3:    cap_trig = i_ecc_err || crc_bad || i_abort;
            default: cap_trig = is_fs;
        endcase
    end
    always_ff @(posedge pclk) begin
        cap_s <= {cap_s[1:0], i_cap_tgl};
        quiet <= (i_nbits != 4'd0) ? 7'd0 : (quiet[6] ? quiet : quiet + 1'b1);
        cap_trig_r <= cap_trig;
        if (prst) begin
            cap_st <= 2'd0;
            cap_wp <= '0;
        end else begin
            if (cap_st == 2'd1 || cap_st == 2'd2) cap_wp <= cap_wp + 1'b1;
            if (cap_s[2] != cap_s[1]) begin
                cap_st   <= 2'd1;
                post_cnt <= '0;
            end else if (cap_st == 2'd1 && cap_trig_r) begin
                cap_st <= 2'd2;
            end else if (cap_st == 2'd2) begin
                post_cnt <= post_cnt + 1'b1;
                if (post_cnt == POST - 1) cap_st <= 2'd3;
            end
        end
        if (cap_st == 2'd1 || cap_st == 2'd2) cap_mem[cap_wp] <= {i_s_d1, i_s_d0, i_s_clk};
    end
    assign cap_done = cap_st == 2'd3;
    always_ff @(posedge clk) o_cap_rdata <= cap_mem[i_cap_raddr];

    // ---------------- event log ----------------
    logic [2:0]  log_s;
    logic [1:0]  log_st;     // 0 idle, 1 waiting for FS, 2 logging
    logic [31:0] tstamp;
    (* syn_ramstyle = "block_ram" *) logic [63:0] log_mem [0:1023];
    logic        log_we;
    logic [63:0] log_rec;
    always_comb begin
        log_we  = 1'b0;
        log_rec = '0;
        if (i_hdr && i_short) begin
            log_we  = 1'b1;
            log_rec = {tstamp[31:8], 4'd1, 3'd0, i_ecc_corr, i_vc, i_dt, i_wc, 8'd0};
        end else if (i_end) begin
            log_we  = 1'b1;
            log_rec = {tstamp[31:8], 4'd2, 2'd0, long_cor, i_crc_ok, long_di, long_wc, 8'd0};
        end else if (i_ecc_err) begin
            log_we  = 1'b1;
            log_rec = {tstamp[31:8], 4'd3, 28'd0, 8'd0};
        end else if (i_abort) begin
            log_we  = 1'b1;
            log_rec = {tstamp[31:8], 4'd4, 28'd0, 8'd0};
        end
    end
    assign log_full = log_cnt[10];
    always_ff @(posedge pclk) begin
        log_s  <= {log_s[1:0], i_log_tgl};
        tstamp <= tstamp + 1'b1;
        if (prst) begin
            log_st  <= 2'd0;
            log_cnt <= '0;
        end else if (log_s[2] != log_s[1]) begin
            log_st  <= i_log_at_fs ? 2'd1 : 2'd2;
            log_cnt <= '0;
        end else begin
            if (log_st == 2'd1 && is_fs) log_st <= 2'd2;
            if ((log_st == 2'd2 || (log_st == 2'd1 && is_fs)) && log_we && !log_full) begin
                log_cnt <= log_cnt + 1'b1;
            end
        end
        if ((log_st == 2'd2 || (log_st == 2'd1 && is_fs)) && log_we && !log_full)
            log_mem[log_cnt[9:0]] <= log_rec;
    end
    always_ff @(posedge clk) o_log_rdata <= log_mem[i_log_raddr];
endmodule
`default_nettype wire
