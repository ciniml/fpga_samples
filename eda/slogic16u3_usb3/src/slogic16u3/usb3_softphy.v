// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// OWNPHY=1: our USB 3.0 PHY in place of Gowin's USB 3.0 PHY soft IP. project.tcl copies the IP's
// serdes.v and swaps the module of USB3_0_PHY_Top_inst for this one (same ports, plus the quad's
// rxdet_result pin, which the IP leaves unconnected); the GTR12 quad, its CSR and the upar arbiter
// stay as generated. The parts are in rtl/usb3 (Veryl): Usb3PhyTx (8b/10b, LFPS square wave),
// Usb3PhyRx (alignment, decoding, SKP removal), Usb3PhyEb (elastic buffer), Usb3PhyCtl /
// Usb3PhyDrp (PhyStatus, receiver detection and the DRP writes seen with TAP=1, see the README).
//
// Clocks (as the IP has them, TAP=1): pclk = the lane's PCS TX clock, which also writes the transmit
// data; the receive FIFO of the quad is read in the lane's recovered clock (PCS RX), the elastic
// buffer goes from there to pclk; the DRP channel runs in the arbiter's clock.
module usb3_softphy (
    input  wire        phy_resetn,
    input  wire        ref_clk,
    output wire        pclk,
    input  wire [31:0] PipeTxData,
    input  wire [3:0]  PipeTxDataK,
    output wire [31:0] PipeRxData,
    output wire [3:0]  PipeRxDataK,
    output wire        PipeRxDataValid,
    input  wire        TxDetectRx_loopback,
    input  wire        TxElecIdle,
    input  wire        RxPolarity,
    input  wire        RxEqTraining,
    input  wire        RxTermination,
    output wire        RxElecIdle,
    output wire [2:0]  RxStatus,
    input  wire        TxOnesZeros,
    input  wire [1:0]  PowerDown,
    output wire        PhyStatus,
    output wire        PowerPresent,
    input  wire        ElasticityBufferMode,
    input  wire        serdes_upar_clk_i,
    output wire        serdes_upar_wren_o,
    output wire [23:0] serdes_upar_addr_o,
    output wire [31:0] serdes_upar_wrdata_o,
    output wire        serdes_upar_rden_o,
    input  wire        serdes_upar_resp_i,
    output wire [7:0]  serdes_upar_strb_o,
    input  wire [31:0] serdes_upar_rddata_i,
    input  wire        serdes_upar_rdvld_i,
    input  wire        serdes_upar_ready_i,
    input  wire        serdes_q0_qpll0_ok_i,
    input  wire        serdes_q0_qpll1_ok_i,
    input  wire        serdes_q1_qpll0_ok_i,
    input  wire        serdes_q1_qpll1_ok_i,
    input  wire        serdes_cpll_ok_i,
    output wire        serdes_fabric_rstn_o,
    input  wire        serdes_pcs_tx_clk_i,
    output wire        serdes_fabric_tx_clk_o,
    output wire        serdes_pcs_tx_rst_o,
    output wire        serdes_fabric_tx_vld_o,
    input  wire [4:0]  serdes_tx_fifo_wrusewd_i,
    output wire [79:0] serdes_txdata_o,
    input  wire        serdes_pcs_rx_clk_i,
    output wire        serdes_fabric_rx_clk_o,
    input  wire        serdes_pma_rx_lock_i,
    output wire        serdes_pcs_rx_rst_o,
    output wire        serdes_rxfifo_rd_en_o,
    input  wire        serdes_rxfifo_aempty_i,
    input  wire [4:0]  serdes_rx_fifo_rdusewd_i,
    input  wire [87:0] serdes_rxdata_i,
    input  wire        serdes_rx_vld_i,
    input  wire        serdes_rxelecidle_i,
    input  wire [5:0]  serdes_astat_i,
    input  wire        serdes_rxdet_result_i
);
    wire rclk = serdes_pcs_rx_clk_i;
    wire dclk = serdes_upar_clk_i;
    assign pclk = serdes_pcs_tx_clk_i;
    // (the IP's port names are from its side: its "fabric_tx_clk" clocks the quad's receive FIFO read,
    // its "fabric_rx_clk" the transmit data; the net names in serdes.v say so)
    assign serdes_fabric_tx_clk_o = rclk;
    assign serdes_fabric_rx_clk_o = pclk;
    assign serdes_fabric_rstn_o = phy_resetn;
    assign serdes_pcs_tx_rst_o = !phy_resetn;
    assign serdes_pcs_rx_rst_o = !phy_resetn;
    assign PowerPresent = 1'b1;

    // resets, released synchronously in each domain
    reg [3:0] prs = 4'hF, rrs = 4'hF, drs = 4'hF;
    always @(posedge pclk or negedge phy_resetn) if (!phy_resetn) prs <= 4'hF; else prs <= {prs[2:0], 1'b0};
    always @(posedge rclk or negedge phy_resetn) if (!phy_resetn) rrs <= 4'hF; else rrs <= {rrs[2:0], 1'b0};
    always @(posedge dclk or negedge phy_resetn) if (!phy_resetn) drs <= 4'hF; else drs <= {drs[2:0], 1'b0};
    wire prst = prs[3], rrst = rrs[3], drst = drs[3];

    // ---- transmit (pclk)
    wire [39:0] txd;
    wire drive, lfps;
    Usb3PhyTx u_tx (.i_clk(pclk), .i_rst(prst), .i_data(PipeTxData), .i_k(PipeTxDataK), .i_elecidle(TxElecIdle),
        .i_detectrx(TxDetectRx_loopback), .i_power_down(PowerDown), .o_txdata(txd), .o_drive(drive), .o_lfps(lfps));
    assign serdes_txdata_o = {40'd0, txd};
    assign serdes_fabric_tx_vld_o = !prst;

    // ---- receive (rclk)
    reg rden = 1'b0;
    always @(posedge rclk) rden <= !rrst && !serdes_rxfifo_aempty_i;
    assign serdes_rxfifo_rd_en_o = rden;
    wire rxv, locked, whigh;
    wire [31:0] rxd; wire [3:0] rxk; wire [2:0] rxst;
    Usb3PhyRx u_rx (.i_clk(rclk), .i_rst(rrst), .i_rxdata(serdes_rxdata_i[39:0]), .i_valid(serdes_rx_vld_i),
        .i_polarity(RxPolarity), .i_drop(whigh), .o_valid(rxv), .o_data(rxd), .o_k(rxk), .o_status(rxst), .o_locked(locked));
    wire rv; wire [38:0] rword;
    Usb3PhyEb u_eb (.i_wclk(rclk), .i_wrst(rrst), .i_wv(rxv), .i_wdata({rxst, rxk, rxd}), .o_whigh(whigh),
        .i_rclk(pclk), .i_rrst(prst), .i_run(PowerDown == 2'd0), .o_rv(rv), .o_rdata(rword));

    // ---- control (pclk) and the register port (dclk)
    wire det_req, det_done, det_res, phy_status;
    wire [2:0] det_status;
    Usb3PhyCtl u_ctl (.i_clk(pclk), .i_rst(prst), .i_power_down(PowerDown), .i_elecidle(TxElecIdle),
        .i_detectrx(TxDetectRx_loopback), .i_sig(serdes_rxelecidle_i), .i_rx_good(rv && rword[38:36] != 3'd4 && rword[38:36] != 3'd7), .i_det_done(det_done), .i_det_res(det_res),
        .o_det_req(det_req), .o_phy_status(phy_status), .o_det_status(det_status), .o_rx_elecidle(RxElecIdle));
    Usb3PhyDrp u_drp (.i_clk(dclk), .i_rst(drst), .i_drive(drive), .i_power_down(PowerDown), .i_det_req(det_req),
        .i_rxdet(serdes_rxdet_result_i), .o_det_done(det_done), .o_det_res(det_res), .o_rd_last(),
        .o_wren(serdes_upar_wren_o), .o_rden(serdes_upar_rden_o), .o_addr(serdes_upar_addr_o),
        .o_wrdata(serdes_upar_wrdata_o), .o_strb(serdes_upar_strb_o),
        .i_ready(serdes_upar_ready_i), .i_rdvld(serdes_upar_rdvld_i), .i_rddata(serdes_upar_rddata_i));

    // registered outputs (the elastic buffer's read data otherwise runs on into the link layer's
    // descrambler in the same clock)
    reg        o_physt = 1'b0, o_rv = 1'b0;
    reg [31:0] o_d = 32'd0;
    reg [3:0]  o_k = 4'd0;
    reg [2:0]  o_st = 3'd0;
    always @(posedge pclk) begin
        o_physt <= phy_status;
        o_rv    <= rv;
        o_d     <= rv ? rword[31:0] : 32'd0;
        o_k     <= rv ? rword[35:32] : 4'd0;
        o_st    <= phy_status ? det_status : (rv ? rword[38:36] : 3'd0);
    end
    assign PhyStatus = o_physt;
    assign PipeRxDataValid = o_rv;
    assign PipeRxData = o_d;
    assign PipeRxDataK = o_k;
    assign RxStatus = o_st;
endmodule
