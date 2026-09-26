// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file async_fifo.sv
 * @brief Small dual-clock FIFO (gray-code pointers, 2-FF synchronizers).
 *
 *   Registered read side: assert i_rd_en while !o_rd_empty; o_rd_data
 *   is valid on the cycle after i_rd_en was accepted.
 */
`default_nettype none

module async_fifo #(
    parameter int WIDTH      = 32,
    parameter int DEPTH_BITS = 4
) (
    // Write side
    input  wire              i_wr_clk,
    input  wire              i_wr_rst,
    input  wire              i_wr_en,
    input  wire [WIDTH-1:0]  i_wr_data,
    output wire              o_wr_full,

    // Read side
    input  wire              i_rd_clk,
    input  wire              i_rd_rst,
    input  wire              i_rd_en,
    output logic [WIDTH-1:0] o_rd_data,
    output wire              o_rd_empty
);
    localparam int DEPTH = 1 << DEPTH_BITS;

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers are DEPTH_BITS+1 wide (wrap bit distinguishes full/empty).
    logic [DEPTH_BITS:0] wr_ptr_bin, wr_ptr_gray;
    logic [DEPTH_BITS:0] rd_ptr_bin, rd_ptr_gray;
    logic [DEPTH_BITS:0] rd_ptr_gray_w1, rd_ptr_gray_w2;   // rd ptr in wr domain
    logic [DEPTH_BITS:0] wr_ptr_gray_r1, wr_ptr_gray_r2;   // wr ptr in rd domain

    function automatic [DEPTH_BITS:0] bin2gray(input [DEPTH_BITS:0] b);
        return b ^ (b >> 1);
    endfunction

    wire [DEPTH_BITS:0] wr_ptr_bin_next  = wr_ptr_bin + (DEPTH_BITS+1)'(i_wr_en && !o_wr_full);
    wire [DEPTH_BITS:0] rd_ptr_bin_next  = rd_ptr_bin + (DEPTH_BITS+1)'(i_rd_en && !o_rd_empty);

    assign o_wr_full  = wr_ptr_gray == {~rd_ptr_gray_w2[DEPTH_BITS:DEPTH_BITS-1],
                                        rd_ptr_gray_w2[DEPTH_BITS-2:0]};
    assign o_rd_empty = rd_ptr_gray == wr_ptr_gray_r2;

    always_ff @(posedge i_wr_clk) begin
        if (i_wr_rst) begin
            wr_ptr_bin     <= '0;
            wr_ptr_gray    <= '0;
            rd_ptr_gray_w1 <= '0;
            rd_ptr_gray_w2 <= '0;
        end else begin
            if (i_wr_en && !o_wr_full) begin
                mem[wr_ptr_bin[DEPTH_BITS-1:0]] <= i_wr_data;
            end
            wr_ptr_bin     <= wr_ptr_bin_next;
            wr_ptr_gray    <= bin2gray(wr_ptr_bin_next);
            rd_ptr_gray_w1 <= rd_ptr_gray;
            rd_ptr_gray_w2 <= rd_ptr_gray_w1;
        end
    end

    always_ff @(posedge i_rd_clk) begin
        if (i_rd_rst) begin
            rd_ptr_bin     <= '0;
            rd_ptr_gray    <= '0;
            wr_ptr_gray_r1 <= '0;
            wr_ptr_gray_r2 <= '0;
        end else begin
            if (i_rd_en && !o_rd_empty) begin
                o_rd_data <= mem[rd_ptr_bin[DEPTH_BITS-1:0]];
            end
            rd_ptr_bin     <= rd_ptr_bin_next;
            rd_ptr_gray    <= bin2gray(rd_ptr_bin_next);
            wr_ptr_gray_r1 <= wr_ptr_gray;
            wr_ptr_gray_r2 <= wr_ptr_gray_r1;
        end
    end

endmodule

`default_nettype wire
