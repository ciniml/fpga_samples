module wb_mux #(
    parameter int ADDRESS_BITS = 32,
    parameter int NUMBER_OF_PORTS = 2,
    parameter int DATA_BYTES = 4,
    parameter bit [ADDRESS_BITS*2-1:0] BASE_ADDRESS [NUMBER_OF_PORTS-1:0] = {64'h08000000_0800ffff, 64'h20000000_2000ffff}
) (
    wishbone_if.slave_port bus_in,
    wishbone_if.master_port bus_out [NUMBER_OF_PORTS-1:0]
);

logic [NUMBER_OF_PORTS-1:0] bus_selected;
logic [NUMBER_OF_PORTS-1:0] bus_out_ack;
logic [DATA_BYTES*8-1:0]    bus_out_dat_i [NUMBER_OF_PORTS-1:0];

for(genvar i = 0; i < NUMBER_OF_PORTS; i++ ) begin : bus_out_mux
    always_comb begin
        bus_selected[i]  = BASE_ADDRESS[i][ADDRESS_BITS +: ADDRESS_BITS] <= bus_in.adr && bus_in.adr <= BASE_ADDRESS[i][0 +: ADDRESS_BITS];
        bus_out[i].adr   = bus_in.adr;
        bus_out[i].cyc   = bus_selected[i] && bus_in.cyc;
        bus_out[i].stb   = bus_selected[i] && bus_in.stb;
        bus_out[i].we    = bus_selected[i] && bus_in.we;
        bus_out[i].sel   = bus_selected[i] && bus_in.sel;
        bus_out[i].dat_o = bus_in.dat_o;
        bus_out_ack[i]   = bus_selected[i] && bus_out[i].ack;
        bus_out_dat_i[i] = bus_out[i].dat_i;
    end
end

always_comb begin
    bus_in.ack = |bus_out_ack;
    bus_in.dat_i = 0;
    for(int i = 0; i < NUMBER_OF_PORTS; i++ ) begin
        if( bus_selected[i] ) begin
            bus_in.dat_i = bus_out_dat_i[i];
        end
    end
end

endmodule