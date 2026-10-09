// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Tang Console 60K: USB 3.2 Gen1 device sample (SerDes Q0 Lane2 = USB3-A port 1).
//
// Build stages (project.tcl defines):
//   M1 : board bring-up only - UART status line and USR_CLK_IN frequency counter.
//   (default): full device (SerDes PHY IP + Usb3Top + Usb3Device).
`default_nettype none
module top (
    input  wire sys_clk,       // 50 MHz
    output wire uart_tx,
    input  wire uart_rx,
    input  wire usr_clk_in     // MS5351 CLK2
`ifndef M1
    ,
    input  wire usb3_ref_clk_p,   // SerDes REFCLK1 (dedicated pads, listed for the SDC)
    input  wire usb3_ref_clk_n
`endif
);
    // ---------------------------------------------------------------- reset
    reg [7:0] rst_cnt = 0;
    wire rst = rst_cnt != 8'hFF;
    always @(posedge sys_clk) if (rst) rst_cnt <= rst_cnt + 1;

    // MS5351: programmed by the BL616 (its console: Ctrl+X Ctrl+C, `pll_clk`), not from the
    // FPGA - the BL616 holds the I2C bus. Defaults: CLK0/CLK1 125 MHz (CLK1 inverted) for
    // SerDes REFCLK1, CLK2 27 MHz on usr_clk_in.
    wire i2c_done = 1'b0, i2c_err = 1'b0;
    wire [7:0] i2c_status = 8'h00;

    // ---------------------------------------------------------------- USR_CLK_IN frequency (edges per second)
    reg [27:0] f_cnt = 0;       // in the usr_clk_in domain
    reg [27:0] f_hold = 0;
    reg        gate_t = 0;      // sys domain 1 s toggle
    reg [25:0] sec_cnt = 0;
    always @(posedge sys_clk) begin
        if (sec_cnt == 26'd49_999_999) begin sec_cnt <= 0; gate_t <= ~gate_t; end
        else sec_cnt <= sec_cnt + 1;
    end
    reg [2:0] gate_s = 0;
    always @(posedge usr_clk_in) begin
        gate_s <= {gate_s[1:0], gate_t};
        if (gate_s[2] != gate_s[1]) begin f_hold <= f_cnt; f_cnt <= 0; end
        else f_cnt <= f_cnt + 1;
    end
    reg [27:0] f_sys = 0;
    reg [2:0] gate_back = 0;
    always @(posedge sys_clk) begin
        gate_back <= {gate_back[1:0], gate_s[2]};
        if (gate_back[2] != gate_back[1]) f_sys <= f_hold;   // settled by then
    end

    // ---------------------------------------------------------------- UART status line once per second
    wire tx_ready;
    reg  tx_valid = 0;
    reg  [7:0] tx_data = 0;
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(434)) u_uart (
        .clock(sys_clk), .reset(rst), .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data), .tx(uart_tx));

    // message: "M1 done=D err=E st=XX f=XXXXXXXX\r\n"
    localparam MSG_LEN = 40;
    reg [5:0] mpos = MSG_LEN;
    reg [63:0] snap;
    function [7:0] hexc(input [3:0] v); hexc = v < 10 ? "0" + v : "A" + v - 10; endfunction
    reg [7:0] mchar;
    always @(*) begin
        case (mpos)
            0: mchar = "M"; 1: mchar = "1"; 2: mchar = " "; 3: mchar = "d"; 4: mchar = "o"; 5: mchar = "n"; 6: mchar = "e"; 7: mchar = "=";
            8: mchar = "0" + snap[0]; 9: mchar = " "; 10: mchar = "e"; 11: mchar = "r"; 12: mchar = "r"; 13: mchar = "=";
            14: mchar = "0" + snap[1]; 15: mchar = " "; 16: mchar = "s"; 17: mchar = "t"; 18: mchar = "=";
            19: mchar = hexc(snap[15:12]); 20: mchar = hexc(snap[11:8]); 21: mchar = " "; 22: mchar = "f"; 23: mchar = "=";
            24: mchar = hexc(snap[47:44]); 25: mchar = hexc(snap[43:40]); 26: mchar = hexc(snap[39:36]); 27: mchar = hexc(snap[35:32]);
            28: mchar = hexc(snap[31:28]); 29: mchar = hexc(snap[27:24]); 30: mchar = hexc(snap[23:20]); 31: mchar = hexc(snap[19:16]);
            32: mchar = " "; 33: mchar = "b"; 34: mchar = "="; 35: mchar = hexc(snap[55:52]); 36: mchar = hexc(snap[51:48]);
            37: mchar = "\r"; 38: mchar = "\n";
            default: mchar = " ";
        endcase
    end
    reg gate_q = 0;
    // bus observation: sticky "seen high" / "seen low" for SDA and SCL inputs (cleared each second)
    reg [7:0] bus_seen = 0;   // {rx_low, rx_high, 0, 0, 0, 0, 0, 0}
    reg [7:0] bus_snap = 0;
    always @(posedge sys_clk) begin
        if (gate_q != gate_t) begin bus_snap <= bus_seen; bus_seen <= 0; end
        else bus_seen <= bus_seen | {~uart_rx, uart_rx, 6'b0};
    end

    always @(posedge sys_clk) begin
        gate_q <= gate_t;
        if (tx_valid && tx_ready) begin
            tx_valid <= 0;
            mpos <= mpos + 1;
        end else if (mpos < 39 && !tx_valid) begin
            tx_data <= mchar;
            tx_valid <= 1;
        end
        if (gate_q != gate_t && mpos >= 39) begin
            snap <= {8'h0, bus_snap, f_sys[27:0] + 32'h0, i2c_status, 6'h0, i2c_err, i2c_done};
            mpos <= 0;
        end
    end
endmodule
`default_nettype wire
