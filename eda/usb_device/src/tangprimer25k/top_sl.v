// USB 2.0 device on Tang Primer 25K + Pmod USB HS Single (eda/pmod_usb_hs/hw/Pmod_USB_HS_Single):
// Gowin USB 2.0 SoftPHY "Single LVDS" wiring with the D+ comparator only (7 pins + VBUS_DET, one Pmod).
//
//   50MHz -> pll_usb 60 MHz -> pll_hs960 (VCO 960) -> 960 MHz FCLK (IDES16 / OSER16, CLKDIV /8 = pclk 120 MHz)
//                                                  + 480 MHz (CLKDIV /8 = clk60, in the PHY)
//   UsbDevice (rtl/usb, 60 MHz) --UTMI--> usb_phy_gowin_sl #(.CMP1(1)) --> Pmod (USB_PMOD, project.tcl USB_SL=1)
//
// Pmod: 1/7 DX_P/DX_N (LVCMOS33D bidirectional), 2/8 D+/VREF (LVDS25 input), 3/9 TERM_DP/TERM_DN,
//       4 PULLUP, 10 VBUS_DET
//
// Debug: every 140 ms a 10-byte status frame on the UART (115200), host/usb_status.py:
//   'U' flags addr frame_l frame_h rst_cnt err_cnt sof_cnt_l sof_cnt_h pkt_cnt[11:4]
//   (err_cnt and pkt_cnt wrap around: rxerror pulses / received packets, take differences)
//   flags: bit1:0 linestate, bit2 high_speed, bit3 configured, bit4 suspended,
//          bit5 vbus, bit6 pll lock, bit7 rxactive seen since the last frame
// 'R' from the host holds the USB core in reset for ~70 ms (pull-up off -> re-enumeration).
module top (
    input  wire clk_in,        // 50MHz
    input  wire reset_in,      // push button, active high
    output wire uart_txd,
    input  wire uart_rxd,

    inout  wire usb_dp,        // DX_P   (pin 1; the IOBUF's P side, constrained to both balls)
    inout  wire usb_dn,        // DX_N   (pin 7)
    input  wire usb_cmp_dp,    // D+     (pin 2)
    input  wire usb_cmp_dp_n,  // VREF   (pin 8)
    inout  wire usb_term_dp,   // TERM_DP (pin 3)
    inout  wire usb_term_dn,   // TERM_DN (pin 9)
    output wire usb_pullup,    // PULLUP (pin 4)
    input  wire vbus_det,      // VBUS_DET (pin 10)

    output wire led_configured,
    output wire led_high_speed
);
    //------------------------------------------------------------------
    // clocks / reset
    //------------------------------------------------------------------
    wire pll_lock, os_lock, rst60;
    wire pll_60m /* synthesis syn_keep=1 */;
    wire os_f960 /* synthesis syn_keep=1 */, os_f480 /* synthesis syn_keep=1 */;
    wire clk60 /* synthesis syn_keep=1 */;      // (syn_keep: the net names are referenced by the SDC)
    wire os_pclk /* synthesis syn_keep=1 */;
    pll_usb u_pll(.lock(pll_lock), .clkout0(), .clkout1(pll_60m), .clkout2(), .clkout3(),
                  .clkin(clk_in), .psdir(1'b0), .pspulse(1'b0));
    pll_hs960 u_pll_os(.lock(os_lock), .clkout0(os_f960), .clkout1(os_f480), .clkin(pll_60m));
    reg [3:0] rst_sr;
    always @(posedge clk60 or posedge reset_in)
        if (reset_in) rst_sr <= 4'hf; else rst_sr <= {rst_sr[2:0], ~pll_lock | ~os_lock | rst60};
    wire rst = rst_sr[3];
    reg [21:0] soft_cnt; reg soft_rst;
    wire h_rx_valid; wire [7:0] h_rx_data;
    always @(posedge clk60 or posedge rst)
        if (rst) begin soft_cnt <= 22'd0; soft_rst <= 1'b0; end
        else if (h_rx_valid && h_rx_data == "R") begin soft_rst <= 1'b1; soft_cnt <= 22'd0; end
        else if (soft_rst) begin soft_cnt <= soft_cnt + 1'b1; if (&soft_cnt) soft_rst <= 1'b0; end
    wire usb_rst = rst | soft_rst;

    //------------------------------------------------------------------
    // USB device core + PHY
    //------------------------------------------------------------------
    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       high_speed, configured, suspended, bus_reset, sof;
    wire [6:0] address;
    wire [10:0] frame;
    wire [15:0] vendor_reg;
    reg  [15:0] sof_cnt;
    reg  [7:0]  rst_cnt, err_cnt;
    reg  [1:0]  vbus_sr;
    always @(posedge clk60) vbus_sr <= {vbus_sr[0], vbus_det};
    wire vbus_s = vbus_sr[1];

`ifdef USB_FS_ONLY
    localparam HS_CAPABLE = 1'b0;   // make USB_FS_ONLY=1
`else
    localparam HS_CAPABLE = 1'b1;
`endif
    UsbDevice #(.HS_CAPABLE(HS_CAPABLE), .CLK_PER_US(60), .BULK_IN_FULL_ONLY(`BULK_IN_FULL_ONLY)) u_dev(
        .i_clk(clk60), .i_rst(usb_rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(bus_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg),
        .i_vendor_status({8'h25, 3'b0, vbus_s, 3'b0, high_speed, sof_cnt}));

    wire [1:0] mon_line;      // term pin inputs {D-, D+}, one sample per clk60
    wire [15:0] os_samples; wire [31:0] os_cmp; wire [95:0] hist; reg hist_run;
    wire       phy_tx_oe, phy_pullup;
    usb_phy_gowin_sl #(.CMP1(1)) u_phy(
        .clk_ref_i(clk_in), .rstn_ref_i(~reset_in), .pll_lock_i(os_lock & pll_lock),
        .fclk_i(os_f960), .fclk480_i(os_f480), .pclk_o(os_pclk), .clk60_o(clk60), .rst60_o(rst60), .rst_i(usb_rst),
        .i_scan_freeze(1'b0), .i_scan_ofs(1'b0), .i_scan_class(2'd0), .i_hist_run(hist_run), .o_hist(hist),
        .o_samples(os_samples), .o_cmp_dbg(os_cmp), .o_tx_oe(phy_tx_oe), .o_mon_line(mon_line),
        .utmi_data_out_i(utmi_data_out), .utmi_txvalid_i(utmi_txvalid), .utmi_txready_o(utmi_txready),
        .utmi_data_in_o(utmi_data_in), .utmi_rxactive_o(utmi_rxactive), .utmi_rxvalid_o(utmi_rxvalid),
        .utmi_rxerror_o(utmi_rxerror), .utmi_linestate_o(utmi_linestate),
        .utmi_opmode_i(utmi_opmode), .utmi_xcvrselect_i(utmi_xcvrselect), .utmi_termselect_i(utmi_termselect),
        .usb_dxp_io(usb_dp), .usb_dxn_io(usb_dn),
        .usb_rxdp_p_i(usb_cmp_dp), .usb_rxdp_n_i(usb_cmp_dp_n),
        .usb_rxdn_p_i(1'b0), .usb_rxdn_n_i(1'b1),
        .usb_pullup_en_o(phy_pullup), .usb_term_dp_o(usb_term_dp), .usb_term_dn_o(usb_term_dn),
        .usb_term_dp_i(usb_term_dp), .usb_term_dn_i(usb_term_dn));
    assign usb_pullup = phy_pullup & ~usb_rst;   // 'R': pull-up off -> the host sees a disconnect
    assign led_configured = configured;
    assign led_high_speed = high_speed;

    //------------------------------------------------------------------
    // counters + UART status frame
    //------------------------------------------------------------------
    reg rxactive_seen;
    reg [11:0] pkt_cnt;
    reg rxact_q; always @(posedge clk60) rxact_q <= utmi_rxactive;
    reg [22:0] tick;           // 2^23 / 60MHz = 140ms
    reg        frame_go;
    always @(posedge clk60 or posedge rst)
        if (rst) begin tick <= 23'd0; frame_go <= 1'b0; end
        else begin tick <= tick + 1'b1; frame_go <= (tick == 23'd0); end
    always @(posedge clk60 or posedge rst) begin
        if (rst) begin
            sof_cnt <= 16'd0; rst_cnt <= 8'd0; err_cnt <= 8'd0; rxactive_seen <= 1'b0; pkt_cnt <= 12'd0;
        end else if (soft_rst) begin
            sof_cnt <= 16'd0; rst_cnt <= 8'd0; err_cnt <= 8'd0; rxactive_seen <= 1'b0;
        end else begin
            if (sof) sof_cnt <= sof_cnt + 1'b1;
            if (bus_reset) rst_cnt <= rst_cnt + 1'b1;
            if (utmi_rxerror) err_cnt <= err_cnt + 1'b1;
            if (rxact_q && !utmi_rxactive) pkt_cnt <= pkt_cnt + 1'b1;
            if (utmi_rxactive) rxactive_seen <= 1'b1;
            if (frame_go) rxactive_seen <= 1'b0;
        end
    end
    wire [79:0] status = {pkt_cnt[11:4], sof_cnt[15:8], sof_cnt[7:0], err_cnt, rst_cnt,
                          {5'b0, frame[10:8]}, frame[7:0], address[6:0], 1'b0,
                          rxactive_seen, pll_lock & os_lock, vbus_s, suspended, configured, high_speed, utmi_linestate,
                          8'h55};
    reg [79:0] shift; reg [3:0] left; reg tx_valid; wire tx_ready;
    always @(posedge clk60 or posedge rst) begin
        if (rst) begin shift <= 80'd0; left <= 4'd0; tx_valid <= 1'b0; end
        else if (frame_go && left == 4'd0) begin shift <= status; left <= 4'd10; tx_valid <= 1'b1; end
        else if (tx_valid && tx_ready) begin
            shift <= {8'd0, shift[79:8]}; left <= left - 1'b1;
            if (left == 4'd1) tx_valid <= 1'b0;
        end
    end
    uart_rx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(60_000_000 / 115200)) u_uart_rx(
        .clock(clk60), .reset(rst), .data_valid(h_rx_valid), .data_ready(1'b1), .data_bits(h_rx_data), .rx(uart_rxd), .overrun());

    //------------------------------------------------------------------
    // 'H': transition histogram over 2^22 clk60 (70 ms) -> 'h' + 4 x 24-bit counts (sample class 0..3, LSB first)
    //------------------------------------------------------------------
    reg [21:0] h_left; reg [103:0] h_shift; reg [3:0] h_n, h_wait; reg h_valid; wire h_ready;
    always @(posedge clk60 or posedge rst) begin
        if (rst) begin hist_run <= 1'b0; h_left <= 22'd0; h_shift <= 104'd0; h_n <= 4'd0; h_wait <= 4'd0; h_valid <= 1'b0; end
        else if (hist_run) begin
            h_left <= h_left - 1'b1;
            if (h_left == 22'd0) begin hist_run <= 1'b0; h_wait <= 4'd15; end   // a few clocks for the pclk side to settle
        end else if (h_wait != 4'd0) begin
            h_wait <= h_wait - 1'b1;
            if (h_wait == 4'd1) begin h_shift <= {hist, 8'h68}; h_n <= 4'd13; h_valid <= 1'b1; end
        end else if (h_valid) begin
            if (h_ready) begin
                h_shift <= {8'd0, h_shift[103:8]}; h_n <= h_n - 1'b1;
                if (h_n == 4'd1) h_valid <= 1'b0;
            end
        end else if (h_rx_valid && h_rx_data == "H") begin hist_run <= 1'b1; h_left <= 22'h3fffff; end
    end

    //------------------------------------------------------------------
    // pclk (120 MHz) capture: 'C' arms (trigger: squelch opens), 'E' arms (trigger: rxerror), 'S' forces the
    // trigger; 1024 words before, 3071 after. 'D' dumps 4096 x 6 bytes, oldest first:
    //   [15:0] dx IDES16 samples (bit 0 earliest), [31:16] D+ comparator samples,
    //   [47:32] {rxerror, rxactive, ph, w_oe, sq, act, gb_valid, cdr_lock, reacq, 3'b0, nbits[3:0]}
    //------------------------------------------------------------------
    wire [47:0] cw = {utmi_rxerror, utmi_rxactive, u_phy.ph, u_phy.w_oe, u_phy.sq, u_phy.act, u_phy.gb_valid, u_phy.cdr_lock,
                      u_phy.reacq, 3'b0, u_phy.nbits, os_cmp[31:16], os_samples};
    reg  [47:0] capmem [0:4095] /* synthesis syn_ramstyle = "block_ram" */;
    reg  [11:0] c_wp; reg [11:0] c_left; reg [1:0] c_st;   // pclk side: 0 idle, 1 pre, 2 armed, 3 post
    reg  [2:0] arm_s, force_s; reg c_mode;
    reg  arm_t, force_t, mode_t;  // clk60 toggles / level
    always @(posedge clk60 or posedge rst)
        if (rst) begin arm_t <= 1'b0; force_t <= 1'b0; mode_t <= 1'b0; end
        else if (h_rx_valid) begin
            if (h_rx_data == "C" || h_rx_data == "E") begin arm_t <= ~arm_t; mode_t <= h_rx_data == "E"; end
            if (h_rx_data == "S") force_t <= ~force_t;
        end
    always @(posedge os_pclk) begin
        arm_s <= {arm_s[1:0], arm_t}; force_s <= {force_s[1:0], force_t};
        case (c_st)
        2'd0: if (arm_s[2] != arm_s[1]) begin c_st <= 2'd1; c_left <= 12'd1024; c_mode <= mode_t; end
        2'd1: begin c_left <= c_left - 1'b1; if (c_left == 12'd1) c_st <= 2'd2; end
        2'd2: if ((c_mode ? utmi_rxerror : ~u_phy.sq) || force_s[2] != force_s[1]) begin c_st <= 2'd3; c_left <= 12'd3070; end
        2'd3: begin c_left <= c_left - 1'b1; if (c_left == 12'd0) c_st <= 2'd0; end
        endcase
        if (c_st != 2'd0) begin capmem[c_wp] <= cw; c_wp <= c_wp + 1'b1; end
    end
    // dump (clk60; the pclk side is idle by then)
    reg  [47:0] c_rd; reg [11:0] c_rp; reg [12:0] d_left; reg [2:0] d_byte; reg d_valid, d_pend, dumping; wire d_ready;
    always @(posedge clk60) c_rd <= capmem[c_rp];
    always @(posedge clk60 or posedge rst) begin
        if (rst) begin c_rp <= 12'd0; d_left <= 13'd0; d_byte <= 3'd0; d_valid <= 1'b0; d_pend <= 1'b0; dumping <= 1'b0; end
        else begin
            d_pend <= 1'b0;
            if (!dumping) begin
                if (h_rx_valid && h_rx_data == "D") begin dumping <= 1'b1; c_rp <= c_wp; d_left <= 13'd4095; d_byte <= 3'd0; d_pend <= 1'b1; end
            end else if (!d_valid && !d_pend) d_valid <= 1'b1;
            else if (d_valid && d_ready) begin
                d_valid <= 1'b0;
                if (d_byte == 3'd5) begin
                    d_byte <= 3'd0; c_rp <= c_rp + 1'b1; d_pend <= 1'b1;
                    if (d_left == 13'd0) dumping <= 1'b0; else d_left <= d_left - 1'b1;
                end else d_byte <= d_byte + 1'b1;
            end
        end
    end
    wire [7:0] d_data = c_rd[d_byte*8 +: 8];

    // UART TX mux: dump > histogram reply > status frames
    wire       mux_valid = dumping ? d_valid : h_valid ? h_valid : tx_valid;
    wire [7:0] mux_data  = dumping ? d_data  : h_valid ? h_shift[7:0] : shift[7:0];
    wire       mux_ready;
    assign d_ready  = dumping & mux_ready;
    assign h_ready  = ~dumping & mux_ready;
    assign tx_ready = ~dumping & ~h_valid & mux_ready;
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(60_000_000 / 115200)) u_uart_tx(
        .clock(clk60), .reset(rst), .data_valid(mux_valid), .data_ready(mux_ready), .data_bits(mux_data), .tx(uart_txd));
endmodule
