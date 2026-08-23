// Family-independent EasyCDR-link transmitter core.
//
// Emits a continuous 10-bit 8b10b symbol stream at the parallel-word rate
// (line rate / 10):
//   - every FRAME_LEN-th word is a K28.5 comma (word alignment marker)
//   - the remaining slots carry the input byte stream; when no byte is
//     offered, a K28.3 idle filler is sent instead
//
// o_symbol bit 0 is the first bit on the wire (matches OSER10 D0).
// Depends only on displayport_encoder_8b10b (rtl/displayport) - no
// device-specific primitives, so it runs on GW1N / GW2A / GW5A alike.
module easycdr_trace_tx_core #(
    parameter FRAME_LEN = 16   // words per frame incl. the K28.5 comma
) (
    input  wire       clk,     // parallel clock = line rate / 10
    input  wire       rstn,

    // byte stream to transmit (consumed one byte per non-comma slot)
    input  wire       i_valid,
    input  wire       i_is_k,
    input  wire [7:0] i_data,
    output wire       o_ready,

    output wire [9:0] o_symbol
);
    localparam [7:0] K28_5 = 8'hbc;  // comma / alignment
    localparam [7:0] K28_3 = 8'h7c;  // idle filler

    reg [$clog2(FRAME_LEN)-1:0] slot;
    wire comma_slot = (slot == FRAME_LEN-1);
    assign o_ready = ~comma_slot;

    reg [7:0] enc_data;
    reg       enc_is_k;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            slot     <= 0;
            enc_data <= K28_5;
            enc_is_k <= 1'b1;
        end else begin
            slot <= comma_slot ? 0 : slot + 1'b1;
            if (comma_slot) begin
                enc_data <= K28_5;
                enc_is_k <= 1'b1;
            end else if (i_valid) begin
                enc_data <= i_data;
                enc_is_k <= i_is_k;
            end else begin
                enc_data <= K28_3;
                enc_is_k <= 1'b1;
            end
        end
    end

    displayport_encoder_8b10b u_enc(
        .i_clk      (clk),
        .i_rstn     (rstn),
        .i_valid    (1'b1),
        .i_data     (enc_data),
        .i_is_k     (enc_is_k),
        .i_rd_reset (1'b0),
        .o_valid    (),
        .o_symbol   (o_symbol)
    );
endmodule
