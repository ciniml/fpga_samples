// USB 2.0 device bring-up on the Sipeed SLogic16U3 (GW5AT-15), full speed first.
//
//   D14 high -> 125 MHz oscillator on SerDes Q0 REFCLK0 -> Customized PHY (Q0 lane 0, GUI-generated,
//   1.25 Gb/s) tx_pcs_clkout 125 MHz -> pll_60m (PLLA) 60 MHz -> UsbDevice + UsbPhy (rtl/usb)
//
// The board wires the USB 2.0 lines in Gowin's USB 2.0 SoftPHY "Single LVDS" arrangement
// (IPUG781): each line reaches three balls -
//   D+ : H3 (D+ / VREF comparator with H2), K3, P2      D- : M2 (comparator with M1), K2, P1
//   K3/K2 and P2/P1 are the dxp/dxn (bidirectional) and term_dp/term_dn pairs, which is which is
//   not known yet -> the CST picks one (project.tcl DX=K | P); C14 = 1.5k pull-up on D+.
// Full speed only needs the 3.3 V levels, so the dx pair is used as two independent LVCMOS33
// pads (drive J / K / SE0 directly, read D+ / D- single-ended once per 60 MHz clock = 5 samples
// per FS bit, which is what UsbPhy uses for FS) and the term pair stays tri-stated.
//
// Status over JTAG: ER1 (IR 0x42) read-only, 128 bits, see jtag_status.v and host/usb2_status.py.
// LED: G14 (red) = configured.
module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,

    inout  wire usb_dp,        // dx pair, D+ side
    inout  wire usb_dn,        // dx pair, D- side
    inout  wire usb_term_dp,   // term pair (tri-stated at full speed)
    inout  wire usb_term_dn,
    input  wire usb_cmp_dp,    // H3 / H2: D+ against VREF (TLVDS input pair)
    input  wire usb_cmp_dp_n,
    input  wire usb_cmp_dn,    // M2 / M1: D- against VREF
    input  wire usb_cmp_dn_n,
    output wire usb_pullup,    // C14
    output wire xo_en,         // D14: 125 MHz oscillator enable
    output wire led_r          // G14
);
    // ---------------------------------------------------------------- oscillator / reset sequencing
    wire osc;   // ~51.7 MHz (measured)
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));
    assign xo_en = 1'b1;

    // ~20 ms: SerDes PMA reset released; ~40 ms: PLLA reset released
    reg [21:0] seq = 22'd0;
    always @(posedge osc) if (!seq[21]) seq <= seq + 22'd1;
    wire pma_rstn = seq[20];
    wire pll_rst  = !seq[21];

    // ---------------------------------------------------------------- SerDes: 125 MHz into the fabric
    wire sd_rxclk, sd_txclk, sd_refclk, sd_sd, sd_cdr, sd_pll, sd_ready;
    SerDes_Top u_serdes (
        .Customized_PHY_Top_q0_ln0_rx_pcs_clkout_o(sd_rxclk),
        .Customized_PHY_Top_q0_ln0_rx_data_o(), .Customized_PHY_Top_q0_ln0_rx_fifo_rdusewd_o(),
        .Customized_PHY_Top_q0_ln0_rx_fifo_aempty_o(), .Customized_PHY_Top_q0_ln0_rx_fifo_empty_o(),
        .Customized_PHY_Top_q0_ln0_rx_valid_o(),
        .Customized_PHY_Top_q0_ln0_tx_pcs_clkout_o(sd_txclk),
        .Customized_PHY_Top_q0_ln0_tx_fifo_wrusewd_o(), .Customized_PHY_Top_q0_ln0_tx_fifo_afull_o(),
        .Customized_PHY_Top_q0_ln0_tx_fifo_full_o(),
        .Customized_PHY_Top_q0_ln0_refclk_o(sd_refclk),
        .Customized_PHY_Top_q0_ln0_signal_detect_o(sd_sd),
        .Customized_PHY_Top_q0_ln0_rx_cdr_lock_o(sd_cdr),
        .Customized_PHY_Top_q0_ln0_pll_lock_o(sd_pll),
        .Customized_PHY_Top_q0_ln0_ready_o(sd_ready),
        .Customized_PHY_Top_q0_ln0_rx_clk_i(sd_rxclk), .Customized_PHY_Top_q0_ln0_rx_fifo_rden_i(1'b0),
        .Customized_PHY_Top_q0_ln0_tx_clk_i(sd_txclk), .Customized_PHY_Top_q0_ln0_tx_data_i(80'd0),
        .Customized_PHY_Top_q0_ln0_tx_fifo_wren_i(1'b0),
        .Customized_PHY_Top_q0_ln0_pma_rstn_i(pma_rstn),
        .Customized_PHY_Top_q0_ln0_pcs_rx_rst_i(!pma_rstn),
        .Customized_PHY_Top_q0_ln0_pcs_tx_rst_i(!pma_rstn));

    // ---------------------------------------------------------------- 60 MHz
    wire pll_lock;
    wire clk60 /* synthesis syn_keep=1 */;
    pll_60m u_pll (.lock(pll_lock), .clkout0(clk60), .clkout1(), .clkout2(), .clkout3(),
                   .clkin(sd_txclk), .reset(pll_rst), .psdir(1'b0), .pspulse(1'b0));
    reg [3:0] rst_sr = 4'hf;
    always @(posedge clk60) rst_sr <= {rst_sr[2:0], ~pll_lock};
    wire rst = rst_sr[3];

    // ---------------------------------------------------------------- USB device core + PHY (full speed)
    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       high_speed, configured, suspended, bus_reset, sof;
    wire [6:0] address;
    wire [10:0] frame;
    wire [15:0] vendor_reg;
    reg  [15:0] sof_cnt = 16'd0;
    reg  [7:0]  rst_cnt = 8'd0, err_cnt = 8'd0;

    UsbDevice #(.HS_CAPABLE(1'b0), .CLK_PER_US(60)) u_dev (
        .i_clk(clk60), .i_rst(rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(bus_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg),
        .i_vendor_status({8'h53, 8'h4C, sof_cnt}),
        .o_rx_valid(), .o_rx_data(), .i_rx_ready(1'b1),
        .i_tx_valid(1'b0), .i_tx_data(8'd0), .o_tx_ready());

    // pads: one sample per 60 MHz clock (two-flop synchroniser), replicated over UsbPhy's 8 sample slots
    reg [1:0] dp_s = 2'b00, dn_s = 2'b00;
    // the comparator pairs must be declared: as unused pins they get the default weak pull-up, which
    // pulls both lines up (the line state read SE1 and the host could not enumerate)
    wire cmp_dp, cmp_dn;
    TLVDS_IBUF u_cmp_dp (.I(usb_cmp_dp), .IB(usb_cmp_dp_n), .O(cmp_dp));
    TLVDS_IBUF u_cmp_dn (.I(usb_cmp_dn), .IB(usb_cmp_dn_n), .O(cmp_dn));
    reg [1:0] cdp_s = 2'b00, cdn_s = 2'b00;
    always @(posedge clk60) begin cdp_s <= {cdp_s[0], cmp_dp}; cdn_s <= {cdn_s[0], cmp_dn}; end
    reg [1:0] tdp_s = 2'b00, tdn_s = 2'b00;   // term pads, read back for the status only
    always @(posedge clk60) begin dp_s <= {dp_s[0], usb_dp}; dn_s <= {dn_s[0], usb_dn}; tdp_s <= {tdp_s[0], usb_term_dp}; tdn_s <= {tdn_s[0], usb_term_dn}; end
    wire [7:0] rx_dp = {8{dp_s[1]}};
    wire [7:0] rx_dn = {8{dn_s[1]}};
    wire [7:0] tx_dp8, tx_dn8;
    wire       tx_oe, pullup_dp_en, pullup_dn_en, term_dp_en, term_dn_en;
    UsbPhy #(.W(8), .FS_CLOCKS_PER_BIT(5), .LS_CLOCKS_PER_BIT(40)) u_phy (
        .i_clk(clk60), .i_rst(rst),
        .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
        .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
        .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
        .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvrselect), .i_utmi_termselect(utmi_termselect),
        .i_rx_dp(rx_dp), .i_rx_dn(rx_dn), .i_rx_dd(rx_dp), .i_rx_dd_valid(1'b1),
        .o_tx_dp(tx_dp8), .o_tx_dn(tx_dn8), .o_tx_oe(tx_oe),
        .o_pullup_dp_en(pullup_dp_en), .o_pullup_dn_en(pullup_dn_en),
        .o_term_dp_en(term_dp_en), .o_term_dn_en(term_dn_en));

    // FS bits last 5 clocks, so the first slot of each clock is the line state for the whole clock
    reg tx_dp_q = 1'b1, tx_dn_q = 1'b0, tx_oe_q = 1'b0;
    always @(posedge clk60) begin tx_dp_q <= tx_dp8[0]; tx_dn_q <= tx_dn8[0]; tx_oe_q <= tx_oe; end
    assign usb_dp = tx_oe_q ? tx_dp_q : 1'bz;
    assign usb_dn = tx_oe_q ? tx_dn_q : 1'bz;
    assign usb_term_dp = 1'bz;
    assign usb_term_dn = 1'bz;
    assign usb_pullup = pullup_dp_en & ~rst;

    // ---------------------------------------------------------------- status
    reg bus_reset_seen = 1'b0, rxact_seen = 1'b0, txoe_seen = 1'b0;
    always @(posedge clk60) begin
        if (sof) sof_cnt <= sof_cnt + 16'd1;
        if (bus_reset) begin rst_cnt <= rst_cnt + 8'd1; bus_reset_seen <= 1'b1; end
        if (utmi_rxerror && err_cnt != 8'hff) err_cnt <= err_cnt + 8'd1;
        if (utmi_rxactive) rxact_seen <= 1'b1;
        if (tx_oe) txoe_seen <= 1'b1;
    end
    assign led_r = configured;

    // 60 MHz check: clk60 edges (/16) per 2^22 osc cycles
    reg [3:0] c60 = 4'd0;
    always @(posedge clk60) c60 <= c60 + 4'd1;
    reg [2:0] c60_s = 3'd0;
    reg [21:0] gate = 22'd0;
    reg [19:0] n60 = 20'd0, f60 = 20'd0;
    always @(posedge osc) begin
        c60_s <= {c60_s[1:0], c60[3]};
        gate <= gate + 22'd1;
        if (&gate) begin f60 <= n60; n60 <= 20'd0; end
        else if (c60_s[1] && !c60_s[2]) n60 <= n60 + 20'd1;
    end

    wire [127:0] status = {
        12'd0, f60,                                         // [127:96] clk60 / 16 per 2^22 osc
        rst_cnt, err_cnt,                                   // [95:80]
        sof_cnt,                                            // [79:64]
        12'd0, cdn_s[1], cdp_s[1], tdn_s[1], tdp_s[1], dn_s[1], dp_s[1], frame, address,  // [63:28] comparators [51:50], term pads [49:48], dx pads [47:46], frame [45:35], address [34:28]
        txoe_seen, rxact_seen, utmi_linestate,              // [27:24]
        bus_reset_seen, suspended, high_speed, configured,  // [23:20]
        sd_ready, sd_pll, pll_lock, ~rst,                   // [19:16]
        16'h5B20 };                                         // [15:0] magic
    jtag_status #(.L(128)) u_js (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap(status));
endmodule
