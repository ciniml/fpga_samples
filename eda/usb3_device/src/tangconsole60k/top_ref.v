// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Tang Console 60K, REF=1 cross-check: Gowin's reference USB 3.0 device controller
// (eda/targets/tangconsole60k/doc/gowin_usb3_ref) on the same SerDes Q0 Lane2 PHY IP, with the
// JTAG ER1 status of eda/slogic16u3_usb3/host/usb3_ref_status.py.
`default_nettype none
module top (
    input  wire sys_clk,
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,
    output wire uart_tx,
    input  wire uart_rx
);
    wire osc = sys_clk;
    assign uart_tx = 1'b1;
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


    wire pclk /* synthesis syn_keep = 1 */;
    reg [7:0] cnt0 = 8'd0;
    reg phy_resetn = 1'b0, sys_rst_n = 1'b0;
    always @(posedge pclk) begin
        if (cnt0 < 8'd255) cnt0 <= cnt0 + 8'd1;
        phy_resetn <= cnt0 == 8'd255;
        sys_rst_n  <= cnt0 == 8'd255;
    end

    wire phy_resetn_o;
    wire [31:0] phy_pipe_rx_data, phy_pipe_tx_data; wire [3:0] phy_pipe_rx_datak, phy_pipe_tx_datak;
    wire phy_pipe_rx_valid, phy_tx_detrx_lpbk, phy_tx_elecidle, phy_rx_elecidle, phy_phy_status, phy_pwrpresent;
    wire [2:0] phy_rx_status; wire [1:0] phy_power_down, phy_tx_deemph; wire [2:0] phy_tx_margin;
    wire phy_tx_oneszeros, phy_tx_swing, phy_rx_polarity, phy_rx_termination, phy_rate, phy_elas_buf_mode;
    SerDes_Top u_serdes (
        .USB3_0_PHY_Top_ref_clk(ref_clk), .USB3_0_PHY_Top_pclk(pclk),
        .USB3_0_PHY_Top_PipeRxData(phy_pipe_rx_data), .USB3_0_PHY_Top_PipeRxDataK(phy_pipe_rx_datak),
        .USB3_0_PHY_Top_PipeRxDataValid(phy_pipe_rx_valid), .USB3_0_PHY_Top_RxElecIdle(phy_rx_elecidle),
        .USB3_0_PHY_Top_RxStatus(phy_rx_status), .USB3_0_PHY_Top_PhyStatus(phy_phy_status),
        .USB3_0_PHY_Top_PowerPresent(phy_pwrpresent), .USB3_0_PHY_Top_phy_resetn(phy_resetn_o),
        .USB3_0_PHY_Top_PipeTxData(phy_pipe_tx_data), .USB3_0_PHY_Top_PipeTxDataK(phy_pipe_tx_datak),
        .USB3_0_PHY_Top_TxDetectRx_loopback(phy_tx_detrx_lpbk), .USB3_0_PHY_Top_TxElecIdle(phy_tx_elecidle),
        .USB3_0_PHY_Top_RxPolarity(phy_rx_polarity), .USB3_0_PHY_Top_RxEqTraining(1'b0),
        .USB3_0_PHY_Top_RxTermination(phy_rx_termination), .USB3_0_PHY_Top_TxOnesZeros(phy_tx_oneszeros),
        .USB3_0_PHY_Top_PowerDown(phy_power_down), .USB3_0_PHY_Top_ElasticityBufferMode(phy_elas_buf_mode));

    wire request_active, warm_or_hot_reset, host_requests_data_from_endpt, itp_received, attached;
    wire [7:0] bmRequestType, bRequest; wire [15:0] wValue, wIndex, wLength; wire [3:0] host_requests_endpt_num;
    wire        transfer_in_mem_wr          [0:15];
    wire [3:0]  transfer_in_mem_wr_mask     [0:15];
    wire [13:0] transfer_in_mem_wr_addr     [0:15];
    wire [31:0] transfer_in_mem_wr_data     [0:15];
    wire        transfer_in_mem_commit      [0:15];
    wire [15:0] transfer_in_mem_commit_len  [0:15];
    wire        transfer_in_mem_ready       [0:15];
    wire        transfer_in_done            [0:15];
    wire        transfer_in_mem_empty       [0:15];
    wire        transfer_out_mem_has_data   [0:15];
    wire [15:0] transfer_out_mem_len        [0:15];
    wire [13:0] transfer_out_mem_rd_addr    [0:15];
    wire [31:0] transfer_out_mem_rd_data    [0:15];
    wire        transfer_out_mem_clr        [0:15];
    USB30_Device_Controller_Top u_ctl (
        .phy_clk_i(pclk), .reset_n_i(phy_resetn),
        .phy_pipe_rx_data_i(phy_pipe_rx_data), .phy_pipe_rx_datak_i(phy_pipe_rx_datak), .phy_pipe_rx_valid_i(phy_pipe_rx_valid),
        .phy_pipe_tx_data_o(phy_pipe_tx_data), .phy_pipe_tx_datak_o(phy_pipe_tx_datak), .phy_reset_n_o(phy_resetn_o),
        .phy_tx_detrx_lpbk_o(phy_tx_detrx_lpbk), .phy_tx_elecidle_o(phy_tx_elecidle), .phy_rx_elecidle_i(phy_rx_elecidle),
        .phy_rx_status_i(phy_rx_status), .phy_power_down_o(phy_power_down), .phy_phy_status_i(phy_phy_status),
        .phy_pwrpresent_i(phy_pwrpresent), .phy_tx_oneszeros_o(phy_tx_oneszeros), .phy_tx_deemph_o(phy_tx_deemph),
        .phy_tx_margin_o(phy_tx_margin), .phy_tx_swing_o(phy_tx_swing), .phy_rx_polarity_o(phy_rx_polarity),
        .phy_rx_termination_o(phy_rx_termination), .phy_rate_o(phy_rate), .phy_elas_buf_mode_o(phy_elas_buf_mode),
        .warm_or_hot_reset_o(warm_or_hot_reset), .host_requests_data_from_endpt_o(host_requests_data_from_endpt),
        .host_requests_endpt_num_o(host_requests_endpt_num), .itp_received_o(itp_received), .attached_o(attached),
        .request_active_o(request_active), .bmRequestType_o(bmRequestType), .bRequest_o(bRequest),
        .wValue_o(wValue), .wIndex_o(wIndex), .wLength_o(wLength),
        .transfer_in_mem_wr_i(transfer_in_mem_wr), .transfer_in_mem_wr_mask_i(transfer_in_mem_wr_mask),
        .transfer_in_mem_wr_addr_i(transfer_in_mem_wr_addr), .transfer_in_mem_wr_data_i(transfer_in_mem_wr_data),
        .transfer_in_mem_commit_i(transfer_in_mem_commit), .transfer_in_mem_commit_len_i(transfer_in_mem_commit_len),
        .transfer_in_mem_ready_o(transfer_in_mem_ready), .transfer_in_done_o(transfer_in_done),
        .transfer_in_mem_empty_o(transfer_in_mem_empty),
        .transfer_out_mem_has_data_o(transfer_out_mem_has_data), .transfer_out_mem_len_o(transfer_out_mem_len),
        .transfer_out_mem_rd_addr_i(transfer_out_mem_rd_addr), .transfer_out_mem_rd_data_o(transfer_out_mem_rd_data),
        .transfer_out_mem_clr_i(transfer_out_mem_clr));
    UserLayer_top u_user (
        .pclk(pclk), .clk_50m(osc), .phy_resetn(sys_rst_n || attached),
        .warm_or_hot_reset(warm_or_hot_reset), .host_requests_data_from_endpt(host_requests_data_from_endpt),
        .host_requests_endpt_num(host_requests_endpt_num), .itp_received(itp_received),
        .request_active(request_active), .bmRequestType(bmRequestType), .bRequest(bRequest),
        .wValue(wValue), .wIndex(wIndex), .wLength(wLength),
        .transfer_in_mem_wr(transfer_in_mem_wr), .transfer_in_mem_wr_mask(transfer_in_mem_wr_mask),
        .transfer_in_mem_wr_addr(transfer_in_mem_wr_addr), .transfer_in_mem_wr_data(transfer_in_mem_wr_data),
        .transfer_in_mem_commit(transfer_in_mem_commit), .transfer_in_mem_commit_len(transfer_in_mem_commit_len),
        .transfer_in_mem_ready(transfer_in_mem_ready), .transfer_in_done(transfer_in_done),
        .transfer_in_mem_empty(transfer_in_mem_empty),
        .transfer_out_mem_has_data(transfer_out_mem_has_data), .transfer_out_mem_len(transfer_out_mem_len),
        .transfer_out_mem_rd_addr(transfer_out_mem_rd_addr), .transfer_out_mem_rd_data(transfer_out_mem_rd_data),
        .transfer_out_mem_clr(transfer_out_mem_clr));

    // ---------------------------------------------------------------- PIPE statistics (pclk, snapshot every 1024)
    reg [31:0] c_cyc = 0, c_valid = 0, c_eidle = 0, c_txon = 0, c_lfps_tx = 0, c_com = 0;
    reg [15:0] c_physt = 0, c_dec = 0;
    wire [3:0] com_k = {phy_pipe_rx_datak[3] && phy_pipe_rx_data[31:24] == 8'hBC, phy_pipe_rx_datak[2] && phy_pipe_rx_data[23:16] == 8'hBC,
                        phy_pipe_rx_datak[1] && phy_pipe_rx_data[15:8] == 8'hBC, phy_pipe_rx_datak[0] && phy_pipe_rx_data[7:0] == 8'hBC};
    always @(posedge pclk) begin
        c_cyc <= c_cyc + 1;
        if (phy_pipe_rx_valid) c_valid <= c_valid + 1;
        if (phy_rx_elecidle) c_eidle <= c_eidle + 1;
        if (!phy_tx_elecidle) c_txon <= c_txon + 1;
        if (phy_tx_elecidle && phy_tx_detrx_lpbk && phy_power_down == 2'b00) c_lfps_tx <= c_lfps_tx + 1;
        if (phy_pipe_rx_valid && |com_k) c_com <= c_com + 1;
        if (phy_phy_status) c_physt <= c_physt + 1;
        if (phy_rx_status == 3'd4) c_dec <= c_dec + 1;
    end
    reg [9:0] sd = 0; reg [239:0] snap = 0;
    always @(posedge pclk) begin
        sd <= sd + 1;
        if (&sd) snap <= {c_dec, c_physt, c_com, c_lfps_tx, c_txon, c_eidle, c_valid, c_cyc[31:0],
                          4'd0, attached, phy_resetn_o, phy_power_down, phy_tx_elecidle, phy_tx_detrx_lpbk, phy_rx_elecidle, phy_pwrpresent, 4'd0};
    end
    // [15:0] magic 0x5B32, [255:16] snapshot
    jtag_status #(.L(256)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap({snap, 16'h5B32}), .cap2(128'd0), .o_w2(), .o_w2_data());
endmodule
`default_nettype wire
