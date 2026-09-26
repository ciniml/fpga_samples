// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file cap_status.sv
 * @brief Once-per-second UART status line for the DVI receiver.
 *
 *   D R0080 A80 H1 | P1 L1 C04830C8A W0500 V02D0 F0000003C M00000000 E00000000
 *
 *   D  side channel:  R  EDID bytes read by the source (16 bit)
 *                     A  DDC offset after the last read
 *                     H  HPD level
 *   P  recovery PLL lock   L  dvi_in word lock ("X": no pixel clock)
 *   C  pixel clocks since power-up (delta per line = pixel clock in Hz)
 *   W / V  active width / lines of the last frame
 *   F  frames   M  frame-CRC mismatches   E  clocks with a decode error
 *
 *   The pixel-clock side is copied on a toggle request and read back
 *   after the acknowledge; without a pixel clock the request times out.
 */
`default_nettype none
module cap_status #(
    parameter int CLK_HZ       = 50_000_000,
    parameter int BAUD         = 115_200,
    parameter int SNAP_TIMEOUT = 100_000
) (
    // board clock domain
    input  wire        clock,
    input  wire        reset,
    input  wire        i_ddc_read_strobe,
    input  wire [7:0]  i_ddc_offset,
    input  wire        i_hpd,
    input  wire        i_pll_lock,          // asynchronous
    output wire        uart_txd,

    // pixel clock domain
    input  wire        pclk,
    input  wire        i_locked,
    input  wire        i_valid,
    input  wire        i_de,
    input  wire        i_vsync,
    input  wire        i_decode_err,
    input  wire        i_crc_mismatch
);
    // =================================================================
    // Pixel clock domain: counters (not reset; they run from power-up)
    // =================================================================
    logic [31:0] p_cycles = '0, p_frames = '0, p_mism = '0, p_derr = '0;
    logic [11:0] p_w = '0, p_h = '0, p_wcnt = '0, p_hcnt = '0;
    logic        p_de_q = 1'b0, p_vs_q = 1'b0;
    always_ff @(posedge pclk) begin
        p_cycles <= p_cycles + 1'd1;
        p_de_q   <= i_valid && i_de;
        p_vs_q   <= i_valid && i_vsync;
        if (i_valid && i_de) p_wcnt <= p_wcnt + 1'd1;
        if (p_de_q && !(i_valid && i_de)) begin
            p_w    <= p_wcnt;
            p_wcnt <= '0;
            p_hcnt <= p_hcnt + 1'd1;
        end
        if (i_valid && i_vsync && !p_vs_q) begin
            p_frames <= p_frames + 1'd1;
            p_h      <= p_hcnt;
            p_hcnt   <= '0;
        end
        if (i_valid && i_decode_err) p_derr <= p_derr + 1'd1;
        if (i_crc_mismatch)          p_mism <= p_mism + 1'd1;
    end

    logic       req_t = 1'b0;           // board domain
    logic [2:0] req_s = '0;             // pixel domain
    logic       ack_t = 1'b0;           // pixel domain
    logic [152:0] p_snap = '0;
    always_ff @(posedge pclk) begin
        req_s <= {req_s[1:0], req_t};
        if (req_s[2] != req_s[1]) begin
            p_snap <= {i_locked, p_cycles, p_w, p_h, p_frames, p_mism, p_derr};
            ack_t  <= ~ack_t;
        end
    end

    // =================================================================
    // Board clock domain
    // =================================================================
    logic [2:0]   ack_s;
    logic [1:0]   pll_s;
    logic [15:0]  ddc_reads;
    logic [152:0] snap;
    logic         snap_ok;
    logic         s_locked;
    logic [31:0]  s_cycles, s_frames, s_mism, s_derr;
    logic [11:0]  s_w, s_h;
    assign {s_locked, s_cycles, s_w, s_h, s_frames, s_mism, s_derr} = snap;

    // The line is assembled into a byte array when the snapshot arrives
    // (fixed positions, constant indices) and then sent byte by byte.
    // "D R#### A## H# | P# L# C######## W#### V#### F######## M######## E########\r\n"
    localparam int LINE_LEN = 76;
    logic [7:0] line [0:LINE_LEN-1];

    function automatic logic [7:0] hex(input logic [3:0] n);
        return n < 4'd10 ? 8'h30 + 8'(n) : 8'h37 + 8'(n);
    endfunction

    logic       tx_valid, tx_ready;
    logic [7:0] tx_char;
    uart_tx #(.BAUD_DIVIDER(CLK_HZ / BAUD)) u_tx (
        .clock     (clock),
        .reset     (reset),
        .data_valid(tx_valid),
        .data_ready(tx_ready),
        .data_bits (tx_char),
        .tx        (uart_txd)
    );

    typedef enum logic [1:0] {S_WAIT, S_SNAP, S_BUILD, S_PRINT} state_t;
    state_t      state;
    logic [31:0] timer;
    logic [6:0]  idx;

    always_ff @(posedge clock) begin
        ack_s <= {ack_s[1:0], ack_t};
        pll_s <= {pll_s[0], i_pll_lock};
        if (reset) begin
            state     <= S_WAIT;
            timer     <= CLK_HZ - 1;
            idx       <= '0;
            tx_valid  <= 1'b0;
            tx_char   <= '0;
            ddc_reads <= '0;
            snap_ok   <= 1'b0;
            snap      <= '0;
        end else begin
            if (i_ddc_read_strobe) ddc_reads <= ddc_reads + 1'd1;
            case (state)
                S_WAIT: begin
                    if (timer == 0) begin
                        req_t <= ~req_t;
                        timer <= SNAP_TIMEOUT;
                        state <= S_SNAP;
                    end else begin
                        timer <= timer - 1'd1;
                    end
                end
                S_SNAP: begin
                    if (ack_s[2] != ack_s[1] || timer == 0) begin
                        snap_ok <= ack_s[2] != ack_s[1];
                        if (ack_s[2] != ack_s[1]) snap <= p_snap;
                        state <= S_BUILD;
                    end else begin
                        timer <= timer - 1'd1;
                    end
                end
                S_BUILD: begin
                    line[0] <= 8'h44;
                    line[1] <= 8'h20;
                    line[2] <= 8'h52;
                    line[3] <= hex(ddc_reads[15:12]);
                    line[4] <= hex(ddc_reads[11:8]);
                    line[5] <= hex(ddc_reads[7:4]);
                    line[6] <= hex(ddc_reads[3:0]);
                    line[7] <= 8'h20;
                    line[8] <= 8'h41;
                    line[9] <= hex(i_ddc_offset[7:4]);
                    line[10] <= hex(i_ddc_offset[3:0]);
                    line[11] <= 8'h20;
                    line[12] <= 8'h48;
                    line[13] <= i_hpd ? 8'h31 : 8'h30;
                    line[14] <= 8'h20;
                    line[15] <= 8'h7C;
                    line[16] <= 8'h20;
                    line[17] <= 8'h50;
                    line[18] <= pll_s[1] ? 8'h31 : 8'h30;
                    line[19] <= 8'h20;
                    line[20] <= 8'h4C;
                    line[21] <= !snap_ok ? 8'h58 : s_locked ? 8'h31 : 8'h30;
                    line[22] <= 8'h20;
                    line[23] <= 8'h43;
                    line[24] <= hex(s_cycles[31:28]);
                    line[25] <= hex(s_cycles[27:24]);
                    line[26] <= hex(s_cycles[23:20]);
                    line[27] <= hex(s_cycles[19:16]);
                    line[28] <= hex(s_cycles[15:12]);
                    line[29] <= hex(s_cycles[11:8]);
                    line[30] <= hex(s_cycles[7:4]);
                    line[31] <= hex(s_cycles[3:0]);
                    line[32] <= 8'h20;
                    line[33] <= 8'h57;
                    line[34] <= 8'h30;
                    line[35] <= hex(s_w[11:8]);
                    line[36] <= hex(s_w[7:4]);
                    line[37] <= hex(s_w[3:0]);
                    line[38] <= 8'h20;
                    line[39] <= 8'h56;
                    line[40] <= 8'h30;
                    line[41] <= hex(s_h[11:8]);
                    line[42] <= hex(s_h[7:4]);
                    line[43] <= hex(s_h[3:0]);
                    line[44] <= 8'h20;
                    line[45] <= 8'h46;
                    line[46] <= hex(s_frames[31:28]);
                    line[47] <= hex(s_frames[27:24]);
                    line[48] <= hex(s_frames[23:20]);
                    line[49] <= hex(s_frames[19:16]);
                    line[50] <= hex(s_frames[15:12]);
                    line[51] <= hex(s_frames[11:8]);
                    line[52] <= hex(s_frames[7:4]);
                    line[53] <= hex(s_frames[3:0]);
                    line[54] <= 8'h20;
                    line[55] <= 8'h4D;
                    line[56] <= hex(s_mism[31:28]);
                    line[57] <= hex(s_mism[27:24]);
                    line[58] <= hex(s_mism[23:20]);
                    line[59] <= hex(s_mism[19:16]);
                    line[60] <= hex(s_mism[15:12]);
                    line[61] <= hex(s_mism[11:8]);
                    line[62] <= hex(s_mism[7:4]);
                    line[63] <= hex(s_mism[3:0]);
                    line[64] <= 8'h20;
                    line[65] <= 8'h45;
                    line[66] <= hex(s_derr[31:28]);
                    line[67] <= hex(s_derr[27:24]);
                    line[68] <= hex(s_derr[23:20]);
                    line[69] <= hex(s_derr[19:16]);
                    line[70] <= hex(s_derr[15:12]);
                    line[71] <= hex(s_derr[11:8]);
                    line[72] <= hex(s_derr[7:4]);
                    line[73] <= hex(s_derr[3:0]);
                    line[74] <= 8'h0D;
                    line[75] <= 8'h0A;
                    idx   <= '0;
                    state <= S_PRINT;
                end
                S_PRINT: begin
                    if (tx_valid) begin
                        if (tx_ready) tx_valid <= 1'b0;
                    end else if (tx_ready) begin
                        if (idx == LINE_LEN) begin
                            timer <= CLK_HZ - 1;
                            state <= S_WAIT;
                        end else begin
                            tx_char  <= line[idx];
                            tx_valid <= 1'b1;
                            idx      <= idx + 1'd1;
                        end
                    end
                end
                default: state <= S_WAIT;
            endcase
        end
    end
endmodule
`default_nettype wire
