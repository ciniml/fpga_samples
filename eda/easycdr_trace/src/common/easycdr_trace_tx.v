// easycdr_trace_tx: family-independent trace transmitter IP.
//
// Samples a WIDTH-bit signal (asynchronous inputs allowed; 2FF-synchronized
// into clk), records a timestamped entry whenever it changes, and emits a
// continuous 10-bit 8b10b symbol stream for an EasyCDR receiver:
//
//   frame : every FRAME_LEN-th symbol is a K28.5 comma (word alignment)
//   record: [K28.1][ts byte0..TS_BYTES-1][data byte0..DATA_BYTES-1]
//           (all multi-byte fields little-endian)
//   K28.2 : emitted once per overflow event (records were dropped)
//   K28.3 : idle filler
//   desc  : [K28.4][VER=0x01][WIDTH][TS_BITS][flags] descriptor record,
//           sent every DESC_INTERVAL cycles (0 = periodic off) and on
//           i_desc_req, always at a record boundary. flags bit0 = i_enable.
//
// Control inputs (tie i_enable=1, i_ignore_mask=0, others 0 when unused):
//   i_enable      : 0 = suppress records (a record is sent on re-enable)
//   i_ignore_mask : 1 = exclude that sig bit from change detection
//   i_desc_req    : one-clock pulse: send a descriptor now
//   i_periodic_en : also record every i_period clocks (i_change_dis = only that)
//   i_arm         : one-clock pulse: TX-side trigger. Records are held back
//                   until (sig & i_trig_mask) == (i_trig_value & i_trig_mask);
//                   the matching sample is recorded, then i_post more records
//                   (0 = unlimited) and the transmitter goes quiet until the
//                   next i_arm. Descriptor flags: bit0 enable, bit1 armed,
//                   bit2 triggered (running), bit3 done, bit4 periodic.
//
// The user instantiates this core with the link parallel clock (line rate /
// 10) and connects o_symbol to an OSER10 (bit 0 = first on the wire) - see
// the tangprimer25k / tangnano9k_pmod tops for the device-specific PLL,
// serializer and output buffer.
module easycdr_trace_tx #(
    parameter WIDTH     = 16,   // trace width, multiple of 8
    parameter TS_BITS   = 24,   // timestamp width, multiple of 8
    parameter FIFO_AW   = 4,    // record FIFO depth = 2^FIFO_AW
    parameter FRAME_LEN = 16,   // symbols per comma frame
    parameter DESC_INTERVAL = 131072  // cycles between descriptors (0 = off)
) (
    input  wire             clk,
    input  wire             rstn,
    input  wire [WIDTH-1:0] sig,
    input  wire             i_enable,
    input  wire [WIDTH-1:0] i_ignore_mask,
    input  wire             i_desc_req,
    input  wire             i_periodic_en,
    input  wire             i_change_dis,
    input  wire [23:0]      i_period,
    input  wire             i_arm,
    input  wire [WIDTH-1:0] i_trig_mask,
    input  wire [WIDTH-1:0] i_trig_value,
    input  wire [15:0]      i_post,
    output wire [9:0]       o_symbol,
    output wire             o_overflow,  // pulses when a record is dropped
    output wire             o_armed,
    output wire             o_triggered,
    output wire             o_done
);
    localparam TS_BYTES   = TS_BITS / 8;
    localparam DATA_BYTES = WIDTH / 8;
    localparam REC_BYTES  = TS_BYTES + DATA_BYTES;
    localparam REC_BITS   = TS_BITS + WIDTH;

    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;
    localparam [7:0] K28_4 = 8'h9c;   // descriptor record marker

    //------------------------------------------------------------------
    // input synchronizer, change detector, timestamp, record FIFO
    //------------------------------------------------------------------
    reg [WIDTH-1:0]   sig_meta, sig_s, sig_prev, sig_d;
    reg               chg_r;       // registered change flag (pipelined so the
                                   // WIDTH-bit compare is not in the FIFO
                                   // write-enable path - GW1N needs this)
    reg               en_q;
    reg               init_done;
    reg [TS_BITS-1:0] ts;

    always @(posedge clk) begin
        sig_meta <= sig;
        sig_s    <= sig_meta;
    end

    reg [REC_BITS-1:0] fifo [0:(1<<FIFO_AW)-1];
    reg [FIFO_AW:0] wp, rp;
    wire fifo_empty = (wp == rp);
    wire fifo_full  = (wp[FIFO_AW] != rp[FIFO_AW]) &&
                      (wp[FIFO_AW-1:0] == rp[FIFO_AW-1:0]);
    reg  ovf_pending, ovf_pulse;
    reg  ovf_ack;
    assign o_overflow = ovf_pulse;
    assign rec_wr = chg_r && !fifo_full;

    // TX-side trigger: TS_FREE passes everything, TS_ARMED holds records
    // until the match, TS_RUN counts i_post records, TS_DONE holds until re-arm
    localparam TS_FREE = 2'd0, TS_ARMED = 2'd1, TS_RUN = 2'd2, TS_DONE = 2'd3;
    reg [1:0]  tstate;
    reg [15:0] post_left;
    reg        match_r;        // registered (sig_s & mask) == value
    reg [23:0] per_cnt;        // down-counter: hit when it reaches 0
    reg [23:0] period_m1;      // i_period - 1, registered (quasi-static input)
    reg        per_over;       // registered per_cnt > period_m1 (period shortened -> reload)
    reg        per_hit;
    reg        rec_wr_r;       // rec_wr delayed one cycle (post counting off the critical path)
    reg        post_last;      // registered post_left <= 1
    wire       pass = (tstate == TS_FREE) || (tstate == TS_RUN);
    assign o_armed     = (tstate == TS_ARMED);
    assign o_triggered = (tstate == TS_RUN);
    assign o_done      = (tstate == TS_DONE);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tstate    <= TS_FREE;
            post_left <= 16'd0;
            match_r   <= 1'b0;
            per_cnt   <= 24'd0;
            period_m1 <= 24'd0;
            per_over  <= 1'b0;
            per_hit   <= 1'b0;
            rec_wr_r  <= 1'b0;
            post_last <= 1'b0;
        end else begin
            match_r   <= ((sig_s ^ i_trig_value) & i_trig_mask) == {WIDTH{1'b0}};
            period_m1 <= i_period - 1'b1;
            per_over  <= (per_cnt > period_m1);
            per_hit   <= 1'b0;
            rec_wr_r  <= rec_wr;
            post_last <= (post_left <= 16'd1);
            if (!i_periodic_en || per_over) per_cnt <= period_m1;
            else if (per_cnt == 24'd0) begin per_cnt <= period_m1; per_hit <= 1'b1; end
            else per_cnt <= per_cnt - 1'b1;
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
    // the trigger sample itself is recorded: force a record on the ARMED->RUN edge
    wire trig_fire = (tstate == TS_ARMED) && match_r && i_enable;
    wire rec_wr;   // a record is written to the FIFO this cycle (see below)

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sig_prev    <= {WIDTH{1'b0}};
            sig_d       <= {WIDTH{1'b0}};
            chg_r       <= 1'b0;
            en_q        <= 1'b0;
            init_done   <= 1'b0;
            ts          <= {TS_BITS{1'b0}};
            wp          <= 0;
            ovf_pending <= 1'b0;
            ovf_pulse   <= 1'b0;
        end else begin
            ts        <= ts + 1'b1;
            ovf_pulse <= 1'b0;
            // stage 1: compare consecutive samples (masked); a record is
            // also sent on the first sample and when i_enable rises
            sig_prev  <= sig_s;
            sig_d     <= sig_s;
            en_q      <= i_enable;
            chg_r     <= i_enable && (trig_fire ||
                         (pass && (!init_done || (i_enable && !en_q) || per_hit ||
                          (!i_change_dis && (((sig_s ^ sig_prev) & ~i_ignore_mask) != {WIDTH{1'b0}})))));
            init_done <= 1'b1;
            // stage 2: record the sample that changed
            if (chg_r) begin
                if (!fifo_full) begin
                    fifo[wp[FIFO_AW-1:0]] <= {ts, sig_d};
                    wp <= wp + 1'b1;
                end else begin
                    ovf_pending <= 1'b1;
                    ovf_pulse   <= 1'b1;
                end
            end
            if (ovf_ack)
                ovf_pending <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // descriptor scheduler: periodic timer + request pulse
    //------------------------------------------------------------------
    localparam DIW = (DESC_INTERVAL <= 1) ? 1 : $clog2(DESC_INTERVAL);
    reg [DIW-1:0] desc_timer;
    reg           desc_pending;
    reg           desc_ack;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            desc_timer   <= {DIW{1'b0}};
            desc_pending <= 1'b0;
        end else begin
            if (DESC_INTERVAL != 0) begin
                if (desc_timer == DESC_INTERVAL-1) begin
                    desc_timer   <= {DIW{1'b0}};
                    desc_pending <= 1'b1;
                end else begin
                    desc_timer <= desc_timer + 1'b1;
                end
            end
            if (i_desc_req) desc_pending <= 1'b1;
            if (desc_ack)   desc_pending <= 1'b0;
        end
    end

    // descriptor payload bytes
    reg [7:0] desc_byte;
    reg [1:0] desc_idx;
    always @(*) begin
        case (desc_idx)
        2'd0: desc_byte = 8'h01;          // format version
        2'd1: desc_byte = WIDTH[7:0];
        2'd2: desc_byte = TS_BITS[7:0];
        2'd3: desc_byte = {3'b0, i_periodic_en, o_done, o_triggered, o_armed, i_enable};
        endcase
    end

    //------------------------------------------------------------------
    // byte serializer: K28.1, then REC_BYTES bytes of {ts, data} LSB first
    //------------------------------------------------------------------
    reg                 sb_active;   // 0: at record boundary
    reg                 desc_active; // sending descriptor payload
    reg [7:0]           sb_idx;      // next byte index within the record
    reg [REC_BITS-1:0]  cur;
    reg                 b_valid, b_is_k;
    reg [7:0]           b_data;
    wire                b_ready;
    wire can_load = !b_valid || b_ready;

    // byte extraction: bytes 0..TS_BYTES-1 = ts, then data (both LSB first)
    wire [7:0] cur_byte = cur[sb_idx*8 +: 8];   // cur = {ts, data}: fix order below

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sb_active   <= 1'b0;
            desc_active <= 1'b0;
            desc_idx    <= 2'd0;
            desc_ack    <= 1'b0;
            sb_idx    <= 8'd0;
            rp        <= 0;
            cur       <= {REC_BITS{1'b0}};
            b_valid   <= 1'b0;
            b_is_k    <= 1'b0;
            b_data    <= 8'h00;
            ovf_ack   <= 1'b0;
        end else begin
            ovf_ack  <= 1'b0;
            desc_ack <= 1'b0;
            if (can_load) begin
                if (desc_active) begin
                    b_valid <= 1'b1; b_is_k <= 1'b0;
                    b_data  <= desc_byte;
                    if (desc_idx == 2'd3) desc_active <= 1'b0;
                    desc_idx <= desc_idx + 1'b1;
                end else if (!sb_active) begin
                    if (ovf_pending && !ovf_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_2;
                        ovf_ack <= 1'b1;
                    end else if (desc_pending && !desc_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_4;
                        desc_active <= 1'b1;
                        desc_idx    <= 2'd0;
                        desc_ack    <= 1'b1;
                    end else if (!fifo_empty) begin
                        // reorder to {data, ts} so byte index 0 is ts[7:0]
                        cur     <= {fifo[rp[FIFO_AW-1:0]][WIDTH-1:0],
                                    fifo[rp[FIFO_AW-1:0]][REC_BITS-1:WIDTH]};
                        rp      <= rp + 1'b1;
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_1;
                        sb_active <= 1'b1;
                        sb_idx    <= 8'd0;
                    end else begin
                        b_valid <= 1'b0;
                    end
                end else begin
                    b_valid <= 1'b1; b_is_k <= 1'b0;
                    b_data  <= cur_byte;
                    if (sb_idx == REC_BYTES-1) begin
                        sb_active <= 1'b0;
                    end
                    sb_idx <= sb_idx + 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // link core: comma framing + idle filler + 8b10b
    //------------------------------------------------------------------
    easycdr_trace_tx_core #(.FRAME_LEN(FRAME_LEN)) u_core(
        .clk      (clk),
        .rstn     (rstn),
        .i_valid  (b_valid),
        .i_is_k   (b_is_k),
        .i_data   (b_data),
        .o_ready  (b_ready),
        .o_symbol (o_symbol)
    );
endmodule
