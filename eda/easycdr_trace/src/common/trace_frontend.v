// trace_frontend: sample-clock-domain part of the trace transmitter.
//
// Runs entirely on the sample clock (the clock of the signals being traced,
// or any convenient clock): input synchroniser (optional), change detection
// with ignore mask, timestamp counter, periodic sampling, TX-side trigger.
// Produces {timestamp, data} records for the record FIFO; the link side
// (trace_link_tx) is clock-independent. All control inputs must already be
// synchronous to sclk (easycdr_trace_tx crosses them from the link clock).
//
//   SYNC_STAGES : 0 = sig is synchronous to sclk (no added latency)
//                 2 = asynchronous inputs (2FF synchroniser)
//   HAS_PERIODIC / HAS_TRIGGER : 0 removes the periodic sampler / trigger
//                 FSM (inputs ignored). Tied-off inputs are folded by
//                 synthesis anyway; the parameters make the intent explicit.
//   TICK_LOG2   : a "tick" record (timestamp only, no data) is emitted every
//                 2^TICK_LOG2 sclk while enabled and !i_tick_dis, so the
//                 receiver knows how far the trace extends past the last
//                 change (end-of-capture marker). Bit REC_BITS of o_rec_data
//                 flags a tick.
module trace_frontend #(
    parameter WIDTH        = 16,
    parameter TS_BITS      = 24,
    parameter SYNC_STAGES  = 2,
    parameter HAS_PERIODIC = 1,
    parameter HAS_TRIGGER  = 1,
    parameter TICK_LOG2    = 16
) (
    input  wire                     sclk,
    input  wire                     rstn,          // synchronous to sclk
    input  wire [WIDTH-1:0]         sig,

    input  wire                     i_enable,
    input  wire [WIDTH-1:0]         i_ignore_mask,
    input  wire                     i_periodic_en,
    input  wire                     i_change_dis,
    input  wire                     i_tick_dis,
    input  wire [23:0]              i_period,      // sclk cycles
    input  wire                     i_arm,         // one sclk pulse
    input  wire [WIDTH-1:0]         i_trig_mask,
    input  wire [WIDTH-1:0]         i_trig_value,
    input  wire [15:0]              i_post,

    input  wire                     i_fifo_full,
    output wire                     o_rec_wr,      // write {tick, ts, data} this cycle
    output wire [TS_BITS+WIDTH:0]   o_rec_data,
    output reg                      o_drop,        // record lost (FIFO full)

    output wire                     o_armed,
    output wire                     o_triggered,
    output wire                     o_done
);
    //------------------------------------------------------------------
    // input synchroniser
    //------------------------------------------------------------------
    wire [WIDTH-1:0] sig_s;
    generate
        if (SYNC_STAGES == 0) begin : g_nosync
            assign sig_s = sig;
        end else begin : g_sync
            reg [WIDTH-1:0] sr [0:SYNC_STAGES-1];
            integer i;
            always @(posedge sclk) begin
                sr[0] <= sig;
                for (i = 1; i < SYNC_STAGES; i = i + 1) sr[i] <= sr[i-1];
            end
            assign sig_s = sr[SYNC_STAGES-1];
        end
    endgenerate

    //------------------------------------------------------------------
    // periodic sampler (down-counter, registered compare - GW1N timing)
    //------------------------------------------------------------------
    reg per_hit;
    generate
        if (HAS_PERIODIC) begin : g_per
            reg [23:0] per_cnt, period_m1;
            reg        per_over;
            always @(posedge sclk or negedge rstn) begin
                if (!rstn) begin
                    per_cnt   <= 24'd0;
                    period_m1 <= 24'd0;
                    per_over  <= 1'b0;
                    per_hit   <= 1'b0;
                end else begin
                    period_m1 <= i_period - 1'b1;
                    per_over  <= (per_cnt > period_m1);
                    per_hit   <= 1'b0;
                    if (!i_periodic_en || per_over) per_cnt <= period_m1;
                    else if (per_cnt == 24'd0) begin per_cnt <= period_m1; per_hit <= 1'b1; end
                    else per_cnt <= per_cnt - 1'b1;
                end
            end
        end else begin : g_noper
            always @(*) per_hit = 1'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // TX-side trigger: TS_FREE passes everything, TS_ARMED holds records
    // until the match, TS_RUN counts i_post records, TS_DONE holds until re-arm
    //------------------------------------------------------------------
    wire rec_wr;
    reg  tick_r;
    wire pass, trig_fire;
    generate
        if (HAS_TRIGGER) begin : g_trig
            localparam TS_FREE = 2'd0, TS_ARMED = 2'd1, TS_RUN = 2'd2, TS_DONE = 2'd3;
            reg [1:0]  tstate;
            reg [15:0] post_left;
            reg        match_r, rec_wr_r, post_last;
            always @(posedge sclk or negedge rstn) begin
                if (!rstn) begin
                    tstate    <= TS_FREE;
                    post_left <= 16'd0;
                    match_r   <= 1'b0;
                    rec_wr_r  <= 1'b0;
                    post_last <= 1'b0;
                end else begin
                    match_r   <= ((sig_s ^ i_trig_value) & i_trig_mask) == {WIDTH{1'b0}};
                    rec_wr_r  <= rec_wr && !tick_r;   // ticks do not count as post-trigger records
                    post_last <= (post_left <= 16'd1);
                    if (i_arm) begin
                        tstate    <= TS_ARMED;
                        post_left <= i_post;
                    end else case (tstate)
                    TS_ARMED: if (match_r && i_enable) begin
                        tstate    <= TS_RUN;
                        post_left <= i_post + 1'b1;   // the trigger record itself + i_post more
                    end
                    TS_RUN: if (rec_wr_r && i_post != 16'd0) begin
                        if (post_last) tstate <= TS_DONE;
                        post_left <= post_left - 1'b1;
                    end
                    default: ;
                    endcase
                end
            end
            assign pass        = (tstate == TS_FREE) || (tstate == TS_RUN);
            assign trig_fire   = (tstate == TS_ARMED) && match_r && i_enable;
            assign o_armed     = (tstate == TS_ARMED);
            assign o_triggered = (tstate == TS_RUN);
            assign o_done      = (tstate == TS_DONE);
        end else begin : g_notrig
            assign pass        = 1'b1;
            assign trig_fire   = 1'b0;
            assign o_armed     = 1'b0;
            assign o_triggered = 1'b0;
            assign o_done      = 1'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // change detector (1-stage pipeline), timestamp, record output
    //------------------------------------------------------------------
    reg [WIDTH-1:0]   sig_prev, sig_d;
    reg               chg_r, en_q, init_done;
    reg [TS_BITS-1:0] ts;
    reg [TICK_LOG2-1:0] tick_cnt;
    wire tick_hit = (tick_cnt == {TICK_LOG2{1'b0}});
    wire chg_now;
    assign rec_wr     = chg_r && !i_fifo_full;
    assign o_rec_wr   = rec_wr;
    assign o_rec_data = {tick_r, ts, sig_d};
    // a data record is sent on the first sample, when i_enable rises, on a
    // periodic hit, on a trigger and on every (unmasked) change
    assign chg_now = trig_fire ||
                     (pass && (!init_done || (i_enable && !en_q) || per_hit ||
                      (!i_change_dis && (((sig_s ^ sig_prev) & ~i_ignore_mask) != {WIDTH{1'b0}}))));

    always @(posedge sclk or negedge rstn) begin
        if (!rstn) begin
            sig_prev  <= {WIDTH{1'b0}};
            sig_d     <= {WIDTH{1'b0}};
            chg_r     <= 1'b0;
            en_q      <= 1'b0;
            init_done <= 1'b0;
            ts        <= {TS_BITS{1'b0}};
            tick_cnt  <= {TICK_LOG2{1'b0}};
            tick_r    <= 1'b0;
            o_drop    <= 1'b0;
        end else begin
            ts       <= ts + 1'b1;
            tick_cnt <= tick_cnt + 1'b1;
            sig_prev <= sig_s;
            sig_d    <= sig_s;
            en_q     <= i_enable;
            // a tick coinciding with a data record is folded into that record
            chg_r    <= i_enable && (chg_now || (tick_hit && !i_tick_dis));
            tick_r   <= i_enable && !chg_now && tick_hit && !i_tick_dis;
            init_done <= 1'b1;
            o_drop    <= chg_r && i_fifo_full;
        end
    end
endmodule
