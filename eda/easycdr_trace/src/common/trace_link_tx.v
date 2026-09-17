// trace_link_tx: link-clock-domain part of the trace transmitter.
//
// Pops {ts, data} records from the record FIFO and serialises them as
//   [K28.1][ts bytes][data bytes]   (little-endian)
//   [K28.7][ts bytes]               tick (FIFO word flagged, no data bytes)
// interleaved with the overflow marker (K28.2, one per request) and the
// descriptor record [K28.4][VER=2][WIDTH][TS_BITS][flags][HASH0..3], all at record
// boundaries; tx_link_core adds the K28.5 comma framing, K28.3 idle filler
// and 8b10b encoding. Only the link clock (line rate / 10) is used here.
module trace_link_tx #(
    parameter WIDTH         = 16,
    parameter TS_BITS       = 24,
    parameter FRAME_LEN     = 16,
    parameter DESC_INTERVAL = 131072,
    parameter [31:0] CFG_HASH = 32'h0   // signal-map hash (tracemap.py), descriptor bytes 4..7
) (
    input  wire                     clk,
    input  wire                     rstn,

    input  wire                     i_fifo_empty,
    input  wire [TS_BITS+WIDTH:0]   i_fifo_data,   // {tick, ts, data}
    output reg                      o_fifo_rd,

    input  wire                     i_ovf_req,     // one clock: schedule a K28.2
    output reg                      o_ovf_ack,     // one clock: K28.2 sent

    input  wire                     i_desc_req,
    input  wire [4:0]               i_desc_flags,  // {periodic, done, triggered, armed, enable}

    input  wire                     i_map_req,     // one clock: send the signal-map text once
    input  wire [7:0]               i_map_len,     // text length (0 = nothing to send)
    output reg  [7:0]               o_map_addr,    // byte ROM interface (combinational read)
    input  wire [7:0]               i_map_data,

    output wire [9:0]               o_symbol
);
    localparam TS_BYTES  = TS_BITS / 8;
    localparam REC_BYTES = TS_BYTES + WIDTH / 8;
    localparam REC_BITS  = TS_BITS + WIDTH;
    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;
    localparam [7:0] K28_4 = 8'h9c;
    localparam [7:0] K28_6 = 8'hdc;   // signal-map text: [K28.6][LEN][LEN bytes]
    localparam [7:0] K28_7 = 8'hfc;   // tick: [K28.7][ts bytes]

    //------------------------------------------------------------------
    // descriptor scheduler and overflow marker request
    //------------------------------------------------------------------
    localparam DIW = (DESC_INTERVAL <= 1) ? 1 : $clog2(DESC_INTERVAL);
    reg [DIW-1:0] desc_timer;
    reg           desc_pending, desc_ack;
    reg           ovf_pending;
    reg           map_pending, map_ack, map_active, map_lenbyte;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            desc_timer   <= {DIW{1'b0}};
            desc_pending <= 1'b0;
            ovf_pending  <= 1'b0;
            map_pending  <= 1'b0;
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
            if (i_map_req && i_map_len != 8'd0) map_pending <= 1'b1;
            if (map_ack)    map_pending  <= 1'b0;
            if (i_ovf_req)  ovf_pending  <= 1'b1;
            if (o_ovf_ack)  ovf_pending  <= 1'b0;
        end
    end

    reg [7:0] desc_byte;
    reg [2:0] desc_idx;
    always @(*) begin
        case (desc_idx)
        3'd0: desc_byte = 8'h02;          // format version 2 (8 bytes)
        3'd1: desc_byte = WIDTH[7:0];
        3'd2: desc_byte = TS_BITS[7:0];
        3'd3: desc_byte = {3'b0, i_desc_flags};
        3'd4: desc_byte = CFG_HASH[7:0];
        3'd5: desc_byte = CFG_HASH[15:8];
        3'd6: desc_byte = CFG_HASH[23:16];
        default: desc_byte = CFG_HASH[31:24];
        endcase
    end

    //------------------------------------------------------------------
    // byte serializer
    //------------------------------------------------------------------
    reg                sb_active, desc_active;
    reg [7:0]          sb_idx, sb_last;
    reg [REC_BITS-1:0] cur;          // {data, ts}: byte 0 = ts[7:0]
    reg                b_valid, b_is_k;
    reg [7:0]          b_data;
    wire               b_ready;
    wire can_load = !b_valid || b_ready;
    wire [7:0] cur_byte = cur[sb_idx*8 +: 8];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sb_active   <= 1'b0;
            desc_active <= 1'b0;
            desc_idx    <= 3'd0;
            desc_ack    <= 1'b0;
            sb_idx      <= 8'd0;
            sb_last     <= 8'd0;
            map_ack     <= 1'b0;
            map_active  <= 1'b0;
            map_lenbyte <= 1'b0;
            o_map_addr  <= 8'd0;
            cur         <= {REC_BITS{1'b0}};
            b_valid     <= 1'b0;
            b_is_k      <= 1'b0;
            b_data      <= 8'h00;
            o_ovf_ack   <= 1'b0;
            o_fifo_rd   <= 1'b0;
        end else begin
            o_ovf_ack <= 1'b0;
            desc_ack  <= 1'b0;
            map_ack   <= 1'b0;
            o_fifo_rd <= 1'b0;
            if (can_load) begin
                if (map_active) begin                    // [LEN] then the text bytes
                    b_valid <= 1'b1; b_is_k <= 1'b0;
                    if (map_lenbyte) begin
                        b_data <= i_map_len; map_lenbyte <= 1'b0; o_map_addr <= 8'd0;
                    end else begin
                        b_data <= i_map_data;
                        if (o_map_addr == i_map_len - 1'b1) map_active <= 1'b0;
                        o_map_addr <= o_map_addr + 1'b1;
                    end
                end else if (desc_active) begin
                    b_valid <= 1'b1; b_is_k <= 1'b0;
                    b_data  <= desc_byte;
                    if (desc_idx == 3'd7) desc_active <= 1'b0;
                    desc_idx <= desc_idx + 1'b1;
                end else if (!sb_active) begin
                    if (ovf_pending && !o_ovf_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_2;
                        o_ovf_ack <= 1'b1;
                    end else if (desc_pending && !desc_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_4;
                        desc_active <= 1'b1;
                        desc_idx    <= 3'd0;
                        desc_ack    <= 1'b1;
                    end else if (map_pending && !map_ack) begin
                        b_valid <= 1'b1; b_is_k <= 1'b1; b_data <= K28_6;
                        map_active  <= 1'b1;
                        map_lenbyte <= 1'b1;
                        map_ack     <= 1'b1;
                    end else if (!i_fifo_empty && !o_fifo_rd) begin
                        cur       <= {i_fifo_data[WIDTH-1:0], i_fifo_data[REC_BITS-1:WIDTH]};
                        o_fifo_rd <= 1'b1;
                        b_valid   <= 1'b1; b_is_k <= 1'b1;
                        b_data    <= i_fifo_data[REC_BITS] ? K28_7 : K28_1;
                        sb_last   <= i_fifo_data[REC_BITS] ? TS_BYTES-1 : REC_BYTES-1;
                        sb_active <= 1'b1;
                        sb_idx    <= 8'd0;
                    end else begin
                        b_valid <= 1'b0;
                    end
                end else begin
                    b_valid <= 1'b1; b_is_k <= 1'b0;
                    b_data  <= cur_byte;
                    if (sb_idx == sb_last) sb_active <= 1'b0;
                    sb_idx <= sb_idx + 1'b1;
                end
            end
        end
    end

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
