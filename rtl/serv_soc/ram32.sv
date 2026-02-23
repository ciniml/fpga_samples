module ram32 #(
    parameter RAM_SIZE = 256*4,
    parameter INITIAL_FILE = "",
    localparam RAM_ADDR_BITS = $clog2(RAM_SIZE/4)
) (
    input wire clock,
    input wire reset,
    wishbone_if.slave_port wb_slave
);

logic [31:0] mem [0:RAM_SIZE/4-1]; /* synthesis syn_ramstyle="block_ram" */
logic [RAM_ADDR_BITS-1:0] addr;

assign addr = wb_slave.adr[RAM_ADDR_BITS+2-1:2];

always_ff @(posedge clock) begin
    if( reset ) begin
        wb_slave.dat_i <= 0;
        wb_slave.ack <= 0;
    end
    else begin
        wb_slave.ack <= 0;
        if(wb_slave.cyc) begin
            wb_slave.dat_i <= wb_slave.we ? wb_slave.dat_o : mem[addr];
            wb_slave.ack <= 1;
        end
    end
end
always_ff @(posedge clock) begin
    if( wb_slave.we ) begin
        mem[addr] <= wb_slave.dat_o;
    end
end

initial if(|INITIAL_FILE) $readmemh(INITIAL_FILE, mem);

endmodule