`default_nettype none

module axis_dispose #(
    parameter TDATA_BYTES = 1
) (
    input wire aclk,
    input wire aresetn,
    
    input  wire [TDATA_BYTES*8-1:0] saxis_tdata,
    input  wire                     saxis_tvalid,
    output wire                     saxis_tready
);

assign saxis_tready = 1;

endmodule

`default_nettype wire
