`default_nettype none
module uart_rx #(
    parameter int NUMBER_OF_BITS = 8,
    parameter int BAUD_DIVIDER = 4,
    parameter int RX_SYNC_STAGES = 3
) (
    input wire  clock,
    input wire  reset,

    output logic                       data_valid,
    input  wire                        data_ready,
    output logic [NUMBER_OF_BITS-1:0] data_bits,

    input wire  rx,
    output logic overrun
);

localparam int RATE_COUNTER_BITS = $clog2(BAUD_DIVIDER*3/2);
localparam int BIT_COUNTER_BITS  = $clog2(NUMBER_OF_BITS);

logic [RATE_COUNTER_BITS-1:0] rate_counter = 0;
logic [BIT_COUNTER_BITS-1:0] bit_counter = 0;
logic [NUMBER_OF_BITS-1:0] bits;
logic [NUMBER_OF_BITS-1:0] next_bits;
logic [RX_SYNC_STAGES+1:0] rx_regs = 0;
logic running = 0;

assign next_bits = { rx_regs[0], bits[NUMBER_OF_BITS-1 : 1] };

always_ff @(posedge clock) begin
    if( reset ) begin
        data_valid <= 0;
        rate_counter <= 0;
        bit_counter <= 0;
        rx_regs <= 0;
        running <= 0;
        overrun <= 0;
    end
    else begin
        // Check if the last transaction completes.
        if( data_valid && data_ready ) begin
            data_valid <= 0;
        end
        // Synchronize RX signal
        rx_regs <= {rx, rx_regs[RX_SYNC_STAGES+1 : 1]};

        if( !running ) begin
            if( !rx_regs[1] && rx_regs[0] ) begin   // falling edge of START bit is detected.
                rate_counter <= BAUD_DIVIDER*3/2 - 1;   // Wait until the center of LSB
                bit_counter <= NUMBER_OF_BITS - 1;
                running <= 1;
            end
        end
        else begin
            if( rate_counter == 0 ) begin   // Sample next bit
                bits <= next_bits;
                if( bit_counter == 0 ) begin
                    data_valid <= 1;
                    data_bits <= next_bits;
                    overrun <= data_valid;
                    running <= 0;
                end
                else begin
                    rate_counter <= BAUD_DIVIDER - 1;
                    bit_counter <= bit_counter - 1;
                end
            end
            else begin
                rate_counter <= rate_counter - 1;
            end
        end
    end
end

endmodule
`default_nettype wire