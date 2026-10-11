//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.03
//IP Version: 1.0
//Part Number: GW5AT-LV15MG132C1/I0
//Device: GW5AT-15
//Device Version: A
//Created Time: Sun Oct 11 13:39:42 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    SerDes_Top your_instance_name(
        .USB3_0_PHY_Top_pclk(USB3_0_PHY_Top_pclk), //output USB3_0_PHY_Top_pclk
        .USB3_0_PHY_Top_PipeRxData(USB3_0_PHY_Top_PipeRxData), //output [31:0] USB3_0_PHY_Top_PipeRxData
        .USB3_0_PHY_Top_PipeRxDataK(USB3_0_PHY_Top_PipeRxDataK), //output [3:0] USB3_0_PHY_Top_PipeRxDataK
        .USB3_0_PHY_Top_PipeRxDataValid(USB3_0_PHY_Top_PipeRxDataValid), //output USB3_0_PHY_Top_PipeRxDataValid
        .USB3_0_PHY_Top_RxElecIdle(USB3_0_PHY_Top_RxElecIdle), //output USB3_0_PHY_Top_RxElecIdle
        .USB3_0_PHY_Top_RxStatus(USB3_0_PHY_Top_RxStatus), //output [2:0] USB3_0_PHY_Top_RxStatus
        .USB3_0_PHY_Top_PhyStatus(USB3_0_PHY_Top_PhyStatus), //output USB3_0_PHY_Top_PhyStatus
        .USB3_0_PHY_Top_PowerPresent(USB3_0_PHY_Top_PowerPresent), //output USB3_0_PHY_Top_PowerPresent
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
