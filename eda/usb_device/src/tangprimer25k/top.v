// USB 2.0 device bring-up on Tang Primer 25K + Pmod USB (TN710 USB2.0-RC circuit).
//
//   50MHz -> pll_usb -> 240MHz FCLK / 60MHz PCLK
//   UsbDevice (rtl/usb, Veryl) --UTMI--> usb_phy_gowin (UsbPhy + IDES8/OSER8) --> Pmod A/B
//
// Pmod A: USB_RX_D+/- (LVDS pair, HS data), D+/VREF and D-/VREF (LVDS pairs
//         used as single-ended comparators), TERM_RXDP / TERM_RXDN (drive low = 45 ohm)
// Pmod B: USB_TX_D+/- (LVCMOS33 pads, series R on the board), PULLUP_EN, VBUS_DET
//
// Debug: every ~100ms a 10-byte status frame on the UART (115200):
//   'U' flags addr frame_l frame_h rst_cnt err_cnt sof_cnt_l sof_cnt_h vendor_reg_l
//   flags: bit1:0 linestate, bit2 high_speed, bit3 configured, bit4 suspended,
//          bit5 vbus, bit6 pll lock, bit7 rxactive seen since the last frame
module top (
    input  wire clk_in,        // 50MHz
    input  wire reset_in,      // push button, active high
    output wire uart_txd,
    input  wire uart_rxd,

    // Pmod A
    input  wire usb_rx_dp,     // USB_RX_D+  (pin 1)
    input  wire usb_rx_dn,     // USB_RX_D-  (pin 7)
    input  wire usb_rxdp_p,    // D+         (pin 2)
    input  wire usb_rxdp_n,    // VREF       (pin 8)
    input  wire usb_rxdn_p,    // D-         (pin 3)
    input  wire usb_rxdn_n,    // VREF       (pin 9)
    output wire usb_term_dp,   // TERM_RXDP  (pin 4)
    output wire usb_term_dn,   // TERM_RXDN  (pin 10)
    // Pmod B
    output wire usb_tx_dp,     // USB_TX_D+  (pin 1)
    output wire usb_tx_dn,     // USB_TX_D-  (pin 7)
    output wire usb_pullup_en, // PULLUP_EN  (pin 2)
    input  wire vbus_det,      // VBUS_DET   (pin 3)

    output wire led_configured,
    output wire led_high_speed
);
    //------------------------------------------------------------------
    // clocks / reset
    //------------------------------------------------------------------
    wire pll_lock, fclk_240m, pclk_60m;
    pll_usb u_pll(.lock(pll_lock), .clkout0(fclk_240m), .clkout1(pclk_60m), .clkout2(), .clkout3(),
                  .clkin(clk_in), .psdir(1'b0), .pspulse(1'b0));
    // synchronous active-high reset in the 60MHz domain, held while the PLL is unlocked
    reg [3:0] rst_sr;
    always @(posedge pclk_60m or posedge reset_in)
        if (reset_in) rst_sr <= 4'hf; else rst_sr <= {rst_sr[2:0], ~pll_lock};
    wire rst = rst_sr[3];

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
    wire        vbus_s;

    UsbDevice #(.HS_CAPABLE(1'b1), .CLK_PER_US(60)) u_dev(
        .i_clk(pclk_60m), .i_rst(rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(bus_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg),
        .i_vendor_status({8'h25, 3'b0, vbus_s, 3'b0, high_speed, sof_cnt}));   // 0x25 = "25K", flags, SOF count

    usb_phy_gowin u_phy(
        .clk_i(pclk_60m), .fclk_i(fclk_240m), .rst_i(rst), .pll_locked_i(pll_lock),
        .utmi_data_out_i(utmi_data_out), .utmi_txvalid_i(utmi_txvalid), .utmi_txready_o(utmi_txready),
        .utmi_data_in_o(utmi_data_in), .utmi_rxactive_o(utmi_rxactive), .utmi_rxvalid_o(utmi_rxvalid),
        .utmi_rxerror_o(utmi_rxerror), .utmi_linestate_o(utmi_linestate),
        .utmi_opmode_i(utmi_opmode), .utmi_xcvrselect_i(utmi_xcvrselect), .utmi_termselect_i(utmi_termselect),
        .usb_rx_dp_i(usb_rx_dp), .usb_rx_dn_i(usb_rx_dn),
        .usb_rxdp_p_i(usb_rxdp_p), .usb_rxdp_n_i(usb_rxdp_n),
        .usb_rxdn_p_i(usb_rxdn_p), .usb_rxdn_n_i(usb_rxdn_n),
        .usb_tx_dp_o(usb_tx_dp), .usb_tx_dn_o(usb_tx_dn),
        .usb_pullup_en_o(usb_pullup_en), .usb_term_dp_o(usb_term_dp), .usb_term_dn_o(usb_term_dn));

    reg [1:0] vbus_sr;
    always @(posedge pclk_60m) vbus_sr <= {vbus_sr[0], vbus_det};
    assign vbus_s = vbus_sr[1];
    assign led_configured = configured;
    assign led_high_speed = high_speed;

    //------------------------------------------------------------------
    // counters + UART status frame (pclk domain, UART at 60MHz)
    //------------------------------------------------------------------
    reg rxactive_seen;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin
            sof_cnt <= 16'd0; rst_cnt <= 8'd0; err_cnt <= 8'd0; rxactive_seen <= 1'b0;
        end else begin
            if (sof) sof_cnt <= sof_cnt + 1'b1;
            if (bus_reset) rst_cnt <= rst_cnt + 1'b1;
            if (utmi_rxerror && err_cnt != 8'hff) err_cnt <= err_cnt + 1'b1;
            if (utmi_rxactive) rxactive_seen <= 1'b1;
            if (frame_go) rxactive_seen <= 1'b0;
        end
    end

    reg [22:0] tick;           // 2^23 / 60MHz = 140ms
    reg        frame_go;
    always @(posedge pclk_60m or posedge rst)
        if (rst) begin tick <= 23'd0; frame_go <= 1'b0; end
        else begin tick <= tick + 1'b1; frame_go <= (tick == 23'd0); end

    wire [79:0] status = {vendor_reg[7:0], sof_cnt[15:8], sof_cnt[7:0], err_cnt, rst_cnt,
                          {5'b0, frame[10:8]}, frame[7:0], address[6:0], 1'b0,
                          rxactive_seen, pll_lock, vbus_s, suspended, configured, high_speed, utmi_linestate,
                          8'h55};
    reg [79:0] shift; reg [3:0] left; reg tx_valid; wire tx_ready;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin shift <= 80'd0; left <= 4'd0; tx_valid <= 1'b0; end
        else if (frame_go && left == 4'd0) begin shift <= status; left <= 4'd10; tx_valid <= 1'b1; end
        else if (tx_valid && tx_ready) begin
            shift <= {8'd0, shift[79:8]}; left <= left - 1'b1;
            if (left == 4'd1) tx_valid <= 1'b0;
        end
    end
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(60_000_000 / 115200)) u_uart_tx(
        .clock(pclk_60m), .reset(rst), .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(shift[7:0]), .tx(uart_txd));
endmodule
