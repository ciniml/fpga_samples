module ram16 #(
    parameter int RAM_SIZE = 64*2,
    localparam RAM_ADDR_BITS = $clog2(RAM_SIZE)
) (
    input  logic clk,
    input  logic resetn,

    input  logic [RAM_ADDR_BITS-1:0] adr,
    input  logic [16:0]              dat,
    input  logic                     sel,
    input  logic                     we,
    input  logic                     cyc,
    output logic [16:0]              rdt,
    output logic                     ack
);

bit [15:0] mem [0:RAM_SIZE/2-1]; /* synthesis syn_ramstyle="block_ram" */

always_ff @(posedge clk) begin
    if( cyc ) begin
        if( we ) begin
            mem[mem_adr] <= dat;
        end
    end
end

always_ff @(posedge clk) begin
    if( !resetn ) begin
        rdt <= 0;
        ack <= 0;
    end
    else if( cyc ) begin
        rdt <= mem[mem_adr];
        ack <= 1;
    end
    else begin
        ack <= 0;
    end
end


endmodule