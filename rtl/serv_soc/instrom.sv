module instrom #(
    parameter RAM_SIZE = 256*4,
    parameter INITIAL_FILE = "",
    localparam RAM_ADDR_BITS = $clog2(RAM_SIZE/4)
) (
    input wire clk,
    input wire resetn,
    input wire [RAM_ADDR_BITS-1:0] addr,
    input wire        ce,
    input wire        we,
    input wire [31:0] data_in,
    output reg [31:0] data_out
);

logic reset;
assign reset = !resetn;

always_ff @(posedge clk or posedge reset) begin
    if( reset ) begin
        data_out <= 0;
    end
    else if( ce ) begin
        case(addr)
            4'h0: data_out <= 32'h00000537;
            4'h1: data_out <= 32'h10050513;
            4'h2: data_out <= 32'h00010337;
            4'h3: data_out <= 32'h00550023;
            4'h4: data_out <= 32'h0042c293;
            4'h5: data_out <= 32'h000073b3;
            4'h5: data_out <= 32'h00138393;
            4'h7: data_out <= 32'hfe731ee3;
            4'h8: data_out <= 32'hfedff06f;
            default: data_out <= 0;
        endcase
    end
end

endmodule