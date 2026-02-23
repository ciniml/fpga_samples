`default_nettype none

module axis_to_xgmii_preamble #(
    parameter PREAMBLE_CHARACTER = 8'h55,
    parameter SFD_CHARACTER = 8'hd5
) (
    input wire clock,
    input wire aresetn,
    
    output reg [63:0] xgmii_d,
    output reg  [7:0] xgmii_c,

    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire  [7:0] saxis_tkeep,
    input  wire        saxis_tuser,
    input  wire        saxis_tlast
);


localparam XGMII_SOF  = 8'hfb;
localparam XGMII_EOF  = 8'hfd;
localparam XGMII_ERR  = 8'hfe;
localparam XGMII_IDLE = 8'h07;

enum {IDLE, OUT_DATA, OUT_IPG, OUT_TERMINATOR_EOF, OUT_TERMINATOR_ERR} state;
assign saxis_tready = state == OUT_DATA;

logic [7:0] terminator;
assign terminator = saxis_tuser ? XGMII_ERR : XGMII_EOF;

logic [63:0] last_xgmii_d;
generate
assign last_xgmii_d[7:0] = saxis_tdata[7:0];
for(genvar i = 1; i < 8; i++) begin
    assign last_xgmii_d[i*8 +: 8] = saxis_tkeep[i] ? saxis_tdata[i*8 +: 8]
                           : !saxis_tkeep[i] && saxis_tkeep[i-1] ? terminator
                           : XGMII_IDLE;
end
endgenerate

always @(posedge clock) begin
    if( !aresetn ) begin
        state <= IDLE;
        xgmii_d <= {8 {XGMII_IDLE} };
        xgmii_c <= {8 {1'b1} };
    end
    else begin
        case(state)
        IDLE: begin
            if( saxis_tvalid ) begin
                xgmii_d <= {SFD_CHARACTER, {6 {PREAMBLE_CHARACTER}}, XGMII_SOF};
                xgmii_c <= 8'b0000_0001;
                state <= OUT_DATA;
            end
            else begin
                xgmii_d <= {8 {XGMII_IDLE} };
                xgmii_c <= {8 {1'b1} };
            end
        end
        OUT_DATA: begin
            if( !saxis_tvalid ) begin
                xgmii_d <= {{7 {XGMII_IDLE}}, XGMII_ERR};   // saxis_valid must be asserted while the current frame continues. 
                xgmii_c <= 8'b1111_1111;                    // If deassertion of saxis_valid has occured, treat the current frame as an errornous frame.
                state <= IDLE;
            end
            else begin
                if( saxis_tlast ) begin
                    xgmii_d <= last_xgmii_d;
                    xgmii_c <= ~saxis_tkeep;
                    state <= !(&saxis_tkeep) ? OUT_IPG          // Insert IPG
                           : saxis_tuser ? OUT_TERMINATOR_ERR
                           :               OUT_TERMINATOR_EOF;  // Output terminator at the next cycle if the last beat contains full of its bytes.
                end
                else begin
                    xgmii_d <= saxis_tdata;
                    xgmii_c <= 0;
                end
            end
        end
        OUT_TERMINATOR_EOF: begin
            xgmii_d <= {{7 {XGMII_IDLE}}, XGMII_EOF};
            xgmii_c <= 8'b1111_1111;
            state <= IDLE;
        end
        OUT_TERMINATOR_ERR: begin
            xgmii_d <= {{7 {XGMII_IDLE}}, XGMII_ERR};
            xgmii_c <= 8'b1111_1111;
            state <= IDLE;
        end
        OUT_IPG: begin
            xgmii_d <= {8 {XGMII_IDLE} };
            xgmii_c <= {8 {1'b1} };
            state <= IDLE;
        end
        endcase
    end
end

endmodule

`default_nettype wire
