// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file hdmi_packet_rx.sv
 * @brief HDMI data island packets from dvi_in's TERC4 nibbles.
 *
 * A data island (dvi_in o_island) is: 2 guard-band words, N packets of
 * 32 words, 2 guard-band words. Per packet word k (HDMI 1.4 5.2.3.1):
 *   lane 0 nibble = {bit3, header bit k, VSYNC, HSYNC}
 *   lane 1 nibble bit i = subpacket i bit 2k
 *   lane 2 nibble bit i = subpacket i bit 2k + 1
 * The header is 24 bits + 8 BCH(32,24) parity bits, each subpacket 56
 * bits + 8 BCH(64,56) parity bits, parity sent last (bit 0 of each field
 * first). The trailing guard band starts an incomplete packet that is
 * dropped when the island ends.
 *
 * Output: one o_pkt_valid pulse per complete packet with the header
 * bytes {HB2, HB1, HB0}, subpackets {SB6, ..., SB0} and their parity check
 * results. o_sym_err: a payload word was not a TERC4 symbol.
 */
`default_nettype none
module hdmi_packet_rx (
    input  wire         clk,
    input  wire         rst,
    input  wire         i_valid,
    input  wire         i_island,
    input  wire         i_island_first,
    input  wire  [11:0] i_terc4,        // {lane 2, lane 1, lane 0}
    input  wire  [2:0]  i_terc4_err,

    output logic        o_pkt_valid,
    output logic [23:0] o_hb,
    output logic [55:0] o_sb [0:3],
    output logic        o_hb_ok,
    output logic [3:0]  o_sb_ok,
    output logic        o_sym_err
);
    // BCH parity shift register (G(x) = 1 + x^6 + x^7 + x^8), data LSB first.
    function automatic [7:0] ecc_next(input [7:0] ecc, input bit b);
        ecc_next = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b1000_0011 : 8'd0);
    endfunction

    logic        in_pkt;           // inside the island, past the leading guard band
    logic        gb_skip;          // second leading guard-band word follows
    logic [4:0]  k;
    logic [31:0] hdr;
    logic [63:0] sub [0:3];
    logic [7:0]  hdr_ecc;
    logic [7:0]  sub_ecc [0:3];
    logic        sym_err;
    logic        done;

    wire [3:0] n0 = i_terc4[3:0];
    wire [3:0] n1 = i_terc4[7:4];
    wire [3:0] n2 = i_terc4[11:8];

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (rst || !i_valid || !i_island) begin
            in_pkt  <= 1'b0;
            gb_skip <= 1'b0;
        end else if (i_island_first) begin
            in_pkt  <= 1'b0;
            gb_skip <= 1'b1;
            k       <= '0;
        end else if (gb_skip) begin
            gb_skip <= 1'b0;
            in_pkt  <= 1'b1;
            k       <= '0;
        end else if (in_pkt) begin
            hdr[k] <= n0[2];
            for (int i = 0; i < 4; i++) begin
                sub[i][{k, 1'b0}] <= n1[i];
                sub[i][{k, 1'b1}] <= n2[i];
            end
            if (k == 0) begin
                hdr_ecc <= ecc_next(8'd0, n0[2]);
                for (int i = 0; i < 4; i++) sub_ecc[i] <= ecc_next(ecc_next(8'd0, n1[i]), n2[i]);
                sym_err <= |i_terc4_err;
            end else begin
                if (k < 24) hdr_ecc <= ecc_next(hdr_ecc, n0[2]);
                if (k < 28) for (int i = 0; i < 4; i++) sub_ecc[i] <= ecc_next(ecc_next(sub_ecc[i], n1[i]), n2[i]);
                sym_err <= sym_err | (|i_terc4_err);
            end
            k    <= k + 1'd1;
            done <= (k == 5'd31);
        end
    end

    always_ff @(posedge clk) begin
        o_pkt_valid <= done && !rst;
        if (done) begin
            o_hb      <= hdr[23:0];
            o_hb_ok   <= hdr[31:24] == hdr_ecc;
            for (int i = 0; i < 4; i++) begin
                o_sb[i]    <= sub[i][55:0];
                o_sb_ok[i] <= sub[i][63:56] == sub_ecc[i];
            end
            o_sym_err <= sym_err;
        end
    end
endmodule
`default_nettype wire
