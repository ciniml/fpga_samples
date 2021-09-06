`default_nettype none

module simple_fifo #(
    parameter int DATA_BITS = 8,
    parameter int DEPTH_BITS = 3
) (
    input  wire clock,
    input  wire reset,
    
    input  wire [DATA_BITS-1:0] saxis_tdata,
    input  wire                 saxis_tvalid,
    output logic                saxis_tready,
    
    output logic [DATA_BITS-1:0] maxis_tdata,
    output logic                 maxis_tvalid,
    input  wire                  maxis_tready
);

logic [DEPTH_BITS:0] index_r;
logic [DEPTH_BITS:0] index_w;

logic [DATA_BITS-1:0] memory[2**DEPTH_BITS-1:0];

always_comb begin
    saxis_tready = index_r[DEPTH_BITS] == index_w[DEPTH_BITS] || index_r[DEPTH_BITS-1:0] != index_w[DEPTH_BITS-1:0];
    maxis_tvalid = index_r != index_w;
    maxis_tdata  = memory[index_r[DEPTH_BITS-1:0]];    
end


always_ff @(posedge clock) begin
    if( reset ) begin
        index_r <= 0;
        index_w <= 0;
    end
    else begin
        index_w <= saxis_tvalid && saxis_tready ? index_w + 1 : index_w;
        index_r <= maxis_tvalid && maxis_tready ? index_r + 1 : index_r;
        if( saxis_tvalid && saxis_tready ) begin
            memory[index_w[DEPTH_BITS-1:0]] <= saxis_tdata;
        end
    end
end

endmodule

`default_nettype wire
