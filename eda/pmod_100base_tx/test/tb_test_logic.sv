// eth100_test (frame generator / FCS checker / UART report) on two Eth100Phy
// cores through the behavioural line model (rtl/eth100_phy/test/eth100_chan.sv).
// Side A sends test frames to side B and vice versa; both must count them as
// good (FCS residue) and none as bad. The UART output of side B is decoded and
// printed. Timers are shortened (CLK_HZ) so that a "second" is 2 ms.
`timescale 1ns/1ps
module tb_test_logic;
    localparam int CLK_HZ = 250_000;        // timer base: 0.5 "s" = 125k clocks = 1 ms (the clock runs at 125 MHz)
    localparam int BAUD   = 62_500;         // BAUD_DIVIDER = 4
    logic clk_a = 0, clk_b = 0, rst = 1;
    always #4.0      clk_a = ~clk_a;
    always #4.0004   clk_b = ~clk_b;        // +100 ppm

    logic       a_tx_p, a_tx_n, b_tx_p, b_tx_n;
    logic [3:0] a_sa, a_sb, b_sa, b_sb;
    eth100_chan ch_ab(.tx_p(a_tx_p), .tx_n(a_tx_n), .rx_clk(clk_b), .a(b_sa), .b(b_sb));
    eth100_chan ch_ba(.tx_p(b_tx_p), .tx_n(b_tx_n), .rx_clk(clk_a), .a(a_sa), .b(a_sb));

    wire b_uart;
    node #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) na(.clk(clk_a), .rst(rst), .sa(a_sa), .sb(a_sb), .tx_p(a_tx_p), .tx_n(a_tx_n), .uart_txd());
    node #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) nb(.clk(clk_b), .rst(rst), .sa(b_sa), .sb(b_sb), .tx_p(b_tx_p), .tx_n(b_tx_n), .uart_txd(b_uart));

    // UART decoder for side B's report (4 clocks per bit)
    string line = "";
    initial begin
        forever begin
            @(negedge b_uart);
            repeat (6) @(posedge clk_b);          // to the middle of bit 0
            begin
                logic [7:0] ch;
                for (int i = 0; i < 8; i++) begin ch[i] = b_uart; repeat (4) @(posedge clk_b); end
                if (ch == 8'h0a) begin $display("B uart: %s", line); line = ""; end
                else if (ch != 8'h0d) line = {line, string'(ch)};
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk_a);
        rst = 0;
        #40ms;
        $display("A: good %0d bad %0d sent %0d | B: good %0d bad %0d sent %0d",
                 na.u_test.rx_good, na.u_test.rx_bad, na.u_test.tx_count,
                 nb.u_test.rx_good, nb.u_test.rx_bad, nb.u_test.tx_count);
        if (na.u_test.rx_good >= 8 && nb.u_test.rx_good >= 8 && na.u_test.rx_bad == 0 && nb.u_test.rx_bad == 0
            && nb.u_test.last_len == 11'd64 && nb.u_test.last_hdr[8*12 +: 16] == 16'hb588)
            $display("PASS");
        else $fatal(1, "FAIL");
        $finish;
    end
endmodule

module node #(parameter int CLK_HZ = 2_000_000, parameter int BAUD = 500_000) (
    input  logic clk, rst,
    input  logic [3:0] sa, sb,
    output logic tx_p, tx_n,
    output wire  uart_txd
);
    wire        tx_req, tx_en, rx_valid, rx_er, rx_sof, rx_eof, rx_dv;
    wire [3:0]  tx_data, rx_data;
    wire        link, fd, pd, cdr_lock, scr_lock, flp_pulse, cdr_slip;
    wire [2:0]  an_state;
    wire [15:0] lp_page;
    wire [9:0]  th_a, th_b;
    wire        force_100, an_restart, cdr_freeze;
    Eth100Phy #(.TDIV(16), .AN_DIV(1000)) u_phy (
        .i_clk(clk), .i_rst(rst), .i_samp_a(sa), .i_samp_b(sb), .o_tx_p(tx_p), .o_tx_n(tx_n), .o_pwm_a(), .o_pwm_b(),
        .i_th_a(th_a), .i_th_b(th_b), .i_force_100(force_100), .i_an_restart(an_restart), .i_cdr_freeze(cdr_freeze),
        .o_tx_req(tx_req), .i_tx_en(tx_en), .i_tx_er(1'b0), .i_tx_data(tx_data),
        .o_rx_valid(rx_valid), .o_rx_data(rx_data), .o_rx_er(rx_er), .o_rx_sof(rx_sof), .o_rx_eof(rx_eof), .o_rx_dv(rx_dv),
        .o_link(link), .o_full_duplex(fd), .o_parallel(pd), .o_an_state(an_state), .o_lp_page(lp_page),
        .o_cdr_lock(cdr_lock), .o_scr_lock(scr_lock), .o_flp_pulse(flp_pulse), .o_cdr_slip(cdr_slip));
    eth100_test #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_test (
        .clk(clk), .rst(rst), .tx_req(tx_req), .tx_en(tx_en), .tx_data(tx_data),
        .rx_valid(rx_valid), .rx_data(rx_data), .rx_er(rx_er), .rx_sof(rx_sof), .rx_eof(rx_eof),
        .link(link), .full_duplex(fd), .parallel(pd), .an_state(an_state), .lp_page(lp_page),
        .cdr_lock(cdr_lock), .scr_lock(scr_lock), .flp_pulse(flp_pulse), .cdr_slip(cdr_slip),
        .th_a(th_a), .th_b(th_b), .force_100(force_100), .an_restart(an_restart), .cdr_freeze(cdr_freeze),
        .led_rx(), .uart_txd(uart_txd), .uart_rxd(1'b1));
endmodule
