// Phase 2: capture the received payload stream into a BSRAM buffer and dump
// it to the host over UART on command.
//
// Capture domain : pclk (125MHz EasyCDR parallel clock), payload bytes at up
//                  to 100MB/s - far faster than the UART, so the model is
//                  "arm, fill once, freeze, then drain slowly".
// Control domain : clk_sys (50MHz), UART command/dump.
//
// UART protocol (single-byte commands from the host):
//   'S' : arm the capture; the buffer fills with the next BUF_SIZE payload
//         bytes and freezes. Replies 'K' when the buffer is full.
//   'D' : dump the frozen buffer (BUF_SIZE raw bytes).
module trace_capture #(
    parameter ADDR_BITS    = 14,               // 16KiB buffer
    parameter BAUD_DIVIDER = 434               // 50MHz / 115200
) (
    // capture side
    input  wire       pclk,
    input  wire       prst,        // active high (EasyCDR share reset)
    input  wire       in_valid,    // payload byte strobe
    input  wire [7:0] in_data,

    // control / drain side
    input  wire       clk_sys,
    input  wire       rst_sys,     // active high
    input  wire       uart_rxd,
    output wire       uart_txd
);
    localparam [ADDR_BITS-1:0] LAST_ADDR = {ADDR_BITS{1'b1}};

    //------------------------------------------------------------------
    // UART
    //------------------------------------------------------------------
    wire       rx_valid;
    wire [7:0] rx_data;
    uart_rx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_uart_rx(
        .clock      (clk_sys),
        .reset      (rst_sys),
        .data_valid (rx_valid),
        .data_ready (1'b1),
        .data_bits  (rx_data),
        .rx         (uart_rxd),
        .overrun    ()
    );

    reg        tx_valid;
    reg  [7:0] tx_data;
    wire       tx_ready;
    uart_tx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_uart_tx(
        .clock      (clk_sys),
        .reset      (rst_sys),
        .data_valid (tx_valid),
        .data_ready (tx_ready),
        .data_bits  (tx_data),
        .tx         (uart_txd)
    );

    //------------------------------------------------------------------
    // Capture memory: write @pclk, read @clk_sys (dual-clock BSRAM)
    //------------------------------------------------------------------
    reg [7:0] buffer [0:(1<<ADDR_BITS)-1];
    reg [ADDR_BITS-1:0] waddr;
    reg [ADDR_BITS-1:0] raddr;
    reg [7:0]           rdata;

    // arm request: clk_sys -> pclk (toggle + 2FF sync)
    reg arm_tgl_sys;
    reg [2:0] arm_sync_p;
    always @(posedge pclk or posedge prst) begin
        if (prst) arm_sync_p <= 3'b000;
        else      arm_sync_p <= {arm_sync_p[1:0], arm_tgl_sys};
    end
    wire arm_req_p = arm_sync_p[2] ^ arm_sync_p[1];

    // capture FSM @pclk
    reg capturing;
    reg full_tgl_p;
    always @(posedge pclk or posedge prst) begin
        if (prst) begin
            capturing  <= 1'b0;
            waddr      <= {ADDR_BITS{1'b0}};
            full_tgl_p <= 1'b0;
        end else begin
            if (arm_req_p) begin
                capturing <= 1'b1;
                waddr     <= {ADDR_BITS{1'b0}};
            end else if (capturing && in_valid) begin
                buffer[waddr] <= in_data;
                waddr <= waddr + 1'b1;
                if (waddr == LAST_ADDR) begin
                    capturing  <= 1'b0;
                    full_tgl_p <= ~full_tgl_p;
                end
            end
        end
    end

    // full notification: pclk -> clk_sys
    reg [2:0] full_sync_s;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) full_sync_s <= 3'b000;
        else         full_sync_s <= {full_sync_s[1:0], full_tgl_p};
    end
    wire full_evt_s = full_sync_s[2] ^ full_sync_s[1];

    //------------------------------------------------------------------
    // Control / dump FSM @clk_sys
    //------------------------------------------------------------------
    localparam ST_IDLE  = 2'd0;
    localparam ST_WAIT  = 2'd1;   // capture in progress
    localparam ST_DUMP  = 2'd2;

    reg [1:0] state;
    reg       rd_pending;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            state       <= ST_IDLE;
            arm_tgl_sys <= 1'b0;
            tx_valid    <= 1'b0;
            tx_data     <= 8'h00;
            raddr       <= {ADDR_BITS{1'b0}};
            rdata       <= 8'h00;
            rd_pending  <= 1'b0;
        end else begin
            if (tx_valid && tx_ready)
                tx_valid <= 1'b0;

            // registered BSRAM read: rdata follows raddr by one cycle
            rdata      <= buffer[raddr];
            rd_pending <= 1'b0;

            case (state)
            ST_IDLE: begin
                if (rx_valid && rx_data == "S") begin
                    arm_tgl_sys <= ~arm_tgl_sys;
                    state       <= ST_WAIT;
                end else if (rx_valid && rx_data == "D") begin
                    raddr      <= {ADDR_BITS{1'b0}};
                    rd_pending <= 1'b1;
                    state      <= ST_DUMP;
                end
            end
            ST_WAIT: begin
                if (full_evt_s) begin
                    tx_data  <= "K";
                    tx_valid <= 1'b1;
                    state    <= ST_IDLE;
                end
            end
            ST_DUMP: begin
                if (!tx_valid && tx_ready && !rd_pending) begin
                    tx_data  <= rdata;
                    tx_valid <= 1'b1;
                    if (raddr == LAST_ADDR) begin
                        state <= ST_IDLE;
                    end else begin
                        raddr      <= raddr + 1'b1;
                        rd_pending <= 1'b1;
                    end
                end
            end
            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
