//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12
//Part Number: GW5AT-LV60PG484AC1/I0
//Device: GW5AT-60
//Device Version: B
//Created Time: Fri Oct  9 19:05:04 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    SerDes_Top your_instance_name(
        .Customized_PHY_Top_q0_ln1_rx_pcs_clkout_o(Customized_PHY_Top_q0_ln1_rx_pcs_clkout_o), //output Customized_PHY_Top_q0_ln1_rx_pcs_clkout_o
        .Customized_PHY_Top_q0_ln1_rx_data_o(Customized_PHY_Top_q0_ln1_rx_data_o), //output [87:0] Customized_PHY_Top_q0_ln1_rx_data_o
        .Customized_PHY_Top_q0_ln1_rx_fifo_rdusewd_o(Customized_PHY_Top_q0_ln1_rx_fifo_rdusewd_o), //output [4:0] Customized_PHY_Top_q0_ln1_rx_fifo_rdusewd_o
        .Customized_PHY_Top_q0_ln1_rx_fifo_aempty_o(Customized_PHY_Top_q0_ln1_rx_fifo_aempty_o), //output Customized_PHY_Top_q0_ln1_rx_fifo_aempty_o
        .Customized_PHY_Top_q0_ln1_rx_fifo_empty_o(Customized_PHY_Top_q0_ln1_rx_fifo_empty_o), //output Customized_PHY_Top_q0_ln1_rx_fifo_empty_o
        .Customized_PHY_Top_q0_ln1_rx_valid_o(Customized_PHY_Top_q0_ln1_rx_valid_o), //output Customized_PHY_Top_q0_ln1_rx_valid_o
        .Customized_PHY_Top_q0_ln1_tx_pcs_clkout_o(Customized_PHY_Top_q0_ln1_tx_pcs_clkout_o), //output Customized_PHY_Top_q0_ln1_tx_pcs_clkout_o
        .Customized_PHY_Top_q0_ln1_tx_fifo_wrusewd_o(Customized_PHY_Top_q0_ln1_tx_fifo_wrusewd_o), //output [4:0] Customized_PHY_Top_q0_ln1_tx_fifo_wrusewd_o
        .Customized_PHY_Top_q0_ln1_tx_fifo_afull_o(Customized_PHY_Top_q0_ln1_tx_fifo_afull_o), //output Customized_PHY_Top_q0_ln1_tx_fifo_afull_o
        .Customized_PHY_Top_q0_ln1_tx_fifo_full_o(Customized_PHY_Top_q0_ln1_tx_fifo_full_o), //output Customized_PHY_Top_q0_ln1_tx_fifo_full_o
        .Customized_PHY_Top_q0_ln1_refclk_o(Customized_PHY_Top_q0_ln1_refclk_o), //output Customized_PHY_Top_q0_ln1_refclk_o
        .Customized_PHY_Top_q0_ln1_signal_detect_o(Customized_PHY_Top_q0_ln1_signal_detect_o), //output Customized_PHY_Top_q0_ln1_signal_detect_o
        .Customized_PHY_Top_q0_ln1_rx_cdr_lock_o(Customized_PHY_Top_q0_ln1_rx_cdr_lock_o), //output Customized_PHY_Top_q0_ln1_rx_cdr_lock_o
        .Customized_PHY_Top_q0_ln1_pll_lock_o(Customized_PHY_Top_q0_ln1_pll_lock_o), //output Customized_PHY_Top_q0_ln1_pll_lock_o
        .Customized_PHY_Top_q0_ln1_k_lock_o(Customized_PHY_Top_q0_ln1_k_lock_o), //output Customized_PHY_Top_q0_ln1_k_lock_o
        .Customized_PHY_Top_q0_ln1_word_align_link_o(Customized_PHY_Top_q0_ln1_word_align_link_o), //output Customized_PHY_Top_q0_ln1_word_align_link_o
        .Customized_PHY_Top_q0_ln1_ready_o(Customized_PHY_Top_q0_ln1_ready_o), //output Customized_PHY_Top_q0_ln1_ready_o
        .USB3_0_PHY_Top_pclk(USB3_0_PHY_Top_pclk), //output USB3_0_PHY_Top_pclk
        .USB3_0_PHY_Top_PipeRxData(USB3_0_PHY_Top_PipeRxData), //output [31:0] USB3_0_PHY_Top_PipeRxData
        .USB3_0_PHY_Top_PipeRxDataK(USB3_0_PHY_Top_PipeRxDataK), //output [3:0] USB3_0_PHY_Top_PipeRxDataK
        .USB3_0_PHY_Top_PipeRxDataValid(USB3_0_PHY_Top_PipeRxDataValid), //output USB3_0_PHY_Top_PipeRxDataValid
        .USB3_0_PHY_Top_RxElecIdle(USB3_0_PHY_Top_RxElecIdle), //output USB3_0_PHY_Top_RxElecIdle
        .USB3_0_PHY_Top_RxStatus(USB3_0_PHY_Top_RxStatus), //output [2:0] USB3_0_PHY_Top_RxStatus
        .USB3_0_PHY_Top_PhyStatus(USB3_0_PHY_Top_PhyStatus), //output USB3_0_PHY_Top_PhyStatus
        .USB3_0_PHY_Top_PowerPresent(USB3_0_PHY_Top_PowerPresent), //output USB3_0_PHY_Top_PowerPresent
        .Customized_PHY_Top_q0_ln1_rx_clk_i(Customized_PHY_Top_q0_ln1_rx_clk_i), //input Customized_PHY_Top_q0_ln1_rx_clk_i
        .Customized_PHY_Top_q0_ln1_rx_fifo_rden_i(Customized_PHY_Top_q0_ln1_rx_fifo_rden_i), //input Customized_PHY_Top_q0_ln1_rx_fifo_rden_i
        .Customized_PHY_Top_q0_ln1_tx_clk_i(Customized_PHY_Top_q0_ln1_tx_clk_i), //input Customized_PHY_Top_q0_ln1_tx_clk_i
        .Customized_PHY_Top_q0_ln1_tx_data_i(Customized_PHY_Top_q0_ln1_tx_data_i), //input [79:0] Customized_PHY_Top_q0_ln1_tx_data_i
        .Customized_PHY_Top_q0_ln1_tx_fifo_wren_i(Customized_PHY_Top_q0_ln1_tx_fifo_wren_i), //input Customized_PHY_Top_q0_ln1_tx_fifo_wren_i
        .Customized_PHY_Top_q0_ln1_pma_rstn_i(Customized_PHY_Top_q0_ln1_pma_rstn_i), //input Customized_PHY_Top_q0_ln1_pma_rstn_i
        .Customized_PHY_Top_q0_ln1_pcs_rx_rst_i(Customized_PHY_Top_q0_ln1_pcs_rx_rst_i), //input Customized_PHY_Top_q0_ln1_pcs_rx_rst_i
        .Customized_PHY_Top_q0_ln1_pcs_tx_rst_i(Customized_PHY_Top_q0_ln1_pcs_tx_rst_i), //input Customized_PHY_Top_q0_ln1_pcs_tx_rst_i
        .USB3_0_PHY_Top_ref_clk(USB3_0_PHY_Top_ref_clk), //input USB3_0_PHY_Top_ref_clk
        .USB3_0_PHY_Top_phy_resetn(USB3_0_PHY_Top_phy_resetn), //input USB3_0_PHY_Top_phy_resetn
        .USB3_0_PHY_Top_PipeTxData(USB3_0_PHY_Top_PipeTxData), //input [31:0] USB3_0_PHY_Top_PipeTxData
        .USB3_0_PHY_Top_PipeTxDataK(USB3_0_PHY_Top_PipeTxDataK), //input [3:0] USB3_0_PHY_Top_PipeTxDataK
        .USB3_0_PHY_Top_TxDetectRx_loopback(USB3_0_PHY_Top_TxDetectRx_loopback), //input USB3_0_PHY_Top_TxDetectRx_loopback
        .USB3_0_PHY_Top_TxElecIdle(USB3_0_PHY_Top_TxElecIdle), //input USB3_0_PHY_Top_TxElecIdle
        .USB3_0_PHY_Top_RxPolarity(USB3_0_PHY_Top_RxPolarity), //input USB3_0_PHY_Top_RxPolarity
        .USB3_0_PHY_Top_RxEqTraining(USB3_0_PHY_Top_RxEqTraining), //input USB3_0_PHY_Top_RxEqTraining
        .USB3_0_PHY_Top_RxTermination(USB3_0_PHY_Top_RxTermination), //input USB3_0_PHY_Top_RxTermination
        .USB3_0_PHY_Top_TxOnesZeros(USB3_0_PHY_Top_TxOnesZeros), //input USB3_0_PHY_Top_TxOnesZeros
        .USB3_0_PHY_Top_PowerDown(USB3_0_PHY_Top_PowerDown), //input [1:0] USB3_0_PHY_Top_PowerDown
        .USB3_0_PHY_Top_ElasticityBufferMode(USB3_0_PHY_Top_ElasticityBufferMode) //input USB3_0_PHY_Top_ElasticityBufferMode
    );

//--------Copy end-------------------
