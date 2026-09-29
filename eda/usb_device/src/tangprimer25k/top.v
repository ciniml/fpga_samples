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
    UsbDevice #(.HS_CAPABLE(HS_CAPABLE), .CLK_PER_US(60), .BULK_IN_FULL_ONLY(`BULK_IN_FULL_ONLY)) u_dev(   // BULK_IN_FULL_ONLY=1: no short packets (hunt test aid)
        .i_clk(pclk_60m), .i_rst(usb_rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(bus_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg),
        .i_vendor_status({8'h25, 3'b0, vbus_s, 3'b0, high_speed,
                          vendor_reg[0] ? ck_rd : vendor_reg[1] ? ck_wr : vendor_reg[2] ? ack_cnt : vendor_reg[3] ? rd_adv : sof_cnt}));
    // vendor reg bit2: number of ACKs taken for our EP1 IN packets, bit3: total rd_ptr advance (bytes, mod 65536)
    reg [15:0] ack_cnt, rd_adv;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin ack_cnt <= 16'd0; rd_adv <= 16'd0; end
        else if (soft_rst) begin ack_cnt <= 16'd0; rd_adv <= 16'd0; end
        else begin
            if (u_dev.rx_handshake && u_dev.rx_pid == 4'h2 && u_dev.in_pending && u_dev.last_in_ep1) ack_cnt <= ack_cnt + 1'b1;   // rx_pid is the 4-bit PID
            if (u_dev.rd_ptr != rd_ptr_q) rd_adv <= rd_adv + (u_dev.rd_ptr - rd_ptr_q);
        end
    end
    // Bulk FIFO checksums (vendor reg bit1: bytes written into the FIFO, bit0: bytes read out for EP1 IN), 16-bit sums;
    // with the host's own sums of what it sent / received they tell on which side of the FIFO a silent corruption happened.
    // Only committed bytes count: a packet's bytes are summed while it arrives / goes out and added when the
    // device advances wr_ptr (OUT accepted, not a repeat) or rd_ptr (our IN packet acknowledged).
    reg [15:0] ck_wr, ck_rd, ck_wtmp, ck_rtmp; reg [12:0] wr_ptr_q, rd_ptr_q;   // pointers are $clog2(BULK_FIFO_DEPTH)+1 = 13 bits
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin ck_wr <= 16'd0; ck_rd <= 16'd0; ck_wtmp <= 16'd0; ck_rtmp <= 16'd0; wr_ptr_q <= 13'd0; rd_ptr_q <= 13'd0; end
        else if (soft_rst) begin ck_wr <= 16'd0; ck_rd <= 16'd0; ck_wtmp <= 16'd0; ck_rtmp <= 16'd0; end
        else begin
            wr_ptr_q <= u_dev.wr_ptr; rd_ptr_q <= u_dev.rd_ptr;
            if (u_dev.rx_data_start) ck_wtmp <= 16'd0; else if (u_dev.fifo_we) ck_wtmp <= ck_wtmp + u_dev.rx_data;
            if (u_dev.wr_ptr != wr_ptr_q) ck_wr <= ck_wr + ck_wtmp;
            if (u_dev.tx_start) ck_rtmp <= 16'd0; else if (u_dev.u_sie.payload_acc && u_dev.last_in_ep1) ck_rtmp <= ck_rtmp + u_dev.u_sie.i_tx_data;
            if (u_dev.rd_ptr != rd_ptr_q) ck_rd <= ck_rd + ck_rtmp;
        end
    end

    // dynamic IODELAY taps on the three receive paths: tracking loop (UART 't' 1, default)
    // or manual (UART 't' 0 then 'd'/'p'/'n' + value)
    reg  [7:0] dly_dd, dly_dp, dly_dn; reg track_en;
    wire [7:0] mon_dd, mon_dp, mon_dn, dly_dd_now;
    // 4-phase oversampling PLL for the HS serial path (fed by the 60 MHz UTMI clock: VCO 960 MHz -> 480 MHz x 4, BANK6-7 HCLK group)
    wire os_lock, os_f0 /* synthesis syn_keep=1 */, os_f90, os_f180, os_f270;
    wire [31:0] os_samples;   // raw OSIDES32 word (os_pclk domain; captured asynchronously for debugging)
    wire [15:0] os_cmp;       // {cdp, cdn} comparator IDES8 words (os_pclk domain)
    wire os_pclk /* synthesis syn_keep=1 */;   // oversampler PCLK (~120.3 MHz), used below so the net survives for the SDC
    reg  os_tick; always @(posedge os_pclk) os_tick <= ~os_tick;   // exercises the net (status bit)
    pll_usb_os #(.FCLKIN("60"), .MDIV(16), .MDIV_FRAC(0), .ODIV(2)) u_pll_os(
        .lock(os_lock), .clkout0(os_f0), .clkout1(os_f90), .clkout2(os_f180), .clkout3(os_f270), .clkin(pclk_60m),
        .pssel(dps_sel), .psdir(dps_dir), .pspulse(dps_pulse));
    // Eye scan ('Z' + byte, bit 7 = direction): the four oversampling phases are stepped one fine
    // step each (1/8 VCO period = 130 ps at VCO 960 MHz, 16 steps per HS bit), one channel at a
    // time, with the CDR frozen ('F'); the packet statistics ('m') then give the error rate per point.
    // (An IODELAY in front of the OSIDES32 is not allowed: its D must come straight from the IBUF.)
    reg  [2:0] dps_sel; reg dps_dir, dps_pulse; reg [3:0] dps_st; reg [4:0] dps_cnt;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin dps_sel <= 3'd0; dps_dir <= 1'b0; dps_pulse <= 1'b0; dps_st <= 4'd0; dps_cnt <= 5'd0; end
        else if (dps_st == 4'd0) begin
            if (dps_go) begin dps_st <= 4'd1; dps_sel <= 3'd0; dps_dir <= dps_dir_req; dps_cnt <= 5'd0; end
        end else begin
            dps_cnt <= dps_cnt + 1'b1;
            if (dps_cnt == 5'd8) dps_pulse <= 1'b1;
            if (dps_cnt == 5'd24) dps_pulse <= 1'b0;
            if (dps_cnt == 5'd31) begin
                if (dps_sel == 3'd3) dps_st <= 4'd0; else dps_sel <= dps_sel + 1'b1;
            end
        end
    end
    usb_phy_gowin #(.SE_FROM_DIFF(1), .DYN_DLY(0), .HS_CDR(0), .HS_OS32(1)) u_phy(
        .os_clk_ref_i(clk_in), .os_rstn_ref_i(~reset_in), .os_pll_lock_i(os_lock),
        .os_fclk0_i(os_f0), .os_fclk90_i(os_f90), .os_fclk180_i(os_f180), .os_fclk270_i(os_f270), .os_pclk_o(os_pclk), .os_samples_o(os_samples), .os_cmp_o(os_cmp), .i_scan_freeze(scan_freeze), .i_scan_ofs(scan_ofs), .i_scan_class(scan_class), .i_hist_run(meas_run), .o_hist(hist), .o_txfifo_dbg(txfifo_dbg),
        .clk_i(pclk_60m), .fclk_i(fclk_240m), .rst_i(usb_rst), .pll_locked_i(pll_lock),
        .i_track_en(track_en), .i_dly_dd(dly_dd), .i_dly_dp(dly_dp), .i_dly_dn(dly_dn), .o_dly_dd(dly_dd_now),
        .o_mon_dd(mon_dd), .o_mon_dp(mon_dp), .o_mon_dn(mon_dn),
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
        end else if (soft_rst) begin
            sof_cnt <= 16'd0; rst_cnt <= 8'd0; err_cnt <= 8'd0; rxactive_seen <= 1'b0;   // 'R' also clears the counters
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

    wire [79:0] status = {{4'b0, os_tick, os_lock, cap_state}, sof_cnt[15:8], sof_cnt[7:0], err_cnt, rst_cnt,
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
    // capture word (6 bytes): raw dp, raw dn, raw dd, CDR byte, dd tap in use, {3'b0, lock, tx_oe, rxactive, rxvalid, rxerror}
    // capture word (6 bytes): OSIDES32 samples[31:0] (raw, sampled at 60 MHz), CDR byte, {se0_60, valid, rxactive, rxvalid, rxerror, 3'b0}
    // 60 MHz capture word (6 bytes): [0] CDR/FIFO byte, [1] utmi_data_in, [2] {tx_oe, txvalid, cmp_se0, se0_60, valid, rxactive, rxvalid, rxerror},
    //   [3] {mon_dp[0], mon_dn[0], linestate, xcvr, termsel, txready}, [4] os_samples[7:0] (async), [5] os_samples[15:8]
    wire [47:0] cap_word = {u_phy.g_os32.u_os32.wp_bin, u_phy.g_os32.u_os32.act, u_phy.g_os32.u_os32.rp_bin, u_phy.g_os32.u_os32.wp_gray_r2,   // (debug: wp_bin/act are PCLK-domain, sampled asynchronously)
                            mon_dp[0], mon_dn[0], utmi_linestate, utmi_xcvrselect, utmi_termselect, utmi_txready,
                            u_phy.tx_oe, utmi_txvalid, ~mon_dp[0] & ~mon_dn[0], u_phy.g_os32.u_os32.se0_60, u_phy.g_os32.u_os32.o_valid, utmi_rxactive, utmi_rxvalid, utmi_rxerror,
                            utmi_data_in, u_phy.g_os32.u_os32.o_byte};
    // 8192 entries: the packet log must outlive the ~2 ms it takes the host's dump command to arrive through the FTDI
    reg  [47:0] capmem [0:8191] /* synthesis syn_ramstyle = "block_ram" */;
    reg  [12:0] cap_wp, cap_rp;
    reg  [12:0] cap_left;
    reg  [1:0]  cap_state;      // 0 idle, 1 armed (ring), 2 post-trigger, 3 dumping
    //------------------------------------------------------------------
    // sample-stream agreement measurement: 'm' counts, over 2^20 words in
    // which the single-ended comparators are not both idle, the samples where
    // dp == dd and where ~dn == dd; reply 'M' + active(32) + match_dp(32) + match_dn(32)
    //------------------------------------------------------------------
    reg  [2:0] cmd_sel; reg cmd_val;    // 'd'/'p'/'n'/'t'/'F' then one value byte
    reg        scan_freeze, scan_ofs; reg [2:0] scan_class;   // 'F' value: bit 7 = freeze the HS CDR at class [2:0]; bit 6 = per-packet acquisition at best + [2:0]
    wire [191:0] hist;
    wire [31:0]  txfifo_dbg;   // {overrun, underrun} counts of the HS transmit FIFO
    reg        dps_go, dps_dir_req;                 // 'Z' value: bit 7 = direction; one fine step on all four phases
    always @(posedge pclk_60m or posedge rst) begin
        // manual defaults: dp / dn comparators +12 taps intrinsic offset, +48 / +96 taps = 1/3 / 2/3 UI (usb_dlyscan.py: 1 UI = 144 taps)
        if (rst) begin dly_dd <= 8'd0; dly_dp <= 8'd0; dly_dn <= 8'd0; track_en <= 1'b1; cmd_sel <= 3'd0; cmd_val <= 1'b0; scan_freeze <= 1'b0; scan_ofs <= 1'b0; scan_class <= 3'd0; dps_go <= 1'b0; dps_dir_req <= 1'b0; end
        else if (h_rx_valid) begin
            dps_go <= 1'b0;
            if (cmd_val) begin
                cmd_val <= 1'b0;
                case (cmd_sel) 3'd1: dly_dd <= h_rx_data; 3'd2: dly_dp <= h_rx_data; 3'd3: dly_dn <= h_rx_data; 3'd4: track_en <= h_rx_data[0];
                               3'd5: begin scan_freeze <= h_rx_data[7]; scan_ofs <= h_rx_data[6]; scan_class <= h_rx_data[2:0]; end
                               3'd6: begin dps_go <= 1'b1; dps_dir_req <= h_rx_data[7]; end default: ; endcase
            end else if (h_rx_data == "d") begin cmd_sel <= 3'd1; cmd_val <= 1'b1; end
            else if (h_rx_data == "p") begin cmd_sel <= 3'd2; cmd_val <= 1'b1; end
            else if (h_rx_data == "n") begin cmd_sel <= 3'd3; cmd_val <= 1'b1; end
            else if (h_rx_data == "t") begin cmd_sel <= 3'd4; cmd_val <= 1'b1; end
            else if (h_rx_data == "F") begin cmd_sel <= 3'd5; cmd_val <= 1'b1; end
            else if (h_rx_data == "Z") begin cmd_sel <= 3'd6; cmd_val <= 1'b1; end
        end
    end
    function [3:0] cnt8(input [7:0] v); integer k; begin cnt8 = 0; for (k = 0; k < 8; k = k + 1) cnt8 = cnt8 + v[k]; end endfunction
    // 'm': packet statistics over 2^20 clocks (17.5 ms): 'M' + {packets, bad packets, rxerror pulses} (3 x 32 bit, LSB first).
    // A packet is bad when it ended with rxerror, its PID check fails, or it is an IN token whose address/CRC bytes
    // differ from those of the first IN token of the window (the host polls the other devices on the hub with
    // identical IN tokens some 600k times a second: a free bit-error reference for the eye scan).
    reg        meas_run; reg [19:0] meas_left;
    reg [31:0] m_active, m_dp, m_dn;
    reg [327:0] m_shift; reg [5:0] m_left; reg m_valid;
    wire       m_ready;
    reg        m_rxact_q, m_err, m_ref_v; reg [7:0] m_pid, m_b1, m_b2, m_ref1, m_ref2; reg [2:0] m_idx;
    wire       m_pid_bad = m_pid[7:4] != ~m_pid[3:0];
    wire       m_tok_bad = m_ref_v && (m_pid == 8'h69) && ((m_b1 != m_ref1) || (m_b2 != m_ref2));
    always @(posedge pclk_60m) begin
        m_rxact_q <= utmi_rxactive;
        if (!utmi_rxactive) begin m_idx <= 3'd0; if (!m_rxact_q) m_err <= 1'b0; end
        if (utmi_rxerror) m_err <= 1'b1;
        if (utmi_rxvalid && m_idx != 3'd7) begin
            m_idx <= m_idx + 1'b1;
            case (m_idx) 3'd0: m_pid <= utmi_data_in; 3'd1: m_b1 <= utmi_data_in; 3'd2: m_b2 <= utmi_data_in; default: ; endcase
        end
    end
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin meas_run <= 1'b0; meas_left <= 20'd0; m_active <= 0; m_dp <= 0; m_dn <= 0; m_shift <= 0; m_left <= 0; m_valid <= 1'b0; m_ref_v <= 1'b0; m_ref1 <= 0; m_ref2 <= 0; end
        else begin
            if (!meas_run && !cmd_val && h_rx_valid && h_rx_data == "m") begin
                meas_run <= 1'b1; meas_left <= 20'hfffff; m_active <= 0; m_dp <= 0; m_dn <= 0; m_ref_v <= 1'b0;
            end else if (meas_run) begin
                if (m_rxact_q && !utmi_rxactive && m_idx != 3'd0) begin   // packet end (with at least one byte)
                    m_active <= m_active + 1'b1;
                    if (m_err || utmi_rxerror || m_pid_bad || m_tok_bad) m_dp <= m_dp + 1'b1;
                    else if (!m_ref_v && m_pid == 8'h69 && m_idx == 3'd3) begin m_ref_v <= 1'b1; m_ref1 <= m_b1; m_ref2 <= m_b2; end
                end
                if (utmi_rxerror) m_dn <= m_dn + 1'b1;
                meas_left <= meas_left - 1'b1;
                if (meas_left == 0) begin meas_run <= 1'b0; m_shift <= {txfifo_dbg, hist, m_dn, m_dp, m_active, 8'h4d}; m_left <= 6'd41; m_valid <= 1'b1; end
            end else if (m_valid && m_ready) begin
                m_shift <= {8'd0, m_shift[327:8]}; m_left <= m_left - 1'b1;
                if (m_left == 6'd1) m_valid <= 1'b0;
            end
        end
    end
    reg  [2:0]  dump_byte;
    reg  [47:0] cap_rdata;
    reg         cap_rd_pending;
    // trigger: any edge on either single-ended comparator (line state change) or host 'S'
    reg  [7:0]  rx_dp_q, rx_dn_q;
    always @(posedge pclk_60m) begin rx_dp_q <= mon_dp; rx_dn_q <= mon_dn; end
    reg  [1:0]  cap_mode;       // 0: line activity / 'S'; 1 ('E'): utmi_rxerror (mostly history); 2 ('T'): own transmission start; 3 ('L'): packet log
    //------------------------------------------------------------------
    // Packet log ('L'): instead of line samples the ring takes one word per
    // event, so it spans hundreds of packets: {tag[3:0], session[3:0], ts[19:0] (60 MHz), byte[7:0], extra[11:0]}
    //   tag 1: received byte (first three bytes of a packet only)
    //   tag 2: packet end (byte = {3'b0, in_pending, toggle_in, toggle_out, bulk_drop, rxerror}, extra = byte count)
    //   tag 3: own transmission start (byte = PID)    tag 4: own transmission end ({byte, extra[7:0]} = 16-bit sum of the payload bytes sent)
    // Tokens for other addresses and SOFs are dropped (decided at their address byte, so
    // bytes go through a one-entry delay), which keeps the FTDI's polling out of the log.
    //------------------------------------------------------------------
    reg  [19:0] log_ts; always @(posedge pclk_60m) log_ts <= log_ts + 1'b1;
    reg  [3:0]  log_sess;
    reg  [2:0]  log_cnt; reg log_skip; reg [7:0] log_held; reg log_heldv; reg log_end_p; reg log_end_err; reg [7:0] log_pid; reg [2:0] log_cnt_l;
    reg  [11:0] log_nbytes, log_nbytes_l;
    reg         rxact_q; always @(posedge pclk_60m) rxact_q <= utmi_rxactive;
    wire        log_is_tok = log_pid[1:0] == 2'b01;
    // two request ports (rx / tx) into a 4-entry queue, one ring write per clock
    reg  [47:0] lq [0:3]; reg [2:0] lq_w, lq_r;
    wire        lq_empty = lq_w == lq_r;
    reg  [47:0] lreq_a, lreq_b; reg lreq_av, lreq_bv;
    always @(posedge pclk_60m) begin
        lreq_av <= 1'b0; lreq_bv <= 1'b0;
        // ---- receive side ----
        if (utmi_rxvalid) begin
            if (log_cnt == 3'd0) log_pid <= utmi_data_in;
            // dropped: SOFs, tokens for other addresses, and PINGs (the host PINGs every 2.4 us while our
            // FIFO is full: they would flush the ring before the host's dump command arrives)
            if (log_cnt == 3'd1 && ((log_pid[1:0] == 2'b01) && (log_pid == 8'ha5 || utmi_data_in[6:0] != address) || log_pid == 8'hb4
                                    || (log_pid == 8'h69 && u_dev.fifo_count < 13'd512)))   // IN we will NAK
                log_skip <= 1'b1;
            else if (log_cnt >= 3'd1 && log_cnt <= 3'd3 && !log_skip && log_heldv) begin   // bytes 0..2 only
                lreq_a <= {4'd1, log_sess, log_ts, log_held, 12'd0}; lreq_av <= 1'b1;
            end
            log_held <= utmi_data_in; log_heldv <= 1'b1;
            if (log_cnt != 3'd7) log_cnt <= log_cnt + 1'b1;
            if (log_nbytes != 12'hfff) log_nbytes <= log_nbytes + 1'b1;
        end
        if (rxact_q && !utmi_rxactive) begin      // packet end
            if (!log_skip && log_heldv && log_cnt <= 3'd3) begin lreq_a <= {4'd1, log_sess, log_ts, log_held, 12'd0}; lreq_av <= 1'b1; end
            log_end_p <= !log_skip && (log_cnt != 3'd0); log_end_err <= utmi_rxerror; log_cnt_l <= log_cnt; log_nbytes_l <= log_nbytes;
            log_cnt <= 3'd0; log_skip <= 1'b0; log_heldv <= 1'b0; log_nbytes <= 12'd0;
        end else if (log_end_p) begin
            log_end_p <= 1'b0;
            lreq_a <= {4'd2, log_sess, log_ts, 3'd0, u_dev.in_pending, u_dev.toggle_in, u_dev.toggle_out, u_dev.bulk_drop, log_end_err | utmi_rxerror,
                       log_nbytes_l}; lreq_av <= 1'b1;
        end
        if (utmi_rxerror && !utmi_rxactive && !rxact_q && !log_end_p) begin   // error outside a packet (stall / blank)
            lreq_a <= {4'd2, log_sess, log_ts, 8'hff, 12'd1}; lreq_av <= 1'b1;
        end
        // ---- transmit side ----
        // our NAKs are not logged either (same reason)
        if (u_phy.tx_oe && !tx_oe_q && u_dev.u_sie.tx_pid != 4'ha) begin lreq_b <= {4'd3, log_sess, log_ts, ~u_dev.u_sie.tx_pid, u_dev.u_sie.tx_pid, 12'd0}; lreq_bv <= 1'b1; end
        if (!u_phy.tx_oe && tx_oe_q && u_dev.u_sie.tx_pid != 4'ha) begin lreq_b <= {4'd4, log_sess, log_ts, ck_rtmp[15:8], 4'd0, ck_rtmp[7:0]}; lreq_bv <= 1'b1; end   // byte sum of the packet just sent
    end
    always @(posedge pclk_60m) begin
        if (cap_state == 2'd0) begin lq_w <= 3'd0; lq_r <= 3'd0; end
        else begin
            if (lreq_av && lreq_bv) begin lq[lq_w[1:0]] <= lreq_a; lq[lq_w[1:0] + 2'd1] <= lreq_b; lq_w <= lq_w + 3'd2; end
            else if (lreq_av) begin lq[lq_w[1:0]] <= lreq_a; lq_w <= lq_w + 3'd1; end
            else if (lreq_bv) begin lq[lq_w[1:0]] <= lreq_b; lq_w <= lq_w + 3'd1; end
            if (!lq_empty) lq_r <= lq_r + 3'd1;
        end
    end
    wire        log_we   = (cap_mode == 2'd3) && !lq_empty;
    wire [47:0] log_word = lq[lq_r[1:0]];
    reg         tx_oe_q; always @(posedge pclk_60m) tx_oe_q <= u_phy.tx_oe;
    reg         utmi_rxactive_q1, rxv_seen;   // first byte of a packet: rxvalid while no earlier byte was seen
    always @(posedge pclk_60m) begin utmi_rxactive_q1 <= rxv_seen; if (!utmi_rxactive) rxv_seen <= 1'b0; else if (utmi_rxvalid) rxv_seen <= 1'b1; end
    reg         cap_ping;       // with 'P': mode 1 triggers on a received PING PID (0xb4) instead of rxerror
    reg         ping_pid_seen;  // PING PID was the previous byte of this packet
    always @(posedge pclk_60m) begin
        if (!utmi_rxactive) ping_pid_seen <= 1'b0;
        else if (utmi_rxvalid) ping_pid_seen <= (utmi_data_in == 8'hb4) && !utmi_rxactive_q1;
    end
    wire        cap_trig = cap_mode == 2'd1 ? (cap_ping ? (utmi_rxvalid && ping_pid_seen && utmi_data_in[6:0] == address) : utmi_rxerror) : cap_mode == 2'd2 ? (u_phy.tx_oe & ~tx_oe_q) :
                           (mon_dp != rx_dp_q) || (mon_dn != rx_dn_q) || (h_rx_valid && h_rx_data == "S");
`ifdef CAP_OS
    // Capture in the oversampler PCLK domain (120 MHz): {gb_valid, lock, se0, nbits[3:0], bits[4:0], 4'b0, samples[31:0]}.
    // The ring is written on every PCLK while the 60 MHz side is armed/post-trigger; the dump starts at the
    // (then static) PCLK write pointer.
    reg [2:0]  os_run_s; always @(posedge os_pclk) os_run_s <= {os_run_s[1:0], cap_state == 2'd1 || cap_state == 2'd2};
    reg [12:0] os_wp;
    wire [47:0] cap_word_os = {u_phy.g_os32.u_os32.gb_valid, u_phy.g_os32.u_os32.o_lock, u_phy.g_os32.u_os32.se0,
                               u_phy.g_os32.u_os32.nbits,
`ifdef CAP_CMP
                               u_phy.g_os32.u_os32.wp_bin,          // (instead of bits)
`else
                               u_phy.g_os32.u_os32.bits,
`endif
                               u_phy.g_os32.u_os32.act, u_phy.g_os32.u_os32.toen, u_phy.g_os32.u_os32.sq_open, u_phy.g_os32.u_os32.reacq,
`ifdef CAP_CMP
                               os_cmp, os_samples[15:0]};   // {cdp, cdn}, samples[15:0]
`else
                               os_samples};
`endif
    always @(posedge os_pclk) if (os_run_s[2]) begin capmem[os_wp] <= cap_word_os; os_wp <= os_wp + 1'b1; end
    wire [12:0] cap_start = os_wp;
    localparam CAP_POST = 13'd3600;
    localparam CAP_POST_TX = 13'd1600;
`else
    always @(posedge pclk_60m) if (cap_state == 2'd1 || cap_state == 2'd2) begin
        if (cap_mode == 2'd3) begin if (log_we) capmem[cap_wp] <= log_word; end
        else capmem[cap_wp] <= cap_word;
    end
    wire [12:0] cap_start = cap_wp;
    localparam CAP_POST = 13'd7167;
    localparam CAP_POST_TX = 13'd6000;
`endif
    always @(posedge pclk_60m) cap_rdata <= capmem[cap_rp];
    reg dump_valid; wire dump_ready;
    always @(posedge pclk_60m or posedge rst) begin
        if (rst) begin
            cap_state <= 2'd0; cap_wp <= 13'd0; cap_rp <= 13'd0; cap_left <= 13'd0; dump_byte <= 3'd0;
            dump_valid <= 1'b0; cap_rd_pending <= 1'b0; cap_mode <= 2'd0; log_sess <= 4'd0; cap_ping <= 1'b0;
        end else begin
            cap_rd_pending <= 1'b0;
            case (cap_state)
            2'd0: if (h_rx_valid && (h_rx_data == "C" || h_rx_data == "E" || h_rx_data == "P" || h_rx_data == "T" || h_rx_data == "L")) begin
                      cap_state <= 2'd1; cap_wp <= 13'd0; cap_left <= 13'd1024; cap_ping <= h_rx_data == "P";
                      cap_mode <= (h_rx_data == "E" || h_rx_data == "P") ? 2'd1 : h_rx_data == "T" ? 2'd2 : h_rx_data == "L" ? 2'd3 : 2'd0;
                      if (h_rx_data == "L") log_sess <= log_sess + 1'b1;
                  end
                  else if (h_rx_valid && h_rx_data == "D") begin
                      cap_state <= 2'd3; cap_rp <= cap_start; cap_left <= 13'd8191; dump_byte <= 3'd0; cap_rd_pending <= 1'b1;
                  end
            2'd1: if (h_rx_valid && h_rx_data == "D") begin   // dump whatever the ring holds (no trigger seen)
                      cap_state <= 2'd3; cap_rp <= cap_start; cap_left <= 13'd8191; dump_byte <= 3'd0; cap_rd_pending <= 1'b1;
                  end else if (cap_mode == 2'd3) begin
                if (log_we) cap_wp <= cap_wp + 1'b1;
            end else begin
                cap_wp <= cap_wp + 1'b1;
                if (cap_left != 0) cap_left <= cap_left - 1'b1;
                else if (cap_trig) begin cap_state <= 2'd2; cap_left <= cap_mode == 2'd1 ? 13'd800 : cap_mode == 2'd2 ? CAP_POST_TX : CAP_POST; end
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
