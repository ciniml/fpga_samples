`default_nettype none
interface wishbone_if #(
    parameter int ADDRESS_BITS = 32,
    parameter int DATA_BYTES = 4
) (
    input wire clk,
    input wire rst
);

    logic [ADDRESS_BITS-1:0] adr;
    logic                    cyc;
    logic                    stb;
    logic                    we;
    logic  [DATA_BYTES-1:0]  sel;
    logic                    ack;
    logic [DATA_BYTES*8-1:0] dat_i;
    logic [DATA_BYTES*8-1:0] dat_o;
    
    modport master_port( 
        output adr, cyc, stb, we, sel, dat_o,
        input  ack, dat_i
    );
    modport slave_port( 
        input  adr, cyc, stb, we, sel, dat_o,
        output ack, dat_i
    );
endinterface
`default_nettype wire