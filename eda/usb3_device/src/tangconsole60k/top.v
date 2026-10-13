// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Tang Console 60K: USB 3.2 Gen1 device sample (SerDes Q0 Lane2 = USB3-A port 1, REFCLK1 = MS5351 125 MHz).
// Ported from eda/slogic16u3_usb3 (the configuration proven on the SLogic16U3): same PHY handling,
// EP1 loopback / PRBS source, JTAG ER1 status + ER2 PIPE trace for the host scripts, plus a UART status line.
`default_nettype none
module top (
    input  wire sys_clk,       // 50 MHz
    input  wire tck_pad_i,     // JTAG (BL616 debugger): GW_JTAG ER1/ER2 status and trace
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,
    output wire uart_tx,
    input  wire uart_rx
);
    wire osc = sys_clk;   // status / JTAG clock (50 MHz; the SLogic used its ~51.7 MHz oscillator)

    // ---------------------------------------------------------------- reset
    reg [7:0] rst_cnt = 0;
    wire rst = rst_cnt != 8'hFF;
    always @(posedge sys_clk) if (rst) rst_cnt <= rst_cnt + 1;

    // MS5351: programmed by the BL616 (its console: Ctrl+X Ctrl+C, `pll_clk`), not from the FPGA.
    // Defaults: CLK0/CLK1 125 MHz (CLK1 inverted) = SerDes REFCLK1, CLK2 27 MHz.

    // ---------------------------------------------------------------- 125 MHz for the PHY wrapper's ref_clk (PLLA: 50 MHz x 20 / 8)
    wire ref_clk /* synthesis syn_keep=1 */, ref_lock;
    wire gw_gnd = 1'b0;
    PLLA u_pll (
        .LOCK(ref_lock), .CLKOUT0(ref_clk), .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(), .CLKIN(sys_clk), .CLKFB(gw_gnd), .RESET(gw_gnd), .PLLPWD(gw_gnd), .RESET_I(gw_gnd), .RESET_O(gw_gnd),
        .PSSEL(3'b0), .PSDIR(gw_gnd), .PSPULSE(gw_gnd), .SSCPOL(gw_gnd), .SSCON(gw_gnd), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .MDCLK(gw_gnd), .MDOPC(2'b0), .MDAINC(gw_gnd), .MDWDI(8'b0));
    defparam u_pll.FCLKIN = "50";
    defparam u_pll.IDIV_SEL = 1;
    defparam u_pll.FBDIV_SEL = 1;
    defparam u_pll.CLKFB_SEL = "INTERNAL";
    defparam u_pll.ODIV0_SEL = 8;
    defparam u_pll.ODIV0_FRAC_SEL = 0;
    defparam u_pll.ODIV1_SEL = 8;
    defparam u_pll.ODIV2_SEL = 8;
    defparam u_pll.ODIV3_SEL = 8;
    defparam u_pll.ODIV4_SEL = 8;
    defparam u_pll.ODIV5_SEL = 8;
    defparam u_pll.ODIV6_SEL = 8;
    defparam u_pll.MDIV_SEL = 20;
    defparam u_pll.MDIV_FRAC_SEL = 0;
    defparam u_pll.CLKOUT0_EN = "TRUE";
    defparam u_pll.CLKOUT1_EN = "FALSE";
    defparam u_pll.CLKOUT2_EN = "FALSE";
    defparam u_pll.CLKOUT3_EN = "FALSE";
    defparam u_pll.CLKOUT4_EN = "FALSE";
    defparam u_pll.CLKOUT5_EN = "FALSE";
    defparam u_pll.CLKOUT6_EN = "FALSE";
    defparam u_pll.CLKOUT0_DT_DIR = 1'b1;
    defparam u_pll.CLKOUT1_DT_DIR = 1'b1;
    defparam u_pll.CLKOUT2_DT_DIR = 1'b1;
    defparam u_pll.CLKOUT3_DT_DIR = 1'b1;
    defparam u_pll.CLKOUT0_DT_STEP = 0;
    defparam u_pll.CLKOUT1_DT_STEP = 0;
    defparam u_pll.CLKOUT2_DT_STEP = 0;
    defparam u_pll.CLKOUT3_DT_STEP = 0;
    defparam u_pll.CLK0_IN_SEL = 1'b0;
    defparam u_pll.CLK0_OUT_SEL = 1'b0;
    defparam u_pll.CLK1_IN_SEL = 1'b0;
    defparam u_pll.CLK1_OUT_SEL = 1'b0;
    defparam u_pll.CLK2_IN_SEL = 1'b0;
    defparam u_pll.CLK2_OUT_SEL = 1'b0;
    defparam u_pll.CLK3_IN_SEL = 1'b0;
    defparam u_pll.CLK3_OUT_SEL = 1'b0;
    defparam u_pll.CLK4_IN_SEL = 2'b00;
    defparam u_pll.CLK4_OUT_SEL = 1'b0;
    defparam u_pll.CLK5_IN_SEL = 1'b0;
    defparam u_pll.CLK5_OUT_SEL = 1'b0;
    defparam u_pll.CLK6_IN_SEL = 1'b0;
    defparam u_pll.CLK6_OUT_SEL = 1'b0;
    defparam u_pll.DYN_DPA_EN = "FALSE";
    defparam u_pll.CLKOUT0_PE_COARSE = 0;
    defparam u_pll.CLKOUT0_PE_FINE = 0;
    defparam u_pll.CLKOUT1_PE_COARSE = 0;
    defparam u_pll.CLKOUT1_PE_FINE = 0;
    defparam u_pll.CLKOUT2_PE_COARSE = 0;
    defparam u_pll.CLKOUT2_PE_FINE = 0;
    defparam u_pll.CLKOUT3_PE_COARSE = 0;
    defparam u_pll.CLKOUT3_PE_FINE = 0;
    defparam u_pll.CLKOUT4_PE_COARSE = 0;
    defparam u_pll.CLKOUT4_PE_FINE = 0;
    defparam u_pll.CLKOUT5_PE_COARSE = 0;
    defparam u_pll.CLKOUT5_PE_FINE = 0;
    defparam u_pll.CLKOUT6_PE_COARSE = 0;
    defparam u_pll.CLKOUT6_PE_FINE = 0;
    defparam u_pll.DYN_PE0_SEL = "FALSE";
    defparam u_pll.DYN_PE1_SEL = "FALSE";
    defparam u_pll.DYN_PE2_SEL = "FALSE";
    defparam u_pll.DYN_PE3_SEL = "FALSE";
    defparam u_pll.DYN_PE4_SEL = "FALSE";
    defparam u_pll.DYN_PE5_SEL = "FALSE";
    defparam u_pll.DYN_PE6_SEL = "FALSE";
    defparam u_pll.DE0_EN = "FALSE";
    defparam u_pll.DE1_EN = "FALSE";
    defparam u_pll.DE2_EN = "FALSE";
    defparam u_pll.DE3_EN = "FALSE";
    defparam u_pll.DE4_EN = "FALSE";
    defparam u_pll.DE5_EN = "FALSE";
    defparam u_pll.DE6_EN = "FALSE";
    defparam u_pll.RESET_I_EN = "FALSE";
    defparam u_pll.RESET_O_EN = "FALSE";
    defparam u_pll.ICP_SEL = 6'bXXXXXX;
    defparam u_pll.LPF_RES = 3'bXXX;
    defparam u_pll.LPF_CAP = 2'b00;
    defparam u_pll.SSC_EN = "FALSE";


    reg [20:0] seq = 21'd0;
    always @(posedge osc) if (!seq[20]) seq <= seq + 21'd1;
    reg [2:0] start_s = 3'd0;
    reg [16:0] phy_rst_cnt = 17'd0;
    wire phy_resetn = phy_rst_cnt[16];
    always @(posedge ref_clk) begin
        start_s <= {start_s[1:0], seq[20] & ref_lock};
        if (!start_s[2]) phy_rst_cnt <= 17'd0;
        else if (!phy_resetn) phy_rst_cnt <= phy_rst_cnt + 17'd1;
    end

    // ---------------------------------------------------------------- PHY
    wire pclk /* synthesis syn_keep=1 */;
    wire [31:0] rx_data, tx_data; wire [3:0] rx_k, tx_k; wire rx_valid, rx_elecidle, phy_status, power_present;
    wire [2:0] rx_status; wire [1:0] power_down; wire tx_elecidle, tx_detectrx, rx_polarity, rx_termination;
    wire [31:0] u3_tx_data; wire [3:0] u3_tx_k; wire [1:0] u3_power_down; wire u3_tx_elecidle, u3_tx_detectrx, u3_rx_polarity, u3_rx_termination;
`ifdef FORCE_LFPS
    // diagnostic (FORCE_LFPS=1, with LANE=2ln): lane 2 idles in FD_PD with termination while lane 3 sends LFPS
    // (P2, TxElecIdle 0) into the cable between the two ports: do lane 2's receive indications react?
`ifndef FD_PD
`define FD_PD 2
`endif
    assign tx_data = 32'd0; assign tx_k = 4'd0; assign tx_elecidle = 1'b1; assign tx_detectrx = 1'b0;
    assign power_down = `FD_PD; assign rx_polarity = 1'b0; assign rx_termination = 1'b1;
    wire [1:0] ln3_power_down = 2'd2;
`ifdef LFPS_BURST
    // Polling.LFPS-like bursts: 1.0 us on, 9 us off (tBurst 0.6-1.4 us, tRepeat 6-14 us)
    reg [10:0] lb_t = 11'd0; always @(posedge pclk3) lb_t <= (lb_t == 11'd1249) ? 11'd0 : lb_t + 11'd1;
    wire ln3_tx_elecidle = !(lb_t < 11'd125);
`else
    wire ln3_tx_elecidle = 1'b0;
`endif
`elsif FORCE_DET
    // diagnostic (FORCE_DET=1): P2, then receiver detection requests every ~40 ms; counts the PHY's answers
    reg [1:0] fd_st = 2'd0; reg [21:0] fd_t = 22'd0; reg fd_detrx = 1'b0;
    reg [15:0] fd_att = 16'd0, fd_resp = 16'd0, fd_det = 16'd0;
    always @(posedge pclk) begin
        fd_t <= fd_t + 22'd1;
        case (fd_st)
            2'd0: if (&fd_t[19:0]) begin fd_st <= 2'd1; fd_t <= 22'd0; end                 // settle in P2
            2'd1: if (&fd_t[18:0]) begin fd_st <= 2'd2; fd_t <= 22'd0; fd_detrx <= 1'b1; fd_att <= fd_att + 16'd1; end
            2'd2: begin if (phy_status) begin fd_resp <= fd_resp + 16'd1; if (rx_status == 3'd3) fd_det <= fd_det + 16'd1; fd_st <= 2'd3; fd_t <= 22'd0; fd_detrx <= 1'b0; end
                        else if (&fd_t) begin fd_st <= 2'd3; fd_t <= 22'd0; fd_detrx <= 1'b0; end end  // 33 ms timeout
            2'd3: if (&fd_t[21:0]) begin fd_st <= 2'd1; fd_t <= 22'd0; end
        endcase
    end
    assign tx_data = 32'd0; assign tx_k = 4'd0; assign tx_elecidle = 1'b1; assign tx_detectrx = fd_detrx;
`ifndef FD_PD
`define FD_PD 2
`endif
    assign power_down = `FD_PD; assign rx_polarity = 1'b0; assign rx_termination = 1'b1;   // FD_PD: power state under test (P1 / P2)
`elsif FORCE_TX
    // diagnostic (FORCE_TX=1): ignore the LTSSM, hold the PHY in P0 and transmit COM + data words forever;
    // with the lane in near-end loopback (LB_NES CSR) the receive counters must show the stream
    reg [1:0] ft_cnt = 2'd0; reg [31:0] ft_data = 32'h4A4A4ABC; reg [3:0] ft_k = 4'b0001; reg [7:0] ft_lfsr = 8'h5A;
    always @(posedge pclk) begin
        ft_cnt <= ft_cnt + 2'd1; ft_lfsr <= {ft_lfsr[6:0], ft_lfsr[7] ^ ft_lfsr[5] ^ ft_lfsr[4] ^ ft_lfsr[3]};
        if (ft_cnt == 2'd3) begin ft_data <= 32'h4A4A4ABC; ft_k <= 4'b0001; end
        else begin ft_data <= {ft_lfsr, ~ft_lfsr, ft_lfsr ^ 8'h0F, ft_lfsr ^ 8'hF0}; ft_k <= 4'b0000; end
    end
    assign tx_data = ft_data; assign tx_k = ft_k; assign tx_elecidle = 1'b0; assign tx_detectrx = 1'b0;
    assign power_down = 2'd0; assign rx_polarity = 1'b0; assign rx_termination = 1'b1;
`else
    assign tx_data = u3_tx_data; assign tx_k = u3_tx_k; assign tx_elecidle = u3_tx_elecidle; assign tx_detectrx = u3_tx_detectrx;
    assign power_down = u3_power_down; assign rx_polarity = u3_rx_polarity; assign rx_termination = u3_rx_termination;
`endif
    wire dbg_cmu_ok, dbg_rx_lock, dbg_rstn, dbg_rxdet; wire [2:0] dbg_ei;
    wire rx_elecidle_eff;
`ifdef EI_RAW
    // EI_RAW=1: the LTSSM sees the quad's raw receiver electrical-idle output instead of the PHY's RxElecIdle
    reg [1:0] ei_raw_s = 2'b11; always @(posedge pclk) ei_raw_s <= {ei_raw_s[0], dbg_ei[0]};
    assign rx_elecidle_eff = `EI_RAW_INV ? !ei_raw_s[1] : ei_raw_s[1];   // EI_RAW=2: inverted (raw output is a signal-present flag)
`else
    assign rx_elecidle_eff = rx_elecidle;
`endif wire [5:0] dbg_astat; wire [12:0] dbg_lane_stat;
    // UPAR diagnostics (TAG=upar build): life clock / DRP clock frequency and PHY<->quad register traffic
    wire dbg_life_clk, dbg_drp_clk; wire [8:0] dbg_upar;
    reg [3:0] ldiv = 4'd0 /* synthesis syn_preserve=1 */; always @(posedge dbg_life_clk) ldiv <= ldiv + 4'd1;
    reg [3:0] ddiv = 4'd0 /* synthesis syn_preserve=1 */; always @(posedge dbg_drp_clk) ddiv <= ddiv + 4'd1;
    reg [2:0] lds = 3'd0, dds = 3'd0; reg [17:0] lgate = 18'd0; reg [15:0] ln = 16'd0 /* synthesis syn_preserve=1 */, lf = 16'd0, dn = 16'd0 /* synthesis syn_preserve=1 */, df = 16'd0;
    always @(posedge osc) begin
        lds <= {lds[1:0], ldiv[3]}; dds <= {dds[1:0], ddiv[3]}; lgate <= lgate + 18'd1;
        if (&lgate) begin lf <= ln; ln <= 16'd0; df <= dn; dn <= 16'd0; end
        else begin if (lds[1] && !lds[2]) ln <= ln + 16'd1; if (dds[1] && !dds[2]) dn <= dn + 16'd1; end
    end
    reg [7:0] c_wren = 8'd0, c_rden = 8'd0, c_ready = 8'd0, c_rdvld = 8'd0;
    always @(posedge dbg_drp_clk) begin
        if (dbg_upar[0]) c_wren <= c_wren + 8'd1; if (dbg_upar[1]) c_rden <= c_rden + 8'd1;
        if (dbg_upar[2]) c_ready <= c_ready + 8'd1; if (dbg_upar[3]) c_rdvld <= c_rdvld + 8'd1;
    end
    reg [7:0] c_swren = 8'd0;
    always @(posedge dbg_life_clk) if (dbg_upar[6]) c_swren <= c_swren + 8'd1;
`ifdef TWO_LANES
    // cable self-test (LANE=2ln + FORCE_TX=1): lane 3 (port 2P) transmits the same stream; the two ports are
    // joined by the cable under test, so each lane must receive the other's COM symbols if the SS pairs are wired
    wire pclk3; wire [31:0] rx3_data; wire [3:0] rx3_k; wire rx3_valid, rx3_eidle, phy3_status; wire [2:0] rx3_status; wire dbg3_rx_lock; wire [12:0] dbg3_lane_stat;
    reg [15:0] cnt3_com = 16'd0, cnt3_dec = 16'd0, cnt3_physt = 16'd0; reg [3:0] p3div = 4'd0 /* synthesis syn_preserve=1 */;
    wire [3:0] com3_k = {rx3_k[3] && rx3_data[31:24] == 8'hBC, rx3_k[2] && rx3_data[23:16] == 8'hBC, rx3_k[1] && rx3_data[15:8] == 8'hBC, rx3_k[0] && rx3_data[7:0] == 8'hBC};
    always @(posedge pclk3) begin
        p3div <= p3div + 4'd1;
        if (rx3_valid && |com3_k) cnt3_com <= cnt3_com + 16'd1;
        if (rx3_status == 3'd4) cnt3_dec <= cnt3_dec + 16'd1;
        if (phy3_status) cnt3_physt <= cnt3_physt + 16'd1;
    end
`endif
`ifdef TWO_LANES
`ifndef FORCE_LFPS
    wire [1:0] ln3_power_down = power_down; wire ln3_tx_elecidle = tx_elecidle;
`endif
`endif
    SerDes_Top u_serdes (
`ifdef TWO_LANES
        .USB3_0_PHY_Top_LN3_pclk(pclk3), .USB3_0_PHY_Top_LN3_PipeRxData(rx3_data), .USB3_0_PHY_Top_LN3_PipeRxDataK(rx3_k),
        .USB3_0_PHY_Top_LN3_PipeRxDataValid(rx3_valid), .USB3_0_PHY_Top_LN3_RxElecIdle(rx3_eidle), .USB3_0_PHY_Top_LN3_RxStatus(rx3_status),
        .USB3_0_PHY_Top_LN3_PhyStatus(phy3_status), .USB3_0_PHY_Top_LN3_PowerPresent(), .USB3_0_PHY_Top_LN3_ref_clk(ref_clk),
        .USB3_0_PHY_Top_LN3_phy_resetn(phy_resetn), .USB3_0_PHY_Top_LN3_PipeTxData(tx_data), .USB3_0_PHY_Top_LN3_PipeTxDataK(tx_k),
        .USB3_0_PHY_Top_LN3_TxDetectRx_loopback(tx_detectrx), .USB3_0_PHY_Top_LN3_TxElecIdle(ln3_tx_elecidle), .USB3_0_PHY_Top_LN3_RxPolarity(1'b0),
        .USB3_0_PHY_Top_LN3_RxEqTraining(1'b0), .USB3_0_PHY_Top_LN3_RxTermination(rx_termination), .USB3_0_PHY_Top_LN3_TxOnesZeros(1'b0),
        .USB3_0_PHY_Top_LN3_PowerDown(ln3_power_down), .USB3_0_PHY_Top_LN3_ElasticityBufferMode(1'b0),
        .dbg3_rx_lock(dbg3_rx_lock), .dbg3_lane_stat(dbg3_lane_stat),
`endif
        .dbg_ei(dbg_ei), .dbg_rxdet(dbg_rxdet), .dbg_life_clk(dbg_life_clk), .dbg_drp_clk(dbg_drp_clk), .dbg_upar(dbg_upar), .dbg_cmu_ok(dbg_cmu_ok), .dbg_rx_lock(dbg_rx_lock), .dbg_rstn(dbg_rstn), .dbg_astat(dbg_astat), .dbg_lane_stat(dbg_lane_stat),
        .USB3_0_PHY_Top_pclk(pclk),
        .USB3_0_PHY_Top_PipeRxData(rx_data),
        .USB3_0_PHY_Top_PipeRxDataK(rx_k),
        .USB3_0_PHY_Top_PipeRxDataValid(rx_valid),
        .USB3_0_PHY_Top_RxElecIdle(rx_elecidle),
        .USB3_0_PHY_Top_RxStatus(rx_status),
        .USB3_0_PHY_Top_PhyStatus(phy_status),
        .USB3_0_PHY_Top_PowerPresent(power_present),
        .USB3_0_PHY_Top_ref_clk(ref_clk),
        .USB3_0_PHY_Top_phy_resetn(phy_resetn),
        .USB3_0_PHY_Top_PipeTxData(tx_data),
        .USB3_0_PHY_Top_PipeTxDataK(tx_k),
        .USB3_0_PHY_Top_TxDetectRx_loopback(tx_detectrx),
        .USB3_0_PHY_Top_TxElecIdle(tx_elecidle),
        .USB3_0_PHY_Top_RxPolarity(rx_polarity),
        .USB3_0_PHY_Top_RxEqTraining(1'b0),
        .USB3_0_PHY_Top_RxTermination(rx_termination),
        .USB3_0_PHY_Top_TxOnesZeros(1'b0),
        .USB3_0_PHY_Top_PowerDown(power_down),
        .USB3_0_PHY_Top_ElasticityBufferMode(1'b0));

    // pclk-domain reset: held for 4096 pclk after phy_resetn (synchronised)
    reg [2:0] prn_s = 3'd0;
    reg [12:0] prst_cnt = 13'd0;
    always @(posedge pclk) begin
        prn_s <= {prn_s[1:0], phy_resetn};
        if (!prn_s[2]) prst_cnt <= 13'd0;
        else if (!prst_cnt[12]) prst_cnt <= prst_cnt + 13'd1;
    end
    wire prst = !prst_cnt[12];

    // ---------------------------------------------------------------- link + protocol
    wire rx_hp_valid; wire [95:0] rx_hp_hdr;
    wire dpp_start, dpp_valid, dpp_end, dpp_err; wire [31:0] dpp_data; wire [3:0] dpp_be;
    wire tx_hp_valid, tx_dpp, tx_hp_ready, tx_hp_idle; wire [95:0] tx_hp_hdr; wire [10:0] tx_dpp_len; wire [12:0] tx_dpp_base;
    wire dpp_rd; wire [12:0] dpp_addr; wire [31:0] dpp_rdata;
    wire [4:0] ltssm_state; wire in_u0, u0_entry, hot_reset, warm_reset, link_configured;
    wire dev_configured, dev_reset, dbg_event, dbg_strobe; wire [63:0] dbg_state; wire [6:0] dev_address; wire [15:0] vendor_reg;
    wire ep_rx_valid, ep_rx_ready, ep_tx_valid, ep_tx_ready; wire [7:0] ep_rx_data, ep_tx_data;
    wire epw_valid, epw_ready; wire [31:0] epw_data;

    Usb3Top #(
`ifdef LTSSM_LOW_PD
        .LOW_PD(`LTSSM_LOW_PD), .RXDET_PD(`LTSSM_RXDET_PD), .RXDET_ASSUME_US(`RXDET_ASSUME_US), .POLL_LFPS_P2(`POLL_LFPS_P2), .POLL_LFPS_BLIND_US(`POLL_LFPS_BLIND_US),
`endif
        .CLK_HZ(125_000_000)) u_usb3 (.i_clk(pclk), .i_rst(prst),
        .i_rx_data(rx_data), .i_rx_k(rx_k), .i_rx_valid(rx_valid), .i_rx_status(rx_status), .i_rx_elecidle(rx_elecidle_eff),
        .i_phy_status(phy_status), .i_power_present(1'b1),
        .o_tx_data(u3_tx_data), .o_tx_k(u3_tx_k), .o_tx_elecidle(u3_tx_elecidle), .o_tx_detectrx(u3_tx_detectrx),
        .o_power_down(u3_power_down), .o_rx_polarity(u3_rx_polarity), .o_rx_termination(u3_rx_termination),
        .o_rx_hp_valid(rx_hp_valid), .o_rx_hp_hdr(rx_hp_hdr),
        .o_dpp_start(dpp_start), .o_dpp_valid(dpp_valid), .o_dpp_data(dpp_data), .o_dpp_be(dpp_be), .o_dpp_end(dpp_end), .o_dpp_err(dpp_err),
        .i_tx_hp_valid(tx_hp_valid), .i_tx_hp_hdr(tx_hp_hdr), .i_tx_dpp(tx_dpp), .i_tx_dpp_len(tx_dpp_len), .i_tx_dpp_base(tx_dpp_base),
        .o_tx_hp_ready(tx_hp_ready), .o_tx_hp_idle(tx_hp_idle),
        .o_dpp_rd(dpp_rd), .o_dpp_addr(dpp_addr), .i_dpp_data(dpp_rdata),
        .o_ltssm_state(ltssm_state), .o_in_u0(in_u0), .o_u0_entry(u0_entry), .o_hot_reset(hot_reset), .o_warm_reset(warm_reset),
        .o_configured(link_configured));

    Usb3Device #(.STREAM_FLUSH_US(1000)) u_dev (.i_clk(pclk), .i_rst(prst),
        .i_in_u0(in_u0), .i_hot_reset(hot_reset), .i_warm_reset(warm_reset),
        .i_rx_hp_valid(rx_hp_valid), .i_rx_hp_hdr(rx_hp_hdr),
        .i_dpp_start(dpp_start), .i_dpp_valid(dpp_valid), .i_dpp_data(dpp_data), .i_dpp_be(dpp_be), .i_dpp_end(dpp_end), .i_dpp_err(dpp_err),
        .o_tx_hp_valid(tx_hp_valid), .o_tx_hp_hdr(tx_hp_hdr), .o_tx_dpp(tx_dpp), .o_tx_dpp_len(tx_dpp_len), .o_tx_dpp_base(tx_dpp_base),
        .i_tx_hp_ready(tx_hp_ready), .i_dpp_rd(dpp_rd), .i_dpp_addr(dpp_addr), .o_dpp_data(dpp_rdata),
        .o_configured(dev_configured), .o_address(dev_address), .o_reset(dev_reset), .o_dbg_event(dbg_event), .o_dbg_strobe(dbg_strobe), .o_dbg_state(dbg_state),
        .o_vendor_reg(vendor_reg), .i_vendor_status({8'h55, 3'b0, ltssm_state, 7'b0, link_configured, 8'h03}),
        .o_reg_wr(), .o_reg_addr(), .o_reg_wdata(), .i_reg_rdata(32'd0),
        .o_rx_valid(ep_rx_valid), .o_rx_data(ep_rx_data), .i_rx_ready(ep_rx_ready),
        .i_tx_valid(ep_tx_valid), .i_tx_data(ep_tx_data), .o_tx_ready(ep_tx_ready),
        .i_txw_valid(epw_valid), .i_txw_data(epw_data), .o_txw_ready(epw_ready));
    // EP1: byte loopback, or (vendor register = 0x0001, vendor request 0x02 wValue) a PRBS15 source on
    // EP1 IN for throughput / integrity tests: x^15 + x^14 + 1, 32 bits per pclk into the 32-bit entry
    // of Usb3Device (byte 0 first, first bit in bit 0 of each byte; restarts from the all-ones state
    // when the mode is switched on; EP1 OUT is then drained and discarded). host/usb3_prbs.py checks it.
    function [14:0] prbs15_adv32(input [14:0] s);
        integer k; reg [14:0] t;
        begin
            t = s;
            for (k = 0; k < 32; k = k + 1) t = {t[13:0], t[14] ^ t[13]};
            prbs15_adv32 = t;
        end
    endfunction
    function [31:0] prbs15_word(input [14:0] s);   // the 32 bits those steps produce, first in bit 0
        integer k; reg [14:0] t; reg [31:0] b;
        begin
            t = s;
            for (k = 0; k < 32; k = k + 1) begin b[k] = t[14] ^ t[13]; t = {t[13:0], t[14] ^ t[13]}; end
            prbs15_word = b;
        end
    endfunction
    wire       prbs_mode = vendor_reg == 16'h0001;   // (exactly 1: usb_echo.py writes 0x5AA5 as a register test)
    reg        prbs_mode_d = 1'b0;
    reg [14:0] prbs_s = 15'h7FFF;
    reg [31:0] prbs_w = 32'd0;            // registered word (keeps the 32-step XOR network off the RAM write)
    always @(posedge pclk) begin
        prbs_mode_d <= prbs_mode;
        if (prbs_mode && !prbs_mode_d) begin prbs_s <= 15'h7FFF; prbs_w <= prbs15_word(15'h7FFF); end
        else if (prbs_mode && epw_ready) begin prbs_s <= prbs15_adv32(prbs_s); prbs_w <= prbs15_word(prbs15_adv32(prbs_s)); end
    end
    assign epw_valid   = prbs_mode && prbs_mode_d;   // (not in the clock that restarts it)
    assign epw_data    = prbs_w;
    assign ep_tx_valid = prbs_mode ? 1'b0 : ep_rx_valid;
    assign ep_tx_data  = ep_rx_data;
    assign ep_rx_ready = prbs_mode ? 1'b1 : ep_tx_ready;

    // ---------------------------------------------------------------- statistics (pclk)
    reg [15:0] cnt_u0 = 16'd0, cnt_hp = 16'd0, cnt_reset = 16'd0, cnt_dpp_err = 16'd0, cnt_physt = 16'd0;
    reg [31:0] cnt_bytes = 32'd0;
    reg [4:0]  st_max = 5'd0, st_d = 5'd0;
    reg [31:0] st_seen = 32'd0;
    reg [79:0] st_trace = 80'd0;    // last 16 LTSSM states entered, newest in [4:0]
    reg [7:0]  cnt_trans = 8'd0;
    reg        elec_d = 1'b1;
    reg [15:0] cnt_lfps = 16'd0;    // RxElecIdle falling edges (LFPS bursts / data start)
    always @(posedge pclk) begin
        if (u0_entry) cnt_u0 <= cnt_u0 + 16'd1;
        if (rx_hp_valid) cnt_hp <= cnt_hp + 16'd1;
        if (hot_reset || warm_reset) cnt_reset <= cnt_reset + 16'd1;
        if (dpp_end && dpp_err) cnt_dpp_err <= cnt_dpp_err + 16'd1;
        if (phy_status) cnt_physt <= cnt_physt + 16'd1;
        if (ep_rx_valid && ep_rx_ready) cnt_bytes <= cnt_bytes + 32'd1;
        if (ltssm_state > st_max) st_max <= ltssm_state;
        st_seen[ltssm_state] <= 1'b1;
        st_d <= ltssm_state;
        if (ltssm_state != st_d) begin st_trace <= {st_trace[74:0], ltssm_state}; cnt_trans <= cnt_trans + 8'd1; end
        elec_d <= rx_elecidle;
        if (elec_d && !rx_elecidle) cnt_lfps <= cnt_lfps + 16'd1;
    end

    // snapshot for the status register: refreshed every 1024 pclk, so the JTAG side (osc) sees a
    // value that stays put for ~8 us around its capture
    reg [9:0]  snap_div = 10'd0;
    // (bit positions below are those of the status register: live[0] lands on bit 44)
    reg [307:0] snap = 308'd0;
    wire [307:0] live = {
`ifdef LFPS_DIAG
        ed_eih, ed_ei,                                          // [351:320] (LFPS diag: quad rxelecidle_o high / PHY RxElecIdle low cycles)
`elsif UPAR_DIAG
        df, lf,                                                 // [351:320] (upar diag: drp / life clock freq)
`else
        cnt_bytes,                                              // [351:320]
`endif
        st_trace,                                               // [319:240]
        st_seen,                                                // [239:208]
`ifdef TWO_LANES
        c_rdvld, c_ready, cnt_physt, c_rden, c_wren, cnt3_physt, cnt3_com, cnt3_dec, // [207:112] (lane 3: physt / com / dec in reset / hp / u0)
`elsif FORCE_DET
        c_rdvld, c_ready, cnt_physt, c_rden, c_wren, fd_det, fd_resp, fd_att,       // [207:112] (detect test: detected / answers / attempts in reset / hp / u0)
`elsif UPAR_DIAG
        c_rdvld, c_ready, cnt_physt, c_rden, c_wren, cnt_reset, cnt_hp, cnt_u0, // [207:112] (upar diag in lfps / dpp_err)
`else
        cnt_lfps, cnt_physt, cnt_dpp_err, cnt_reset, cnt_hp, cnt_u0, // [207:112]
`endif
`ifdef TWO_LANES
        dbg_upar[5], dbg_upar[2], dbg3_lane_stat[3:0], dbg3_rx_lock, rx3_eidle, c_swren, // [111:96]
`elsif FORCE_DET
        dbg_upar[5], dbg_upar[2], 2'b0, fd_st, dbg_rxdet, fd_detrx, c_swren, // [111:96]
`else
        dbg_upar[5], dbg_upar[2], 6'b0, c_swren,                // [111:96] (upar diag: ready levels, master writes)
`endif
        cnt_trans,                                              // [95:88]
        1'b0, dev_address,                                      // [87:80]
        dbg_cmu_ok, dbg_rx_lock, power_present, rx_elecidle, phy_status, rx_status, // [79:72]
        dbg_rstn, dbg_lane_stat[1:0], st_max,                   // [71:64]
        dbg_lane_stat[4:2], ltssm_state,                        // [63:56]
        dbg_lane_stat[5], power_down, tx_elecidle, tx_detectrx, rx_termination, rx_polarity, rx_valid, // [55:48]
        dev_configured, link_configured, in_u0, prst};          // [47:44]
    always @(posedge pclk) begin snap_div <= snap_div + 10'd1; if (&snap_div) snap <= live; end

    // pclk frequency: pclk / 16 edges per 2^22 osc cycles
    reg [3:0] pdiv = 4'd0 /* synthesis syn_preserve=1 */;
    always @(posedge pclk) pdiv <= pdiv + 4'd1;
    reg [2:0] pds = 3'd0; reg [21:0] gate = 22'd0; reg [19:0] pn = 20'd0, pf = 20'd0;
    always @(posedge osc) begin
        pds <= {pds[1:0], pdiv[3]}; gate <= gate + 22'd1;
        if (&gate) begin pf <= pn; pn <= 20'd0; end
        else if (pds[1] && !pds[2]) pn <= pn + 20'd1;
    end
    reg [31:0] up = 32'd0; reg [15:0] upl = 16'd0;
    always @(posedge osc) begin upl <= upl + 16'd1; if (&upl) up <= up + 32'd1; end
    reg [5:0] pads_s = 6'd0;
    always @(posedge osc) pads_s <= dbg_astat;   // lane analog status (Console: SerDes lane 2 debug)

`ifdef LFPS_DIAG
    // LFPS_DIAG=1: saturating counters of pclk cycles in which the receive indications were active
    // (PHY RxElecIdle low, quad rxelecidle_o high, rx_vld_out high, astat[0] / astat[5] high): 0 = never seen
    reg [10:0] ed_duty = 11'd0; reg [4:0] ed_s = 5'd0;   // (syn_preserve: GowinSynthesis merges same-shaped counters of other clocks into these)
    reg [15:0] ed_ei = 16'd0 /* synthesis syn_preserve=1 */, ed_eih = 16'd0 /* synthesis syn_preserve=1 */, ed_vld = 16'd0 /* synthesis syn_preserve=1 */, ed_a0 = 16'd0 /* synthesis syn_preserve=1 */, ed_a5 = 16'd0 /* synthesis syn_preserve=1 */;
    always @(posedge pclk) begin
        ed_s <= {dbg_astat[5], dbg_astat[0], dbg_ei[2], dbg_ei[0], !rx_elecidle};
        if (ed_s[0] && !(&ed_ei)) ed_ei <= ed_ei + 16'd1;
        if (ed_s[1] && !(&ed_eih)) ed_eih <= ed_eih + 16'd1;
        // ed_vld: duty of the quad signal detect (rxelecidle_o) in the last snapshot window, cycles high per 1024
        if (&snap_div) begin ed_vld <= {5'd0, ed_duty}; ed_duty <= 11'd0; end else if (ed_s[1]) ed_duty <= ed_duty + 11'd1;
        if (ed_s[3] && !(&ed_a0)) ed_a0 <= ed_a0 + 16'd1;
        if (ed_s[4] && !(&ed_a5)) ed_a5 <= ed_a5 + 16'd1;
    end
`endif
    // ---------------------------------------------------------------- receive-side counters (pclk)
    // K28.5 symbols (COM), decode errors (RxStatus 4) and disparity errors (RxStatus 7). (The
    // Polling-time statistics and the Polling.Config capture that found the bring-up problems were
    // removed again: the device sits at 83 % of the CLSs and the debug logic cost pclk timing.)
    reg [15:0] cnt_com = 16'd0, cnt_dec = 16'd0, cnt_disp = 16'd0;
    wire [3:0] com_k = {rx_k[3] && rx_data[31:24] == 8'hBC, rx_k[2] && rx_data[23:16] == 8'hBC,
                        rx_k[1] && rx_data[15:8] == 8'hBC, rx_k[0] && rx_data[7:0] == 8'hBC};
    always @(posedge pclk) begin
        if (rx_valid && |com_k) cnt_com <= cnt_com + 16'd1;
        if (rx_status == 3'd4) cnt_dec <= cnt_dec + 16'd1;
        if (rx_status == 3'd7) cnt_disp <= cnt_disp + 16'd1;
    end

    // [15:0] magic, [16] ref_lock, [17] phy_resetn, [23:18] USB 2.0 pads {cdn, cdp, tdn, tdp, dxn, dxp},
    // [43:24] pclk / 16 edges per 2^22 osc, [351:44] pclk snapshot, [383:352] uptime (2^16 osc),
    // [399:384] COM count, [415:400] decode errors, [431:416] disparity errors (pclk, sampled as is)
`ifdef LFPS_DIAG
    wire [431:0] cap = {ed_a5, ed_a0, ed_vld, up, snap, pf, pads_s, phy_resetn, ref_lock, 16'h5B31};
`else
    wire [431:0] cap = {cnt_disp, cnt_dec, cnt_com, up, snap, pf, pads_s, phy_resetn, ref_lock, 16'h5B31};
`endif
    // ---------------------------------------------------------------- packet trace (ER2)
    // 1024 pclk words of {RxStatus, RxValid, RxDataK, RxData, TxDataK, TxData} in a ring that runs
    // until a trigger, then 'post' more words and frozen; the write pointer is then the oldest entry.
    // Trigger modes (ER2 write with bit 30 = re-arm, bits 29:28 = mode; default mode 1 after reset):
    //   0: the header after the first data packet header in U0 (a SETUP's next stage), 768 after it
    //   1: U0 -> Recovery.Active, 256 after it (768 words of U0 traffic before the link dropped)
    //   2: a data packet payload with a bad CRC-32 / framing (Usb3Top o_dpp_err), 256 after it
    //   3: Usb3Device o_dbg_event (an EP1 IN ACK ignored / with Retry, a response lost), 256 after
    //      it; the header log then runs as a ring of EP1 IN headers only and stops 64 entries after it
    wire        w2; wire [30:0] w2_data;
    reg  [1:0]  tmode = 2'd1;
    reg         rearm_t = 1'b0;            // osc toggle -> pclk
    always @(posedge osc) if (w2 && w2_data[30]) begin tmode <= w2_data[29:28]; rearm_t <= ~rearm_t; end
    reg  [2:0]  rearm_s = 3'd0;
    always @(posedge pclk) rearm_s <= {rearm_s[1:0], rearm_t};
    wire        rearm = rearm_s[2] != rearm_s[1];
    reg  [1:0]  tmode_p = 2'd1;
    reg         dph_seen = 1'b0;
    reg  [4:0]  st_q = 5'd0;
    always @(posedge pclk) begin
        st_q <= ltssm_state;
        if (rearm) begin dph_seen <= 1'b0; tmode_p <= tmode; end
        else if (rx_hp_valid && rx_hp_hdr[4:0] == 5'h08) dph_seen <= 1'b1;
    end
    wire t_ev = tmode_p == 2'd0 ? (rx_hp_valid && dph_seen) :
                tmode_p == 2'd2 ? dpp_err :
                                  dbg_event;
    wire [9:0] t_post = tmode_p == 2'd0 ? 10'd767 : 10'd255;
    reg  [75:0] tbuf [0:1023];
    reg  [9:0]  twp = 10'd0, tpost = 10'd0;
    reg         ttrig = 1'b0, tfull = 1'b0;
    always @(posedge pclk) begin
        if (rearm) begin ttrig <= 1'b0; tfull <= 1'b0; tpost <= 10'd0; end
        else if (!tfull) begin
            tbuf[twp] <= {rx_status, rx_valid, rx_k, rx_data, tx_k, tx_data};
            twp <= twp + 10'd1;
            if (ttrig) begin tpost <= tpost + 10'd1; if (tpost == t_post) tfull <= 1'b1; end
            else if (t_ev) ttrig <= 1'b1;
        end
    end
    // header log: every header packet received (rx_hp_valid) or handed to the link for
    // transmission, from the first U0 entry: 128 entries of {dir (1 = tx), 24-bit pclk timestamp
    // (wraps every 134 ms), header DW2..DW0}, then frozen
    reg  [120:0] hlog [0:127];
    reg  [7:0]   hwp = 8'd0;
    reg  [23:0]  hts = 24'd0;
    reg          hrun = 1'b0, hwrap = 1'b0, htrig = 1'b0, hfrz = 1'b0;
    reg  [6:0]   hpost = 7'd0;
    wire         hring = tmode_p == 2'd3;     // ring mode: frozen 64 entries after the trigger
    // ITPs (every 125 us) are not logged; in ring mode only EP1 IN traffic (DW1 direction 1, endpoint 1)
    wire         hin_rx = rx_hp_hdr[39] && rx_hp_hdr[43:40] == 4'd1;
    wire         hin_tx = tx_hp_hdr[39] && tx_hp_hdr[43:40] == 4'd1;
    wire         hev_rx = rx_hp_valid && rx_hp_hdr[4:0] != 5'h0C && (!hring || hin_rx);
    wire         hev_tx = tx_hp_valid && tx_hp_ready && (!hring || hin_tx);
    always @(posedge pclk) begin
        hts <= hts + 24'd1;
        if (in_u0) hrun <= 1'b1;
        if (rearm) begin hwp <= 8'd0; hrun <= in_u0; hwrap <= 1'b0; htrig <= 1'b0; hfrz <= 1'b0; hpost <= 7'd0; end
        else begin
            if (hring && t_ev) htrig <= 1'b1;
            // ring mode also logs Usb3Device's EP1 IN state at every ACK it handles / packet it issues:
            // an entry of type 5'h1F with the state in DW1
            if (hrun && !hfrz && (hring || !hwp[7]) && (hev_rx || hev_tx || (hring && dbg_strobe))) begin
                hlog[hwp[6:0]] <= hev_rx ? {1'b0, hts, rx_hp_hdr} : (hring && dbg_strobe) ? {1'b1, hts, dbg_state, 32'h1F} :
                                  {1'b1, hts, tx_hp_hdr};
                hwp <= {1'b0, hwp[6:0] + 7'd1} | {hring ? 1'b0 : hwp[6:0] == 7'd127, 7'd0};
                if (hring && hwp[6:0] == 7'd127) hwrap <= 1'b1;
                if (hring && htrig) begin hpost <= hpost + 7'd1; if (hpost == 7'd63) hfrz <= 1'b1; end
            end
        end
    end
    reg  [10:0] tidx = 11'd0;          // [10] = 1: header log entry tidx[6:0], else trace entry
    reg  [120:0] tq = 121'd0;
    reg  [10:0] tq_idx = 11'd0;
    always @(posedge osc) begin
        if (w2 && !w2_data[30]) tidx <= w2_data[10:0];
        tq <= tidx[10] ? hlog[tidx[6:0]] : {45'd0, tbuf[tidx[9:0]]};   // static once full
        tq_idx <= tidx;
    end
    // ER2 (192 bits): [15:0] magic 0x5B33, [16] triggered, [17] full, [27:18] trace write pointer,
    // [38:28] index shown, [159:39] entry, [167:160] header log write pointer / count (128 = full),
    // [169:168] trigger mode, [170] header log wrapped (ring mode: oldest = pointer), [171] header log frozen
    wire [191:0] cap2 = {20'd0, hfrz, hwrap, tmode_p, hwp, tq, tq_idx, twp, tfull, ttrig, 16'h5B33};

    jtag_status #(.L(432), .L2(192)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap(cap), .cap2(cap2), .o_w2(w2), .o_w2_data(w2_data));


    // ---------------------------------------------------------------- UART status line once per second
    // "U3 st=<ltssm> max=<st_max> u0=<cnt_u0> hp=<cnt_hp> rst=<cnt_reset> cfg=<link,dev>\r\n"
    wire tx_ready;
    reg  utx_valid = 0;
    reg  [7:0] utx_data = 0;
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(434)) u_uart (
        .clock(sys_clk), .reset(rst), .data_valid(utx_valid), .data_ready(tx_ready), .data_bits(utx_data), .tx(uart_tx));
    reg [25:0] sec_cnt = 0; reg gate_t = 0;
    always @(posedge sys_clk) begin
        if (sec_cnt == 26'd49_999_999) begin sec_cnt <= 0; gate_t <= ~gate_t; end
        else sec_cnt <= sec_cnt + 1;
    end
    function [7:0] hexc(input [3:0] v); hexc = v < 10 ? "0" + v : "A" + v - 10; endfunction
    reg [5:0] mpos = 6'd63;
    reg [63:0] usnap = 0;
    reg [7:0] mchar;
    always @(*) begin
        case (mpos)
            0: mchar = "U"; 1: mchar = "3"; 2: mchar = " "; 3: mchar = "s"; 4: mchar = "t"; 5: mchar = "=";
            6: mchar = hexc(usnap[7:4]); 7: mchar = hexc(usnap[3:0]); 8: mchar = " "; 9: mchar = "m"; 10: mchar = "x"; 11: mchar = "=";
            12: mchar = hexc(usnap[15:12]); 13: mchar = hexc(usnap[11:8]); 14: mchar = " "; 15: mchar = "u"; 16: mchar = "0"; 17: mchar = "=";
            18: mchar = hexc(usnap[31:28]); 19: mchar = hexc(usnap[27:24]); 20: mchar = hexc(usnap[23:20]); 21: mchar = hexc(usnap[19:16]);
            22: mchar = " "; 23: mchar = "h"; 24: mchar = "p"; 25: mchar = "=";
            26: mchar = hexc(usnap[47:44]); 27: mchar = hexc(usnap[43:40]); 28: mchar = hexc(usnap[39:36]); 29: mchar = hexc(usnap[35:32]);
            30: mchar = " "; 31: mchar = "r"; 32: mchar = "s"; 33: mchar = "t"; 34: mchar = "=";
            35: mchar = hexc(usnap[55:52]); 36: mchar = hexc(usnap[51:48]);
            37: mchar = " "; 38: mchar = "c"; 39: mchar = "f"; 40: mchar = "g"; 41: mchar = "=";
            42: mchar = "0" + usnap[57]; 43: mchar = "0" + usnap[56];
            44: mchar = "\r"; 45: mchar = "\n";
            default: mchar = " ";
        endcase
    end
    reg gate_q = 0;
    always @(posedge sys_clk) begin
        gate_q <= gate_t;
        if (utx_valid && tx_ready) begin utx_valid <= 0; mpos <= mpos + 1; end
        else if (mpos < 46 && !utx_valid) begin utx_data <= mchar; utx_valid <= 1; end
        if (gate_q != gate_t && mpos >= 46) begin
            usnap <= {6'b0, link_configured, dev_configured, 4'h0, cnt_reset[11:0], cnt_hp, cnt_u0, 3'b0, st_max, 3'b0, ltssm_state};
            mpos <= 0;
        end
    end
endmodule
`default_nettype wire
