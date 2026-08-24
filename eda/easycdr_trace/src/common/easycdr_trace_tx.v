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
//
// The user instantiates this core with the link parallel clock (line rate /
// 10) and connects o_symbol to an OSER10 (bit 0 = first on the wire) - see
// the tangprimer25k / tangnano9k_pmod tops for the device-specific PLL,
// serializer and output buffer.
module easycdr_trace_tx #(
    parameter WIDTH     = 16,   // trace width, multiple of 8
    parameter TS_BITS   = 24,   // timestamp width, multiple of 8
    parameter FIFO_AW   = 4,    // record FIFO depth = 2^FIFO_AW
    parameter FRAME_LEN = 16    // symbols per comma frame
) (
    input  wire             clk,
    input  wire             rstn,
    input  wire [WIDTH-1:0] sig,
    output wire [9:0]       o_symbol,
    output wire             o_overflow   // pulses when a record is dropped
);
    localparam TS_BYTES   = TS_BITS / 8;
    localparam DATA_BYTES = WIDTH / 8;
    localparam REC_BYTES  = TS_BYTES + DATA_BYTES;
    localparam REC_BITS   = TS_BITS + WIDTH;

    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;

    //------------------------------------------------------------------
    // input synchronizer, change detector, timestamp, record FIFO
    //------------------------------------------------------------------
    reg [WIDTH-1:0]   sig_meta, sig_s, sig_prev, sig_d;
    reg               chg_r;       // registered change flag (pipelined so the
                                   // WIDTH-bit compare is not in the FIFO
                                   // write-enable path - GW1N needs this)
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

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sig_prev    <= {WIDTH{1'b0}};
            sig_d       <= {WIDTH{1'b0}};
            chg_r       <= 1'b0;
            init_done   <= 1'b0;
            ts          <= {TS_BITS{1'b0}};
            wp          <= 0;
            ovf_pending <= 1'b0;
            ovf_pulse   <= 1'b0;
        end else begin
            ts        <= ts + 1'b1;
            ovf_pulse <= 1'b0;
            // stage 1: compare consecutive samples
            sig_prev  <= sig_s;
            sig_d     <= sig_s;
            chg_r     <= !init_done || (sig_s != sig_prev);
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
    // byte serializer: K28.1, then REC_BYTES bytes of {ts, data} LSB first
    //------------------------------------------------------------------
    reg                 sb_active;   // 0: at record boundary
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
            sb_active <= 1'b0;
            sb_idx    <= 8'd0;
            rp        <= 0;
            cur       <= {REC_BITS{1'b0}};
            b_valid   <= 1'b0;
            b_is_k    <= 1'b0;
            b_data    <= 8'h00;
            ovf_ack   <= 1'b0;
        end else begin
            ovf_ack <= 1'b0;
            if (can_load) begin
                if (!sb_active) begin
                    if (ovf_pending && !ovf_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_2;
                        ovf_ack <= 1'b1;
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
