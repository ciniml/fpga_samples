`default_nettype none

module uart_system (
    input wire clock,
    input wire resetn,

    output wire tx,
    input wire rx
);

localparam int CLOCK_HZ = 24000000;
localparam int BAUD_RATE = 115200;

logic reset;
assign reset = !resetn;
logic data_valid;
logic data_ready;
logic [7:0] data_bits;
logic overrun;

uart_rx #(.BAUD_DIVIDER(CLOCK_HZ/BAUD_RATE)) uart_rx_inst(.*);
uart_tx #(.BAUD_DIVIDER(CLOCK_HZ/BAUD_RATE)) uart_tx_inst(
    .data_bits(data_bits + 8'd1), 
    .*);

endmodule

`default_nettype wire