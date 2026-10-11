// Test pattern source for the SLogic16U3 logic analyzer (eda/slogic16u3_la) on a Tang Primer 25K:
//   PMOD0 (8 lines) -> SLogic CH0..7 : an 8-bit counter (line k = bit k, on Pmod pins 1,7,2,8,3,9,4,10)
//   PMOD2 (8 lines) -> SLogic CH8..15: the same counter in Gray code
//   PMOD1 pin 1     -> SLogic CK0    : a clock rising in the middle of each pattern step
// The pattern advances every PATTERN_DIV clocks of the 50 MHz oscillator (make DIV=...): 25 MHz with 2.
// All outputs come from flip-flops in the 50 MHz domain (LVCMOS33).
module top (
    input  wire       clock,     // E2, 50 MHz
    output reg  [7:0] pa = 8'd0, // PMOD0 1,2,3,4,7,8,9,10
    output reg  [7:0] pb = 8'd0, // PMOD2 1,2,3,4,7,8,9,10
    output reg        ck = 1'b0  // PMOD1 1
);
    localparam integer DIV = `PATTERN_DIV;
    reg [15:0] ph = 16'd0;
    reg [7:0]  c = 8'd0;
    always @(posedge clock) begin
        ph <= (ph == DIV - 1) ? 16'd0 : ph + 16'd1;
        if (ph == DIV - 1) begin
            c  <= c + 8'd1;
            pa <= c + 8'd1;
            pb <= (c + 8'd1) ^ ((c + 8'd1) >> 1);
        end
        ck <= (ph >= DIV / 2 - 1) && (ph != DIV - 1);   // high for the second half of a step
`ifdef PATTERN_STATIC
        pa <= 8'h55; pb <= 8'h0F; ck <= 1'b0;             // (wiring check: fixed levels)
`endif
    end
endmodule
