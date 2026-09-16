// Re-frames the {K flag, byte} word stream from the EasyCDR receiver into
// trace records: [K28.1][ts LSB..MSB][data LSB..MSB].
// K28.5 commas and K28.3 fillers interleaved inside a record are ignored;
// K28.1 restarts a record, K28.2 (overflow marker) is flagged.
// K28.4 starts a descriptor ([VER][WIDTH][TS_BITS][flags] for VER 1, plus
// [HASH0..3] for VER 2) which is latched to o_desc_* (quasi-static once the
// link is up). o_desc_hash is 0 for VER 1 transmitters.
//
// The record layout is taken from the descriptor at run time (WIDTH and
// TS_BITS in bits, multiples of 8, up to MAX_WIDTH / MAX_TS_BITS), so one
// host bitstream serves any transmitter configuration. Until the first
// descriptor arrives DEFAULT_WIDTH / DEFAULT_TS_BITS are assumed.
module trace_rx_decoder #(
    parameter MAX_WIDTH       = 64,
    parameter MAX_TS_BITS     = 32,
    parameter DEFAULT_WIDTH   = 16,
    parameter DEFAULT_TS_BITS = 24
) (
    input  wire                   clk,
    input  wire                   rst,       // active high
    input  wire                   in_valid,  // aligned word strobe
    input  wire [8:0]             in_word,   // {K flag, byte}
    output reg                    rec_valid,
    output reg  [MAX_TS_BITS-1:0] rec_ts,    // upper bits 0 when TS_BITS < MAX
    output reg  [MAX_WIDTH-1:0]   rec_data,  // upper bits 0 when WIDTH < MAX
    output reg                    ovf_seen,  // pulse on K28.2
    output reg  [7:0]             o_desc_ver,    // 0 until a descriptor is seen
    output reg  [7:0]             o_desc_width,
    output reg  [7:0]             o_desc_tsbits,
    output reg  [7:0]             o_desc_flags,
    output reg  [31:0]            o_desc_hash,
    output wire                   o_desc_busy    // descriptor bytes in flight
);
    localparam MAX_TB = MAX_TS_BITS / 8;
    localparam MAX_DB = MAX_WIDTH / 8;
    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;
    localparam [7:0] K28_4 = 8'h9c;

    // record layout in bytes (from the descriptor, clamped to the maxima)
    wire [7:0] d_tb = (o_desc_ver == 8'd0) ? DEFAULT_TS_BITS / 8 : {3'b0, o_desc_tsbits[7:3]};
    wire [7:0] d_db = (o_desc_ver == 8'd0) ? DEFAULT_WIDTH / 8   : {3'b0, o_desc_width[7:3]};
    reg  [7:0] tb, db, rec_last;
    always @(posedge clk) begin
        tb       <= (d_tb > MAX_TB) ? MAX_TB[7:0] : d_tb;
        db       <= (d_db > MAX_DB) ? MAX_DB[7:0] : d_db;
        rec_last <= tb + db - 1'b1;
    end

    reg                   active, done;
    reg [7:0]             idx;
    reg [MAX_TS_BITS-1:0] ts_acc;
    reg [MAX_WIDTH-1:0]   data_acc;
    reg                   desc_active;
    reg [2:0]             desc_idx;
    reg [55:0]            desc_acc;       // bytes 0..6 (byte 7 arrives with the latch)
    reg [2:0]             desc_last;      // 3 (VER 1) or 7 (VER 2)
    assign o_desc_busy = desc_active;

    wire [7:0] didx = idx - tb;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active      <= 1'b0;
            done        <= 1'b0;
            desc_active <= 1'b0;
            desc_idx    <= 3'd0;
            desc_acc    <= 56'd0;
            desc_last   <= 3'd3;
            o_desc_hash <= 32'd0;
            o_desc_ver    <= 8'd0;
            o_desc_width  <= 8'd0;
            o_desc_tsbits <= 8'd0;
            o_desc_flags  <= 8'd0;
            idx       <= 8'd0;
            ts_acc    <= {MAX_TS_BITS{1'b0}};
            data_acc  <= {MAX_WIDTH{1'b0}};
            rec_valid <= 1'b0;
            rec_ts    <= {MAX_TS_BITS{1'b0}};
            rec_data  <= {MAX_WIDTH{1'b0}};
            ovf_seen  <= 1'b0;
        end else begin
            rec_valid <= 1'b0;
            ovf_seen  <= 1'b0;
            done      <= 1'b0;
            if (done) begin                       // one cycle after the last byte
                rec_valid <= 1'b1;
                rec_ts    <= ts_acc;
                rec_data  <= data_acc;
            end
            if (in_valid) begin
                if (in_word[8]) begin
                    if (in_word[7:0] == K28_1) begin
                        active      <= 1'b1;
                        desc_active <= 1'b0;
                        idx         <= 8'd0;
                        ts_acc      <= {MAX_TS_BITS{1'b0}};
                        data_acc    <= {MAX_WIDTH{1'b0}};
                    end else if (in_word[7:0] == K28_2) begin
                        ovf_seen <= 1'b1;
                    end else if (in_word[7:0] == K28_4) begin
                        active      <= 1'b0;
                        desc_active <= 1'b1;
                        desc_idx    <= 3'd0;
                        desc_last   <= 3'd3;
                    end
                    // other K codes (comma / filler): ignore
                end else if (desc_active) begin
                    if (desc_idx == 3'd0) desc_last <= (in_word[7:0] >= 8'd2) ? 3'd7 : 3'd3;
                    if (desc_idx == desc_last) begin
                        if (desc_last == 3'd3) begin
                            {o_desc_flags, o_desc_tsbits, o_desc_width, o_desc_ver} <= {in_word[7:0], desc_acc[23:0]};
                            o_desc_hash <= 32'd0;
                        end else begin
                            {o_desc_flags, o_desc_tsbits, o_desc_width, o_desc_ver} <= desc_acc[31:0];
                            o_desc_hash <= {in_word[7:0], desc_acc[55:32]};
                        end
                        desc_active <= 1'b0;
                    end
                    desc_acc[desc_idx*8 +: 8] <= in_word[7:0];
                    desc_idx <= desc_idx + 1'b1;
                end else if (active) begin
                    if (idx < tb) ts_acc[idx*8 +: 8]    <= in_word[7:0];
                    else          data_acc[didx*8 +: 8] <= in_word[7:0];
                    if (idx == rec_last) begin
                        active <= 1'b0;
                        done   <= 1'b1;
                    end
                    idx <= idx + 1'b1;
                end
            end
        end
    end
endmodule
