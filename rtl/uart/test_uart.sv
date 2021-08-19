`default_nettype none
`timescale 1ns/1ps

module test_uart ();

logic clock;
logic reset;

initial begin
        clock = 0;
end 
always #(5) begin
    clock = ~clock;
end

logic overrun;
logic tx;
logic rx;
assign rx = tx;

logic tx_data_valid;
logic tx_data_ready;
logic [7:0] tx_data_bits;
logic rx_data_valid;
logic rx_data_ready;
logic [7:0] rx_data_bits;

uart_rx #(.BAUD_DIVIDER(4)) uart_rx_inst(
    .data_valid(rx_data_valid),
    .data_ready(rx_data_ready),
    .data_bits  (rx_data_bits),
    .*);
uart_tx #(.BAUD_DIVIDER(4)) uart_tx_inst(
    .data_valid(tx_data_valid),
    .data_ready(tx_data_ready),
    .data_bits  (tx_data_bits),
    .*);

initial begin
    $dumpfile("test_uart.vcd");
    $dumpvars(0);
    tx_data_valid <= 0;
    rx_data_ready <= 0;
    reset <= 1;
    repeat(2) @(posedge clock);
    reset <= 0;
    repeat(2) @(posedge clock);

    fork
        fork
            begin
                for(int i = 0; i < 255; i++) begin
                    tx_data_valid <= 1;
                    tx_data_bits <= i;
                    do @(posedge clock); while(!tx_data_ready);
                    tx_data_valid <= 0;
                    repeat($urandom_range(0, 2)) @(posedge clock);
                end
            end
            begin
                for(int i = 0; i < 255; i++) begin
                    rx_data_ready <= 0;
                    repeat($urandom_range(0, 2)) @(posedge clock);
                    rx_data_ready <= 1;
                    while(!rx_data_valid) @(posedge clock);
                    @(negedge clock);
                    if( rx_data_bits != i ) $error("#%02d data mismatch. expected: %02x, actual: %02x", i, i, rx_data_bits);
                end
            end
        join
        begin
            static int limit = 256*4*8*2;
            for(int cycles = 0; cycles < limit; cycles++ ) @(posedge clock);
            $error("Error: simulation timed out after %d cycles.", limit);
        end
    join_any
    disable fork;
    $finish;
end

endmodule

`default_nettype wire