// Cross-check build (REF=1): Gowin's USB 3.0 reference device controller (CDC/bulk reference design
// for the GW5AT-60, eda/targets/tangconsole60k/doc/gowin_usb3_ref, not part of this repository's
// sources) on the same USB 3.0 PHY IP (Q0 lane 0), clocks and pins as top.v. It tells a problem of
// rtl/usb3 apart from one of the board / PHY. JTAG ER1 (IR 0x42): 256 bits of PIPE statistics,
// see host/usb3_ref_status.py.
module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,
    input  wire usb_cmp_dp, input wire usb_cmp_dp_n, input wire usb_cmp_dn, input wire usb_cmp_dn_n,
    input  wire usb_dxp, input wire usb_dxn, input wire usb_tdp, input wire usb_tdn,
    output wire usb_pullup,
    output wire xo_en,
    output wire led_r
);
    wire osc;
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));
    assign xo_en = 1'b1;
    assign usb_pullup = 1'b0;
    wire cmp_dp, cmp_dn;
    TLVDS_IBUF u_cmp_dp (.I(usb_cmp_dp), .IB(usb_cmp_dp_n), .O(cmp_dp));
    TLVDS_IBUF u_cmp_dn (.I(usb_cmp_dn), .IB(usb_cmp_dn_n), .O(cmp_dn));
    wire ref_clk /* synthesis syn_keep=1 */, ref_lock;
    pll_ref125 u_pll (.lock(ref_lock), .clkout0(ref_clk), .clkin(osc));

    // as the reference top: 256 pclk after start, the controller leaves reset and drives the PHY reset
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
    reg [26:0] blink = 0; always @(posedge pclk) blink <= blink + 1;
    assign led_r = attached | blink[26];
endmodule
