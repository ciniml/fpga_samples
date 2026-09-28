// USB 2.0 device bring-up on Tang Primer 25K + Pmod USB (TN710 USB2.0-RC circuit).
//
//   50MHz -> pll_usb -> 240MHz FCLK / 60MHz PCLK
//   UsbDevice (rtl/usb, Veryl) --UTMI--> usb_phy_gowin (UsbPhy + IDES8/OSER8) --> Pmod A/B
//
// Pmod A: USB_RX_D+/- (LVDS pair, HS data), D+/VREF and D-/VREF (LVDS pairs
//         used as single-ended comparators), TERM_RXDP / TERM_RXDN (drive low = 45 ohm)
// Pmod B: USB_TX_D+/- (LVCMOS33 pads, series R on the board), PULLUP_EN, VBUS_DET
//
// Debug: every ~100ms a 10-byte status frame on the UART (115200):
//   'U' flags addr frame_l frame_h rst_cnt err_cnt sof_cnt_l sof_cnt_h cap_state
//   flags: bit1:0 linestate, bit2 high_speed, bit3 configured, bit4 suspended,
//          bit5 vbus, bit6 pll lock, bit7 rxactive seen since the last frame
module top (
    input  wire clk_in,        // 50MHz
    input  wire reset_in,      // push button, active high
    output wire uart_txd,
    input  wire uart_rxd,

    // Pmod A
    input  wire usb_rx_dp,     // USB_RX_D+  (pin 1)
    input  wire usb_rx_dn,     // USB_RX_D-  (pin 7)
    input  wire usb_rxdp_p,    // D+         (pin 2)
    input  wire usb_rxdp_n,    // VREF       (pin 8)
    input  wire usb_rxdn_p,    // D-         (pin 3)
    input  wire usb_rxdn_n,    // VREF       (pin 9)
    output wire usb_term_dp,   // TERM_RXDP  (pin 4)
    output wire usb_term_dn,   // TERM_RXDN  (pin 10)
    // Pmod B
    output wire usb_tx_dp,     // USB_TX_D+  (pin 1)
    output wire usb_tx_dn,     // USB_TX_D-  (pin 7)
    output wire usb_pullup_en, // PULLUP_EN  (pin 2)
    input  wire vbus_det,      // VBUS_DET   (pin 3)

    output wire led_configured,
    output wire led_high_speed
);
    //------------------------------------------------------------------
    // clocks / reset
    //------------------------------------------------------------------
    wire pll_lock, fclk_240m, pclk_60m;
    pll_usb u_pll(.lock(pll_lock), .clkout0(fclk_240m), .clkout1(pclk_60m), .clkout2(), .clkout3(),
                  .clkin(clk_in), .psdir(1'b0), .pspulse(1'b0));
    // synchronous active-high reset in the 60MHz domain, held while the PLL is unlocked
    reg [3:0] rst_sr;
    always @(posedge pclk_60m or posedge reset_in)
        if (reset_in) rst_sr <= 4'hf; else rst_sr <= {rst_sr[2:0], ~pll_lock};
    wire rst = rst_sr[3];
    // 'R' from the host: hold the USB core in reset for ~70ms (pull-up off ->
    // the host sees a disconnect and re-enumerates); the capture/UART keep running
    reg [21:0] soft_cnt; reg soft_rst;
    wire h_rx_valid; wire [7:0] h_rx_data;
    always @(posedge pclk_60m or posedge rst)
        if (rst) begin soft_cnt <= 22'd0; soft_rst <= 1'b0; end
        else if (h_rx_valid && h_rx_data == "R") begin soft_rst <= 1'b1; soft_cnt <= 22'd0; end
        else if (soft_rst) begin soft_cnt <= soft_cnt + 1'b1; if (&soft_cnt) soft_rst <= 1'b0; end
    wire usb_rst = rst | soft_rst;

    //------------------------------------------------------------------
    // USB device core + PHY
    //------------------------------------------------------------------
    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       high_speed, configured, suspended, bus_reset, sof;
    wire [6:0] address;
    wire [10:0] frame;
    wire [15:0] vendor_reg;
    reg  [15:0] sof_cnt;
    reg  [7:0]  rst_cnt, err_cnt;
    wire        vbus_s;

`ifdef USB_FS_ONLY
    localparam HS_CAPABLE = 1'b0;   // make USB_FS_ONLY=1
`else
    localparam HS_CAPABLE = 1'b1;
`endif
    UsbDevice #(.HS_CAPABLE(HS_CAPABLE), .CLK_PER_US(60)) u_dev(
        .i_clk(pclk_60m), .i_rst(usb_rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(bus_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg),
        .i_vendor_status({8'h25, 3'b0, vbus_s, 3'b0, high_speed, sof_cnt}));   // 0x25 = "25K", flags, SOF count

    // dynamic IODELAY taps on the three receive paths (UART 'd'/'p'/'n' + value)
    reg  [7:0] dly_dd, dly_dp, dly_dn;
    wire [7:0] mon_dd, mon_dp, mon_dn;
    usb_phy_gowin #(.SE_FROM_DIFF(1), .DYN_DLY(1), .HS_CDR(1)) u_phy(
        .clk_i(pclk_60m), .fclk_i(fclk_240m), .rst_i(usb_rst), .pll_locked_i(pll_lock),
        .i_dly_dd(dly_dd), .i_dly_dp(dly_dp), .i_dly_dn(dly_dn), .o_mon_dd(mon_dd), .o_mon_dp(mon_dp), .o_mon_dn(mon_dn),
        .utmi_data_out_i(utmi_data_out), .utmi_txvalid_i(utmi_txvalid), .utmi_txready_o(utmi_txready),
        .utmi_data_in_o(utmi_data_in), .utmi_rxactive_o(utmi_rxactive), .utmi_rxvalid_o(utmi_rxvalid),
        .utmi_rxerror_o(utmi_rxerror), .utmi_linestate_o(utmi_linestate),
        .utmi_opmode_i(utmi_opmode), .utmi_xcvrselect_i(utmi_xcvrselect), .utmi_termselect_i(utmi_termselect),
        .usb_rx_dp_i(usb_rx_dp), .usb_rx_dn_i(usb_rx_dn),
        .usb_rxdp_p_i(usb_rxdp_p), .usb_rxdp_n_i(usb_rxdp_n),
        .usb_rxdn_p_i(usb_rxdn_p), .usb_rxdn_n_i(usb_rxdn_n),
        .usb_tx_dp_o(usb_tx_dp), .usb_tx_dn_o(usb_tx_dn),
        .usb_pullup_en_o(usb_pullup_en), .usb_term_dp_o(usb_term_dp), .usb_term_dn_o(usb_term_dn));

    reg [1:0] vbus_sr;
    always @(posedge pclk_60m) vbus_sr <= {vbus_sr[0], vbus_det};
    assign vbus_s = vbus_sr[1];
    assign led_configured = configured;
    assign led_high_speed = high_speed;

    //------------------------------------------------------------------
    // counters + UART status frame (pclk domain, UART at 60MHz)
    //------------------------------------------------------------------
    reg rxactive_seen;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin
            sof_cnt <= 16'd0; rst_cnt <= 8'd0; err_cnt <= 8'd0; rxactive_seen <= 1'b0;
        end else begin
            if (sof) sof_cnt <= sof_cnt + 1'b1;
            if (bus_reset) rst_cnt <= rst_cnt + 1'b1;
            if (utmi_rxerror && err_cnt != 8'hff) err_cnt <= err_cnt + 1'b1;
            if (utmi_rxactive) rxactive_seen <= 1'b1;
            if (frame_go) rxactive_seen <= 1'b0;
        end
    end

    reg [22:0] tick;           // 2^23 / 60MHz = 140ms
    reg        frame_go;
    always @(posedge pclk_60m or posedge rst)
        if (rst) begin tick <= 23'd0; frame_go <= 1'b0; end
        else begin tick <= tick + 1'b1; frame_go <= (tick == 23'd0); end

    wire [79:0] status = {{6'b0, cap_state}, sof_cnt[15:8], sof_cnt[7:0], err_cnt, rst_cnt,
                          {5'b0, frame[10:8]}, frame[7:0], address[6:0], 1'b0,
                          rxactive_seen, pll_lock, vbus_s, suspended, configured, high_speed, utmi_linestate,
                          8'h55};
    reg [79:0] shift; reg [3:0] left; reg tx_valid; wire tx_ready;   // tx_ready is driven by the UART mux below
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin shift <= 80'd0; left <= 4'd0; tx_valid <= 1'b0; end
        else if (frame_go && left == 4'd0) begin shift <= status; left <= 4'd10; tx_valid <= 1'b1; end
        else if (tx_valid && tx_ready) begin
            shift <= {8'd0, shift[79:8]}; left <= left - 1'b1;
            if (left == 4'd1) tx_valid <= 1'b0;
        end
    end
    //------------------------------------------------------------------
    // sample capture (debug): host 'C' arms, the ring keeps 256 words of
    // history and stops 1792 words after the first K sample on the
    // single-ended receivers; 'R' soft-resets the USB core (re-enumeration); 'D' dumps 2048 x 6 bytes (oldest first):
    //   rx_dp rx_dn rx_dd tx_dp tx_dn {4'b0, rxerror, rxvalid, rxactive, tx_oe}   (bit 0 = first sample)
    //------------------------------------------------------------------
    uart_rx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(60_000_000 / 115200)) u_uart_rx(
        .clock(pclk_60m), .reset(rst), .data_valid(h_rx_valid), .data_ready(1'b1), .data_bits(h_rx_data), .rx(uart_rxd), .overrun());
    // capture word (6 bytes): raw dp, raw dn, raw dd, CDR byte, {se0_f, valid, nbits[3:0], dsel[1:0]}, {rxerror, rxvalid, rxactive, tx_oe, lock, 3'b0}
    wire [47:0] cap_word = {3'b0, u_phy.g_cdr.u_hs_cdr.o_lock, u_phy.tx_oe, utmi_rxactive, utmi_rxvalid, utmi_rxerror,
                            u_phy.g_cdr.u_hs_cdr.u_cdr.dsel, u_phy.g_cdr.u_hs_cdr.u_cdr.o_nbits, u_phy.g_cdr.u_hs_cdr.o_valid, u_phy.se0_f,
                            u_phy.g_cdr.u_hs_cdr.o_byte, mon_dd, mon_dn, mon_dp};
    reg  [47:0] capmem [0:2047] /* synthesis syn_ramstyle = "block_ram" */;
    reg  [10:0] cap_wp, cap_rp;
    reg  [10:0] cap_left;
    reg  [1:0]  cap_state;      // 0 idle, 1 armed (ring), 2 post-trigger, 3 dumping
    //------------------------------------------------------------------
    // sample-stream agreement measurement: 'm' counts, over 2^20 words in
    // which the single-ended comparators are not both idle, the samples where
    // dp == dd and where ~dn == dd; reply 'M' + active(32) + match_dp(32) + match_dn(32)
    //------------------------------------------------------------------
    reg  [1:0] cmd_sel; reg cmd_val;    // 'd'/'p'/'n' then one value byte
    always @(posedge pclk_60m or posedge rst) begin
        // defaults: dp / dn comparators +16 taps intrinsic offset, +56 / +111 taps = 1/3 / 2/3 UI (usb_dlyscan.py)
        if (rst) begin dly_dd <= 8'd0; dly_dp <= 8'd72; dly_dn <= 8'd127; cmd_sel <= 2'd0; cmd_val <= 1'b0; end
        else if (h_rx_valid) begin
            if (cmd_val) begin
                cmd_val <= 1'b0;
                case (cmd_sel) 2'd1: dly_dd <= h_rx_data; 2'd2: dly_dp <= h_rx_data; 2'd3: dly_dn <= h_rx_data; default: ; endcase
            end else if (h_rx_data == "d") begin cmd_sel <= 2'd1; cmd_val <= 1'b1; end
            else if (h_rx_data == "p") begin cmd_sel <= 2'd2; cmd_val <= 1'b1; end
            else if (h_rx_data == "n") begin cmd_sel <= 2'd3; cmd_val <= 1'b1; end
        end
    end
    function [3:0] cnt8(input [7:0] v); integer k; begin cnt8 = 0; for (k = 0; k < 8; k = k + 1) cnt8 = cnt8 + v[k]; end endfunction
    reg        meas_run; reg [19:0] meas_left;
    reg [31:0] m_active, m_dp, m_dn;
    reg [103:0] m_shift; reg [3:0] m_left; reg m_valid;
    wire       m_ready;
    wire       m_word_active = |(mon_dp | mon_dn);
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin meas_run <= 1'b0; meas_left <= 20'd0; m_active <= 0; m_dp <= 0; m_dn <= 0; m_shift <= 0; m_left <= 0; m_valid <= 1'b0; end
        else begin
            if (!meas_run && !cmd_val && h_rx_valid && h_rx_data == "m") begin
                meas_run <= 1'b1; meas_left <= 20'hfffff; m_active <= 0; m_dp <= 0; m_dn <= 0;
            end else if (meas_run) begin
                if (m_word_active) begin
                    m_active <= m_active + 8;
                    m_dp <= m_dp + cnt8(~(mon_dp ^ mon_dd));
                    m_dn <= m_dn + cnt8(mon_dn ^ mon_dd);
                end
                meas_left <= meas_left - 1'b1;
                if (meas_left == 0) begin meas_run <= 1'b0; m_shift <= {m_dn, m_dp, m_active, 8'h4d}; m_left <= 4'd13; m_valid <= 1'b1; end
            end else if (m_valid && m_ready) begin
                m_shift <= {8'd0, m_shift[103:8]}; m_left <= m_left - 1'b1;
                if (m_left == 4'd1) m_valid <= 1'b0;
            end
        end
    end
    reg  [2:0]  dump_byte;
    reg  [47:0] cap_rdata;
    reg         cap_rd_pending;
    // trigger: any edge on either single-ended comparator (line state change) or host 'S'
    reg  [7:0]  rx_dp_q, rx_dn_q;
    always @(posedge pclk_60m) begin rx_dp_q <= mon_dp; rx_dn_q <= mon_dn; end
    wire        cap_trig = (mon_dp != rx_dp_q) || (mon_dn != rx_dn_q) || (h_rx_valid && h_rx_data == "S");
    always @(posedge pclk_60m) if (cap_state == 2'd1 || cap_state == 2'd2) capmem[cap_wp] <= cap_word;
    always @(posedge pclk_60m) cap_rdata <= capmem[cap_rp];
    reg dump_valid; wire dump_ready;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin
            cap_state <= 2'd0; cap_wp <= 11'd0; cap_rp <= 11'd0; cap_left <= 11'd0; dump_byte <= 3'd0;
            dump_valid <= 1'b0; cap_rd_pending <= 1'b0;
        end else begin
            cap_rd_pending <= 1'b0;
            case (cap_state)
            2'd0: if (h_rx_valid && h_rx_data == "C") begin cap_state <= 2'd1; cap_wp <= 11'd0; cap_left <= 11'd256; end
                  else if (h_rx_valid && h_rx_data == "D") begin
                      cap_state <= 2'd3; cap_rp <= cap_wp; cap_left <= 11'd2047; dump_byte <= 3'd0; cap_rd_pending <= 1'b1;
                  end
            2'd1: if (h_rx_valid && h_rx_data == "D") begin   // dump whatever the ring holds (no trigger seen)
                      cap_state <= 2'd3; cap_rp <= cap_wp; cap_left <= 11'd2047; dump_byte <= 3'd0; cap_rd_pending <= 1'b1;
                  end else begin
                cap_wp <= cap_wp + 1'b1;
                if (cap_left != 0) cap_left <= cap_left - 1'b1;
                else if (cap_trig) begin cap_state <= 2'd2; cap_left <= 11'd1791; end
            end
            2'd2: begin
                cap_wp <= cap_wp + 1'b1;
                if (cap_left == 0) cap_state <= 2'd0; else cap_left <= cap_left - 1'b1;
            end
            2'd3: if (!dump_valid && !cap_rd_pending) begin
                dump_valid <= 1'b1;
            end else if (dump_valid && dump_ready) begin
                dump_valid <= 1'b0;
                if (dump_byte == 3'd5) begin
                    dump_byte <= 3'd0; cap_rp <= cap_rp + 1'b1; cap_rd_pending <= 1'b1;
                    if (cap_left == 0) cap_state <= 2'd0; else cap_left <= cap_left - 1'b1;
                end else dump_byte <= dump_byte + 1'b1;
            end
            endcase
        end
    end
    wire [7:0] dump_data = cap_rdata[dump_byte*8 +: 8];

    // UART TX mux: dump > measurement reply > status frames
    wire        mux_valid = (cap_state == 2'd3) ? dump_valid : m_valid ? m_valid : tx_valid;
    wire [7:0]  mux_data  = (cap_state == 2'd3) ? dump_data  : m_valid ? m_shift[7:0] : shift[7:0];
    wire        mux_ready;
    assign dump_ready = (cap_state == 2'd3) & mux_ready;
    assign m_ready    = (cap_state != 2'd3) & mux_ready;
    assign tx_ready   = (cap_state != 2'd3) & ~m_valid & mux_ready;
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(60_000_000 / 115200)) u_uart_tx(
        .clock(pclk_60m), .reset(rst), .data_valid(mux_valid), .data_ready(mux_ready), .data_bits(mux_data), .tx(uart_txd));
endmodule
