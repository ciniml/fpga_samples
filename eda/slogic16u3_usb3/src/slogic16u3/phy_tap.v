// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// TAP=1: observation of the boundary between Gowin's USB 3.0 PHY soft IP (USB3_0_PHY_Top, encrypted)
// and the GTR12 quad, to learn what a PHY of our own has to do there (LFPS, Rx.Detect, P states).
// Only the plaintext wiring of serdes.v is looked at (project.tcl brings it out on SerDes_Top TAP_o);
// the IP itself is not touched.
//
// phy_tap_log (DRP clock of the IP's register channel): 1024 entries of {type[3:0], ts[31:0], payload[67:0]}
//   type 1 W: DRP write          {4'b0, addr[23:0], data[31:0], strb[7:0]}
//   type 2 R: DRP read           {rep[11:0], addr[23:0], data[31:0]}  rep = identical reads (same address
//                                and data as the previous read) skipped before this one, saturating
//   type 3 S: status change      {4'b0, st[63:0]} (see top.v for the bits), logged when a bit outside the
//                                masked groups differs from the last logged value
//   type 4 A: (re)armed          {46'b0, start_en, start_state[4:0], mask[15:0]}
//   type 5 G: start condition met (the LTSSM state, st[16:12], equals start_state) {4'b0, st[63:0]}
// With start_en nothing but the A entry is logged until the start condition is met.
// It fills once and stops (1024 entries); further events are counted in o_drop.
// Mask (ignore) bits: 0 reads, 1 writes, 2 PIPE control, 3 RxStatus / RxValid, 4 astat, 5 rxelecidle,
//   6 stat_o, 7 stat_o_h, 8 rx/tx valid / rx fifo aempty, 9 LTSSM state, 10 keep identical reads,
//   11 lock / reset group (pma_rx_lock, rxdet_result, cmu_ok, ln0 rstn, pcs tx / rx reset).
//
// phy_tap_win (clock of the lane's transmit data): 1024 words of {pd[1:0], tx_elecidle, tx_vld, txdata[39:0]}
//   as written into the quad, in a ring that runs from arming until a trigger and then 'post' more words.
//   Triggers: 0 TxElecIdle falls, 1 PowerDown changes, 2 at once, 3 TxDetectRx rises,
//   4 / 5 TxElecIdle falls / rises in P2 (LFPS on / off), 6 TxElecIdle falls in P0, 7 PowerDown becomes P0.
module phy_tap_log (
    input  wire         dclk,
    input  wire         wren,
    input  wire         rden,
    input  wire [23:0]  addr,
    input  wire [31:0]  wdata,
    input  wire [7:0]   strb,
    input  wire         ready,
    input  wire         rdvld,
    input  wire [31:0]  rdata,
    input  wire [63:0]  st,           // asynchronous to dclk, synchronised here
    input  wire         osc,
    input  wire         i_arm,        // osc: one-cycle arm request with i_mask
    input  wire [15:0]  i_mask,
    input  wire         i_start_en,
    input  wire [4:0]   i_start_state,
    input  wire [9:0]   i_ridx,       // osc: entry to read
    output reg  [103:0] o_rq = 104'd0,   // osc
    output wire         o_gate,       // logging (start condition met, or none given)
    output wire [10:0]  o_wp,         // dclk (read when quiet)
    output wire [15:0]  o_drop,
    output wire [15:0]  o_mask
);
    reg        arm_t = 1'b0;
    reg [15:0] mask_o = 16'h0108;
    reg        sen_o = 1'b0;
    reg [4:0]  sst_o = 5'd0;
    always @(posedge osc) if (i_arm) begin arm_t <= ~arm_t; mask_o <= i_mask; sen_o <= i_start_en; sst_o <= i_start_state; end
    reg [2:0]  arm_s = 3'd0;
    reg        arm_d = 1'b1;           // log an A entry after configuration too
    reg [15:0] mask = 16'h0108;
    reg        sen = 1'b0;
    reg [4:0]  sst = 5'd0;
    reg        gate = 1'b1;
    always @(posedge dclk) arm_s <= {arm_s[1:0], arm_t};
    wire       arm = arm_s[2] != arm_s[1];

    wire [63:0] gmask = {4'hF,
        {13{mask[7]}}, {13{mask[6]}}, {3{mask[8]}}, {6{mask[11]}}, {2{mask[5]}}, {6{mask[4]}},
        {5{mask[9]}}, {4{mask[3]}}, {8{mask[2]}}};
    reg [63:0] st_s1 = 64'd0, st_s2 = 64'd0, st_last = 64'd0;
    reg [31:0] ts = 32'd0;
    reg [10:0] wp = 11'd0;
    reg [15:0] drop = 16'd0;
    reg [23:0] r_addr = 24'd0;
    reg [31:0] r_data = 32'd0;
    reg        r_have = 1'b0;
    reg [11:0] rep = 12'd0;
    reg [103:0] mem [0:1023];
    reg        we;
    reg [103:0] wd;
    wire       g_open = !gate && st_s2[16:12] == sst;
    wire       st_ev = gate && |((st_s2 ^ st_last) & ~gmask);
    wire       w_ev = gate && wren && ready && !mask[1];
    wire       r_hit = gate && rden && rdvld && !mask[0];
    wire       r_same = !mask[10] && r_have && addr == r_addr && rdata == r_data;
    always @(*) begin
        we = 1'b0; wd = 104'd0;
        if (arm_d)                  begin we = 1'b1; wd = {4'd4, ts, 46'd0, sen, sst, mask}; end
        else if (g_open)            begin we = 1'b1; wd = {4'd5, ts, 4'd0, st_s2}; end
        else if (w_ev)              begin we = 1'b1; wd = {4'd1, ts, 4'd0, addr, wdata, strb}; end
        else if (r_hit && !r_same)  begin we = 1'b1; wd = {4'd2, ts, rep, addr, rdata}; end
        else if (st_ev)             begin we = 1'b1; wd = {4'd3, ts, 4'd0, st_s2}; end
    end
    always @(posedge dclk) begin
        st_s1 <= st; st_s2 <= st_s1;
        ts <= ts + 32'd1;
        if (arm) begin
            wp <= 11'd0; drop <= 16'd0; r_have <= 1'b0; rep <= 12'd0; arm_d <= 1'b1; mask <= mask_o;
            sen <= sen_o; sst <= sst_o; gate <= !sen_o;
            st_last <= st_s2;
        end else begin
            arm_d <= 1'b0;
            if (g_open) gate <= 1'b1;
            if (!gate) st_last <= st_s2;
            if (r_hit && r_same && rep != 12'hFFF) rep <= rep + 12'd1;
            if (we) begin
                if (!wp[10]) begin mem[wp[9:0]] <= wd; wp <= wp + 11'd1; end
                else if (drop != 16'hFFFF) drop <= drop + 16'd1;
                if (!arm_d && !w_ev && r_hit && !r_same) begin r_have <= 1'b1; r_addr <= addr; r_data <= rdata; rep <= 12'd0; end
                if (!arm_d && (g_open || (!w_ev && !(r_hit && !r_same)))) st_last <= st_s2;
            end
        end
    end
    always @(posedge osc) o_rq <= mem[i_ridx];
    assign o_wp = wp;
    assign o_drop = drop;
    assign o_mask = mask;
    assign o_gate = gate;
endmodule

module phy_tap_win (
    input  wire         tclk,
    input  wire [39:0]  txd,
    input  wire         tx_vld,
    input  wire [1:0]   pd,           // asynchronous (pclk)
    input  wire         tx_elecidle,  // asynchronous (pclk)
    input  wire         tx_detectrx,  // asynchronous (pclk)
    input  wire         osc,
    input  wire         i_arm,        // osc: one-cycle arm request
    input  wire [2:0]   i_trig,
    input  wire [9:0]   i_post,
    input  wire [9:0]   i_ridx,
    output reg  [43:0]  o_rq = 44'd0,
    output wire [9:0]   o_wp,
    output wire         o_trig,
    output wire         o_full,
    output wire [2:0]   o_mode
);
    reg        arm_t = 1'b0;
    reg [2:0]  trig_o = 3'd4;
    reg [9:0]  post_o = 10'd895;
    always @(posedge osc) if (i_arm) begin arm_t <= ~arm_t; trig_o <= i_trig; post_o <= i_post; end
    reg [2:0]  arm_s = 3'd0;
    always @(posedge tclk) arm_s <= {arm_s[1:0], arm_t};
    wire       arm = arm_s[2] != arm_s[1];
    reg [3:0]  c_s1 = 4'd0, c_s2 = 4'd0, c_s3 = 4'd0;   // {tx_detectrx, tx_elecidle, pd}
    always @(posedge tclk) begin c_s1 <= {tx_detectrx, tx_elecidle, pd}; c_s2 <= c_s1; c_s3 <= c_s2; end
    reg [2:0]  mode = 3'd4;
    reg [9:0]  post = 10'd895, pcnt = 10'd0;
    reg [9:0]  wp = 10'd0;
    reg        trig = 1'b0, full = 1'b0;
    reg [43:0] mem [0:1023];
    wire       ei_fall = c_s3[2] && !c_s2[2], ei_rise = !c_s3[2] && c_s2[2];
    wire       ev = mode == 3'd0 ? ei_fall :
                    mode == 3'd1 ? (c_s3[1:0] != c_s2[1:0]) :
                    mode == 3'd2 ? 1'b1 :
                    mode == 3'd3 ? (!c_s3[3] && c_s2[3]) :
                    mode == 3'd4 ? (ei_fall && c_s2[1:0] == 2'd2) :
                    mode == 3'd5 ? (ei_rise && c_s2[1:0] == 2'd2) :
                    mode == 3'd6 ? (ei_fall && c_s2[1:0] == 2'd0) :
                                   (c_s3[1:0] != 2'd0 && c_s2[1:0] == 2'd0);
    always @(posedge tclk) begin
        if (arm) begin trig <= 1'b0; full <= 1'b0; pcnt <= 10'd0; mode <= trig_o; post <= post_o; end
        else if (!full) begin
            mem[wp] <= {c_s2[1:0], c_s2[2], tx_vld, txd};
            wp <= wp + 10'd1;
            if (trig) begin pcnt <= pcnt + 10'd1; if (pcnt == post) full <= 1'b1; end
            else if (ev) trig <= 1'b1;
        end
    end
    always @(posedge osc) o_rq <= mem[i_ridx];
    assign o_wp = wp;
    assign o_trig = trig;
    assign o_full = full;
    assign o_mode = mode;
endmodule

// clock frequency: clk / 64 edges per 2^20 osc cycles (osc ~51.66 MHz: 20.3 ms gate)
module phy_tap_freq (
    input  wire        clk,
    input  wire        osc,
    output reg  [15:0] o_cnt = 16'd0
);
    reg [5:0] div = 6'd0 /* synthesis syn_preserve=1 */;
    always @(posedge clk) div <= div + 6'd1;
    reg [2:0]  s = 3'd0;
    reg [19:0] gate = 20'd0;
    reg [15:0] n = 16'd0;
    always @(posedge osc) begin
        s <= {s[1:0], div[5]}; gate <= gate + 20'd1;
        if (&gate) begin o_cnt <= n; n <= 16'd0; end
        else if (s[1] && !s[2] && n != 16'hFFFF) n <= n + 16'd1;
    end
endmodule
