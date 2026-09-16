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
//                                 DB = WIDTH/8 bytes each, WIDTH from the
//                                 last descriptor - send '?' first)
//   'A' post_hi post_lo         : arm and wait for the trigger, then keep
//                                 POST entries after it
//   'D'                         : dump the buffer in chronological order
//                                 (2 bytes per entry: entry[DATA_BITS-1:8] then
//                                 entry[7:0]; bit 0 of the first byte = K flag)
//   '?'                         : reply 8 bytes [VER][WIDTH][TS_BITS][ADDR_BITS]
//                                 [HASH0..HASH3]. VER/WIDTH/TS_BITS/HASH come
//                                 from the last link descriptor (0 if none seen
//                                 yet; HASH 0 for VER 1), ADDR_BITS from the
//                                 local parameter.
//   'X' len byte0..len-1        : forward len bytes to the reverse control
//                                 channel (o_fwd_valid/o_fwd_data strobes;
//                                 the top level buffers them for its
//                                 ManchesterTx)
//   'F'                         : reply 1 byte: TX descriptor flags (bit0 enable,
//                                 bit1 armed, bit2 triggered, bit3 done, bit4 periodic)
//   'Z'                         : abort - disarm a pending capture and return
//                                 to idle (also accepted while waiting for
//                                 the trigger; replies 'Z')
//   'R' mode                    : raw capture mode (top level: 1 = store every
//                                 received word as {align, err, dout[9:0]}, no
//                                 record filtering); replies 'R'
//   'J' mode len sym0_lo sym0_hi ...: load len raw 10-bit symbols (LSB first, bit 0
//                                 = first on the wire) into the self-test symbol
//                                 injector and start it: mode 0 stop, 1 once,
//                                 2 loop (see trace_sym_inject.v); replies 'J'
//   'L'                         : link diagnostics: o_diag_req strobe, then the 14
//                                 bytes of i_diag_data (see trace_link_diag.v)
//   'P'                         : one-clock o_pulse_req strobe (reset burst for
//                                 the pulse-only reverse channel); replies 'P'.
//                                 Also accepted while waiting for the trigger
//                                 (reset the TX inside the capture window)
// FPGA -> host: 'K' when the capture has frozen.
module trace_capture #(
    parameter ADDR_BITS    = 14,
    parameter DATA_BITS    = 9,
    parameter MAX_WIDTH    = 64,     // trigger compare width (>= any TX WIDTH)
    parameter DEFAULT_WIDTH = 16     // assumed until a descriptor is seen
) (
    input  wire                 pclk,
    input  wire                 prst,
    input  wire                 in_valid,   // entry strobe (buffer content)
    input  wire [DATA_BITS-1:0] in_data,
    input  wire                 rec_valid,  // decoded record (trigger source)
    input  wire [MAX_WIDTH-1:0] rec_data,
    // link descriptor (pclk domain, quasi-static)
    input  wire [7:0]           i_desc_ver,
    input  wire [7:0]           i_desc_width,
    input  wire [7:0]           i_desc_tsbits,
    input  wire [7:0]           i_desc_flags,
    input  wire [31:0]          i_desc_hash,

    input  wire                 clk_sys,
    input  wire                 rst_sys,
    // host byte stream (transport-agnostic)
    input  wire                 h_rx_valid,   // byte from host
    input  wire [7:0]           h_rx_data,
    output wire                 h_tx_valid,   // byte to host
    output wire [7:0]           h_tx_data,
    input  wire                 h_tx_ready,
    // reverse control channel ('X' payload, clk_sys domain)
    output reg                  o_fwd_valid,
    output reg  [7:0]           o_fwd_data,
    output reg                  o_pulse_req,
    // link diagnostics (trace_link_diag, clk_sys domain)
    output reg                  o_diag_req,
    input  wire                 i_diag_done,
    input  wire [111:0]         i_diag_data,
    // raw capture mode + symbol injector (clk_sys domain)
    output reg                  o_raw_mode,
    output reg                  o_inj_wr_valid,
    output reg  [5:0]           o_inj_wr_idx,
    output reg  [9:0]           o_inj_wr_data,
    output reg                  o_inj_set,
    output reg  [1:0]           o_inj_mode,
    output reg  [6:0]           o_inj_len
);
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
    reg [MAX_WIDTH-1:0] trig_mask, trig_value;
    reg [ADDR_BITS:0]   post_count;     // entries to keep after the trigger
    reg                 arm_immediate;  // 1: 'S' (trigger at once)
    reg                 arm_tgl_sys;
    reg                 abort_tgl_sys;

    // arm request: clk_sys -> pclk
    reg [2:0] arm_sync_p;
    always @(posedge pclk or posedge prst)
        if (prst) arm_sync_p <= 3'b000;
        else      arm_sync_p <= {arm_sync_p[1:0], arm_tgl_sys};
    wire arm_req_p = arm_sync_p[2] ^ arm_sync_p[1];
    reg [2:0] abort_sync_p;
    always @(posedge pclk or posedge prst)
        if (prst) abort_sync_p <= 3'b000;
        else      abort_sync_p <= {abort_sync_p[1:0], abort_tgl_sys};
    wire abort_req_p = abort_sync_p[2] ^ abort_sync_p[1];

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
            if (abort_req_p) cstate <= CS_IDLE;
            else case (cstate)
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

    // descriptor bytes: quasi-static, double-registered into clk_sys
    reg [63:0] desc_m, desc_s;
    always @(posedge clk_sys) begin
        desc_m <= {i_desc_hash, i_desc_flags, i_desc_tsbits, i_desc_width, i_desc_ver};
        desc_s <= desc_m;
    end
    // trigger argument byte count = WIDTH/8 from the descriptor (clamped)
    wire [7:0] db_raw = (desc_s[7:0] == 8'd0) ? DEFAULT_WIDTH / 8 : {3'b0, desc_s[15:11]};
    wire [7:0] db     = (db_raw > MAX_WIDTH / 8) ? MAX_WIDTH / 8 : db_raw;

    //------------------------------------------------------------------
    // command parser / dump FSM (clk_sys)
    //------------------------------------------------------------------
    localparam ST_IDLE   = 3'd0;
    localparam ST_ARGS   = 3'd1;   // collecting command arguments
    localparam ST_WAIT   = 3'd2;   // capture in progress
    localparam ST_DUMP   = 3'd3;
    localparam ST_INFO   = 3'd4;   // '?' reply
    localparam ST_FWD    = 3'd5;   // 'X' payload forwarding
    localparam ST_DIAGW  = 3'd6;   // 'L': waiting for the snapshot
    localparam ST_DIAG   = 3'd7;   // 'L': sending 14 bytes

    reg [2:0]           state;
    reg [7:0]           cmd;
    reg [7:0]           arg_idx;
    reg [ADDR_BITS-1:0] raddr;
    reg [ADDR_BITS:0]   dump_left;
    reg [DATA_BITS-1:0] rdata;
    reg                 rd_pending;
    reg                 dump_lo;
    reg [7:0]           fwd_left;
    reg [111:0]         diag_q;
    reg [7:0]           inj_lo;
    reg [7:0]           inj_n;

    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            state         <= ST_IDLE;
            cmd           <= 8'h00;
            arg_idx       <= 8'd0;
            trig_mask     <= {MAX_WIDTH{1'b0}};
            trig_value    <= {MAX_WIDTH{1'b0}};
            post_count    <= 0;
            arm_immediate <= 1'b0;
            arm_tgl_sys   <= 1'b0;
            abort_tgl_sys <= 1'b0;
            tx_valid      <= 1'b0;
            tx_data       <= 8'h00;
            raddr         <= {ADDR_BITS{1'b0}};
            dump_left     <= 0;
            rdata         <= {DATA_BITS{1'b0}};
            rd_pending    <= 1'b0;
            dump_lo       <= 1'b0;
            o_fwd_valid   <= 1'b0;
            o_fwd_data    <= 8'h00;
            o_pulse_req   <= 1'b0;
            o_diag_req    <= 1'b0;
            diag_q        <= 112'd0;
            o_raw_mode    <= 1'b0;
            o_inj_wr_valid <= 1'b0;
            o_inj_wr_idx  <= 6'd0;
            o_inj_wr_data <= 10'd0;
            o_inj_set     <= 1'b0;
            o_inj_mode    <= 2'd0;
            o_inj_len     <= 7'd0;
            inj_lo        <= 8'd0;
            inj_n         <= 8'd0;
            fwd_left      <= 8'd0;
        end else begin
            o_fwd_valid <= 1'b0;
            o_pulse_req <= 1'b0;
            o_diag_req  <= 1'b0;
            o_inj_wr_valid <= 1'b0;
            o_inj_set   <= 1'b0;
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
                "T", "A", "R", "J": state <= ST_ARGS;
                "?": begin
                    arg_idx <= 8'd0;
                    state   <= ST_INFO;
                end
                "X": begin
                    fwd_left <= 8'd0;
                    state    <= ST_FWD;
                end
                "Z": begin
                    abort_tgl_sys <= ~abort_tgl_sys;
                    tx_data       <= "Z";
                    tx_valid      <= 1'b1;
                end
                "F": begin
                    tx_data  <= desc_s[31:24];
                    tx_valid <= 1'b1;
                end
                "P": begin
                    o_pulse_req <= 1'b1;
                    tx_data     <= "P";
                    tx_valid    <= 1'b1;
                end
                "L": begin
                    o_diag_req <= 1'b1;
                    state      <= ST_DIAGW;
                end
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
                case (cmd)
                "T": begin
                    if (arg_idx < db) trig_mask [arg_idx*8 +: 8]      <= rx_data;
                    else              trig_value[(arg_idx-db)*8 +: 8] <= rx_data;
                    if (arg_idx == 2*db-1) state <= ST_IDLE;
                end
                "A": begin // post count, big-endian 16 bit
                    if (arg_idx == 0) post_count[ADDR_BITS:8] <= rx_data[ADDR_BITS-8:0];
                    else begin
                        post_count[7:0] <= rx_data;
                        arm_immediate   <= 1'b0;
                        arm_tgl_sys     <= ~arm_tgl_sys;
                        state           <= ST_WAIT;
                    end
                end
                "R": begin
                    o_raw_mode <= rx_data[0];
                    tx_data <= "R"; tx_valid <= 1'b1;
                    state <= ST_IDLE;
                end
                "J": begin
                    if (arg_idx == 8'd0) begin
                        o_inj_mode <= rx_data[1:0];
                    end else if (arg_idx == 8'd1) begin
                        o_inj_len <= rx_data[6:0];
                        inj_n     <= rx_data;
                        if (rx_data == 8'd0) begin
                            o_inj_set <= 1'b1;
                            tx_data <= "J"; tx_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end else if (!arg_idx[0]) begin        // even: low byte
                        inj_lo <= rx_data;
                    end else begin                          // odd: high byte -> write
                        o_inj_wr_valid <= 1'b1;
                        o_inj_wr_idx   <= (arg_idx - 8'd3) >> 1;
                        o_inj_wr_data  <= {rx_data[1:0], inj_lo};
                        if (((arg_idx - 8'd3) >> 1) == inj_n - 1'b1) begin
                            o_inj_set <= 1'b1;
                            tx_data <= "J"; tx_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end
                end
                default: state <= ST_IDLE;
                endcase
            end
            ST_INFO: if (!tx_valid || tx_ready) begin
                case (arg_idx[2:0])
                3'd0: tx_data <= desc_s[7:0];    // VER
                3'd1: tx_data <= desc_s[15:8];   // WIDTH
                3'd2: tx_data <= desc_s[23:16];  // TS_BITS
                3'd3: tx_data <= ADDR_BITS[7:0];
                3'd4: tx_data <= desc_s[39:32];  // HASH LSB
                3'd5: tx_data <= desc_s[47:40];
                3'd6: tx_data <= desc_s[55:48];
                default: tx_data <= desc_s[63:56];
                endcase
                tx_valid <= 1'b1;
                arg_idx  <= arg_idx + 1'b1;
                if (arg_idx[2:0] == 3'd7) state <= ST_IDLE;
            end
            ST_FWD: if (rx_valid) begin
                if (fwd_left == 8'd0) begin
                    fwd_left <= rx_data;             // first byte = length
                    if (rx_data == 8'd0) state <= ST_IDLE;
                end else begin
                    o_fwd_valid <= 1'b1;
                    o_fwd_data  <= rx_data;
                    fwd_left    <= fwd_left - 1'b1;
                    if (fwd_left == 8'd1) state <= ST_IDLE;
                end
            end
            ST_WAIT: if (full_evt_s) begin
                tx_data  <= "K";
                tx_valid <= 1'b1;
                state    <= ST_IDLE;
            end else if (rx_valid && rx_data == "Z") begin
                abort_tgl_sys <= ~abort_tgl_sys;
                tx_data       <= "Z";
                tx_valid      <= 1'b1;
                state         <= ST_IDLE;
            end else if (rx_valid && rx_data == "P") begin
                o_pulse_req <= 1'b1;
                tx_data     <= "P";
                tx_valid    <= 1'b1;
            end
            ST_DUMP: if (!tx_valid && tx_ready && !rd_pending) begin
                if (!dump_lo) begin
                    tx_data  <= rdata[DATA_BITS-1:8];      // bit 0 = K flag; raw mode adds dout[9], err, align
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
            ST_DIAGW: if (i_diag_done) begin
                diag_q  <= i_diag_data;
                arg_idx <= 8'd0;
                state   <= ST_DIAG;
            end
            ST_DIAG: if (!tx_valid || tx_ready) begin
                tx_data  <= diag_q[7:0];
                tx_valid <= 1'b1;
                diag_q   <= {8'd0, diag_q[111:8]};
                arg_idx  <= arg_idx + 1'b1;
                if (arg_idx == 8'd13) state <= ST_IDLE;
            end
            default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
