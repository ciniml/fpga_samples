`default_nettype none
module uart_tx #(
    parameter int NUMBER_OF_BITS = 8,
    parameter int BAUD_DIVIDER = 4
) (
    input wire   clock,
    input wire   reset,

    input  logic                      data_valid,
    output logic                      data_ready,
    input  logic [NUMBER_OF_BITS-1:0] data_bits,

    output logic tx
);

localparam int RATE_COUNTER_BITS = $clog2(BAUD_DIVIDER);
localparam int BIT_COUNTER_BITS  = $clog2(NUMBER_OF_BITS+2);

logic [RATE_COUNTER_BITS-1:0] rate_counter = 0;
logic [BIT_COUNTER_BITS-1:0] bit_counter = 0;
logic [NUMBER_OF_BITS+1:0] bits;

assign tx = bit_counter == 0 || bits[0];
assign data_ready = bit_counter == 0;

always_ff @(posedge clock) begin
    if( reset ) begin
        rate_counter <= 0;
        bit_counter <= 0;
    end
    else begin
       if( data_valid && data_ready ) begin
           bits <= {1'b1, data_bits, 1'b0 };    // STOP(1), DATA, START(0)
           bit_counter <= NUMBER_OF_BITS + 2;
           rate_counter <= BAUD_DIVIDER - 1;
       end
       if( bit_counter > 0 ) begin
           if( rate_counter == 0 ) begin
                bits <= {1'b0, bits[NUMBER_OF_BITS+1:1]};
                bit_counter <= bit_counter - 1;
                rate_counter <= BAUD_DIVIDER - 1;    
           end
           else begin
               rate_counter <= rate_counter - 1;
           end
       end
    end
end

endmodule
`default_nettype wire