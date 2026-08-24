// Trace capture buffer with trigger / pre-trigger support and UART dump.
//
// Capture domain : pclk (EasyCDR parallel clock). While armed, every entry
//                  ({K flag, byte}) is written into a ring buffer. Records
//                  are decoded on the fly; when the trigger condition
//                  (rec_data & mask) == (value & mask) is met, POST more
//                  entries are written and the buffer freezes. Entries
//                  written before the trigger are the pre-trigger history.
// Control domain : clk_sys. The host transport is abstracted as a byte
//                  stream (valid/ready both ways) so UART, USB CDC or any
//                  other bridge can be attached at the top level.
//
// Command protocol (host -> FPGA):
//   'S'                         : arm, trigger immediately, fill the whole
//                                 buffer (POST = buffer size)
//   'T' mask[0..DB-1] val[0..DB-1]: set trigger mask/value (LSB first,
//                                 DB = WIDTH/8 bytes each)
//   'A' post_hi post_lo         : arm and wait for the trigger, then keep
//                                 POST entries after it
//   'D'                         : dump the buffer in chronological order
//                                 (2 bytes per entry: {7'b0,K} then data)
// FPGA -> host: 'K' when the capture has frozen.
module trace_capture #(
    parameter ADDR_BITS    = 14,
    parameter DATA_BITS    = 9,
    parameter WIDTH        = 16,
    parameter TS_BITS      = 24
) (
    input  wire                 pclk,
    input  wire                 prst,
    input  wire                 in_valid,   // entry strobe (buffer content)
    input  wire [DATA_BITS-1:0] in_data,
    input  wire                 rec_valid,  // decoded record (trigger source)
    input  wire [WIDTH-1:0]     rec_data,

    input  wire                 clk_sys,
    input  wire                 rst_sys,
    // host byte stream (transport-agnostic)
    input  wire                 h_rx_valid,   // byte from host
    input  wire [7:0]           h_rx_data,
    output wire                 h_tx_valid,   // byte to host
    output wire [7:0]           h_tx_data,
    input  wire                 h_tx_ready
);
    localparam DB = WIDTH / 8;
    localparam [ADDR_BITS-1:0] LAST_ADDR = {ADDR_BITS{1'b1}};

    wire       rx_valid = h_rx_valid;
    wire [7:0] rx_data  = h_rx_data;
    reg        tx_valid;
    reg  [7:0] tx_data;
    wire       tx_ready = h_tx_ready;
    assign h_tx_valid = tx_valid;
    assign h_tx_data  = tx_data;

    //------------------------------------------------------------------
    // control registers (clk_sys), quasi-static towards pclk
    //------------------------------------------------------------------
    reg [WIDTH-1:0]     trig_mask, trig_value;
    reg [ADDR_BITS:0]   post_count;     // entries to keep after the trigger
    reg                 arm_immediate;  // 1: 'S' (trigger at once)
    reg                 arm_tgl_sys;

    // arm request: clk_sys -> pclk
    reg [2:0] arm_sync_p;
    always @(posedge pclk or posedge prst)
        if (prst) arm_sync_p <= 3'b000;
        else      arm_sync_p <= {arm_sync_p[1:0], arm_tgl_sys};
    wire arm_req_p = arm_sync_p[2] ^ arm_sync_p[1];

    //------------------------------------------------------------------
    // capture memory + FSM (pclk)
    //------------------------------------------------------------------
    reg [DATA_BITS-1:0] buffer [0:(1<<ADDR_BITS)-1];
    reg [ADDR_BITS-1:0] waddr;

    localparam CS_IDLE = 2'd0;
    localparam CS_WAIT = 2'd1;   // ring-writing, waiting for the trigger
    localparam CS_POST = 2'd2;   // ring-writing, counting down
    reg [1:0]         cstate;
    reg [ADDR_BITS:0] post_left;
    reg               full_tgl_p;

    wire trig_hit = rec_valid && ((rec_data & trig_mask) == (trig_value & trig_mask));

    always @(posedge pclk or posedge prst) begin
        if (prst) begin
            cstate     <= CS_IDLE;
            waddr      <= {ADDR_BITS{1'b0}};
            post_left  <= 0;
            full_tgl_p <= 1'b0;
        end else begin
            if (cstate != CS_IDLE && in_valid) begin
                buffer[waddr] <= in_data;
                waddr <= waddr + 1'b1;
            end
            case (cstate)
            CS_IDLE:
                if (arm_req_p) begin
                    post_left <= post_count;
                    cstate    <= arm_immediate ? CS_POST : CS_WAIT;
                end
            CS_WAIT:
                if (trig_hit) cstate <= CS_POST;
            CS_POST:
                if (in_valid) begin
                    if (post_left <= 1) begin
                        cstate     <= CS_IDLE;
                        full_tgl_p <= ~full_tgl_p;
                    end
                    post_left <= post_left - 1'b1;
                end
            default: cstate <= CS_IDLE;
            endcase
        end
    end

    // capture-done notification: pclk -> clk_sys
    reg [2:0] full_sync_s;
    always @(posedge clk_sys or posedge rst_sys)
        if (rst_sys) full_sync_s <= 3'b000;
        else         full_sync_s <= {full_sync_s[1:0], full_tgl_p};
    wire full_evt_s = full_sync_s[2] ^ full_sync_s[1];

    // oldest entry = current write pointer (quasi-static once frozen)
    reg [ADDR_BITS-1:0] waddr_s;
    always @(posedge clk_sys) waddr_s <= waddr;

    //------------------------------------------------------------------
    // command parser / dump FSM (clk_sys)
    //------------------------------------------------------------------
    localparam ST_IDLE   = 3'd0;
    localparam ST_ARGS   = 3'd1;   // collecting command arguments
    localparam ST_WAIT   = 3'd2;   // capture in progress
    localparam ST_DUMP   = 3'd3;

    reg [2:0]           state;
    reg [7:0]           cmd;
    reg [7:0]           arg_idx;
    reg [ADDR_BITS-1:0] raddr;
    reg [ADDR_BITS:0]   dump_left;
    reg [DATA_BITS-1:0] rdata;
    reg                 rd_pending;
    reg                 dump_lo;

    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            state         <= ST_IDLE;
            cmd           <= 8'h00;
            arg_idx       <= 8'd0;
            trig_mask     <= {WIDTH{1'b0}};
            trig_value    <= {WIDTH{1'b0}};
            post_count    <= 0;
            arm_immediate <= 1'b0;
            arm_tgl_sys   <= 1'b0;
            tx_valid      <= 1'b0;
            tx_data       <= 8'h00;
            raddr         <= {ADDR_BITS{1'b0}};
            dump_left     <= 0;
            rdata         <= {DATA_BITS{1'b0}};
            rd_pending    <= 1'b0;
            dump_lo       <= 1'b0;
        end else begin
            if (tx_valid && tx_ready) tx_valid <= 1'b0;
            rdata      <= buffer[raddr];
            rd_pending <= 1'b0;

            case (state)
            ST_IDLE: if (rx_valid) begin
                cmd     <= rx_data;
                arg_idx <= 8'd0;
                case (rx_data)
                "S": begin
                    post_count    <= (1 << ADDR_BITS);
                    arm_immediate <= 1'b1;
                    arm_tgl_sys   <= ~arm_tgl_sys;
                    state         <= ST_WAIT;
                end
                "T", "A": state <= ST_ARGS;
                "D": begin
                    raddr      <= waddr_s;
                    dump_left  <= (1 << ADDR_BITS);
                    rd_pending <= 1'b1;
                    dump_lo    <= 1'b0;
                    state      <= ST_DUMP;
                end
                default: ;
                endcase
            end
            ST_ARGS: if (rx_valid) begin
                arg_idx <= arg_idx + 1'b1;
                if (cmd == "T") begin
                    if (arg_idx < DB) trig_mask [arg_idx*8 +: 8]      <= rx_data;
                    else              trig_value[(arg_idx-DB)*8 +: 8] <= rx_data;
                    if (arg_idx == 2*DB-1) state <= ST_IDLE;
                end else begin // "A": post count, big-endian 16 bit
                    if (arg_idx == 0) post_count[ADDR_BITS:8] <= rx_data[ADDR_BITS-8:0];
                    else begin
                        post_count[7:0] <= rx_data;
                        arm_immediate   <= 1'b0;
                        arm_tgl_sys     <= ~arm_tgl_sys;
                        state           <= ST_WAIT;
                    end
                end
            end
            ST_WAIT: if (full_evt_s) begin
                tx_data  <= "K";
                tx_valid <= 1'b1;
                state    <= ST_IDLE;
            end
            ST_DUMP: if (!tx_valid && tx_ready && !rd_pending) begin
                if (!dump_lo) begin
                    tx_data  <= {7'b0, rdata[DATA_BITS-1]};
                    tx_valid <= 1'b1;
                    dump_lo  <= 1'b1;
                end else begin
                    tx_data  <= rdata[7:0];
                    tx_valid <= 1'b1;
                    dump_lo  <= 1'b0;
                    raddr      <= raddr + 1'b1;
                    rd_pending <= 1'b1;
                    dump_left  <= dump_left - 1'b1;
                    if (dump_left == 1) state <= ST_IDLE;
                end
            end
            default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
