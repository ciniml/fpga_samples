// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// MAC model for the T1sPhy tests: sends `nframes` frames (preamble + SFD,
// broadcast, src = 02:00:00:00:00:<id>, random payload, FCS) through the
// PHY's MII-like interface (i_pending / o_tx_go / o_tx_req), and checks
// received frames: SFD search, CRC-32 residue, length. Frames heard while
// transmitting (own echo) are counted apart.
`timescale 1ns/1ps
module t1s_mac_model #(
    parameter int ID   = 0,
    parameter int SEED = 1
) (
    input  logic       clk,
    input  logic       rst,
    input  int         nframes,     // frames to send (latched when start rises)
    input  logic       start,
    output logic       pending,
    input  logic       tx_go,
    input  logic       tx_req,
    output logic       tx_en,
    output logic [3:0] txd,
    input  logic       rx_valid,
    input  logic [3:0] rx_data,
    input  logic       rx_er,
    input  logic       rx_sof,
    input  logic       rx_eof,
    input  logic       rx_bad,
    input  logic       rx_own,
    output int         sent,
    output int         rx_good,
    output int         rx_badcnt,
    output int         rx_owncnt,
    output int         rx_from [8]   // good frames per source id
);
    function automatic logic [31:0] crc_byte(input logic [31:0] c, input logic [7:0] d);
        logic [31:0] r;
        r = c;
        for (int i = 0; i < 8; i++) r = (r[0] ^ d[i]) ? ((r >> 1) ^ 32'hEDB88320) : (r >> 1);
        return r;
    endfunction

    // ---- TX ----
    int        todo;
    logic [7:0] fr [0:1600];
    int        flen;        // bytes incl. preamble, SFD and FCS
    int        nib;         // current nibble index
    logic      active;
    int unsigned rnd;

    task automatic build_frame();
        logic [31:0] c;
        int L;
        L = 46 + ($urandom(rnd) % 60);
        rnd = $urandom(rnd);
        for (int i = 0; i < 7; i++) fr[i] = 8'h55;
        fr[7] = 8'hd5;
        for (int i = 0; i < 6; i++) fr[8 + i] = 8'hff;
        fr[14] = 8'h02; fr[15] = 0; fr[16] = 0; fr[17] = 0; fr[18] = 0; fr[19] = ID[7:0];
        fr[20] = 8'h88; fr[21] = 8'hb5;
        for (int i = 0; i < L; i++) begin
            fr[22 + i] = $urandom(rnd);
            rnd = rnd * 1103515245 + 12345;
        end
        c = '1;
        for (int i = 8; i < 22 + L; i++) c = crc_byte(c, fr[i]);
        c = ~c;
        for (int i = 0; i < 4; i++) fr[22 + L + i] = c[8 * i +: 8];
        flen = 26 + L;
    endtask

    assign pending = todo > 0 && !active;
    initial rnd = SEED;

    always @(posedge clk) begin
        if (rst) begin
            todo <= 0; active <= 0; tx_en <= 0; txd <= 0; sent <= 0; nib <= 0;
        end else begin
            if (start) todo <= nframes;
            if (tx_go && !active && todo > 0) begin
                build_frame();
                active <= 1;
                tx_en  <= 1;
                txd    <= 4'h5;
                nib    <= 0;
            end else if (active && tx_req) begin
                if (nib + 1 >= 2 * flen) begin
                    active <= 0;
                    tx_en  <= 0;
                    todo   <= todo - 1;
                    sent   <= sent + 1;
                end else begin
                    nib <= nib + 1;
                    txd <= ((nib + 1) & 1) ? fr[(nib + 1) >> 1][7:4] : fr[(nib + 1) >> 1][3:0];
                end
            end
        end
    end

    // ---- RX ----
    logic        in_frame, in_data, hi, err;
    logic [3:0]  lo, prev;
    logic [31:0] crc;
    int          len;
    logic [7:0]  src;
    always @(posedge clk) begin
        if (rst) begin
            in_frame <= 0; rx_good <= 0; rx_badcnt <= 0; rx_owncnt <= 0;
            for (int i = 0; i < 8; i++) rx_from[i] <= 0;
        end else begin
            if (rx_valid) begin
                if (rx_sof) begin
                    in_frame <= 1; in_data <= 0; hi <= 0; err <= rx_er; crc <= '1; len <= 0;
                    prev <= rx_data;
                end else if (in_frame) begin
                    if (rx_er) err <= 1;
                    if (!in_data) begin
                        if (prev == 4'h5 && rx_data == 4'hd) begin in_data <= 1; hi <= 0; end
                        else if (rx_data != 4'h5) err <= 1;
                        prev <= rx_data;
                    end else if (!hi) begin
                        lo <= rx_data; hi <= 1;
                    end else begin
                        hi  <= 0;
                        crc <= crc_byte(crc, {rx_data, lo});
                        if (len == 11) src <= {rx_data, lo};
                        len <= len + 1;
                    end
                end
            end
            if (rx_eof && in_frame) begin
                in_frame <= 0;
                if (rx_own) rx_owncnt <= rx_owncnt + 1;
                else if (!rx_bad && !err && in_data && !hi && crc == 32'hDEBB20E3 && len >= 64) begin
                    rx_good <= rx_good + 1;
                    if (src < 8) rx_from[src] <= rx_from[src] + 1;
                end else begin
                    rx_badcnt <= rx_badcnt + 1;
                    $display("%t node %0d: bad frame (bad %0d err %0d data %0d hi %0d crc %h len %0d)",
                             $realtime, ID, rx_bad, err, in_data, hi, crc, len);
                end
            end
        end
    end
endmodule
