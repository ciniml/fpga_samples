// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Tang Primer 25K + Pmod 10BASE-T1S (no PHY chip) bring-up top.
// Board / circuit: ../../hw/Pmod_10BASE_T1S, PHY core + test logic: rtl/t1s_phy (T1sPhy, T1sBringup).
//
//   Pmod (csv pmod0 = Dock J6): 1/7 comparator H (F5/G5), 2/8 comparator L (G7/G8),
//                               3 PWM_TH (H8), 9 TX_EN (H7), 4/10 TX_P/TX_N (H5/J5)
//   Clocks: 50 MHz -> PLLA 200 MHz (IDES4 FCLK) -> CLKDIV /2 = 100 MHz (all logic, HALF = 4)
//   Comparators: TLVDS_IBUF -> IDES4 = 4 samples / clock (400 MS/s), Q0 the oldest
//   UART C3 (TX) / B3 (RX) 115200: status line every 0.5 s, commands in t1s_bringup.veryl
//   B2 = carrier (bus activity), C2 = toggles on every good received frame
//   TX drive mode (UART 'd', default 0): 0 = TX_EN closes the board's TMUX1511 and the TX pins always drive;
//   1 = direct (board solder jumpers JP2 / JP3 on the L side): TX_EN stays low and TX_P / TX_N are released
//   (high-Z) whenever they are equal, i.e. idle and the PMA's PRE / POST half-bits
module top (
    input  wire clk_in,      // 50 MHz
    input  wire reset_in,    // button, active high
    input  wire cmp_h_p, cmp_h_n,
    input  wire cmp_l_p, cmp_l_n,
    output wire tx_p, tx_n, tx_en,
    output wire pwm_th,
    output wire uart_txd,
    input  wire uart_rxd,
    output wire led_crs,
    output wire led_rx
);
    // ---- clocks / reset ----
    wire pll_lock;
    wire fclk /* synthesis syn_keep=1 */;
    wire pclk /* synthesis syn_keep=1 */;
    pll_t1s u_pll(.lock(pll_lock), .clkout0(fclk), .clkin(clk_in));
    wire resetn_div = pll_lock & ~reset_in;
    CLKDIV u_clkdiv(.HCLKIN(fclk), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv.DIV_MODE = "2";
    reg [3:0] rst_sync;
    always @(posedge pclk or negedge resetn_div)
        if (!resetn_div) rst_sync <= 4'hf; else rst_sync <= {rst_sync[2:0], 1'b0};
    wire rst = rst_sync[3];

    // ---- comparators ----
    wire h_ib, l_ib;
    TLVDS_IBUF u_ibuf_h(.I(cmp_h_p), .IB(cmp_h_n), .O(h_ib));
    TLVDS_IBUF u_ibuf_l(.I(cmp_l_p), .IB(cmp_l_n), .O(l_ib));
    wire [3:0] sh, sl;
    IDES4 u_ides_h(.D(h_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(rst),
                   .Q0(sh[0]), .Q1(sh[1]), .Q2(sh[2]), .Q3(sh[3]));
    IDES4 u_ides_l(.D(l_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(rst),
                   .Q0(sl[0]), .Q1(sl[1]), .Q2(sl[2]), .Q3(sl[3]));
    reg [3:0] sh_r, sl_r;
    always @(posedge pclk) begin
        sh_r <= sh;
        sl_r <= sl;
    end

    // ---- PHY + bring-up logic ----
    wire [9:0] th;
    wire [7:0] plca_id, plca_cnt, plca_to;
    wire [1:0] test_mode, order;
    wire [3:0] txd, rx_data;
    wire [2:0] plca_state;
    wire drv_direct;
    wire left_first, auto_order, plca_en, pending, tx_go, tx_req, m_tx_en;
    wire rx_valid, rx_er, rx_sof, rx_eof, rx_bad, rx_own, crs, beacon, viol;
    wire p_tx_p, p_tx_n, p_tx_en, p_pwm;

    T1sPhy #(.HALF(4), .SPC(4)) u_phy (
        .i_clk(pclk), .i_rst(rst),
        .i_h(sh_r), .i_l(sl_r), .o_tx_p(p_tx_p), .o_tx_n(p_tx_n), .o_tx_en(p_tx_en), .o_pwm(p_pwm),
        .i_th(th), .i_left_first(left_first), .i_auto(auto_order), .i_test(test_mode),
        .i_plca_en(plca_en), .i_plca_id(plca_id), .i_plca_cnt(plca_cnt), .i_plca_to(plca_to),
        .i_pending(pending), .o_tx_go(tx_go), .o_tx_req(tx_req), .i_tx_en(m_tx_en), .i_tx_er(1'b0), .i_txd(txd),
        .o_rx_valid(rx_valid), .o_rx_data(rx_data), .o_rx_er(rx_er), .o_rx_sof(rx_sof), .o_rx_eof(rx_eof),
        .o_rx_bad(rx_bad), .o_rx_dv(), .o_rx_own(rx_own),
        .o_crs(crs), .o_tx_active(), .o_beacon_rx(), .o_beacon_end(), .o_commit(), .o_order(order),
        .o_viol_pma(viol), .o_viol_pcs(), .o_plca_cur(), .o_plca_state(plca_state), .o_plca_sync(),
        .o_plca_bcn(beacon));

    T1sBringup #(.CLK_HZ(100_000_000), .BAUD(115200)) u_bu (
        .i_clk(pclk), .i_rst(rst),
        .o_th(th), .o_left_first(left_first), .o_auto(auto_order), .o_test(test_mode), .o_drv_direct(drv_direct), .o_plca_en(plca_en),
        .o_plca_id(plca_id), .o_plca_cnt(plca_cnt), .o_plca_to(plca_to), .o_pending(pending), .i_tx_go(tx_go),
        .i_tx_req(tx_req), .o_tx_en(m_tx_en), .o_txd(txd), .i_rx_valid(rx_valid), .i_rx_data(rx_data),
        .i_rx_er(rx_er), .i_rx_sof(rx_sof), .i_rx_eof(rx_eof), .i_rx_bad(rx_bad), .i_rx_own(rx_own),
        .i_crs(crs), .i_beacon(beacon), .i_viol(viol), .i_order(order), .i_plca_state(plca_state),
        .o_led_rx(led_rx), .o_txd_u(uart_txd), .i_rxd_u(uart_rxd));

    // ---- outputs: registered in the IOBs (equal delay on TX_P / TX_N) ----
    reg tx_p_r /* synthesis syn_useioff=1 */;
    reg tx_n_r /* synthesis syn_useioff=1 */;
    reg tx_oe_r /* synthesis syn_useioff=1 */;
    reg tx_en_r, pwm_r;
    always @(posedge pclk) begin
        tx_p_r  <= p_tx_p;
        tx_n_r  <= p_tx_n;
        tx_oe_r <= !drv_direct || (p_tx_p ^ p_tx_n);
        tx_en_r <= p_tx_en && !drv_direct;
        pwm_r   <= p_pwm;
    end
    assign tx_p    = tx_oe_r ? tx_p_r : 1'bz;
    assign tx_n    = tx_oe_r ? tx_n_r : 1'bz;
    assign tx_en   = tx_en_r;
    assign pwm_th  = pwm_r;
    assign led_crs = crs;
endmodule
