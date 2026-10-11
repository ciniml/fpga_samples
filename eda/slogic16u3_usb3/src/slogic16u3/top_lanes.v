// USB 3.0 bring-up on the Sipeed SLogic16U3 (GW5AT-15), step 1: which SerDes lane is wired to the
// USB-C connector (through the VL162 Type-C 2:1 mux).
//
//   D14 high -> 125 MHz oscillator on Q0 REFCLK0 -> Customized PHY (GUI, src/slogic16u3/serdes_4ln):
//   Q0 lanes 0..3, 5 Gb/s, 8b10b, 1:4 gear (32 bits / 125 MHz), K28.5 word alignment. The transmitters
//   stay idle (no data written). A USB 3 host that finds the receiver terminations (Rx.Detect) starts
//   Polling.LFPS: LFPS bursts on the receive pair of the lane in use show up on its signal_detect,
//   and the host retries (Rx.Detect again) as long as no LFPS comes back.
//
// Status over JTAG: ER1 (IR 0x42) read-only, 256 bits (jtag_status.v, host/usb3_lanes.py):
//   [15:0] magic 0x5B30, per lane n at 16 + 48 n: [5:0] {ready, pll_lock, word_align_link, k_lock,
//   cdr_lock, signal_detect} now, [11:6] the same, seen high since configuration, [15:12] 0,
//   [31:16] signal_detect rising edges, [47:32] cdr_lock rising edges (osc domain, wrapping);
//   [223:208] 0, [255:224] uptime in 2^16 osc cycles.
// The USB 2.0 pins are kept quiet: comparator pairs declared (no weak pull-ups on D+/D-), pull-up off.
module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,

    input  wire usb_cmp_dp,    // H3 / H2 (USB 2.0 comparator pairs, unused here)
    input  wire usb_cmp_dp_n,
    input  wire usb_cmp_dn,    // M2 / M1
    input  wire usb_cmp_dn_n,
    output wire usb_pullup,    // C14 (USB 2.0 D+ pull-up: off)
    output wire xo_en,         // D14: 125 MHz oscillator enable
    output wire led_r          // G14
);
    wire osc;   // ~51.7 MHz (measured)
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));
    assign xo_en = 1'b1;
    assign usb_pullup = 1'b0;
    wire cmp_dp, cmp_dn;
    TLVDS_IBUF u_cmp_dp (.I(usb_cmp_dp), .IB(usb_cmp_dp_n), .O(cmp_dp));
    TLVDS_IBUF u_cmp_dn (.I(usb_cmp_dn), .IB(usb_cmp_dn_n), .O(cmp_dn));

    // ~20 ms after configuration: SerDes PMA / PCS resets released
    reg [20:0] seq = 21'd0;
    always @(posedge osc) if (!seq[20]) seq <= seq + 21'd1;
    wire pma_rstn = seq[20];

    wire [3:0] rxclk, txclk, sd, cdr, pll, klock, align, ready;
    SerDes_Top u_serdes (
        .Customized_PHY_Top_q0_ln0_rx_pcs_clkout_o(rxclk[0]), .Customized_PHY_Top_q0_ln0_rx_data_o(), .Customized_PHY_Top_q0_ln0_rx_fifo_rdusewd_o(),
        .Customized_PHY_Top_q0_ln0_rx_fifo_aempty_o(), .Customized_PHY_Top_q0_ln0_rx_fifo_empty_o(), .Customized_PHY_Top_q0_ln0_rx_valid_o(),
        .Customized_PHY_Top_q0_ln0_tx_pcs_clkout_o(txclk[0]), .Customized_PHY_Top_q0_ln0_tx_fifo_wrusewd_o(), .Customized_PHY_Top_q0_ln0_tx_fifo_afull_o(), .Customized_PHY_Top_q0_ln0_tx_fifo_full_o(),
        .Customized_PHY_Top_q0_ln0_refclk_o(), .Customized_PHY_Top_q0_ln0_signal_detect_o(sd[0]), .Customized_PHY_Top_q0_ln0_rx_cdr_lock_o(cdr[0]), .Customized_PHY_Top_q0_ln0_pll_lock_o(pll[0]),
        .Customized_PHY_Top_q0_ln0_k_lock_o(klock[0]), .Customized_PHY_Top_q0_ln0_word_align_link_o(align[0]), .Customized_PHY_Top_q0_ln0_ready_o(ready[0]),
        .Customized_PHY_Top_q0_ln0_rx_clk_i(rxclk[0]), .Customized_PHY_Top_q0_ln0_rx_fifo_rden_i(1'b0), .Customized_PHY_Top_q0_ln0_tx_clk_i(txclk[0]), .Customized_PHY_Top_q0_ln0_tx_data_i(80'd0),
        .Customized_PHY_Top_q0_ln0_tx_fifo_wren_i(1'b0), .Customized_PHY_Top_q0_ln0_pma_rstn_i(pma_rstn), .Customized_PHY_Top_q0_ln0_pcs_rx_rst_i(!pma_rstn), .Customized_PHY_Top_q0_ln0_pcs_tx_rst_i(!pma_rstn),
        .Customized_PHY_Top_q0_ln1_rx_pcs_clkout_o(rxclk[1]), .Customized_PHY_Top_q0_ln1_rx_data_o(), .Customized_PHY_Top_q0_ln1_rx_fifo_rdusewd_o(),
        .Customized_PHY_Top_q0_ln1_rx_fifo_aempty_o(), .Customized_PHY_Top_q0_ln1_rx_fifo_empty_o(), .Customized_PHY_Top_q0_ln1_rx_valid_o(),
        .Customized_PHY_Top_q0_ln1_tx_pcs_clkout_o(txclk[1]), .Customized_PHY_Top_q0_ln1_tx_fifo_wrusewd_o(), .Customized_PHY_Top_q0_ln1_tx_fifo_afull_o(), .Customized_PHY_Top_q0_ln1_tx_fifo_full_o(),
        .Customized_PHY_Top_q0_ln1_refclk_o(), .Customized_PHY_Top_q0_ln1_signal_detect_o(sd[1]), .Customized_PHY_Top_q0_ln1_rx_cdr_lock_o(cdr[1]), .Customized_PHY_Top_q0_ln1_pll_lock_o(pll[1]),
        .Customized_PHY_Top_q0_ln1_k_lock_o(klock[1]), .Customized_PHY_Top_q0_ln1_word_align_link_o(align[1]), .Customized_PHY_Top_q0_ln1_ready_o(ready[1]),
        .Customized_PHY_Top_q0_ln1_rx_clk_i(rxclk[1]), .Customized_PHY_Top_q0_ln1_rx_fifo_rden_i(1'b0), .Customized_PHY_Top_q0_ln1_tx_clk_i(txclk[1]), .Customized_PHY_Top_q0_ln1_tx_data_i(80'd0),
        .Customized_PHY_Top_q0_ln1_tx_fifo_wren_i(1'b0), .Customized_PHY_Top_q0_ln1_pma_rstn_i(pma_rstn), .Customized_PHY_Top_q0_ln1_pcs_rx_rst_i(!pma_rstn), .Customized_PHY_Top_q0_ln1_pcs_tx_rst_i(!pma_rstn),
        .Customized_PHY_Top_q0_ln2_rx_pcs_clkout_o(rxclk[2]), .Customized_PHY_Top_q0_ln2_rx_data_o(), .Customized_PHY_Top_q0_ln2_rx_fifo_rdusewd_o(),
        .Customized_PHY_Top_q0_ln2_rx_fifo_aempty_o(), .Customized_PHY_Top_q0_ln2_rx_fifo_empty_o(), .Customized_PHY_Top_q0_ln2_rx_valid_o(),
        .Customized_PHY_Top_q0_ln2_tx_pcs_clkout_o(txclk[2]), .Customized_PHY_Top_q0_ln2_tx_fifo_wrusewd_o(), .Customized_PHY_Top_q0_ln2_tx_fifo_afull_o(), .Customized_PHY_Top_q0_ln2_tx_fifo_full_o(),
        .Customized_PHY_Top_q0_ln2_refclk_o(), .Customized_PHY_Top_q0_ln2_signal_detect_o(sd[2]), .Customized_PHY_Top_q0_ln2_rx_cdr_lock_o(cdr[2]), .Customized_PHY_Top_q0_ln2_pll_lock_o(pll[2]),
        .Customized_PHY_Top_q0_ln2_k_lock_o(klock[2]), .Customized_PHY_Top_q0_ln2_word_align_link_o(align[2]), .Customized_PHY_Top_q0_ln2_ready_o(ready[2]),
        .Customized_PHY_Top_q0_ln2_rx_clk_i(rxclk[2]), .Customized_PHY_Top_q0_ln2_rx_fifo_rden_i(1'b0), .Customized_PHY_Top_q0_ln2_tx_clk_i(txclk[2]), .Customized_PHY_Top_q0_ln2_tx_data_i(80'd0),
        .Customized_PHY_Top_q0_ln2_tx_fifo_wren_i(1'b0), .Customized_PHY_Top_q0_ln2_pma_rstn_i(pma_rstn), .Customized_PHY_Top_q0_ln2_pcs_rx_rst_i(!pma_rstn), .Customized_PHY_Top_q0_ln2_pcs_tx_rst_i(!pma_rstn),
        .Customized_PHY_Top_q0_ln3_rx_pcs_clkout_o(rxclk[3]), .Customized_PHY_Top_q0_ln3_rx_data_o(), .Customized_PHY_Top_q0_ln3_rx_fifo_rdusewd_o(),
        .Customized_PHY_Top_q0_ln3_rx_fifo_aempty_o(), .Customized_PHY_Top_q0_ln3_rx_fifo_empty_o(), .Customized_PHY_Top_q0_ln3_rx_valid_o(),
        .Customized_PHY_Top_q0_ln3_tx_pcs_clkout_o(txclk[3]), .Customized_PHY_Top_q0_ln3_tx_fifo_wrusewd_o(), .Customized_PHY_Top_q0_ln3_tx_fifo_afull_o(), .Customized_PHY_Top_q0_ln3_tx_fifo_full_o(),
        .Customized_PHY_Top_q0_ln3_refclk_o(), .Customized_PHY_Top_q0_ln3_signal_detect_o(sd[3]), .Customized_PHY_Top_q0_ln3_rx_cdr_lock_o(cdr[3]), .Customized_PHY_Top_q0_ln3_pll_lock_o(pll[3]),
        .Customized_PHY_Top_q0_ln3_k_lock_o(klock[3]), .Customized_PHY_Top_q0_ln3_word_align_link_o(align[3]), .Customized_PHY_Top_q0_ln3_ready_o(ready[3]),
        .Customized_PHY_Top_q0_ln3_rx_clk_i(rxclk[3]), .Customized_PHY_Top_q0_ln3_rx_fifo_rden_i(1'b0), .Customized_PHY_Top_q0_ln3_tx_clk_i(txclk[3]), .Customized_PHY_Top_q0_ln3_tx_data_i(80'd0),
        .Customized_PHY_Top_q0_ln3_tx_fifo_wren_i(1'b0), .Customized_PHY_Top_q0_ln3_pma_rstn_i(pma_rstn), .Customized_PHY_Top_q0_ln3_pcs_rx_rst_i(!pma_rstn), .Customized_PHY_Top_q0_ln3_pcs_tx_rst_i(!pma_rstn));

    // ---------------------------------------------------------------- per-lane status (osc domain)
    reg [255:0] cap;
    reg [31:0]  up = 32'd0;
    reg [15:0]  upl = 16'd0;
    always @(posedge osc) begin upl <= upl + 16'd1; if (&upl) up <= up + 32'd1; end
    genvar n;
    generate for (n = 0; n < 4; n = n + 1) begin : g_ln
        wire [5:0] lv = {ready[n], pll[n], align[n], klock[n], cdr[n], sd[n]};
        reg  [5:0] s1 = 6'd0, s2 = 6'd0, seen = 6'd0;
        reg  [15:0] sd_n = 16'd0, cdr_n = 16'd0;
        reg        sd_d = 1'b0, cdr_d = 1'b0;
        always @(posedge osc) begin
            s1 <= lv; s2 <= s1;
            seen <= seen | s2;
            sd_d <= s2[0]; cdr_d <= s2[1];
            if (s2[0] && !sd_d)  sd_n  <= sd_n + 16'd1;
            if (s2[1] && !cdr_d) cdr_n <= cdr_n + 16'd1;
        end
        always @(*) cap[16 + 48*n +: 48] = {cdr_n, sd_n, 4'd0, seen, s2};
    end endgenerate
    always @(*) begin cap[15:0] = 16'h5B30; cap[223:208] = 16'd0; cap[255:224] = up; end

    jtag_status #(.L(256)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap(cap), .cap2(128'd0), .o_w2(), .o_w2_data());

    // LED: any lane's signal_detect seen
    assign led_r = |{g_ln[0].seen[0], g_ln[1].seen[0], g_ln[2].seen[0], g_ln[3].seen[0]};
endmodule
