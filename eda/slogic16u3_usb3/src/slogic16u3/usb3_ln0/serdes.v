//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.12.03
//IP Version: 1.0
//Part Number: GW5AT-LV15MG132C1/I0
//Device: GW5AT-15
//Device Version: A
//Created Time: Sun Oct 11 13:39:42 2026

module SerDes_Top (USB3_0_PHY_Top_pclk, USB3_0_PHY_Top_PipeRxData, USB3_0_PHY_Top_PipeRxDataK, USB3_0_PHY_Top_PipeRxDataValid, USB3_0_PHY_Top_RxElecIdle, USB3_0_PHY_Top_RxStatus, USB3_0_PHY_Top_PhyStatus, USB3_0_PHY_Top_PowerPresent, USB3_0_PHY_Top_ref_clk, USB3_0_PHY_Top_phy_resetn, USB3_0_PHY_Top_PipeTxData, USB3_0_PHY_Top_PipeTxDataK, USB3_0_PHY_Top_TxDetectRx_loopback, USB3_0_PHY_Top_TxElecIdle, USB3_0_PHY_Top_RxPolarity, USB3_0_PHY_Top_RxEqTraining, USB3_0_PHY_Top_RxTermination, USB3_0_PHY_Top_TxOnesZeros, USB3_0_PHY_Top_PowerDown, USB3_0_PHY_Top_ElasticityBufferMode);

output USB3_0_PHY_Top_pclk;
output [31:0] USB3_0_PHY_Top_PipeRxData;
output [3:0] USB3_0_PHY_Top_PipeRxDataK;
output USB3_0_PHY_Top_PipeRxDataValid;
output USB3_0_PHY_Top_RxElecIdle;
output [2:0] USB3_0_PHY_Top_RxStatus;
output USB3_0_PHY_Top_PhyStatus;
output USB3_0_PHY_Top_PowerPresent;
input USB3_0_PHY_Top_ref_clk;
input USB3_0_PHY_Top_phy_resetn;
input [31:0] USB3_0_PHY_Top_PipeTxData;
input [3:0] USB3_0_PHY_Top_PipeTxDataK;
input USB3_0_PHY_Top_TxDetectRx_loopback;
input USB3_0_PHY_Top_TxElecIdle;
input USB3_0_PHY_Top_RxPolarity;
input USB3_0_PHY_Top_RxEqTraining;
input USB3_0_PHY_Top_RxTermination;
input USB3_0_PHY_Top_TxOnesZeros;
input [1:0] USB3_0_PHY_Top_PowerDown;
input USB3_0_PHY_Top_ElasticityBufferMode;

wire q0_fabric_ln0_rstn_i;
wire [79:0] q0_fabric_ln0_txdata_i;
wire q0_lane0_pcs_rx_rst;
wire q0_lane0_pcs_tx_rst;
wire q0_lane0_fabric_rx_clk;
wire q0_lane0_fabric_tx_clk;
wire q0_lane0_rx_if_fifo_rden;
wire q0_fabric_ln0_tx_vld_in;
wire q0_fabric_cm_life_clk_o;
wire ahb_rstn_o;
wire quad_cfg_test_dec_en;
wire q0_ln0_txm_o;
wire q0_ln0_txp_o;
wire q0_ln1_txm_o;
wire q0_ln1_txp_o;
wire q0_ln2_txm_o;
wire q0_ln2_txp_o;
wire q0_ln3_txm_o;
wire q0_ln3_txp_o;
wire q0_fabric_ln0_rxdet_result;
wire q0_fabric_ln1_rxdet_result;
wire q0_fabric_ln2_rxdet_result;
wire q0_fabric_ln3_rxdet_result;
wire q0_fabric_pma_cm0_dr_refclk_det_o;
wire q0_fabric_pma_cm1_dr_refclk_det_o;
wire q0_fabric_cm1_life_clk_o;
wire q0_fabric_cmu1_ck_ref_o;
wire q0_fabric_cmu1_ok_o;
wire q0_fabric_cmu1_refclk_gate_ack_o;
wire q0_fabric_cmu_ck_ref_o;
wire q0_fabric_cmu_ok_o;
wire q0_fabric_cmu_refclk_gate_ack_o;
wire q0_fabric_lane0_cmu_ck_ref_o;
wire q0_fabric_lane1_cmu_ck_ref_o;
wire q0_fabric_lane2_cmu_ck_ref_o;
wire q0_fabric_lane3_cmu_ck_ref_o;
wire [5:0] q0_fabric_ln0_astat_o;
wire q0_fabric_ln0_burn_in_toggle_o;
wire q0_fabric_ln0_pma_rx_lock_o;
wire [87:0] q0_fabric_ln0_rxdata_o;
wire [12:0] q0_fabric_ln0_stat_o;
wire [5:0] q0_fabric_ln1_astat_o;
wire q0_fabric_ln1_burn_in_toggle_o;
wire q0_fabric_ln1_pma_rx_lock_o;
wire [87:0] q0_fabric_ln1_rxdata_o;
wire [12:0] q0_fabric_ln1_stat_o;
wire [5:0] q0_fabric_ln2_astat_o;
wire q0_fabric_ln2_burn_in_toggle_o;
wire q0_fabric_ln2_pma_rx_lock_o;
wire [87:0] q0_fabric_ln2_rxdata_o;
wire [12:0] q0_fabric_ln2_stat_o;
wire [5:0] q0_fabric_ln3_astat_o;
wire q0_fabric_ln3_burn_in_toggle_o;
wire q0_fabric_ln3_pma_rx_lock_o;
wire [87:0] q0_fabric_ln3_rxdata_o;
wire [12:0] q0_fabric_ln3_stat_o;
wire q0_fabric_refclk_gate_ack_o;
wire q0_lane0_align_link;
wire q0_lane1_align_link;
wire q0_lane2_align_link;
wire q0_lane3_align_link;
wire q0_lane0_k_lock;
wire q0_lane1_k_lock;
wire q0_lane2_k_lock;
wire q0_lane3_k_lock;
wire [1:0] q0_lane0_disp_err_o;
wire [1:0] q0_lane1_disp_err_o;
wire [1:0] q0_lane2_disp_err_o;
wire [1:0] q0_lane3_disp_err_o;
wire [1:0] q0_lane0_dec_err_o;
wire [1:0] q0_lane1_dec_err_o;
wire [1:0] q0_lane2_dec_err_o;
wire [1:0] q0_lane3_dec_err_o;
wire [1:0] q0_lane0_cur_disp_o;
wire [1:0] q0_lane1_cur_disp_o;
wire [1:0] q0_lane2_cur_disp_o;
wire [1:0] q0_lane3_cur_disp_o;
wire q0_lane0_pcs_rx_o_fabric_clk;
wire q0_lane1_pcs_rx_o_fabric_clk;
wire q0_lane2_pcs_rx_o_fabric_clk;
wire q0_lane3_pcs_rx_o_fabric_clk;
wire q0_lane0_pcs_tx_o_fabric_clk;
wire q0_lane1_pcs_tx_o_fabric_clk;
wire q0_lane2_pcs_tx_o_fabric_clk;
wire q0_lane3_pcs_tx_o_fabric_clk;
wire q0_fabric_cmu0_clk;
wire q0_fabric_cmu1_clk;
wire q0_fabric_quad_clk_rx;
wire [4:0] q0_lane0_rx_if_fifo_rdusewd;
wire [4:0] q0_lane1_rx_if_fifo_rdusewd;
wire [4:0] q0_lane2_rx_if_fifo_rdusewd;
wire [4:0] q0_lane3_rx_if_fifo_rdusewd;
wire q0_lane0_rx_if_fifo_aempty;
wire q0_lane1_rx_if_fifo_aempty;
wire q0_lane2_rx_if_fifo_aempty;
wire q0_lane3_rx_if_fifo_aempty;
wire q0_lane0_rx_if_fifo_empty;
wire q0_lane1_rx_if_fifo_empty;
wire q0_lane2_rx_if_fifo_empty;
wire q0_lane3_rx_if_fifo_empty;
wire [4:0] q0_lane0_tx_if_fifo_wrusewd;
wire q0_lane0_tx_if_fifo_afull;
wire q0_lane0_tx_if_fifo_full;
wire [4:0] q0_lane1_tx_if_fifo_wrusewd;
wire q0_lane1_tx_if_fifo_afull;
wire q0_lane1_tx_if_fifo_full;
wire [4:0] q0_lane2_tx_if_fifo_wrusewd;
wire q0_lane2_tx_if_fifo_afull;
wire q0_lane2_tx_if_fifo_full;
wire [4:0] q0_lane3_tx_if_fifo_wrusewd;
wire q0_lane3_tx_if_fifo_afull;
wire q0_lane3_tx_if_fifo_full;
wire q0_fabric_clk_mon_o;
wire q0_fabric_gearfifo_err_rpt;
wire q0_fabric_ln0_rx_vld_out;
wire q0_fabric_ln0_rxelecidle_o;
wire q0_fabric_ln0_rxelecidle_o_h;
wire [12:0] q0_fabric_ln0_stat_o_h;
wire q0_fabric_ln1_rx_vld_out;
wire q0_fabric_ln1_rxelecidle_o;
wire q0_fabric_ln1_rxelecidle_o_h;
wire [12:0] q0_fabric_ln1_stat_o_h;
wire q0_fabric_ln2_rx_vld_out;
wire q0_fabric_ln2_rxelecidle_o;
wire q0_fabric_ln2_rxelecidle_o_h;
wire [12:0] q0_fabric_ln2_stat_o_h;
wire q0_fabric_ln3_rx_vld_out;
wire q0_fabric_ln3_rxelecidle_o;
wire q0_fabric_ln3_rxelecidle_o_h;
wire [12:0] q0_fabric_ln3_stat_o_h;
wire q0_fabric_lane0_cmu_ok_o;
wire q0_fabric_lane1_cmu_ok_o;
wire q0_fabric_lane2_cmu_ok_o;
wire q0_fabric_lane3_cmu_ok_o;
wire q0_fabric_pma_cm3_dr_refclk_det_o;
wire q0_fabric_pma_cm2_dr_refclk_det_o;
wire q0_quad_pclk1;
wire q0_quad_pclk0;
wire q0_fabric_lane0_64b66b_tx_invld_blk;
wire q0_fabric_lane0_64b66b_tx_fetch;
wire q0_fabric_lane0_64b66b_rx_valid;
wire q0_fabric_lane1_64b66b_tx_invld_blk;
wire q0_fabric_lane1_64b66b_tx_fetch;
wire q0_fabric_lane1_64b66b_rx_valid;
wire q0_fabric_lane2_64b66b_tx_invld_blk;
wire q0_fabric_lane2_64b66b_tx_fetch;
wire q0_fabric_lane2_64b66b_rx_valid;
wire q0_fabric_lane3_64b66b_tx_invld_blk;
wire q0_fabric_lane3_64b66b_tx_fetch;
wire q0_fabric_lane3_64b66b_rx_valid;
wire q0_ckp_mipi_1;
wire q0_ckp_mipi_0;
wire q0_ckn_mipi_1;
wire q0_ckn_mipi_0;
wire upar_rst;
wire upar_wren_s;
wire [23:0] upar_addr_s;
wire [31:0] upar_wrdata_s;
wire upar_rden_s;
wire [7:0] upar_strb_s;
wire upar_bus_width_s;
wire csr_tdo;
wire [31:0] upar_rddata_s;
wire upar_rdvld_s;
wire upar_ready_s;
wire spi_miso;
wire ahb_clk_o;
wire [95:0] upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i;
wire [127:0] upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i;
wire [31:0] upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o;
wire [127:0] upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o;
wire [3:0] upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o;
wire gw_vcc;
wire gw_gnd;




assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

GTR12_QUADB gtr12_quad_inst0 (
    .LN0_TXM_O(q0_ln0_txm_o),
    .LN0_TXP_O(q0_ln0_txp_o),
    .LN1_TXM_O(q0_ln1_txm_o),
    .LN1_TXP_O(q0_ln1_txp_o),
    .LN2_TXM_O(q0_ln2_txm_o),
    .LN2_TXP_O(q0_ln2_txp_o),
    .LN3_TXM_O(q0_ln3_txm_o),
    .LN3_TXP_O(q0_ln3_txp_o),
    .FABRIC_LN0_RXDET_RESULT(q0_fabric_ln0_rxdet_result),
    .FABRIC_LN1_RXDET_RESULT(q0_fabric_ln1_rxdet_result),
    .FABRIC_LN2_RXDET_RESULT(q0_fabric_ln2_rxdet_result),
    .FABRIC_LN3_RXDET_RESULT(q0_fabric_ln3_rxdet_result),
    .FABRIC_PMA_CM0_DR_REFCLK_DET_O(q0_fabric_pma_cm0_dr_refclk_det_o),
    .FABRIC_PMA_CM1_DR_REFCLK_DET_O(q0_fabric_pma_cm1_dr_refclk_det_o),
    .FABRIC_CM1_LIFE_CLK_O(q0_fabric_cm1_life_clk_o),
    .FABRIC_CM_LIFE_CLK_O(q0_fabric_cm_life_clk_o),
    .FABRIC_CMU1_CK_REF_O(q0_fabric_cmu1_ck_ref_o),
    .FABRIC_CMU1_OK_O(q0_fabric_cmu1_ok_o),
    .FABRIC_CMU1_REFCLK_GATE_ACK_O(q0_fabric_cmu1_refclk_gate_ack_o),
    .FABRIC_CMU_CK_REF_O(q0_fabric_cmu_ck_ref_o),
    .FABRIC_CMU_OK_O(q0_fabric_cmu_ok_o),
    .FABRIC_CMU_REFCLK_GATE_ACK_O(q0_fabric_cmu_refclk_gate_ack_o),
    .FABRIC_LANE0_CMU_CK_REF_O(q0_fabric_lane0_cmu_ck_ref_o),
    .FABRIC_LANE1_CMU_CK_REF_O(q0_fabric_lane1_cmu_ck_ref_o),
    .FABRIC_LANE2_CMU_CK_REF_O(q0_fabric_lane2_cmu_ck_ref_o),
    .FABRIC_LANE3_CMU_CK_REF_O(q0_fabric_lane3_cmu_ck_ref_o),
    .FABRIC_LN0_ASTAT_O(q0_fabric_ln0_astat_o),
    .FABRIC_LN0_BURN_IN_TOGGLE_O(q0_fabric_ln0_burn_in_toggle_o),
    .FABRIC_LN0_PMA_RX_LOCK_O(q0_fabric_ln0_pma_rx_lock_o),
    .FABRIC_LN0_RXDATA_O(q0_fabric_ln0_rxdata_o),
    .FABRIC_LN0_STAT_O(q0_fabric_ln0_stat_o),
    .FABRIC_LN1_ASTAT_O(q0_fabric_ln1_astat_o),
    .FABRIC_LN1_BURN_IN_TOGGLE_O(q0_fabric_ln1_burn_in_toggle_o),
    .FABRIC_LN1_PMA_RX_LOCK_O(q0_fabric_ln1_pma_rx_lock_o),
    .FABRIC_LN1_RXDATA_O(q0_fabric_ln1_rxdata_o),
    .FABRIC_LN1_STAT_O(q0_fabric_ln1_stat_o),
    .FABRIC_LN2_ASTAT_O(q0_fabric_ln2_astat_o),
    .FABRIC_LN2_BURN_IN_TOGGLE_O(q0_fabric_ln2_burn_in_toggle_o),
    .FABRIC_LN2_PMA_RX_LOCK_O(q0_fabric_ln2_pma_rx_lock_o),
    .FABRIC_LN2_RXDATA_O(q0_fabric_ln2_rxdata_o),
    .FABRIC_LN2_STAT_O(q0_fabric_ln2_stat_o),
    .FABRIC_LN3_ASTAT_O(q0_fabric_ln3_astat_o),
    .FABRIC_LN3_BURN_IN_TOGGLE_O(q0_fabric_ln3_burn_in_toggle_o),
    .FABRIC_LN3_PMA_RX_LOCK_O(q0_fabric_ln3_pma_rx_lock_o),
    .FABRIC_LN3_RXDATA_O(q0_fabric_ln3_rxdata_o),
    .FABRIC_LN3_STAT_O(q0_fabric_ln3_stat_o),
    .FABRIC_REFCLK_GATE_ACK_O(q0_fabric_refclk_gate_ack_o),
    .LANE0_ALIGN_LINK(q0_lane0_align_link),
    .LANE1_ALIGN_LINK(q0_lane1_align_link),
    .LANE2_ALIGN_LINK(q0_lane2_align_link),
    .LANE3_ALIGN_LINK(q0_lane3_align_link),
    .LANE0_K_LOCK(q0_lane0_k_lock),
    .LANE1_K_LOCK(q0_lane1_k_lock),
    .LANE2_K_LOCK(q0_lane2_k_lock),
    .LANE3_K_LOCK(q0_lane3_k_lock),
    .LANE0_DISP_ERR_O(q0_lane0_disp_err_o),
    .LANE1_DISP_ERR_O(q0_lane1_disp_err_o),
    .LANE2_DISP_ERR_O(q0_lane2_disp_err_o),
    .LANE3_DISP_ERR_O(q0_lane3_disp_err_o),
    .LANE0_DEC_ERR_O(q0_lane0_dec_err_o),
    .LANE1_DEC_ERR_O(q0_lane1_dec_err_o),
    .LANE2_DEC_ERR_O(q0_lane2_dec_err_o),
    .LANE3_DEC_ERR_O(q0_lane3_dec_err_o),
    .LANE0_CUR_DISP_O(q0_lane0_cur_disp_o),
    .LANE1_CUR_DISP_O(q0_lane1_cur_disp_o),
    .LANE2_CUR_DISP_O(q0_lane2_cur_disp_o),
    .LANE3_CUR_DISP_O(q0_lane3_cur_disp_o),
    .LANE0_PCS_RX_O_FABRIC_CLK(q0_lane0_pcs_rx_o_fabric_clk),
    .LANE1_PCS_RX_O_FABRIC_CLK(q0_lane1_pcs_rx_o_fabric_clk),
    .LANE2_PCS_RX_O_FABRIC_CLK(q0_lane2_pcs_rx_o_fabric_clk),
    .LANE3_PCS_RX_O_FABRIC_CLK(q0_lane3_pcs_rx_o_fabric_clk),
    .LANE0_PCS_TX_O_FABRIC_CLK(q0_lane0_pcs_tx_o_fabric_clk),
    .LANE1_PCS_TX_O_FABRIC_CLK(q0_lane1_pcs_tx_o_fabric_clk),
    .LANE2_PCS_TX_O_FABRIC_CLK(q0_lane2_pcs_tx_o_fabric_clk),
    .LANE3_PCS_TX_O_FABRIC_CLK(q0_lane3_pcs_tx_o_fabric_clk),
    .FABRIC_CMU0_CLK(q0_fabric_cmu0_clk),
    .FABRIC_CMU1_CLK(q0_fabric_cmu1_clk),
    .FABRIC_QUAD_CLK_RX(q0_fabric_quad_clk_rx),
    .LANE0_RX_IF_FIFO_RDUSEWD(q0_lane0_rx_if_fifo_rdusewd),
    .LANE1_RX_IF_FIFO_RDUSEWD(q0_lane1_rx_if_fifo_rdusewd),
    .LANE2_RX_IF_FIFO_RDUSEWD(q0_lane2_rx_if_fifo_rdusewd),
    .LANE3_RX_IF_FIFO_RDUSEWD(q0_lane3_rx_if_fifo_rdusewd),
    .LANE0_RX_IF_FIFO_AEMPTY(q0_lane0_rx_if_fifo_aempty),
    .LANE1_RX_IF_FIFO_AEMPTY(q0_lane1_rx_if_fifo_aempty),
    .LANE2_RX_IF_FIFO_AEMPTY(q0_lane2_rx_if_fifo_aempty),
    .LANE3_RX_IF_FIFO_AEMPTY(q0_lane3_rx_if_fifo_aempty),
    .LANE0_RX_IF_FIFO_EMPTY(q0_lane0_rx_if_fifo_empty),
    .LANE1_RX_IF_FIFO_EMPTY(q0_lane1_rx_if_fifo_empty),
    .LANE2_RX_IF_FIFO_EMPTY(q0_lane2_rx_if_fifo_empty),
    .LANE3_RX_IF_FIFO_EMPTY(q0_lane3_rx_if_fifo_empty),
    .LANE0_TX_IF_FIFO_WRUSEWD(q0_lane0_tx_if_fifo_wrusewd),
    .LANE0_TX_IF_FIFO_AFULL(q0_lane0_tx_if_fifo_afull),
    .LANE0_TX_IF_FIFO_FULL(q0_lane0_tx_if_fifo_full),
    .LANE1_TX_IF_FIFO_WRUSEWD(q0_lane1_tx_if_fifo_wrusewd),
    .LANE1_TX_IF_FIFO_AFULL(q0_lane1_tx_if_fifo_afull),
    .LANE1_TX_IF_FIFO_FULL(q0_lane1_tx_if_fifo_full),
    .LANE2_TX_IF_FIFO_WRUSEWD(q0_lane2_tx_if_fifo_wrusewd),
    .LANE2_TX_IF_FIFO_AFULL(q0_lane2_tx_if_fifo_afull),
    .LANE2_TX_IF_FIFO_FULL(q0_lane2_tx_if_fifo_full),
    .LANE3_TX_IF_FIFO_WRUSEWD(q0_lane3_tx_if_fifo_wrusewd),
    .LANE3_TX_IF_FIFO_AFULL(q0_lane3_tx_if_fifo_afull),
    .LANE3_TX_IF_FIFO_FULL(q0_lane3_tx_if_fifo_full),
    .FABRIC_CLK_MON_O(q0_fabric_clk_mon_o),
    .FABRIC_GEARFIFO_ERR_RPT(q0_fabric_gearfifo_err_rpt),
    .FABRIC_LN0_RX_VLD_OUT(q0_fabric_ln0_rx_vld_out),
    .FABRIC_LN0_RXELECIDLE_O(q0_fabric_ln0_rxelecidle_o),
    .FABRIC_LN0_RXELECIDLE_O_H(q0_fabric_ln0_rxelecidle_o_h),
    .FABRIC_LN0_STAT_O_H(q0_fabric_ln0_stat_o_h),
    .FABRIC_LN1_RX_VLD_OUT(q0_fabric_ln1_rx_vld_out),
    .FABRIC_LN1_RXELECIDLE_O(q0_fabric_ln1_rxelecidle_o),
    .FABRIC_LN1_RXELECIDLE_O_H(q0_fabric_ln1_rxelecidle_o_h),
    .FABRIC_LN1_STAT_O_H(q0_fabric_ln1_stat_o_h),
    .FABRIC_LN2_RX_VLD_OUT(q0_fabric_ln2_rx_vld_out),
    .FABRIC_LN2_RXELECIDLE_O(q0_fabric_ln2_rxelecidle_o),
    .FABRIC_LN2_RXELECIDLE_O_H(q0_fabric_ln2_rxelecidle_o_h),
    .FABRIC_LN2_STAT_O_H(q0_fabric_ln2_stat_o_h),
    .FABRIC_LN3_RX_VLD_OUT(q0_fabric_ln3_rx_vld_out),
    .FABRIC_LN3_RXELECIDLE_O(q0_fabric_ln3_rxelecidle_o),
    .FABRIC_LN3_RXELECIDLE_O_H(q0_fabric_ln3_rxelecidle_o_h),
    .FABRIC_LN3_STAT_O_H(q0_fabric_ln3_stat_o_h),
    .FABRIC_LANE0_CMU_OK_O(q0_fabric_lane0_cmu_ok_o),
    .FABRIC_LANE1_CMU_OK_O(q0_fabric_lane1_cmu_ok_o),
    .FABRIC_LANE2_CMU_OK_O(q0_fabric_lane2_cmu_ok_o),
    .FABRIC_LANE3_CMU_OK_O(q0_fabric_lane3_cmu_ok_o),
    .FABRIC_PMA_CM3_DR_REFCLK_DET_O(q0_fabric_pma_cm3_dr_refclk_det_o),
    .FABRIC_PMA_CM2_DR_REFCLK_DET_O(q0_fabric_pma_cm2_dr_refclk_det_o),
    .QUAD_PCLK1(q0_quad_pclk1),
    .QUAD_PCLK0(q0_quad_pclk0),
    .FABRIC_LANE0_64B66B_TX_INVLD_BLK(q0_fabric_lane0_64b66b_tx_invld_blk),
    .FABRIC_LANE0_64B66B_TX_FETCH(q0_fabric_lane0_64b66b_tx_fetch),
    .FABRIC_LANE0_64B66B_RX_VALID(q0_fabric_lane0_64b66b_rx_valid),
    .FABRIC_LANE1_64B66B_TX_INVLD_BLK(q0_fabric_lane1_64b66b_tx_invld_blk),
    .FABRIC_LANE1_64B66B_TX_FETCH(q0_fabric_lane1_64b66b_tx_fetch),
    .FABRIC_LANE1_64B66B_RX_VALID(q0_fabric_lane1_64b66b_rx_valid),
    .FABRIC_LANE2_64B66B_TX_INVLD_BLK(q0_fabric_lane2_64b66b_tx_invld_blk),
    .FABRIC_LANE2_64B66B_TX_FETCH(q0_fabric_lane2_64b66b_tx_fetch),
    .FABRIC_LANE2_64B66B_RX_VALID(q0_fabric_lane2_64b66b_rx_valid),
    .FABRIC_LANE3_64B66B_TX_INVLD_BLK(q0_fabric_lane3_64b66b_tx_invld_blk),
    .FABRIC_LANE3_64B66B_TX_FETCH(q0_fabric_lane3_64b66b_tx_fetch),
    .FABRIC_LANE3_64B66B_RX_VALID(q0_fabric_lane3_64b66b_rx_valid),
    .CKP_MIPI_1(q0_ckp_mipi_1),
    .CKP_MIPI_0(q0_ckp_mipi_0),
    .CKN_MIPI_1(q0_ckn_mipi_1),
    .CKN_MIPI_0(q0_ckn_mipi_0),
    .LN0_RXM_I(gw_gnd),
    .LN0_RXP_I(gw_gnd),
    .LN1_RXM_I(gw_gnd),
    .LN1_RXP_I(gw_gnd),
    .LN2_RXM_I(gw_gnd),
    .LN2_RXP_I(gw_gnd),
    .LN3_RXM_I(gw_gnd),
    .LN3_RXP_I(gw_gnd),
    .FABRIC_PMA_PD_REFHCLK_I(gw_gnd),
    .FABRIC_REFCLK1_INPUT_SEL_I({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_REFCLK_INPUT_SEL_I({gw_gnd,gw_gnd,gw_gnd}),
    .REFCLKM0_I(gw_gnd),
    .REFCLKM1_I(gw_gnd),
    .REFCLKP0_I(gw_gnd),
    .REFCLKP1_I(gw_gnd),
    .FABRIC_BURN_IN_I(gw_gnd),
    .FABRIC_CK_SOC_DIV_I({gw_gnd,gw_gnd}),
    .FABRIC_CLK_REF_CORE_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_CMU1_REFCLK_GATE_I(gw_gnd),
    .FABRIC_CMU_REFCLK_GATE_I(gw_gnd),
    .FABRIC_GLUE_MAC_INIT_INFO_I(gw_gnd),
    .FABRIC_LN0_CTRL_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN1_CTRL_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_CTRL_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_CTRL_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN0_IDDQ_I(gw_gnd),
    .FABRIC_LN1_IDDQ_I(gw_gnd),
    .FABRIC_LN2_IDDQ_I(gw_gnd),
    .FABRIC_LN3_IDDQ_I(gw_gnd),
    .FABRIC_LN0_PD_I({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN1_PD_I({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_PD_I({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_PD_I({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN0_RATE_I({gw_gnd,gw_gnd}),
    .FABRIC_LN1_RATE_I({gw_gnd,gw_gnd}),
    .FABRIC_LN2_RATE_I({gw_gnd,gw_gnd}),
    .FABRIC_LN3_RATE_I({gw_gnd,gw_gnd}),
    .FABRIC_LN0_RSTN_I(q0_fabric_ln0_rstn_i),
    .FABRIC_LN1_RSTN_I(gw_gnd),
    .FABRIC_LN2_RSTN_I(gw_gnd),
    .FABRIC_LN3_RSTN_I(gw_gnd),
    .FABRIC_LN0_TXDATA_I(q0_fabric_ln0_txdata_i),
    .FABRIC_LN1_TXDATA_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_TXDATA_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_TXDATA_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_REFCLK_GATE_I(gw_gnd),
    .LANE0_PCS_RX_RST(q0_lane0_pcs_rx_rst),
    .LANE1_PCS_RX_RST(gw_gnd),
    .LANE2_PCS_RX_RST(gw_gnd),
    .LANE3_PCS_RX_RST(gw_gnd),
    .LANE0_ALIGN_TRIGGER(gw_gnd),
    .LANE1_ALIGN_TRIGGER(gw_gnd),
    .LANE2_ALIGN_TRIGGER(gw_gnd),
    .LANE3_ALIGN_TRIGGER(gw_gnd),
    .LANE0_CHBOND_START(gw_gnd),
    .LANE1_CHBOND_START(gw_gnd),
    .LANE2_CHBOND_START(gw_gnd),
    .LANE3_CHBOND_START(gw_gnd),
    .LANE0_PCS_TX_RST(q0_lane0_pcs_tx_rst),
    .LANE1_PCS_TX_RST(gw_gnd),
    .LANE2_PCS_TX_RST(gw_gnd),
    .LANE3_PCS_TX_RST(gw_gnd),
    .LANE0_FABRIC_RX_CLK(q0_lane0_fabric_rx_clk),
    .LANE1_FABRIC_RX_CLK(gw_gnd),
    .LANE2_FABRIC_RX_CLK(gw_gnd),
    .LANE3_FABRIC_RX_CLK(gw_gnd),
    .LANE0_FABRIC_C2I_CLK(gw_gnd),
    .LANE1_FABRIC_C2I_CLK(gw_gnd),
    .LANE2_FABRIC_C2I_CLK(gw_gnd),
    .LANE3_FABRIC_C2I_CLK(gw_gnd),
    .LANE0_FABRIC_TX_CLK(q0_lane0_fabric_tx_clk),
    .LANE1_FABRIC_TX_CLK(gw_gnd),
    .LANE2_FABRIC_TX_CLK(gw_gnd),
    .LANE3_FABRIC_TX_CLK(gw_gnd),
    .LANE0_RX_IF_FIFO_RDEN(q0_lane0_rx_if_fifo_rden),
    .LANE1_RX_IF_FIFO_RDEN(gw_gnd),
    .LANE2_RX_IF_FIFO_RDEN(gw_gnd),
    .LANE3_RX_IF_FIFO_RDEN(gw_gnd),
    .FABRIC_CMU0_RESETN_I(gw_gnd),
    .FABRIC_CMU0_PD_I(gw_gnd),
    .FABRIC_CMU0_IDDQ_I(gw_gnd),
    .FABRIC_CMU1_RESETN_I(gw_gnd),
    .FABRIC_CMU1_PD_I(gw_gnd),
    .FABRIC_CMU1_IDDQ_I(gw_gnd),
    .FABRIC_PLL_CDN_I(gw_gnd),
    .FABRIC_LN0_CPLL_RESETN_I(gw_gnd),
    .FABRIC_LN0_CPLL_PD_I(gw_gnd),
    .FABRIC_LN0_CPLL_IDDQ_I(gw_gnd),
    .FABRIC_LN1_CPLL_RESETN_I(gw_gnd),
    .FABRIC_LN1_CPLL_PD_I(gw_gnd),
    .FABRIC_LN1_CPLL_IDDQ_I(gw_gnd),
    .FABRIC_LN2_CPLL_RESETN_I(gw_gnd),
    .FABRIC_LN2_CPLL_PD_I(gw_gnd),
    .FABRIC_LN2_CPLL_IDDQ_I(gw_gnd),
    .FABRIC_LN3_CPLL_RESETN_I(gw_gnd),
    .FABRIC_LN3_CPLL_PD_I(gw_gnd),
    .FABRIC_LN3_CPLL_IDDQ_I(gw_gnd),
    .FABRIC_CM1_PD_REFCLK_DET_I(gw_gnd),
    .FABRIC_CM0_PD_REFCLK_DET_I(gw_gnd),
    .FABRIC_LN0_CTRL_I_H({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN0_PD_I_H({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN0_RATE_I_H({gw_gnd,gw_gnd}),
    .FABRIC_LN0_TX_VLD_IN(q0_fabric_ln0_tx_vld_in),
    .FABRIC_LN1_CTRL_I_H({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN1_PD_I_H({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN1_RATE_I_H({gw_gnd,gw_gnd}),
    .FABRIC_LN1_TX_VLD_IN(gw_gnd),
    .FABRIC_LN2_CTRL_I_H({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_PD_I_H({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_RATE_I_H({gw_gnd,gw_gnd}),
    .FABRIC_LN2_TX_VLD_IN(gw_gnd),
    .FABRIC_LN3_CTRL_I_H({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_PD_I_H({gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_RATE_I_H({gw_gnd,gw_gnd}),
    .FABRIC_LN3_TX_VLD_IN(gw_gnd),
    .FABRIC_POR_N_I(gw_gnd),
    .FABRIC_QUAD_MCU_REQ_I(gw_gnd),
    .CK_AHB_I(q0_fabric_cm_life_clk_o),
    .AHB_RSTN(ahb_rstn_o),
    .TEST_DEC_EN(quad_cfg_test_dec_en),
    .QUAD_PCIE_CLK(gw_gnd),
    .PCIE_DIV2_REG(gw_gnd),
    .PCIE_DIV4_REG(gw_gnd),
    .PMAC_LN_RSTN(gw_gnd),
    .FABRIC_CM3_PD_REFCLK_DET_I(gw_gnd),
    .FABRIC_CM2_PD_REFCLK_DET_I(gw_gnd),
    .FABRIC_LN0_TX_DISPARITY_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN1_TX_DISPARITY_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN2_TX_DISPARITY_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FABRIC_LN3_TX_DISPARITY_I({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .CLK_VIQ_I({gw_gnd,gw_gnd})
);

GTR12_UPARA gtr12_upar_inst (
    .CSR_TDO(csr_tdo),
    .UPAR_RDDATA_S(upar_rddata_s),
    .UPAR_RDVLD_S(upar_rdvld_s),
    .UPAR_READY_S(upar_ready_s),
    .SPI_MISO(spi_miso),
    .AHB_CLK_O(ahb_clk_o),
    .QUAD_CFG_TEST_DEC_EN(quad_cfg_test_dec_en),
    .AHB_RSTN_O(ahb_rstn_o),
    .CSR_TCK(gw_gnd),
    .CSR_TMS(gw_gnd),
    .CSR_TDI(gw_gnd),
    .UPAR_CLK(q0_fabric_cm_life_clk_o),
    .UPAR_RST(upar_rst),
    .SPI_CLK(gw_gnd),
    .UPAR_WREN_S(upar_wren_s),
    .UPAR_ADDR_S(upar_addr_s),
    .UPAR_WRDATA_S(upar_wrdata_s),
    .UPAR_RDEN_S(upar_rden_s),
    .UPAR_STRB_S(upar_strb_s),
    .UPAR_BUS_WIDTH_S(upar_bus_width_s),
    .SPI_MOSI(gw_gnd),
    .SPI_SS(gw_gnd),
    .CSR_MODE({gw_vcc,gw_gnd,gw_vcc,gw_gnd,gw_gnd}),
    .FABRIC_DFT_EDT_UPDATE(gw_gnd),
    .FABRIC_DFT_IJTAG_CE(gw_gnd),
    .FABRIC_DFT_IJTAG_RESET(gw_gnd),
    .FABRIC_DFT_IJTAG_SE(gw_gnd),
    .FABRIC_DFT_IJTAG_SEL(gw_gnd),
    .FABRIC_DFT_IJTAG_SI(gw_gnd),
    .FABRIC_DFT_IJTAG_TCK(gw_gnd),
    .FABRIC_DFT_IJTAG_UE(gw_gnd),
    .FABRIC_DFT_PLL_BYPASS_CLK(gw_gnd),
    .FABRIC_DFT_PLL_BYPASS_MODE(gw_gnd),
    .FABRIC_DFT_SCAN_CLK(gw_gnd),
    .FABRIC_DFT_SCAN_EN(gw_gnd),
    .FABRIC_DFT_SCAN_IN0(gw_gnd),
    .FABRIC_DFT_SCAN_IN1(gw_gnd),
    .FABRIC_DFT_SCAN_IN2(gw_gnd),
    .FABRIC_DFT_SCAN_IN3(gw_gnd),
    .FABRIC_DFT_SCAN_IN4(gw_gnd),
    .FABRIC_DFT_SCAN_IN5(gw_gnd),
    .FABRIC_DFT_SCAN_IN6(gw_gnd),
    .FABRIC_DFT_SCAN_RSTN(gw_gnd),
    .FABRIC_DFT_SHIFT_SCAN_EN(gw_gnd)
);

\~upar_arbiter_wrap.SerDes_Top upar_arbiter_wrap_SerDes_Top_inst (
    .drp_clk_o({upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[3],upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[2],upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[1],upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[0]}),
    .drp_ready_o({upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o[3],upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o[2],upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o[1],upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o[0]}),
    .drp_rdvld_o({upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o[3],upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o[2],upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o[1],upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o[0]}),
    .drp_rddata_o({upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o[127:96],upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o[95:64],upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o[63:32],upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o[31:0]}),
    .drp_resp_o({upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o[3],upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o[2],upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o[1],upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o[0]}),
    .upar_rst_o(upar_rst),
    .upar_addr_o(upar_addr_s),
    .upar_wren_o(upar_wren_s),
    .upar_wrdata_o(upar_wrdata_s),
    .upar_strb_o(upar_strb_s),
    .upar_rden_o(upar_rden_s),
    .upar_bus_width_o(upar_bus_width_s),
    .drp_addr_i({upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i[95:72],upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i[71:48],upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i[47:24],upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i[23:0]}),
    .drp_wren_i({upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i[3],upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i[2],upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i[1],upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i[0]}),
    .drp_wrdata_i({upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i[127:96],upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i[95:64],upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i[63:32],upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i[31:0]}),
    .drp_strb_i({upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i[31:24],upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i[23:16],upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i[15:8],upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i[7:0]}),
    .drp_rden_i({upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i[3],upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i[2],upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i[1],upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i[0]}),
    .upar_clk_i(q0_fabric_cm_life_clk_o),
    .upar_ready_i(upar_ready_s),
    .upar_rdvld_i(upar_rdvld_s),
    .upar_rddata_i(upar_rddata_s)
);

USB3_0_PHY_Top USB3_0_PHY_Top_inst (
    .pclk(USB3_0_PHY_Top_pclk),
    .PipeRxData(USB3_0_PHY_Top_PipeRxData[31:0]),
    .PipeRxDataK(USB3_0_PHY_Top_PipeRxDataK[3:0]),
    .PipeRxDataValid(USB3_0_PHY_Top_PipeRxDataValid),
    .RxElecIdle(USB3_0_PHY_Top_RxElecIdle),
    .RxStatus(USB3_0_PHY_Top_RxStatus[2:0]),
    .PhyStatus(USB3_0_PHY_Top_PhyStatus),
    .PowerPresent(USB3_0_PHY_Top_PowerPresent),
    .serdes_upar_wren_o(upar_arbiter_wrap_SerDes_Top_inst_drp_wren_i[0]),
    .serdes_upar_addr_o(upar_arbiter_wrap_SerDes_Top_inst_drp_addr_i[23:0]),
    .serdes_upar_wrdata_o(upar_arbiter_wrap_SerDes_Top_inst_drp_wrdata_i[31:0]),
    .serdes_upar_rden_o(upar_arbiter_wrap_SerDes_Top_inst_drp_rden_i[0]),
    .serdes_upar_strb_o(upar_arbiter_wrap_SerDes_Top_inst_drp_strb_i[7:0]),
    .serdes_fabric_rstn_o(q0_fabric_ln0_rstn_i),
    .serdes_fabric_tx_clk_o(q0_lane0_fabric_rx_clk),
    .serdes_pcs_tx_rst_o(q0_lane0_pcs_tx_rst),
    .serdes_fabric_tx_vld_o(q0_fabric_ln0_tx_vld_in),
    .serdes_txdata_o(q0_fabric_ln0_txdata_i[79:0]),
    .serdes_fabric_rx_clk_o(q0_lane0_fabric_tx_clk),
    .serdes_pcs_rx_rst_o(q0_lane0_pcs_rx_rst),
    .serdes_rxfifo_rd_en_o(q0_lane0_rx_if_fifo_rden),
    .ref_clk(USB3_0_PHY_Top_ref_clk),
    .phy_resetn(USB3_0_PHY_Top_phy_resetn),
    .PipeTxData(USB3_0_PHY_Top_PipeTxData[31:0]),
    .PipeTxDataK(USB3_0_PHY_Top_PipeTxDataK[3:0]),
    .TxDetectRx_loopback(USB3_0_PHY_Top_TxDetectRx_loopback),
    .TxElecIdle(USB3_0_PHY_Top_TxElecIdle),
    .RxPolarity(USB3_0_PHY_Top_RxPolarity),
    .RxEqTraining(USB3_0_PHY_Top_RxEqTraining),
    .RxTermination(USB3_0_PHY_Top_RxTermination),
    .TxOnesZeros(USB3_0_PHY_Top_TxOnesZeros),
    .PowerDown(USB3_0_PHY_Top_PowerDown[1:0]),
    .ElasticityBufferMode(USB3_0_PHY_Top_ElasticityBufferMode),
    .serdes_upar_clk_i(upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[0]),
    .serdes_upar_resp_i(upar_arbiter_wrap_SerDes_Top_inst_drp_resp_o[0]),
    .serdes_upar_rddata_i(upar_arbiter_wrap_SerDes_Top_inst_drp_rddata_o[31:0]),
    .serdes_upar_rdvld_i(upar_arbiter_wrap_SerDes_Top_inst_drp_rdvld_o[0]),
    .serdes_upar_ready_i(upar_arbiter_wrap_SerDes_Top_inst_drp_ready_o[0]),
    .serdes_q0_qpll0_ok_i(q0_fabric_cmu_ok_o),
    .serdes_q0_qpll1_ok_i(gw_gnd),
    .serdes_q1_qpll0_ok_i(gw_gnd),
    .serdes_q1_qpll1_ok_i(gw_gnd),
    .serdes_cpll_ok_i(gw_gnd),
    .serdes_pcs_tx_clk_i(q0_lane0_pcs_tx_o_fabric_clk),
    .serdes_tx_fifo_wrusewd_i(q0_lane0_tx_if_fifo_wrusewd[4:0]),
    .serdes_pcs_rx_clk_i(q0_lane0_pcs_rx_o_fabric_clk),
    .serdes_pma_rx_lock_i(q0_fabric_ln0_pma_rx_lock_o),
    .serdes_rxfifo_aempty_i(q0_lane0_rx_if_fifo_aempty),
    .serdes_rx_fifo_rdusewd_i(q0_lane0_rx_if_fifo_rdusewd[4:0]),
    .serdes_rxdata_i(q0_fabric_ln0_rxdata_o[87:0]),
    .serdes_rx_vld_i(q0_fabric_ln0_rx_vld_out),
    .serdes_rxelecidle_i(q0_fabric_ln0_rxelecidle_o),
    .serdes_astat_i(q0_fabric_ln0_astat_o[5:0])
);

endmodule //SerDes_Top
