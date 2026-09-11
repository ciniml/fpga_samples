// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file line_dword_cache.veryl
 * @brief Dword-addressed synchronous RAM interface (with a ready/stall)
 *        backed by a 16-byte LineBusIf (Ddr3Ctrl) through a one-line
 *        write-back cache.
 *
 * Same user-side contract as PsramDwordCache: a plain single-port
 * synchronous RAM (address, write enable/data, read enable, read data
 * one cycle later) plus o_ready. An access only takes place in a cycle
 * where o_ready is high, so the user holds i_addr/i_wen/i_ren until
 * then. o_ready is high while the addressed line (LINE_BYTES) sits in
 * the cache; on a miss the dirty line is written back and the new one
 * fetched as LINE_BYTES/16 line-bus transactions (one BL8 burst each).
 *
 * Single clock: the line bus master runs on i_clk, so i_clk is
 * Ddr3Ctrl's i_clk_cpu and the controller does the crossing into the
 * DRAM clock. The line is held in four 32-bit lane RAMs (lane = dword
 * index mod 4) so a user access touches one lane and the miss engine
 * moves a whole 16-byte bus beat per cycle.
 *
 * Meant for sequential block traffic (the NVMe core reads and writes
 * whole LBAs); random accesses across lines would thrash.
 */
module LineDwordCache #(
    parameter int unsigned ADDR_BITS  = 25 , // dword address bits (25 = 128MiB)
    parameter int unsigned LINE_BYTES = 512 // cache line size (power of two, >= 64)
) (
    input var logic i_clk,
    input var logic i_rst,
    // ---- user side ----
    input  var logic [ADDR_BITS-1:0] i_addr ,
    input  var logic                 i_wen  ,
    input  var logic [32-1:0]        i_wdata,
    input  var logic                 i_ren  ,
    output var logic [32-1:0]        o_rdata,
    output var logic                 o_ready,
    output var logic [3-1:0]         o_dbg  , // {valid, dirty, busy}
    // ---- memory side ----
    LineBusIf.master line
);
    localparam int unsigned                 LINE_DW    = LINE_BYTES / 4; // dwords per line
    localparam int unsigned                 LINE_BITS  = $clog2(LINE_DW); // dword index bits within a line
    localparam int unsigned                 BEATS      = LINE_BYTES / 16; // 16-byte bus beats per line
    localparam int unsigned                 BEAT_BITS  = $clog2(BEATS);
    localparam logic        [BEAT_BITS-1:0] LAST_BEAT  = BEATS - 1;
    localparam int unsigned                 TAG_BITS   = ADDR_BITS - LINE_BITS;
    localparam int unsigned                 LANE_ABITS = LINE_BITS - 2; // entries per lane RAM

    // ================= state =================
    typedef enum logic [3-1:0] {
        St_Idle, // serving hits
        St_WbAddr, // present beat's address to the lane RAMs (read latency 1)
        St_WbRead, // capture the beat (4 lanes) of the old line
        St_WbReq, // present the beat as a bus write until accepted
        St_FtReq, // present a bus read until accepted
        St_FtWait, // wait for the read data, write it into the buffer
        St_Done // install the new tag
    } St;
    St                    st        ;
    logic                 valid     ;
    logic                 dirty     ;
    logic [TAG_BITS-1:0]  tag       ;
    logic [BEAT_BITS-1:0] beat      ;
    logic                 rq_dirty  ;
    logic [TAG_BITS-1:0]  rq_old_tag;
    logic [TAG_BITS-1:0]  rq_new_tag;
    logic [128-1:0]       wb_data   ;

    logic busy   ; always_comb busy    = st != St_Idle;
    logic hit    ; always_comb hit     = valid && (tag == i_addr[ADDR_BITS - 1:LINE_BITS]) && !busy;
    always_comb o_ready = hit;
    always_comb o_dbg   = {valid, dirty, busy};

    // ================= line buffer: 4 lane RAMs =================
    // user access: entry = i_addr[LINE_BITS-1:2], lane = i_addr[1:0]
    // engine    : entry = beat, all four lanes
    logic [LANE_ABITS-1:0] u_entry; always_comb u_entry = i_addr[LINE_BITS - 1:2];
    logic [2-1:0]          u_lane ; always_comb u_lane  = i_addr[1:0];
    logic                  eng    ; always_comb eng     = busy;

    logic [4-1:0]          lane_we     ;
    logic [LANE_ABITS-1:0] lane_wa     ;
    logic [32-1:0]         lane_wd  [4];
    logic [LANE_ABITS-1:0] lane_ra     ;
    logic [32-1:0]         lane_rd  [4];
    logic [2-1:0]          u_lane_r    ; // lane of the read presented last cycle

    always_comb begin
        lane_wa = ((eng) ? ( beat ) : ( u_entry ));
        lane_ra = ((eng) ? ( beat ) : ( u_entry ));
        for (int k = 0; k < 4; k++) begin
            lane_wd[k] = ((eng) ? ( line.rdata[32 * k+:32] ) : ( i_wdata ));
            lane_we[k] = ((eng) ? ( (st == St_FtWait && line.rvalid) ) : ( (i_wen && hit && (u_lane == k)) ));
        end
    end
    always_comb o_rdata = lane_rd[u_lane_r];

    line_lane_ram #(
        .ABITS (LANE_ABITS)
    ) u_l0 (
        .clk (i_clk     ),
        .we  (lane_we[0]),
        .wa  (lane_wa   ),
        .wd  (lane_wd[0]),
        .ra  (lane_ra   ),
        .rd  (lane_rd[0])
    );
    line_lane_ram #(
        .ABITS (LANE_ABITS)
    ) u_l1 (
        .clk (i_clk     ),
        .we  (lane_we[1]),
        .wa  (lane_wa   ),
        .wd  (lane_wd[1]),
        .ra  (lane_ra   ),
        .rd  (lane_rd[1])
    );
    line_lane_ram #(
        .ABITS (LANE_ABITS)
    ) u_l2 (
        .clk (i_clk     ),
        .we  (lane_we[2]),
        .wa  (lane_wa   ),
        .wd  (lane_wd[2]),
        .ra  (lane_ra   ),
        .rd  (lane_rd[2])
    );
    line_lane_ram #(
        .ABITS (LANE_ABITS)
    ) u_l3 (
        .clk (i_clk     ),
        .we  (lane_we[3]),
        .wa  (lane_wa   ),
        .wd  (lane_wd[3]),
        .ra  (lane_ra   ),
        .rd  (lane_rd[3])
    );

    // ================= line bus master =================
    // byte address of a beat: {tag, beat, 4'b0}
    logic [32-1:0] wb_addr   ; always_comb wb_addr    = {rq_old_tag, beat, 4'b0};
    logic [32-1:0] ft_addr   ; always_comb ft_addr    = {rq_new_tag, beat, 4'b0};
    always_comb line.valid = (st == St_WbReq) || (st == St_FtReq);
    always_comb line.we    = st == St_WbReq;
    always_comb line.wstrb = 16'hFFFF;
    always_comb line.wdata = wb_data;
    always_comb line.addr  = (((st == St_WbReq)) ? ( wb_addr ) : ( ft_addr ));

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            st         <= St_Idle;
            valid      <= 0;
            dirty      <= 0;
            tag        <= 0;
            beat       <= 0;
            rq_dirty   <= 0;
            rq_old_tag <= 0;
            rq_new_tag <= 0;
            wb_data    <= 0;
            u_lane_r   <= 0;
        end else begin
            u_lane_r <= u_lane;
            case (st)
                St_Idle: begin
                    if (i_wen && hit) begin
                        dirty <= 1;
                    end
                    if ((i_ren || i_wen) && !hit) begin
                        rq_dirty   <= valid && dirty;
                        rq_old_tag <= tag;
                        rq_new_tag <= i_addr[ADDR_BITS - 1:LINE_BITS];
                        valid      <= 0;
                        beat       <= 0;
                        st         <= (((valid && dirty)) ? ( St_WbAddr ) : ( St_FtReq ));
                    end
                end
                St_WbAddr: begin
                    // lane_ra = beat is presented this cycle (busy), the
                    // registered lane outputs are valid in the next one
                    st <= St_WbRead;
                end
                St_WbRead: begin
                    wb_data <= {lane_rd[3], lane_rd[2], lane_rd[1], lane_rd[0]};
                    st      <= St_WbReq;
                end
                St_WbReq: begin
                    if (line.ready) begin
                        if (beat == LAST_BEAT) begin
                            beat <= 0;
                            st   <= St_FtReq;
                        end else begin
                            beat <= beat + 1;
                            st   <= St_WbAddr;
                        end
                    end
                end
                St_FtReq: begin
                    if (line.ready) begin
                        st <= St_FtWait;
                    end
                end
                St_FtWait: begin
                    if (line.rvalid) begin
                        if (beat == LAST_BEAT) begin
                            st <= St_Done;
                        end else begin
                            beat <= beat + 1;
                            st   <= St_FtReq;
                        end
                    end
                end
                St_Done: begin
                    valid <= 1;
                    dirty <= 0;
                    tag   <= rq_new_tag;
                    beat  <= 0;
                    st    <= St_Idle;
                end
                default: st <= St_Idle;
            endcase
        end
    end
endmodule

`ifndef SYNTHESIS
// simple two-port 32-bit RAM: write port A, synchronous read port B
// (latency 1, unconditional read so the tool cannot pick a pipelined mode)
module line_lane_ram #(parameter ABITS = 5) (
    input  logic             clk,
    input  logic             we,
    input  logic [ABITS-1:0] wa,
    input  logic [31:0]      wd,
    input  logic [ABITS-1:0] ra,
    output logic [31:0]      rd
);
    logic [31:0] mem [0:(1<<ABITS)-1];
    always_ff @(posedge clk) begin
        if (we) mem[wa] <= wd;
        rd <= mem[ra];
    end
endmodule
`endif
//# sourceMappingURL=line_dword_cache.sv.map
