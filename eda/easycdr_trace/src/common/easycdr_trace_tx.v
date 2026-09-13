// easycdr_trace_tx: family-independent trace transmitter IP.
//
// Samples a WIDTH-bit signal in its own clock domain (sclk), records a
// timestamped entry whenever it changes (or periodically, or after a
// TX-side trigger), and emits a continuous 10-bit 8b10b symbol stream on the
// link clock for an EasyCDR receiver:
//
//   frame : every FRAME_LEN-th symbol is a K28.5 comma (word alignment)
//   record: [K28.1][ts byte0..TS_BYTES-1][data byte0..DATA_BYTES-1]
//           (all multi-byte fields little-endian; ts counts sclk cycles)
//   K28.2 : emitted once per overflow event (records were dropped)
//   K28.3 : idle filler
//   desc  : [K28.4][VER=0x01][WIDTH][TS_BITS][flags] descriptor record,
//           sent every DESC_INTERVAL link cycles (0 = periodic off) and on
//           i_desc_req, always at a record boundary. flags bit0 enable,
//           bit1 armed, bit2 triggered (running), bit3 done, bit4 periodic.
//
// Clocks:
//   sclk / srstn : sample clock (the traced design's clock, or any clock).
//                  srstn is an optional extra reset for that domain (tie 1).
//                  sclk may be the same net as clk.
//   clk  / rstn  : link parallel clock = line rate / 10; rstn (async) resets
//                  both domains (the sclk side through a reset synchroniser).
// All control inputs are in the clk domain; they cross to sclk inside
// (quasi-static values with a handshake, i_arm as a pulse). Status outputs
// are in the clk domain. o_overflow is an sclk-domain pulse.
//
// Structure: trace_frontend (sclk) -> trace_afifo -> trace_link_tx (clk).
// Reconfiguration: WIDTH / TS_BITS / FIFO_AW / SYNC_STAGES / HAS_* are
// parameters of this wrapper only; the link format follows WIDTH / TS_BITS
// and is announced to the host by the descriptor.
module easycdr_trace_tx #(
    parameter WIDTH         = 16,     // trace width, multiple of 8
    parameter TS_BITS       = 24,     // timestamp width, multiple of 8
    parameter FIFO_AW       = 4,      // record FIFO depth = 2^FIFO_AW (>= 2)
    parameter FRAME_LEN     = 16,     // symbols per comma frame
    parameter DESC_INTERVAL = 131072, // link cycles between descriptors (0 = off)
    parameter SYNC_STAGES   = 2,      // 0: sig synchronous to sclk, 2: asynchronous
    parameter HAS_PERIODIC  = 1,
    parameter HAS_TRIGGER   = 1,
    parameter FIFO_RAM      = "distributed" // "block" on GW5A (no distributed RAM)
) (
    input  wire             sclk,
    input  wire             srstn,
    input  wire [WIDTH-1:0] sig,

    input  wire             clk,
    input  wire             rstn,
    input  wire             i_enable,
    input  wire [WIDTH-1:0] i_ignore_mask,
    input  wire             i_desc_req,
    input  wire             i_periodic_en,
    input  wire             i_change_dis,
    input  wire [23:0]      i_period,       // sclk cycles
    input  wire             i_arm,
    input  wire [WIDTH-1:0] i_trig_mask,
    input  wire [WIDTH-1:0] i_trig_value,
    input  wire [15:0]      i_post,
    output wire [9:0]       o_symbol,
    output wire             o_overflow,     // sclk domain
    output wire             o_armed,
    output wire             o_triggered,
    output wire             o_done
);
    localparam REC_BITS = TS_BITS + WIDTH;
    localparam CFG_W    = 1 + WIDTH + 1 + 1 + 24 + WIDTH + WIDTH + 16;

    //------------------------------------------------------------------
    // sample-domain reset: link reset (async) + user reset, released in sclk
    //------------------------------------------------------------------
    wire frstn;
    trace_reset_sync u_frst(.clk(sclk), .arstn(rstn & srstn), .rstn(frstn));

    //------------------------------------------------------------------
    // control crossing clk -> sclk
    //------------------------------------------------------------------
    wire [CFG_W-1:0] cfg_l = {i_enable, i_ignore_mask, i_periodic_en, i_change_dis,
                              i_period, i_trig_mask, i_trig_value, i_post};
    wire [CFG_W-1:0] cfg_s;
    trace_cdc_bus #(.W(CFG_W)) u_cfg(
        .sclk(clk), .srstn(rstn), .i_bus(cfg_l), .dclk(sclk), .drstn(frstn), .o_bus(cfg_s));
    wire             f_enable      = cfg_s[CFG_W-1];
    wire [WIDTH-1:0] f_ignore_mask = cfg_s[CFG_W-2 -: WIDTH];
    wire             f_periodic_en = cfg_s[CFG_W-2-WIDTH];
    wire             f_change_dis  = cfg_s[CFG_W-3-WIDTH];
    wire [23:0]      f_period      = cfg_s[CFG_W-4-WIDTH -: 24];
    wire [WIDTH-1:0] f_trig_mask   = cfg_s[CFG_W-28-WIDTH -: WIDTH];
    wire [WIDTH-1:0] f_trig_value  = cfg_s[CFG_W-28-2*WIDTH -: WIDTH];
    wire [15:0]      f_post        = cfg_s[15:0];

    wire f_arm;
    trace_sync_pulse u_arm(.sclk(clk), .srstn(rstn), .i_pulse(i_arm),
                           .dclk(sclk), .drstn(frstn), .o_pulse(f_arm));

    //------------------------------------------------------------------
    // frontend (sclk) -> async FIFO -> link serializer (clk)
    //------------------------------------------------------------------
    wire                rec_wr, fifo_full, fifo_empty, fifo_rd, drop;
    wire [REC_BITS-1:0] rec_data, fifo_data;
    wire                f_armed, f_triggered, f_done;

    trace_frontend #(
        .WIDTH(WIDTH), .TS_BITS(TS_BITS), .SYNC_STAGES(SYNC_STAGES),
        .HAS_PERIODIC(HAS_PERIODIC), .HAS_TRIGGER(HAS_TRIGGER)
    ) u_fe(
        .sclk(sclk), .rstn(frstn), .sig(sig),
        .i_enable(f_enable), .i_ignore_mask(f_ignore_mask),
        .i_periodic_en(f_periodic_en), .i_change_dis(f_change_dis), .i_period(f_period),
        .i_arm(f_arm), .i_trig_mask(f_trig_mask), .i_trig_value(f_trig_value), .i_post(f_post),
        .i_fifo_full(fifo_full), .o_rec_wr(rec_wr), .o_rec_data(rec_data), .o_drop(drop),
        .o_armed(f_armed), .o_triggered(f_triggered), .o_done(f_done));

    trace_afifo #(.DW(REC_BITS), .AW(FIFO_AW), .RAM_STYLE(FIFO_RAM)) u_fifo(
        .wclk(sclk), .wrstn(frstn), .wr_en(rec_wr), .wr_data(rec_data), .wfull(fifo_full),
        .rclk(clk), .rrstn(rstn), .rd_en(fifo_rd), .rd_data(fifo_data), .rempty(fifo_empty));

    // overflow: one K28.2 per pending episode (sclk pending flag, ack from clk)
    reg  ovf_pending;
    wire ovf_ack_s, ovf_req_l, ovf_ack_l;
    assign o_overflow = drop;
    always @(posedge sclk or negedge frstn) begin
        if (!frstn)         ovf_pending <= 1'b0;
        else if (ovf_ack_s) ovf_pending <= 1'b0;
        else if (drop)      ovf_pending <= 1'b1;
    end
    trace_sync_pulse u_ovf_req(.sclk(sclk), .srstn(frstn), .i_pulse(drop && !ovf_pending),
                               .dclk(clk), .drstn(rstn), .o_pulse(ovf_req_l));
    trace_sync_pulse u_ovf_ack(.sclk(clk), .srstn(rstn), .i_pulse(ovf_ack_l),
                               .dclk(sclk), .drstn(frstn), .o_pulse(ovf_ack_s));

    //------------------------------------------------------------------
    // status + descriptor request. A descriptor requested together with a
    // control change (e.g. ARM | DESC_REQ in one frame) must show the new
    // state, so the request goes to sclk (ordered after i_arm by one link
    // cycle), waits for the frontend state to settle, and comes back as a
    // sequence number in the same handshaked word as the status flags.
    //------------------------------------------------------------------
    reg  desc_req_d;
    always @(posedge clk or negedge rstn)
        if (!rstn) desc_req_d <= 1'b0; else desc_req_d <= i_desc_req;
    wire f_desc_req;
    trace_sync_pulse u_dreq(.sclk(clk), .srstn(rstn), .i_pulse(desc_req_d),
                            .dclk(sclk), .drstn(frstn), .o_pulse(f_desc_req));
    reg [1:0] f_desc_dly;
    reg [1:0] f_desc_seq;
    always @(posedge sclk or negedge frstn) begin
        if (!frstn) begin
            f_desc_dly <= 2'b00;
            f_desc_seq <= 2'b00;
        end else begin
            f_desc_dly <= {f_desc_dly[0], f_desc_req};
            if (f_desc_dly[1]) f_desc_seq <= f_desc_seq + 1'b1;
        end
    end
    wire [4:0] st_l;
    trace_cdc_bus #(.W(5)) u_st(
        .sclk(sclk), .srstn(frstn), .i_bus({f_desc_seq, f_done, f_triggered, f_armed}),
        .dclk(clk), .drstn(rstn), .o_bus(st_l));
    assign {o_done, o_triggered, o_armed} = st_l[2:0];
    reg [1:0] desc_seq_q;
    always @(posedge clk or negedge rstn)
        if (!rstn) desc_seq_q <= 2'b00; else desc_seq_q <= st_l[4:3];
    wire desc_evt = (st_l[4:3] != desc_seq_q);

    trace_link_tx #(.WIDTH(WIDTH), .TS_BITS(TS_BITS), .FRAME_LEN(FRAME_LEN), .DESC_INTERVAL(DESC_INTERVAL)) u_link(
        .clk(clk), .rstn(rstn),
        .i_fifo_empty(fifo_empty), .i_fifo_data(fifo_data), .o_fifo_rd(fifo_rd),
        .i_ovf_req(ovf_req_l), .o_ovf_ack(ovf_ack_l),
        .i_desc_req(desc_evt),
        .i_desc_flags({i_periodic_en, o_done, o_triggered, o_armed, i_enable}),
        .o_symbol(o_symbol));
endmodule
