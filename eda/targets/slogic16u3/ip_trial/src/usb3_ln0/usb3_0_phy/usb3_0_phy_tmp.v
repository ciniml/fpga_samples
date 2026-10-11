//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.03
//Part Number: GW5AT-LV15MG132C1/I0
//Device: GW5AT-15
//Device Version: A
//Created Time: Sun Oct 11 13:39:40 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	USB3_0_PHY_Top your_instance_name(
		.phy_resetn(phy_resetn), //input phy_resetn
		.ref_clk(ref_clk), //input ref_clk
		.pclk(pclk), //output pclk
		.PipeTxData(PipeTxData), //input [31:0] PipeTxData
		.PipeTxDataK(PipeTxDataK), //input [3:0] PipeTxDataK
		.PipeRxData(PipeRxData), //output [31:0] PipeRxData
		.PipeRxDataK(PipeRxDataK), //output [3:0] PipeRxDataK
		.PipeRxDataValid(PipeRxDataValid), //output PipeRxDataValid
		.TxDetectRx_loopback(TxDetectRx_loopback), //input TxDetectRx_loopback
		.TxElecIdle(TxElecIdle), //input TxElecIdle
		.RxPolarity(RxPolarity), //input RxPolarity
		.RxEqTraining(RxEqTraining), //input RxEqTraining
		.RxTermination(RxTermination), //input RxTermination
		.RxElecIdle(RxElecIdle), //output RxElecIdle
		.RxStatus(RxStatus), //output [2:0] RxStatus
		.TxOnesZeros(TxOnesZeros), //input TxOnesZeros
		.PowerDown(PowerDown), //input [1:0] PowerDown
		.PhyStatus(PhyStatus), //output PhyStatus
		.PowerPresent(PowerPresent), //output PowerPresent
		.ElasticityBufferMode(ElasticityBufferMode), //input ElasticityBufferMode
		.serdes_upar_clk_i(serdes_upar_clk_i), //input serdes_upar_clk_i
		.serdes_upar_wren_o(serdes_upar_wren_o), //output serdes_upar_wren_o
		.serdes_upar_addr_o(serdes_upar_addr_o), //output [23:0] serdes_upar_addr_o
		.serdes_upar_wrdata_o(serdes_upar_wrdata_o), //output [31:0] serdes_upar_wrdata_o
		.serdes_upar_rden_o(serdes_upar_rden_o), //output serdes_upar_rden_o
		.serdes_upar_resp_i(serdes_upar_resp_i), //input serdes_upar_resp_i
		.serdes_upar_strb_o(serdes_upar_strb_o), //output [7:0] serdes_upar_strb_o
		.serdes_upar_rddata_i(serdes_upar_rddata_i), //input [31:0] serdes_upar_rddata_i
		.serdes_upar_rdvld_i(serdes_upar_rdvld_i), //input serdes_upar_rdvld_i
		.serdes_upar_ready_i(serdes_upar_ready_i), //input serdes_upar_ready_i
		.serdes_q0_qpll0_ok_i(serdes_q0_qpll0_ok_i), //input serdes_q0_qpll0_ok_i
		.serdes_q0_qpll1_ok_i(serdes_q0_qpll1_ok_i), //input serdes_q0_qpll1_ok_i
		.serdes_q1_qpll0_ok_i(serdes_q1_qpll0_ok_i), //input serdes_q1_qpll0_ok_i
		.serdes_q1_qpll1_ok_i(serdes_q1_qpll1_ok_i), //input serdes_q1_qpll1_ok_i
		.serdes_cpll_ok_i(serdes_cpll_ok_i), //input serdes_cpll_ok_i
		.serdes_fabric_rstn_o(serdes_fabric_rstn_o), //output serdes_fabric_rstn_o
		.serdes_pcs_tx_clk_i(serdes_pcs_tx_clk_i), //input serdes_pcs_tx_clk_i
		.serdes_fabric_tx_clk_o(serdes_fabric_tx_clk_o), //output serdes_fabric_tx_clk_o
		.serdes_pcs_tx_rst_o(serdes_pcs_tx_rst_o), //output serdes_pcs_tx_rst_o
		.serdes_fabric_tx_vld_o(serdes_fabric_tx_vld_o), //output serdes_fabric_tx_vld_o
		.serdes_tx_fifo_wrusewd_i(serdes_tx_fifo_wrusewd_i), //input [4:0] serdes_tx_fifo_wrusewd_i
		.serdes_txdata_o(serdes_txdata_o), //output [79:0] serdes_txdata_o
		.serdes_pcs_rx_clk_i(serdes_pcs_rx_clk_i), //input serdes_pcs_rx_clk_i
		.serdes_fabric_rx_clk_o(serdes_fabric_rx_clk_o), //output serdes_fabric_rx_clk_o
		.serdes_pma_rx_lock_i(serdes_pma_rx_lock_i), //input serdes_pma_rx_lock_i
		.serdes_pcs_rx_rst_o(serdes_pcs_rx_rst_o), //output serdes_pcs_rx_rst_o
		.serdes_rxfifo_rd_en_o(serdes_rxfifo_rd_en_o), //output serdes_rxfifo_rd_en_o
		.serdes_rxfifo_aempty_i(serdes_rxfifo_aempty_i), //input serdes_rxfifo_aempty_i
		.serdes_rx_fifo_rdusewd_i(serdes_rx_fifo_rdusewd_i), //input [4:0] serdes_rx_fifo_rdusewd_i
		.serdes_rxdata_i(serdes_rxdata_i), //input [87:0] serdes_rxdata_i
		.serdes_rx_vld_i(serdes_rx_vld_i), //input serdes_rx_vld_i
		.serdes_rxelecidle_i(serdes_rxelecidle_i), //input serdes_rxelecidle_i
		.serdes_astat_i(serdes_astat_i) //input [5:0] serdes_astat_i
	);

//--------Copy end-------------------
