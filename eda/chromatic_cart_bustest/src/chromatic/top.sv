// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// ModRetro Chromatic: cartridge bus test master (for testing cartridge hardware such as the FPGA
// cartridge adapter with eda/cart_target; NOT for real cartridges). Host: util/chromatic_bustest.
//
//   CLK_24MHz -> pll_60m_24 -> clk60 -> UsbDevice (full speed, EP1 byte stream, rtl/usb)
//                                    -> BtCmd (+ BusTest) -> TestBus -> cartridge slot (rtl/chromatic)
//                                    -> CartPower (slot power / shifter sequencing)
//
// Writes, the static mode and test runs are refused until BtCmd's handshake has found the test
// target in the slot (rtl/chromatic/bt_cmd.veryl).
//
// The USB-C D+/D- reach the FPGA in Gowin's SoftPHY "single LVDS" wiring (behind the on-board
// hub that also carries the GWU2X JTAG bridge). Full speed only needs 3.3 V levels: the dx pair
// is two plain LVCMOS33 pads (drive J / K / SE0, read D+ / D- once per 60 MHz clock = 5 samples
// per FS bit), the termination pair stays tri-stated, the comparator inputs are only declared
// (as unused pins they would get the default pull-up). Host side: util/chromatic_bustest.
//
// Every other board pin is held as in eda/chromatic_blink (ESP32 in reset, codec in reset,
// backlight off, ...). LED: see the end of this file.
module top (
    input  wire        CLK_FPGA,
    input  wire        CLK_24MHz,
    input  wire        POWER_ON_FPGA,   // 1: switch OFF (USB powered)
    input  wire        VERSION_DET,

    output wire        FPGA_LED_EN,
    output wire        FPGA_LED_R,      // active Low
    output wire        FPGA_LED_G,
    output wire        FPGA_LED_B,

    output wire [15:0] CART_A,
    inout  wire [7:0]  CART_D,
    output wire        CART_CLK,
    output wire        CART_RD,
    output wire        CART_WR,
    output wire        CART_CS,
    inout  wire        CART_RST,
    output wire        CART_DATA_DIR_E,
    output wire        CART_CTRL_OE,
    output wire        CART_PWR_EN,
    input  wire        CART_DET,

    output wire        CHG_EN_FPGA,
    output wire        SDIO_LS,
    inout  wire        POWER_DOWN_IO,
    output wire        ADC_SEL,
    output wire        ESP32_EN,
    output wire        ESP32_IO0,
    output wire        LCD_PWM,
    output wire        LCD_RESET,
    output wire        AUD_RESET,
    output wire        IR_LED,
    output wire        LINK_CLK_DIR_LV,
    output wire        LINK_SD_DIR_LV,

    input  wire        usb_rxdp_i,
    input  wire        usb_rxdn_i,
    inout  wire        usb_dxp_io,
    inout  wire        usb_dxn_io,
    inout  wire        usb_term_dp_io,
    inout  wire        usb_term_dn_io,
    output wire        usb_pullup_en_o
);
    // ---- housekeeping (as eda/chromatic_blink) ----
    assign CHG_EN_FPGA     = 1'b1;
    assign SDIO_LS         = 1'b1;
    assign POWER_DOWN_IO   = 1'bz;
    assign ADC_SEL         = 1'b0;
    assign ESP32_EN        = 1'b0;
    assign ESP32_IO0       = 1'b1;
    assign LCD_PWM         = 1'b0;
    assign LCD_RESET       = 1'b0;
    assign AUD_RESET       = 1'b0;
    assign IR_LED          = 1'b0;
    assign LINK_CLK_DIR_LV = 1'b0;
    assign LINK_SD_DIR_LV  = 1'b0;

    // ---- clocks / reset ----
    // PLL reset for ~2 ms after configuration (CLK_FPGA domain)
    logic [16:0] por = '0;
    always_ff @(posedge CLK_FPGA) if (!por[16]) por <= por + 17'd1;
    wire pll_lock;
    wire clk60 /* synthesis syn_keep=1 */;
    pll_60m_24 u_pll (.lock(pll_lock), .clkout0(clk60), .clkin(CLK_24MHz), .reset(!por[16]));
    logic [3:0] rst_sr = 4'hf;
    always_ff @(posedge clk60) rst_sr <= {rst_sr[2:0], ~pll_lock};
    wire rst = rst_sr[3];

    // ---- USB device (full speed) ----
    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       configured;
    wire       rx_valid, rx_ready, tx_valid, tx_ready;
    wire [7:0] rx_data, tx_data;

    UsbDevice #(.HS_CAPABLE(1'b0), .CLK_PER_US(60), .EP1_STREAM(1'b1), .STREAM_FLUSH_US(200)) u_dev (
        .i_clk(clk60), .i_rst(rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(), .o_configured(configured), .o_suspended(), .o_reset(),
        .o_address(), .o_frame(), .o_sof(),
        .o_vendor_reg(),
        .i_vendor_status(32'h5442_4247),          // "GBBT": util/chromatic_bustest checks it
        .o_rx_valid(rx_valid), .o_rx_data(rx_data), .i_rx_ready(rx_ready),
        .i_tx_valid(tx_valid), .i_tx_data(tx_data), .o_tx_ready(tx_ready));

    // pads: one sample per 60 MHz clock (two-flop synchroniser), replicated over UsbPhy's 8 slots
    logic [1:0] dp_s = 2'b00, dn_s = 2'b00;
    always_ff @(posedge clk60) begin dp_s <= {dp_s[0], usb_dxp_io}; dn_s <= {dn_s[0], usb_dxn_io}; end
    wire [7:0] tx_dp8, tx_dn8;
    wire       tx_oe, pullup_dp_en;
    UsbPhy #(.W(8), .FS_CLOCKS_PER_BIT(5), .LS_CLOCKS_PER_BIT(40)) u_phy (
        .i_clk(clk60), .i_rst(rst),
        .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
        .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
        .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
        .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvrselect), .i_utmi_termselect(utmi_termselect),
        .i_rx_dp({8{dp_s[1]}}), .i_rx_dn({8{dn_s[1]}}), .i_rx_dd({8{dp_s[1]}}), .i_rx_dd_valid(1'b1),
        .o_tx_dp(tx_dp8), .o_tx_dn(tx_dn8), .o_tx_oe(tx_oe),
        .o_pullup_dp_en(pullup_dp_en), .o_pullup_dn_en(),
        .o_term_dp_en(), .o_term_dn_en());
    logic tx_dp_q = 1'b1, tx_dn_q = 1'b0, tx_oe_q = 1'b0;
    always_ff @(posedge clk60) begin tx_dp_q <= tx_dp8[0]; tx_dn_q <= tx_dn8[0]; tx_oe_q <= tx_oe; end
    assign usb_dxp_io      = tx_oe_q ? tx_dp_q : 1'bz;
    assign usb_dxn_io      = tx_oe_q ? tx_dn_q : 1'bz;
    assign usb_term_dp_io  = 1'bz;
    assign usb_term_dn_io  = 1'bz;
    // no pull-up (no attach) while the switch is OFF, as the upstream design keeps USB in reset then
    assign usb_pullup_en_o = pullup_dp_en & ~rst & ~POWER_ON_FPGA;

    // ---- cartridge bus test ----
    wire legacy, pw_ready, pwr_en, ctrl_oe, drive_low, power_en, rst_done, rst_force, unlocked, cmd_busy;
    wire req_valid, req_write, req_ready, rsp_valid;
    wire [15:0] req_addr, bus_a, st_a;
    wire [7:0]  req_wdata, rsp_data, bus_dout, d_seen, st_d, cyc, sample, wr_on, wr_off;
    wire [5:0]  st_ctl;
    wire st_en, bus_doe, bus_clk, bus_rd_n, bus_wr_n, bus_cs_n, bus_dir_e, bus_rst_low;

    CartPower #(.CLK_HZ(60000000)) u_pwr (
        .i_clk(clk60), .i_rst(rst), .i_enable(power_en), .i_version_det(VERSION_DET),
        .o_legacy(legacy), .o_ready(pw_ready), .o_pwr_en(pwr_en), .o_ctrl_oe(ctrl_oe), .o_drive_low(drive_low));
    TestBus u_bus (
        .i_clk(clk60), .i_rst(rst), .i_ready(pw_ready), .i_drive_low(drive_low), .i_rst_force(rst_force),
        .i_cyc(cyc), .i_sample(sample), .i_wr_on(wr_on), .i_wr_off(wr_off),
        .i_static(st_en), .i_st_a(st_a), .i_st_ctl(st_ctl), .i_st_d(st_d), .o_d_seen(d_seen),
        .i_req_valid(req_valid), .i_req_write(req_write), .i_req_addr(req_addr), .i_req_wdata(req_wdata),
        .o_req_ready(req_ready), .o_rsp_valid(rsp_valid), .o_rsp_data(rsp_data),
        .o_a(bus_a), .o_d_out(bus_dout), .o_d_oe(bus_doe), .i_d_in(CART_D), .o_clk(bus_clk),
        .o_rd_n(bus_rd_n), .o_wr_n(bus_wr_n), .o_cs_n(bus_cs_n), .o_dir_e(bus_dir_e),
        .o_rst_low(bus_rst_low), .o_rst_done(rst_done));
    BtCmd #(.CLK_HZ(60000000)) u_cmd (
        .i_clk(clk60), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_cart_det(CART_DET), .i_switch_on(~POWER_ON_FPGA), .i_rst_in(CART_RST), .i_pwr_en(pwr_en),
        .i_legacy(legacy), .i_bus_ready(pw_ready & rst_done), .o_power_en(power_en), .o_busy(cmd_busy), .o_unlocked(unlocked),
        .o_cyc(cyc), .o_sample(sample), .o_wr_on(wr_on), .o_wr_off(wr_off),
        .o_static(st_en), .o_st_a(st_a), .o_st_ctl(st_ctl), .o_st_d(st_d), .i_d_seen(d_seen), .o_rst_force(rst_force),
        .o_req_valid(req_valid), .o_req_write(req_write), .o_req_addr(req_addr), .o_req_wdata(req_wdata),
        .i_req_ready(req_ready), .i_rsp_valid(rsp_valid), .i_rsp_data(rsp_data));

    assign CART_A          = bus_a;
    assign CART_D          = bus_doe ? bus_dout : 8'hzz;
    assign CART_CLK        = bus_clk;
    assign CART_RD         = bus_rd_n;
    assign CART_WR         = bus_wr_n;
    assign CART_CS         = bus_cs_n;
    assign CART_DATA_DIR_E = bus_dir_e;
    assign CART_RST        = bus_rst_low ? 1'b0 : 1'bz;
    assign CART_CTRL_OE    = ctrl_oe;
    assign CART_PWR_EN     = pwr_en;

    // ---- LED: green blink = USB not configured, green = idle, yellow = powering,
    //      blue = powered (locked), cyan = unlocked (test target found), white flicker = running ----
    logic [25:0] blink = '0;
    always_ff @(posedge clk60) blink <= blink + 26'd1;
    logic r, g, b;
    always_comb begin
        r = 1'b0; g = 1'b0; b = 1'b0;
        if (!configured)                 g = blink[25];
        else if (cmd_busy)               begin r = blink[20]; g = blink[20]; b = blink[20]; end
        else if (unlocked)               begin g = 1'b1; b = 1'b1; end
        else if (pw_ready && rst_done)   b = 1'b1;
        else if (pwr_en || power_en)     begin r = 1'b1; g = 1'b1; end
        else                             g = 1'b1;
    end
    assign FPGA_LED_EN = ~POWER_ON_FPGA;
    assign FPGA_LED_R  = ~r;
    assign FPGA_LED_G  = ~g;
    assign FPGA_LED_B  = ~b;
endmodule
