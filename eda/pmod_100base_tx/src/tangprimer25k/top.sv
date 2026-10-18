// Tang Primer 25K + Pmod 100BASE-TX direct (transformerless) PHY bring-up top.
// Board / circuit: ../README.md, PHY core: rtl/eth100_phy, wrapper: eth100_phy_gw5a.v,
// test logic + UART protocol: eth100_test.sv.
//
//   Pmod (csv pmod0): 1/7 comparator A (F5/G5), 2/8 comparator B (G7/G8),
//                     3/9 PWM_A/PWM_B (H8/H7), 4/10 TX_P/TX_N (H5/J5)
//   UART C3 (TX) / B3 (RX) 115200 (status line every 0.5 s, commands: eth100_test.sv)
//   B2 = link, C2 = toggles on every good received frame
module top (
    input  wire clk_in,      // 50 MHz
    input  wire reset_in,    // button, active high
    input  wire cmp_a_p, cmp_a_n,
    input  wire cmp_b_p, cmp_b_n,
    output wire tx_p, tx_n,
    output wire pwm_a, pwm_b,
    output wire uart_txd,
    input  wire uart_rxd,
    output wire led_link,
    output wire led_rx
);
    wire        clk, rst, pll_lock;
    wire        tx_req, tx_en, rx_valid, rx_er, rx_sof, rx_eof, rx_dv;
    wire [3:0]  tx_data, rx_data;
    wire        link, full_duplex, parallel, cdr_lock, scr_lock, flp_pulse, cdr_slip;
    wire [2:0]  an_state;
    wire [15:0] lp_page;
    wire [9:0]  th_a, th_b;
    wire        force_100, an_restart, cdr_freeze;

    eth100_phy_gw5a u_phy (
        .clk_in(clk_in), .reset_in(reset_in),
        .cmp_a_p(cmp_a_p), .cmp_a_n(cmp_a_n), .cmp_b_p(cmp_b_p), .cmp_b_n(cmp_b_n),
        .tx_p_o(tx_p), .tx_n_o(tx_n), .pwm_a_o(pwm_a), .pwm_b_o(pwm_b),
        .pclk_o(clk), .rst_o(rst), .pll_lock_o(pll_lock),
        .th_a(th_a), .th_b(th_b), .force_100(force_100), .an_restart(an_restart), .cdr_freeze(cdr_freeze),
        .tx_req(tx_req), .tx_en(tx_en), .tx_er(1'b0), .tx_data(tx_data),
        .rx_valid(rx_valid), .rx_data(rx_data), .rx_er(rx_er), .rx_sof(rx_sof), .rx_eof(rx_eof), .rx_dv(rx_dv),
        .link(link), .full_duplex(full_duplex), .parallel(parallel), .an_state(an_state), .lp_page(lp_page),
        .cdr_lock(cdr_lock), .scr_lock(scr_lock), .flp_pulse(flp_pulse), .cdr_slip(cdr_slip),
        .samp_a_o(), .samp_b_o());

    wire led_rx_t;
    eth100_test u_test (
        .clk(clk), .rst(rst),
        .tx_req(tx_req), .tx_en(tx_en), .tx_data(tx_data),
        .rx_valid(rx_valid), .rx_data(rx_data), .rx_er(rx_er), .rx_sof(rx_sof), .rx_eof(rx_eof),
        .link(link), .full_duplex(full_duplex), .parallel(parallel), .an_state(an_state), .lp_page(lp_page),
        .cdr_lock(cdr_lock), .scr_lock(scr_lock), .flp_pulse(flp_pulse), .cdr_slip(cdr_slip),
        .th_a(th_a), .th_b(th_b), .force_100(force_100), .an_restart(an_restart), .cdr_freeze(cdr_freeze),
        .led_rx(led_rx_t), .uart_txd(uart_txd), .uart_rxd(uart_rxd));

    assign led_link = link;
    assign led_rx   = led_rx_t;
endmodule
