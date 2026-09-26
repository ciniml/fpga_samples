// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file loop_report.sv
 * @brief UART status reporter and command interpreter for the DVI
 *        loopback (board clock domain).
 *
 *   Once per PERIOD_CYCLES it prints the cumulative counters:
 *
 *     R L1 F00000E10 B00000000 E00000000 E0000000 E1000000 E2000000 U0001 N001FA400 O20
 *
 *     L  word lock (1/0), or X when the RX clock is absent (no answer)
 *     F  frames compared with the transmitter    B  of which mismatched
 *     E  clocks with a decode error; E0/E1/E2 per lane (low 24 bits)
 *     U  word-lock losses
 *     P  RX recovery PLL lock        C  RX clock count (delta per line = frequency)
 *     N  active pixels in the last compared frame (1080p: 001FA400)
 *     O  IODELAY offset added to dvi_in's tap (DLYSTEP = 24 + O)
 *
 *   Commands (one character):
 *     +  offset += 4     -  offset -= 4     d  offset = default
 *     c  clear the counters
 *     s  sampling-phase scan: for O = 00, 04, .. FC, settle SETTLE_CYCLES,
 *        then print an "S" line with the counter deltas over DWELL_CYCLES
 *        (L = lock at the end of the dwell). The offset is restored after.
 *     w  raw words: 12 consecutive deserializer words of each lane from
 *        the first lane-0 control symbol, one "Wn" line per lane, hex,
 *        bit 0 = first bit received. Control symbols: 354 0AB 154 2AB.
 */
`default_nettype none
module loop_report #(
    parameter int BAUD_DIVIDER   = 434,         // 50 MHz / 115200
    parameter int PERIOD_CYCLES  = 50_000_000,  // 1 s
    parameter int SETTLE_CYCLES  = 3_000_000,   // 60 ms (> lock-loss timeout + realign)
    parameter int DWELL_CYCLES   = 12_500_000,  // 250 ms (15 frames at 60 Hz)
    parameter int SNAP_TIMEOUT   = 100_000,     // 2 ms
    parameter logic [7:0] OFFSET_DEFAULT = 8'd32
) (
    input  wire         clock,
    input  wire         reset,

    input  wire         uart_rxd,
    output logic        uart_txd,

    output logic [7:0]  o_offset,
    output logic        o_snap_req,
    input  wire         i_snap_done,
    input  wire         i_locked,
    input  wire  [31:0] i_frames,
    input  wire  [31:0] i_bad,
    input  wire  [31:0] i_derr,
    input  wire  [15:0] i_unlock,
    input  wire  [31:0] i_last_count,
    input  wire  [23:0] i_lane_err [0:2],
    input  wire  [31:0] i_rx_cycles,
    input  wire         i_pll_lock,       // RX PLL lock (asynchronous)
    output logic        o_clear,
    output logic        o_words_req,
    input  wire         i_words_done,
    input  wire  [9:0]  i_words [0:2][0:11]
);
    // -----------------------------------------------------------------
    // UART
    // -----------------------------------------------------------------
    logic       tx_valid;
    logic       tx_ready;
    logic [7:0] tx_char;
    uart_tx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_tx (
        .clock     (clock),
        .reset     (reset),
        .data_valid(tx_valid),
        .data_ready(tx_ready),
        .data_bits (tx_char),
        .tx        (uart_txd)
    );

    logic       rx_valid;
    logic [7:0] rx_char;
    uart_rx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_rx (
        .clock     (clock),
        .reset     (reset),
        .data_valid(rx_valid),
        .data_ready(1'b1),
        .data_bits (rx_char),
        .rx        (uart_rxd),
        .overrun   ()
    );

    // -----------------------------------------------------------------
    // Line formatter:
    //   "K Lx Fxxxxxxxx Bxxxxxxxx Exxxxxxxx E0xxxxxx E1xxxxxx E2xxxxxx Uxxxx Nxxxxxxxx Oxx\r\n"
    //   "Wn www www ... (12 words)\r\n"
    // -----------------------------------------------------------------
    localparam int LINE_LEN  = 96;
    localparam int WLINE_LEN = 53;

    logic [7:0]  p_kind;
    logic [7:0]  p_lock;
    logic [31:0] p_frames, p_bad, p_derr, p_count;
    logic [15:0] p_unlock;
    logic [7:0]  p_offset;
    logic [23:0] p_lane [0:2];
    logic [31:0] p_cycles;
    logic [7:0]  p_pll;
    logic [2:0]  pll_sync;
    logic [1:0]  p_wlane;
    logic [9:0]  p_wline [0:11];
    logic [6:0]  line_len;

    function automatic logic [7:0] hex(input logic [3:0] n);
        return n < 4'd10 ? 8'h30 + 8'(n) : 8'h37 + 8'(n);
    endfunction

    function automatic logic [7:0] nib32(input logic [31:0] v, input int k);  // k = 0: MSB nibble
        return hex(v[(7 - k) * 4 +: 4]);
    endfunction

    function automatic logic [7:0] wline_char(input int i);
        int k, j;
        if (i == 0)              return "W";
        if (i == 1)              return hex({2'b00, p_wlane});
        if (i >= 3 && i <= 50) begin
            k = (i - 3) >> 2;
            j = (i - 3) & 3;
            if (j == 0) return hex({2'b00, p_wline[k][9:8]});
            if (j == 1) return hex(p_wline[k][7:4]);
            if (j == 2) return hex(p_wline[k][3:0]);
        end
        if (i == 51)             return 8'h0D;
        if (i == 52)             return 8'h0A;
        return " ";
    endfunction

    function automatic logic [7:0] line_char(input int i);
        if (p_kind == "W")       return wline_char(i);
        if (i == 0)              return p_kind;
        if (i == 2)              return "L";
        if (i == 3)              return p_lock;
        if (i == 5)              return "F";
        if (i >= 6  && i <= 13)  return nib32(p_frames, i - 6);
        if (i == 15)             return "B";
        if (i >= 16 && i <= 23)  return nib32(p_bad, i - 16);
        if (i == 25)             return "E";
        if (i >= 26 && i <= 33)  return nib32(p_derr, i - 26);
        if (i == 35 || i == 44 || i == 53) return "E";
        if (i == 36)             return "0";
        if (i >= 37 && i <= 42)  return nib32({8'd0, p_lane[0]}, i - 35);
        if (i == 45)             return "1";
        if (i >= 46 && i <= 51)  return nib32({8'd0, p_lane[1]}, i - 44);
        if (i == 54)             return "2";
        if (i >= 55 && i <= 60)  return nib32({8'd0, p_lane[2]}, i - 53);
        if (i == 62)             return "U";
        if (i >= 63 && i <= 66)  return nib32({16'd0, p_unlock}, i - 59);
        if (i == 68)             return "N";
        if (i >= 69 && i <= 76)  return nib32(p_count, i - 69);
        if (i == 78)             return "O";
        if (i >= 79 && i <= 80)  return nib32({24'd0, p_offset}, i - 73);
        if (i == 82)             return "P";
        if (i == 83)             return p_pll;
        if (i == 85)             return "C";
        if (i >= 86 && i <= 93)  return nib32(p_cycles, i - 86);
        if (i == 94)             return 8'h0D;
        if (i == 95)             return 8'h0A;
        return " ";
    endfunction

    // -----------------------------------------------------------------
    // Control FSM
    // -----------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE,
        S_SNAP,         // waiting for a snapshot; returns to snap_ret
        S_PRINT,
        S_SCAN_SET,
        S_SCAN_A,       // snapshot A taken -> dwell
        S_SCAN_DWELL,
        S_SCAN_B,       // snapshot B taken -> print deltas
        S_WORDS_WAIT,   // raw word capture requested
        S_WORDS_NEXT    // print the next lane
    } state_t;

    state_t      state;
    state_t      snap_ret;
    state_t      print_ret;
    logic [31:0] timer;
    logic [31:0] period;
    logic [6:0]  char_idx;
    logic [6:0]  scan_step;
    logic [7:0]  saved_offset;
    logic        snap_ok;        // last snapshot answered
    logic        scan_a_req;     // snapshot A of this scan step requested

    // Snapshot result registers (A = scan start)
    logic        s_locked;
    logic [31:0] s_frames, s_bad, s_derr, s_count;
    logic [15:0] s_unlock;
    logic [31:0] a_frames, a_bad, a_derr;
    logic [15:0] a_unlock;
    logic [23:0] s_lane [0:2];
    logic [23:0] a_lane [0:2];
    logic [9:0]  words [0:2][0:11];

    always_ff @(posedge clock) begin
        if (reset) begin
            state        <= S_IDLE;
            snap_ret     <= S_IDLE;
            print_ret    <= S_IDLE;
            timer        <= '0;
            period       <= PERIOD_CYCLES - 1;
            char_idx     <= '0;
            scan_step    <= '0;
            o_offset     <= OFFSET_DEFAULT;
            saved_offset <= OFFSET_DEFAULT;
            o_snap_req   <= 1'b0;
            o_clear      <= 1'b0;
            o_words_req  <= 1'b0;
            line_len     <= LINE_LEN;
            p_wlane      <= '0;
            tx_valid     <= 1'b0;
            tx_char      <= '0;
            snap_ok      <= 1'b0;
            scan_a_req   <= 1'b0;
            s_locked     <= 1'b0;
            {s_frames, s_bad, s_derr, s_count, s_unlock} <= '0;
            {a_frames, a_bad, a_derr, a_unlock}          <= '0;
            {p_kind, p_lock, p_frames, p_bad, p_derr, p_count, p_unlock, p_offset} <= '0;
        end else begin
            o_snap_req  <= 1'b0;
            o_clear     <= 1'b0;
            o_words_req <= 1'b0;
            pll_sync    <= {pll_sync[1:0], i_pll_lock};
            if (period != 0) period <= period - 1'd1;

            case (state)
                S_IDLE: begin
                    if (rx_valid) begin
                        case (rx_char)
                            "+": o_offset <= o_offset + 8'd4;
                            "-": o_offset <= o_offset - 8'd4;
                            "d": o_offset <= OFFSET_DEFAULT;
                            "c": o_clear  <= 1'b1;
                            "s": begin
                                saved_offset <= o_offset;
                                scan_step    <= '0;
                                state        <= S_SCAN_SET;
                            end
                            "w": begin
                                o_words_req <= 1'b1;
                                timer       <= SNAP_TIMEOUT * 10;
                                state       <= S_WORDS_WAIT;
                            end
                            default: ;
                        endcase
                    end else if (period == 0) begin
                        // Periodic report (S_SNAP prints when returning to S_IDLE)
                        period     <= PERIOD_CYCLES - 1;
                        o_snap_req <= 1'b1;
                        timer      <= SNAP_TIMEOUT;
                        snap_ret   <= S_IDLE;
                        state      <= S_SNAP;
                    end
                end

                S_SNAP: begin
                    if (i_snap_done || timer == 0) begin
                        timer    <= '0;
                        snap_ok  <= i_snap_done;
                        s_locked <= i_snap_done && i_locked;
                        if (i_snap_done) begin
                            s_frames <= i_frames;
                            s_bad    <= i_bad;
                            s_derr   <= i_derr;
                            s_unlock <= i_unlock;
                            s_count  <= i_last_count;
                            s_lane   <= i_lane_err;
                        end
                        case (snap_ret)
                            S_IDLE: begin
                                // Periodic report: cumulative counters.
                                p_kind    <= "R";
                                p_lock    <= !i_snap_done ? "X" : i_locked ? "1" : "0";
                                p_frames  <= i_snap_done ? i_frames     : s_frames;
                                p_bad     <= i_snap_done ? i_bad        : s_bad;
                                p_derr    <= i_snap_done ? i_derr       : s_derr;
                                p_unlock  <= i_snap_done ? i_unlock     : s_unlock;
                                p_count   <= i_snap_done ? i_last_count : s_count;
                                p_lane    <= i_snap_done ? i_lane_err   : s_lane;
                                p_cycles  <= i_rx_cycles;
                                p_pll     <= pll_sync[2] ? "1" : "0";
                                p_offset  <= o_offset;
                                line_len  <= LINE_LEN;
                                char_idx  <= '0;
                                print_ret <= S_IDLE;
                                state     <= S_PRINT;
                            end
                            default: state <= snap_ret;
                        endcase
                    end else begin
                        timer <= timer - 1'd1;
                    end
                end

                S_PRINT: begin
                    if (tx_valid) begin
                        if (tx_ready) tx_valid <= 1'b0;  // accepted this cycle
                    end else if (tx_ready) begin
                        if (char_idx == line_len) begin
                            state <= print_ret;
                            if (p_kind == "W") p_wlane <= p_wlane + 1'd1;
                        end else begin
                            tx_char  <= line_char(char_idx);
                            tx_valid <= 1'b1;
                            char_idx <= char_idx + 1'd1;
                        end
                    end
                end

                S_SCAN_SET: begin
                    if (scan_step == 7'd64) begin
                        o_offset <= saved_offset;
                        state    <= S_IDLE;
                    end else begin
                        o_offset   <= {scan_step[5:0], 2'b00};
                        timer      <= SETTLE_CYCLES;
                        state      <= S_SCAN_A;
                        scan_a_req <= 1'b0;
                    end
                end

                S_SCAN_A: begin
                    // settle, then snapshot A
                    if (timer != 0) begin
                        timer <= timer - 1'd1;
                    end else if (!scan_a_req) begin
                        scan_a_req <= 1'b1;
                        o_snap_req <= 1'b1;
                        timer      <= SNAP_TIMEOUT;
                        snap_ret   <= S_SCAN_A;
                        state      <= S_SNAP;
                    end else begin
                        a_frames <= s_frames;
                        a_bad    <= s_bad;
                        a_derr   <= s_derr;
                        a_unlock <= s_unlock;
                        a_lane   <= s_lane;
                        timer    <= DWELL_CYCLES;
                        state    <= S_SCAN_DWELL;
                    end
                end

                S_SCAN_DWELL: begin
                    if (timer != 0) begin
                        timer <= timer - 1'd1;
                    end else begin
                        o_snap_req <= 1'b1;
                        timer      <= SNAP_TIMEOUT;
                        snap_ret   <= S_SCAN_B;
                        state      <= S_SNAP;
                    end
                end

                S_SCAN_B: begin
                    p_kind    <= "S";
                    p_lock    <= !snap_ok ? "X" : s_locked ? "1" : "0";
                    p_frames  <= s_frames - a_frames;
                    p_bad     <= s_bad - a_bad;
                    p_derr    <= s_derr - a_derr;
                    p_unlock  <= s_unlock - a_unlock;
                    p_count   <= s_count;
                    for (int l = 0; l < 3; l++) p_lane[l] <= s_lane[l] - a_lane[l];
                    p_cycles  <= i_rx_cycles;
                    p_pll     <= pll_sync[2] ? "1" : "0";
                    p_offset  <= o_offset;
                    line_len  <= LINE_LEN;
                    char_idx  <= '0;
                    print_ret <= S_SCAN_SET;
                    scan_step <= scan_step + 1'd1;
                    state     <= S_PRINT;
                end

                S_WORDS_WAIT: begin
                    if (i_words_done || timer == 0) begin
                        if (i_words_done) words <= i_words;
                        p_kind  <= i_words_done ? "W" : "w";   // "w": no answer
                        p_wlane <= '0;
                        state   <= S_WORDS_NEXT;
                    end else begin
                        timer <= timer - 1'd1;
                    end
                end

                S_WORDS_NEXT: begin
                    if (p_kind != "W" || p_wlane == 2'd3) begin
                        state <= S_IDLE;
                    end else begin
                        p_wline   <= words[p_wlane];
                        line_len  <= WLINE_LEN;
                        char_idx  <= '0;
                        print_ret <= S_WORDS_NEXT;
                        state     <= S_PRINT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
