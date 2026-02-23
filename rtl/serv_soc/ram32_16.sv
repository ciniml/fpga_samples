`default_nettype none
module ram32_16 #(
    parameter int RAM_SIZE = 256*4,
    localparam RAM_ADDR_BITS = $clog2(RAM_SIZE)
) (
    input wire clock,
    input wire reset,
    wishbone_if.slave_port wb_slave
);

bit [15:0] mem [0:RAM_SIZE/2-1]; /* synthesis syn_ramstyle="block_ram" */

logic [RAM_ADDR_BITS-2:0] mem_adr_base;
logic [RAM_ADDR_BITS-1:0] mem_adr;
logic state;
assign mem_adr_base = wb_slave.adr[$bits(wb_slave.adr)-1:2]; 
assign mem_adr = {mem_adr_base, state ? 1'b1 : 1'b0 };
logic [15:0] mem_wdata;
assign mem_wdata = state ? wb_slave.dat_o[31:16] : wb_slave.dat_o[15:0];
logic [15:0] mem_rdata;
assign mem_rdata = mem[mem_adr];

always_ff @(posedge clock) begin
    if( reset ) begin
        state <= 0;
        wb_slave.dat_i <= 0;
        wb_slave.ack <= 0;
    end
    else begin
        wb_slave.ack <= 0;
        if( wb_slave.cyc ) begin
            if( wb_slave.we ) begin
                mem[mem_adr] <= mem_wdata;
            end
            if( !state ) begin
                wb_slave.dat_i[15:0] <= mem_rdata;
            end
            else begin
                wb_slave.dat_i[31:16] <= mem_rdata;
            end
            state <= !state;
            wb_slave.ack   <= state;
        end
    end
end
endmodule
`default_nettype wire