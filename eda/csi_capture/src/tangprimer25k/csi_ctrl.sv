// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file csi_ctrl.sv
 * @brief Host interface (USB-UART, binary commands) for eda/csi_capture:
 *        sensor register access over I2C, the power-up init sequence,
 *        receiver settings and the csi_stats readouts.
 *
 * Commands (request bytes -> reply bytes), multi-byte values little endian:
 *   'P'                -> 'p' VERSION
 *   'W' ah al d        -> 'w' nack          sensor register write
 *   'R' ah al          -> 'r' d nack        sensor register read
 *   'D' dev            -> 'd'               7-bit I2C address (default 0x10)
 *   'C' ofs inv        -> 'c'               ofs = {lane1, lane0} sample offsets
 *                                           (+8 = at the clock edge), inv[1:0]
 *   'I'                -> 'i' nacks         run the init ROM (imx219_init_rom)
 *   'S'                -> 'S' 25 x u32      counter snapshot (csi_stats)
 *   'A' mode           -> 'a'               arm the raw capture (trigger mode)
 *   'G'                -> 'G' 1024 x 12 B   capture memory, address order
 *   'E' at_fs          -> 'e'               arm the event log
 *   'L' nl nh          -> 'L' n x 8 B       first n log records
 * The init ROM also runs once ~20 ms after configuration (AUTO_INIT).
 */
`default_nettype none
module csi_ctrl #(
    parameter int CLOCK_HZ     = 50_000_000,
    parameter int BAUD_DIVIDER = 434,          // 115200
    parameter bit AUTO_INIT    = 1'b1,
    parameter int BOOT_CYCLES  = CLOCK_HZ / 50,  // auto init after ~20 ms
    parameter int MS_CYCLES    = CLOCK_HZ / 1000,
    parameter logic [7:0] VERSION = 8'h01
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rxd,
    output wire        uart_txd,

    // I2C pads
    output wire        o_scl_oe,
    output wire        o_sda_oe,
    input  wire        i_scl,
    input  wire        i_sda,

    // receiver settings (quasi-static)
    output logic [3:0] o_ofs0,
    output logic [3:0] o_ofs1,
    output logic [1:0] o_inv,
    output logic       o_init_busy,

    // csi_stats
    output logic       o_snap_tgl,
    input  wire        i_snap_ack,
    output logic [4:0] o_snap_idx,
    input  wire [31:0] i_snap_data,
    output logic       o_cap_tgl,
    output logic [2:0] o_cap_mode,
    output logic [9:0] o_cap_raddr,
    input  wire [95:0] i_cap_rdata,
    output logic       o_log_tgl,
    output logic       o_log_at_fs,
    output logic [9:0] o_log_raddr,
    input  wire [63:0] i_log_rdata
);
    // ---------------- UART ----------------
    logic       rx_valid;
    logic [7:0] rx_data;
    logic       rx_ready;
    uart_rx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_rx (
        .clock(clk), .reset(rst), .data_valid(rx_valid), .data_ready(rx_ready),
        .data_bits(rx_data), .rx(uart_rxd), .overrun());
    logic       tx_valid;
    logic [7:0] tx_data;
    logic       tx_ready;
    uart_tx #(.BAUD_DIVIDER(BAUD_DIVIDER)) u_tx (
        .clock(clk), .reset(rst), .data_valid(tx_valid), .data_ready(tx_ready),
        .data_bits(tx_data), .tx(uart_txd));
    wire tx_accept = tx_valid && tx_ready;

    // ---------------- I2C ----------------
    logic        i2c_start, i2c_read, i2c_busy, i2c_done, i2c_nack;
    logic [6:0]  i2c_dev;
    logic [15:0] i2c_addr;
    logic [7:0]  i2c_wdata, i2c_rdata;
    i2c_reg16 #(.CLOCK_HZ(CLOCK_HZ), .SCL_HZ(100_000)) u_i2c (
        .clk(clk), .rst(rst), .i_start(i2c_start), .i_read(i2c_read), .i_dev(i2c_dev),
        .i_addr(i2c_addr), .i_wdata(i2c_wdata), .o_busy(i2c_busy), .o_done(i2c_done),
        .o_rdata(i2c_rdata), .o_nack(i2c_nack), .o_scl_oe(o_scl_oe), .o_sda_oe(o_sda_oe),
        .i_sda(i_sda), .i_scl(i_scl));

    logic [6:0]  rom_idx;
    logic [23:0] rom_entry;
    imx219_init_rom u_rom (.i_idx(rom_idx), .o_entry(rom_entry));

    // ---------------- command FSM ----------------
    typedef enum logic [3:0] {
        S_BOOT, S_IDLE, S_ARGS, S_EXEC, S_I2C, S_INIT, S_INIT_WAIT, S_DELAY, S_SNAP,
        S_HDR, S_FETCH, S_BYTES
    } state_t;
    state_t      st;
    logic [7:0]  cmd;
    logic [7:0]  arg [0:2];
    logic [1:0]  argn, argc;
    logic [7:0]  hdr [0:2];
    logic [1:0]  hdr_len, hi;
    logic [1:0]  src;        // 0 none, 1 stats, 2 capture, 3 log
    logic [10:0] nwords, wi;
    logic [3:0]  wbytes, bi;
    logic [95:0] word;
    logic [1:0]  wait_c;
    logic [7:0]  nacks;
    logic        init_reply;
    logic [25:0] dly;        // ms delay / boot timer
    logic [7:0]  dly_ms;
    logic        snap_wait_ack;

    // arguments per command
    function automatic logic [1:0] nargs(input logic [7:0] c);
        case (c)
            "W": return 2'd3;
            "R": return 2'd2;
            "D", "A", "E": return 2'd1;
            "C", "L": return 2'd2;
            default: return 2'd0;
        endcase
    endfunction

    assign rx_ready = (st == S_IDLE) || (st == S_ARGS);
    assign o_cap_raddr = wi[9:0];
    assign o_log_raddr = wi[9:0];
    assign o_snap_idx  = wi[4:0];
    assign o_init_busy = (st == S_INIT) || (st == S_INIT_WAIT) || (st == S_DELAY) || (st == S_BOOT);

    always_ff @(posedge clk) begin
        i2c_start <= 1'b0;
        if (tx_accept) tx_valid <= 1'b0;
        if (rst) begin
            st          <= AUTO_INIT ? S_BOOT : S_IDLE;
            tx_valid    <= 1'b0;
            i2c_dev     <= 7'h10;
            o_ofs0      <= 4'd8;
            o_ofs1      <= 4'd8;
            o_inv       <= 2'b00;
            o_snap_tgl  <= 1'b0;
            o_cap_tgl   <= 1'b0;
            o_cap_mode  <= 3'd0;
            o_log_tgl   <= 1'b0;
            o_log_at_fs <= 1'b0;
            dly         <= '0;
            init_reply  <= 1'b0;
            nacks       <= '0;
            rom_idx     <= '0;
        end else begin
            case (st)
                S_BOOT: begin            // ~20 ms after configuration: sensor init
                    dly <= dly + 1'b1;
                    if (dly == BOOT_CYCLES) begin
                        rom_idx    <= '0;
                        nacks      <= '0;
                        init_reply <= 1'b0;
                        st         <= S_INIT;
                    end
                end
                S_IDLE: if (rx_valid) begin
                    cmd  <= rx_data;
                    argn <= '0;
                    argc <= nargs(rx_data);
                    st   <= (nargs(rx_data) == 2'd0) ? S_EXEC : S_ARGS;
                end
                S_ARGS: if (rx_valid) begin
                    arg[argn] <= rx_data;
                    argn      <= argn + 1'b1;
                    if (argn + 1'b1 == argc) st <= S_EXEC;
                end
                S_EXEC: begin
                    // default reply: lower-case echo, no payload
                    hdr[0]  <= cmd | 8'h20;
                    hdr_len <= 2'd1;
                    hi      <= '0;
                    src     <= 2'd0;
                    nwords  <= '0;
                    st      <= S_HDR;
                    case (cmd)
                        "P": begin hdr[1] <= VERSION; hdr_len <= 2'd2; end
                        "W", "R": begin
                            i2c_read  <= cmd == "R";
                            i2c_addr  <= {arg[0], arg[1]};
                            i2c_wdata <= arg[2];
                            i2c_start <= 1'b1;
                            st        <= S_I2C;
                        end
                        "D": i2c_dev <= arg[0][6:0];
                        "C": begin o_ofs0 <= arg[0][3:0]; o_ofs1 <= arg[0][7:4]; o_inv <= arg[1][1:0]; end
                        "I": begin rom_idx <= '0; nacks <= '0; init_reply <= 1'b1; st <= S_INIT; end
                        "S": begin o_snap_tgl <= ~o_snap_tgl; st <= S_SNAP; end
                        "A": begin o_cap_mode <= arg[0][2:0]; o_cap_tgl <= ~o_cap_tgl; end
                        "G": begin hdr[0] <= "G"; src <= 2'd2; nwords <= 11'd1024; wbytes <= 4'd12; end
                        "E": begin o_log_at_fs <= arg[0][0]; o_log_tgl <= ~o_log_tgl; end
                        "L": begin
                            hdr[0] <= "L"; src <= 2'd3; wbytes <= 4'd8;
                            nwords <= ({arg[1][2:0], arg[0]} > 11'd1024) ? 11'd1024 : {arg[1][2:0], arg[0]};
                        end
                        default: hdr[0] <= "?";
                    endcase
                end
                S_I2C: if (i2c_done) begin
                    if (i2c_read) begin hdr[1] <= i2c_rdata; hdr[2] <= {7'd0, i2c_nack}; hdr_len <= 2'd3; end
                    else          begin hdr[1] <= {7'd0, i2c_nack}; hdr_len <= 2'd2; end
                    st <= S_HDR;
                end
                S_INIT: begin
                    if (rom_entry[23:8] == 16'hFFFE) begin
                        hdr[0]  <= "i";
                        hdr[1]  <= nacks;
                        hdr_len <= 2'd2;
                        hi      <= '0;
                        src     <= 2'd0;
                        nwords  <= '0;
                        st      <= init_reply ? S_HDR : S_IDLE;
                    end else if (rom_entry[23:8] == 16'hFFFF) begin
                        dly    <= '0;
                        dly_ms <= rom_entry[7:0];
                        st     <= S_DELAY;
                    end else begin
                        i2c_read  <= 1'b0;
                        i2c_addr  <= rom_entry[23:8];
                        i2c_wdata <= rom_entry[7:0];
                        i2c_start <= 1'b1;
                        st        <= S_INIT_WAIT;
                    end
                end
                S_INIT_WAIT: if (i2c_done) begin
                    if (i2c_nack && nacks != 8'hFF) nacks <= nacks + 1'b1;
                    rom_idx <= rom_idx + 1'b1;
                    st      <= S_INIT;
                end
                S_DELAY: begin
                    dly <= dly + 1'b1;
                    if (dly == MS_CYCLES) begin
                        dly <= '0;
                        if (dly_ms <= 8'd1) begin rom_idx <= rom_idx + 1'b1; st <= S_INIT; end
                        else dly_ms <= dly_ms - 1'b1;
                    end
                end
                S_SNAP: if (i_snap_ack == o_snap_tgl) begin
                    hdr[0] <= "S"; src <= 2'd1; nwords <= 11'd25; wbytes <= 4'd4;
                    st     <= S_HDR;
                end
                S_HDR: if (!tx_valid && tx_ready) begin
                    tx_data  <= hdr[hi];
                    tx_valid <= 1'b1;
                    hi       <= hi + 1'b1;
                    if (hi + 1'b1 == hdr_len) begin
                        wi <= '0;
                        st <= (nwords == '0) ? S_IDLE : S_FETCH;
                        wait_c <= '0;
                    end
                end
                S_FETCH: begin
                    wait_c <= wait_c + 1'b1;
                    if (wait_c == 2'd3) begin
                        case (src)
                            2'd1:    word <= {64'd0, i_snap_data};
                            2'd2:    word <= i_cap_rdata;
                            default: word <= {32'd0, i_log_rdata};
                        endcase
                        bi <= '0;
                        st <= S_BYTES;
                    end
                end
                S_BYTES: if (!tx_valid && tx_ready) begin
                    tx_data  <= word[7:0];
                    tx_valid <= 1'b1;
                    word     <= {8'd0, word[95:8]};
                    bi       <= bi + 1'b1;
                    if (bi + 1'b1 == wbytes) begin
                        wi     <= wi + 1'b1;
                        wait_c <= '0;
                        st     <= (wi + 1'b1 == nwords) ? S_IDLE : S_FETCH;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
