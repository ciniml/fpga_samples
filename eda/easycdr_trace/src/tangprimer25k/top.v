// EasyCDR trace-link (1Gbps, 8b10b): phase 3 - timestamped signal tracing.
//
// TX: trace_frontend samples a demo signal, emits [K28.1][ts x3][data x2]
//     records into the link (K28.3 idle filler between records).
// RX: records ({K flag, byte} entries) are captured into the buffer and
//     dumped over UART; host/trace_view.py reconstructs the events.
//
// TX (pmod2 lane L1, D10/D11): reverse control channel - 2Mbps Manchester
//     (rtl/manchester ManchesterTx). Host 'X' frames are forwarded to the
//     trace transmitter FPGA (reset / enable / ignore mask, see
//     rtl/manchester/README.md). The old 8b10b demo TX was replaced; its
//     PLL (pll_tx_500m) is gone.
// RX: EasyCDR in the 10-bit + Word Alignment + 8B/10B Decoding
//     configuration (line rate 1Gbps, HCLK 500MHz x4 phases, PCLK 125MHz):
//       dout_o[8]   = K-character flag
//       dout_o[7:0] = decoded byte
//       align_flag_o / error_o come from the IP itself.
// The RX checker verifies the counter sequence and drives the same
// observation pins as the PRBS samples (lock/err/marker).
//
// Physical link: ExtEasyCDR modules + passive USB-C cable (see the
// gowin_easycdr_1g2_sample README); TX on pmod0 lane L1 (G7/G8), RX on
// pmod2 lane L0 (G11/G10).
//
// USB_HOST (make USB=1): the host transport is USB 2.0 high speed through
// the Pmod USB board (rtl/usb: UsbDevice EP1 byte stream + usb_phy_gowin,
// 20 MB/s instead of 11 kB/s on the UART; the UART stays as a fallback and
// the reply goes to whichever transport sent the last command). The USB
// board takes pmod2 (A, receivers) and pmod1 (B, transmitter) and its
// 480 MHz 4-phase clocks the whole BANK6/7 HCLK group, so the EasyCDR
// module moves to pmod0 (RX lane L0 = F5/G5, reverse channel lane L1 =
// G7/G8, BANK0/1 group) and the self-test transmitter is not built. The
// system clock (clk_sys) is the USB 60 MHz instead of the 50 MHz crystal.
module top(
    input            clk_in,          // 50MHz
    input            i_serial_p,
    input            i_serial_n,
`ifndef USB_HOST
    output           o_selftest_p,   // pmod0 lane L1 (G7/G8): own trace stream for the loopback self-test
    output           o_selftest_n,
`else
    // Pmod USB board (TN710 USB2.0-RC circuit): A = pmod2, B = pmod1
    input            usb_rx_dp,      // USB_RX_D+  (A pin 1)
    input            usb_rx_dn,      // USB_RX_D-  (A pin 7)
    input            usb_rxdp_p,     // D+         (A pin 2)
    input            usb_rxdp_n,     // VREF       (A pin 8)
    input            usb_rxdn_p,     // D-         (A pin 3)
    input            usb_rxdn_n,     // VREF       (A pin 9)
    output           usb_term_dp,    // TERM_RXDP  (A pin 4)
    output           usb_term_dn,    // TERM_RXDN  (A pin 10)
    output           usb_tx_dp,      // USB_TX_D+  (B pin 1)
    output           usb_tx_dn,      // USB_TX_D-  (B pin 7)
    output           usb_pullup_en,  // PULLUP_EN  (B pin 2)
    input            vbus_det,       // VBUS_DET   (B pin 3)
`endif
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,        // push button, active high (pull-down)
    output           o_dat_err,      // counter mismatch or 8b10b decode error
    output           o_dat_lock,     // aligned + comma watchdog
    output wire[7:0] o_dat_err_num,  // error count
    output           O_ERROR,        // sticky 8b10b decode error
    output           dout_flag_xor,  // toggles every 256 commas (~82us square)
    output           uart_txd,       // to host (BL616 bridge, 115200 8N1)
    input            uart_rxd        // from host
    );

    wire resetn_in = ~reset_in;

    // Host UART baud rate (BL616 bridge). 115200 is the proven default;
    // build variants at 921600 / 2000000 exist for faster dumps.
    localparam UART_BAUD = 115200;

    //------------------------------------------------------------------
    // System clock (command / dump FSM, UART, reverse channel): the 50 MHz
    // crystal, or with USB_HOST the USB 60 MHz PLL output.
    //------------------------------------------------------------------
`ifdef USB_HOST
    localparam SYS_HZ = 60_000_000;
    wire usb_pll_lock, usb_fclk_240m, clk_sys;
    pll_usb u_pll_usb(.lock(usb_pll_lock), .clkout0(usb_fclk_240m), .clkout1(clk_sys), .clkout2(), .clkout3(),
                      .clkin(clk_in), .psdir(1'b0), .pspulse(1'b0));
    reg [3:0] sys_rst_sr;
    always @(posedge clk_sys or posedge reset_in)
        if (reset_in) sys_rst_sr <= 4'hf; else sys_rst_sr <= {sys_rst_sr[2:0], ~usb_pll_lock};
    wire rst_sys  = sys_rst_sr[3];
`else
    localparam SYS_HZ = 50_000_000;
    wire clk_sys = clk_in;
    wire rst_sys = reset_in;
`endif
    wire rstn_sys = ~rst_sys;

    //------------------------------------------------------------------
    // RX clocking: 500MHz x 4 phases for the EasyCDR IP (PLL_T)
    //------------------------------------------------------------------
    wire pll_rx_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90;
    wire rxclk_500m_180;
    wire rxclk_500m_270;

`ifdef RATE_742M5
    pll_rx_371m_4ph u_pll_rx(     // 742.5Mbps variant (make RATE=742M5)
`else
    pll_rx_500m_4ph #(.MDIV(`RATE_MDIV), .MDIV_FRAC(`RATE_MDIV_FRAC), .ODIV(`RATE_ODIV)) u_pll_rx(   // RATE variants (project.tcl)
`endif
        .lock    (pll_rx_lock),
        .clkout0 (rxclk_500m_0),
        .clkout1 (rxclk_500m_90),
        .clkout2 (rxclk_500m_180),
        .clkout3 (rxclk_500m_270),
        .clkin   (clk_in)
    );

    //------------------------------------------------------------------
    // EasyCDR IP: 10bit + WORD_ALI + DECODE_8B10B (see easycdr_1912/define.v)
    //------------------------------------------------------------------
    wire       pclk_rx;        // share_clk4_o = 125MHz
    wire       rx_reset;       // share_reset_o, active high
    wire [9:0] rx_data;        // [8]=K flag, [7:0]=decoded byte
    wire       rx_data_en;     // ~80% duty (10-bit words at 100M word/s)
    wire       rx_align;       // align_flag_o
    wire       rx_decerr;      // error_o (disparity / code violation)

    EasyCDR_Top u_EasyCDR_Top(
        .rxp_i         (i_serial_p),
        .rxn_i         (i_serial_n),
        .rstn_i        (resetn_in),
        .pll_clkin_i   (clk_in),
        .pll_clkout0_i (rxclk_500m_0),
        .pll_clkout1_i (rxclk_500m_90),
        .pll_clkout2_i (rxclk_500m_180),
        .pll_clkout3_i (rxclk_500m_270),
        .pll_lock_i    (pll_rx_lock),
        .share_clk0_o  (),
        .share_clk1_o  (),
        .share_clk2_o  (),
        .share_clk3_o  (),
        .share_clk4_o  (pclk_rx),
        .share_reset_o (rx_reset),
        .align_flag_o  (rx_align),
        .error_o       (rx_decerr),
        .dout_o        (rx_data),
        .dout_en_o     (rx_data_en)
    );

    //------------------------------------------------------------------
    // Reverse control channel TX: 2Mbps Manchester on lane L1 (G7/G8).
    // Bytes come from the host 'X' command (trace_capture o_fwd_*) through
    // a small elastic FIFO (the UART can outpace the 2Mbps link at high
    // baud rates; frames are 4 bytes, so 16 entries are plenty).
    //------------------------------------------------------------------
    wire       fwd_valid;
    wire [7:0] fwd_data;

    reg [7:0] cfifo [0:15];
    reg [4:0] cwp, crp;
    wire cf_empty = (cwp == crp);
    wire cf_full  = (cwp[4] != crp[4]) && (cwp[3:0] == crp[3:0]);
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            cwp <= 5'd0;
        end else if (fwd_valid && !cf_full) begin
            cfifo[cwp[3:0]] <= fwd_data;
            cwp <= cwp + 1'b1;
        end
    end

    wire ctrl_tx_ready;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys)                             crp <= 5'd0;
        else if (ctrl_tx_ready && !cf_empty)     crp <= crp + 1'b1;
    end

    wire man_txd;
    ManchesterTx #(.BIT_CYCLES(SYS_HZ / 2_000_000)) u_ctrl_tx(   // 2Mbps
        .i_clk   (clk_sys),
        .i_rst   (rst_sys),
        .i_valid (!cf_empty),
        .i_data  (cfifo[crp[3:0]]),
        .o_ready (ctrl_tx_ready),
        .o_txd   (man_txd)
    );

    // Reset burst for the CTRL_PULSE Nano9K variant (host command 'P'):
    // 4 levels x 20us, takes over the line while busy. Harmless to the
    // Manchester receiver (it just sees link loss for 80us; frames are
    // never sent during a burst because the host waits for the 'P' reply).
    wire pulse_req, pulse_busy, pulse_txd;
    PulseResetTx #(.HALF_CYCLES(SYS_HZ / 50_000), .HALVES(4), .IDLE_HALF(SYS_HZ / 2_000_000)) u_pulse_tx(   // 4 x 20us
        .i_clk  (clk_sys),
        .i_rst  (rst_sys),
        .i_req  (pulse_req),
        .o_busy (pulse_busy),
        .o_txd  (pulse_txd)
    );
    wire ctrl_txd = pulse_busy ? pulse_txd : man_txd;

    ELVDS_OBUF u_tx(
        .I  (ctrl_txd),
        .O  (o_serial_p),
        .OB (o_serial_n)
    );

    //------------------------------------------------------------------
    // RX checker (125MHz parallel-clock domain)
    //------------------------------------------------------------------
    localparam [7:0] K28_5 = 8'hbc;

    wire rx_word_en = rx_data_en && rx_align;
    wire rx_is_k    = rx_word_en &&  rx_data[8] && (rx_data[7:0] == K28_5);
    wire rx_is_d    = rx_word_en && !rx_data[8];

    reg       err_pulse;
    reg [7:0] err_num;
    reg       decerr_sticky;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            err_pulse     <= 1'b0;
            err_num       <= 8'd0;
            decerr_sticky <= 1'b0;
        end else begin
            err_pulse <= 1'b0;
            if (rx_data_en && rx_decerr) begin
                err_pulse     <= 1'b1;
                err_num       <= err_num + 1'b1;
                decerr_sticky <= 1'b1;
            end
        end
    end

    // Comma watchdog: commas arrive every 160ns on a healthy link; drop the
    // lock indication if none is seen for ~65us.
    reg [12:0] act_cnt;
    reg        act_ok;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b0;
        end else if (rx_is_k) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b1;
        end else if (&act_cnt) begin
            act_ok <= 1'b0;
        end else begin
            act_cnt <= act_cnt + 1'b1;
        end
    end

    // Marker output: toggle every 256 commas -> ~82us period square wave.
    reg [7:0] k_cnt;
    reg       k_flag;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            k_cnt  <= 8'd0;
            k_flag <= 1'b0;
        end else if (rx_is_k) begin
            k_cnt <= k_cnt + 1'b1;
            if (&k_cnt) k_flag <= ~k_flag;
        end
    end

    //------------------------------------------------------------------
    // Phase 2: payload capture buffer + UART dump (see trace_capture.v)
    //------------------------------------------------------------------
    localparam [7:0] K28_1 = 8'h3c;   // start of record
    localparam [7:0] K28_2 = 8'h5c;   // overflow marker
    localparam [7:0] K28_7 = 8'hfc;   // tick (timestamp only)
    // descriptor payload bytes must not enter the capture buffer
    wire desc_busy;
    // raw capture mode ('R' 1): every received word, {align, err, dout[9:0]}
    wire raw_mode;
    reg  [1:0] raw_sync;
    always @(posedge pclk_rx) raw_sync <= {raw_sync[0], raw_mode};
    wire        raw_p     = raw_sync[1];
    wire        cap_valid = raw_p ? rx_data_en : cap_valid_rec;
    wire [11:0] cap_data  = raw_p ? {rx_align, rx_decerr, rx_data[9:0]} : {3'b0, rx_data[8:0]};
    wire cap_valid_rec = rx_word_en && !desc_busy && !map_busy &&
                     (!rx_data[8] ||
                      rx_data[7:0] == K28_1 || rx_data[7:0] == K28_2 || rx_data[7:0] == K28_7);

    // on-the-fly record decoder feeding the trigger comparator
    wire        rec_valid;
    wire [31:0] rec_ts;
    wire [63:0] rec_data;
    wire [7:0]  desc_ver, desc_width, desc_tsbits, desc_flags;
    wire [31:0] desc_hash;
    wire        map_wr, map_busy;
    wire [7:0]  map_addr, map_data, map_len;
    trace_rx_decoder #(.MAX_WIDTH(64), .MAX_TS_BITS(32)) u_decoder(   // layout from the descriptor
        .clk       (pclk_rx),
        .rst       (rx_reset),
        .in_valid  (rx_word_en),
        .in_word   (rx_data[8:0]),
        .rec_valid (rec_valid),
        .rec_ts    (rec_ts),
        .rec_data  (rec_data),
        .ovf_seen  (),
        .o_desc_ver    (desc_ver),
        .o_desc_width  (desc_width),
        .o_desc_tsbits (desc_tsbits),
        .o_desc_flags  (desc_flags),
        .o_desc_hash   (desc_hash),
        .o_map_wr(map_wr), .o_map_addr(map_addr), .o_map_data(map_data), .o_map_len(map_len), .o_map_busy(map_busy),
        .o_desc_busy   (desc_busy)
    );

    // Host transport: the UART, and with USB_HOST the USB EP1 byte stream as
    // well. Commands from either side go to trace_capture; the reply stream
    // goes to the side that sent the last command.
    wire       h_rx_valid, h_tx_valid, h_tx_ready;
    wire [7:0] h_rx_data,  h_tx_data;
    wire       u_rx_valid, u_tx_ready;
    wire [7:0] u_rx_data;
    uart_rx #(.BAUD_DIVIDER(SYS_HZ / UART_BAUD)) u_uart_rx(
        .clock(clk_sys), .reset(rst_sys),
        .data_valid(u_rx_valid), .data_ready(1'b1), .data_bits(u_rx_data),
        .rx(uart_rxd), .overrun());
`ifdef USB_HOST
    wire       s_rx_valid, s_tx_ready, s_configured;
    wire [7:0] s_rx_data;
    reg        use_usb;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) use_usb <= 1'b0;
        else if (s_rx_valid) use_usb <= 1'b1;
        else if (u_rx_valid) use_usb <= 1'b0;
    end
    assign h_rx_valid = s_rx_valid | u_rx_valid;        // (both in one clock: the UART byte is lost)
    assign h_rx_data  = s_rx_valid ? s_rx_data : u_rx_data;
    assign h_tx_ready = use_usb ? s_tx_ready : u_tx_ready;
    wire   uart_tx_valid = h_tx_valid & ~use_usb;
    wire   usb_tx_valid  = h_tx_valid &  use_usb;
`else
    assign h_rx_valid = u_rx_valid;
    assign h_rx_data  = u_rx_data;
    assign h_tx_ready = u_tx_ready;
    wire   uart_tx_valid = h_tx_valid;
`endif
    uart_tx #(.BAUD_DIVIDER(SYS_HZ / UART_BAUD)) u_uart_tx(
        .clock(clk_sys), .reset(rst_sys),
        .data_valid(uart_tx_valid), .data_ready(u_tx_ready), .data_bits(h_tx_data),
        .tx(uart_txd));

`ifdef USB_HOST
    //------------------------------------------------------------------
    // USB 2.0 HS device (rtl/usb): EP1 OUT = host commands, EP1 IN = reply
    // stream (full packets while data flows, the remainder / a ZLP after
    // 1 ms of idle). PHY front end and clocking as eda/usb_device (proven
    // HS_OS32 configuration): 60 MHz -> pll_usb_os -> 480 MHz x 4 phases
    // on the BANK6/7 HCLK group, oversampler PCLK 120 MHz.
    //------------------------------------------------------------------
    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       usb_hs, usb_suspended, usb_bus_reset, usb_sof;
    wire [6:0] usb_address;
    wire [10:0] usb_frame;
    wire [15:0] usb_vendor_reg;
    wire os_lock, os_f0 /* synthesis syn_keep=1 */, os_f90, os_f180, os_f270;
    wire os_pclk /* synthesis syn_keep=1 */;   // oversampler PCLK: used below so the net survives for the SDC
    reg  os_tick; always @(posedge os_pclk) os_tick <= ~os_tick;
    pll_usb_os #(.FCLKIN("60"), .MDIV(16), .MDIV_FRAC(0), .ODIV(2)) u_pll_os(
        .lock(os_lock), .clkout0(os_f0), .clkout1(os_f90), .clkout2(os_f180), .clkout3(os_f270), .clkin(clk_sys),
        .pssel(3'd0), .psdir(1'b0), .pspulse(1'b0));
    reg [1:0] vbus_sr; always @(posedge clk_sys) vbus_sr <= {vbus_sr[0], vbus_det};
    UsbDevice #(.HS_CAPABLE(1), .CLK_PER_US(60), .EP1_STREAM(1), .STREAM_FLUSH_US(1000)) u_usb_dev(
        .i_clk(clk_sys), .i_rst(rst_sys),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(usb_hs), .o_configured(s_configured), .o_suspended(usb_suspended), .o_reset(usb_bus_reset),
        .o_address(usb_address), .o_frame(usb_frame), .o_sof(usb_sof),
        .o_vendor_reg(usb_vendor_reg),
        .i_vendor_status({8'h54, 4'b0, os_tick, vbus_sr[1], rx_align, usb_hs, 16'd0}),   // 'T'race: link / speed flags
        .o_rx_valid(s_rx_valid), .o_rx_data(s_rx_data), .i_rx_ready(1'b1),
        .i_tx_valid(usb_tx_valid), .i_tx_data(h_tx_data), .o_tx_ready(s_tx_ready));
    usb_phy_gowin #(.SE_FROM_DIFF(1), .DYN_DLY(0), .HS_CDR(0), .HS_OS32(1)) u_usb_phy(
        .os_clk_ref_i(clk_in), .os_rstn_ref_i(~reset_in), .os_pll_lock_i(os_lock),
        .os_fclk0_i(os_f0), .os_fclk90_i(os_f90), .os_fclk180_i(os_f180), .os_fclk270_i(os_f270), .os_pclk_o(os_pclk), .os_samples_o(), .os_cmp_o(),
        .i_scan_freeze(1'b0), .i_scan_ofs(1'b0), .i_scan_class(3'd0), .i_hist_run(1'b0), .o_hist(), .o_txfifo_dbg(),
        .clk_i(clk_sys), .fclk_i(usb_fclk_240m), .rst_i(rst_sys), .pll_locked_i(usb_pll_lock),
        .i_track_en(1'b0), .i_dly_dd(8'd0), .i_dly_dp(8'd0), .i_dly_dn(8'd0), .o_dly_dd(),
        .o_mon_dd(), .o_mon_dp(), .o_mon_dn(),
        .utmi_data_out_i(utmi_data_out), .utmi_txvalid_i(utmi_txvalid), .utmi_txready_o(utmi_txready),
        .utmi_data_in_o(utmi_data_in), .utmi_rxactive_o(utmi_rxactive), .utmi_rxvalid_o(utmi_rxvalid),
        .utmi_rxerror_o(utmi_rxerror), .utmi_linestate_o(utmi_linestate),
        .utmi_opmode_i(utmi_opmode), .utmi_xcvrselect_i(utmi_xcvrselect), .utmi_termselect_i(utmi_termselect),
        .usb_rx_dp_i(usb_rx_dp), .usb_rx_dn_i(usb_rx_dn),
        .usb_rxdp_p_i(usb_rxdp_p), .usb_rxdp_n_i(usb_rxdp_n),
        .usb_rxdn_p_i(usb_rxdn_p), .usb_rxdn_n_i(usb_rxdn_n),
        .usb_tx_dp_o(usb_tx_dp), .usb_tx_dn_o(usb_tx_dn),
        .usb_pullup_en_o(usb_pullup_en), .usb_term_dp_o(usb_term_dp), .usb_term_dn_o(usb_term_dn));
`endif

    //------------------------------------------------------------------
    // Link diagnostics (host command 'L') and loopback self-test source
    //------------------------------------------------------------------
    wire         diag_req, diag_done;
    wire [111:0] diag_data;
    trace_link_diag u_diag(
        .pclk(pclk_rx), .prst(rx_reset),
        .i_data_en(rx_data_en), .i_word(rx_data[8:0]), .i_decerr(rx_decerr),
        .i_status({3'b0, rx_reset, act_ok, desc_ver != 8'd0, rx_align, pll_rx_lock}),
        .i_desc_ver(desc_ver),
        .clk_sys(clk_sys), .rst_sys(rst_sys),
        .i_req(diag_req), .o_done(diag_done), .o_data(diag_data));

    // Self-test transmitter: a second trace core sending a free-running
    // 16-bit counter (steps every 5.12us) on pmod0 lane L1. Loop a USB-C
    // cable from pmod0 to pmod2 and the receiver sees this stream without
    // any other board (ctrl_test.py --selftest). Not built in the 742.5Mbps
    // variant (separate TX PLL would be needed).
    wire st_serial;
    wire       inj_wr_valid, inj_set;      // symbol injector ('J'), driven by trace_capture
    wire [5:0] inj_wr_idx;
    wire [9:0] inj_wr_data;
    wire [1:0] inj_mode;
    wire [6:0] inj_len;
`ifdef USB_HOST
    // (no self-test transmitter: pmod0 carries the EasyCDR module, see the header)
`elsif RATE_742M5
    assign st_serial = 1'b0;
`else
    wire pll_tx_lock;
    wire txclk_500m /* synthesis syn_keep=1 */;
    wire txclk_100m;
    pll_tx_500m #(.MDIV(`RATE_MDIV), .MDIV_FRAC(`RATE_MDIV_FRAC), .ODIV(`RATE_ODIV)) u_pll_tx(
        .lock(pll_tx_lock), .clkout0(txclk_500m), .clkout1(), .clkout2(), .clkout3(), .clkin(clk_in));
    CLKDIV u_clkdiv_tx(.HCLKIN(txclk_500m), .RESETN(resetn_in), .CALIB(1'b0), .CLKOUT(txclk_100m));
    defparam u_clkdiv_tx.DIV_MODE = "5";
    wire st_rstn = resetn_in & pll_tx_lock;

    reg [23:0] st_cnt;
    always @(posedge clk_in or posedge reset_in)
        if (reset_in) st_cnt <= 24'd0; else st_cnt <= st_cnt + 1'b1;

    wire [9:0] st_symbol, st_sym_out;
    trace_sym_inject #(.AW(6)) u_inject(
        .clk_sys(clk_in), .rst_sys(reset_in),
        .i_wr_valid(inj_wr_valid), .i_wr_idx(inj_wr_idx), .i_wr_data(inj_wr_data),
        .i_set(inj_set), .i_mode(inj_mode), .i_len(inj_len),
        .txclk(txclk_100m), .txrstn(st_rstn), .i_core_sym(st_symbol), .o_sym(st_sym_out), .o_active());
    // self-test signal map: ROM generated by project.tcl from maps/primer25k_selftest.map;
    // the text is re-sent every 2^24 sample clocks (0.34 s) so 'N' works in loopback
    wire [7:0] st_map_addr, st_map_data, st_map_len;
    trace_map_rom_selftest u_st_map(.addr(st_map_addr), .data(st_map_data), .len(st_map_len));
    reg st_map_req;
    always @(posedge clk_in) st_map_req <= (st_cnt == 24'd0);
    // CFG_HASH = tracemap.py hash of "count:16" (the self-test map)
    easycdr_trace_tx #(.WIDTH(16), .TS_BITS(24), .SYNC_STAGES(0), .HAS_PERIODIC(0), .HAS_TRIGGER(0), .FIFO_RAM("block"), .CFG_HASH(32'hff13d4c5)) u_st_tx(
        .sclk(clk_in), .srstn(resetn_in), .sig(st_cnt[23:8]),
        .clk(txclk_100m), .rstn(st_rstn),
        .i_enable(1'b1), .i_ignore_mask(16'd0), .i_desc_req(1'b0), .i_periodic_en(1'b0), .i_change_dis(1'b0), .i_tick_dis(1'b0),
        .i_period(24'd0), .i_arm(1'b0), .i_trig_mask(16'd0), .i_trig_value(16'd0), .i_post(16'd0),
        .i_map_req(st_map_req), .i_map_len(st_map_len), .o_map_addr(st_map_addr), .i_map_data(st_map_data),
        .o_symbol(st_symbol), .o_overflow(), .o_armed(), .o_triggered(), .o_done());
    OSER10 u_st_oser(
        .Q(st_serial),
        .D0(st_sym_out[0]), .D1(st_sym_out[1]), .D2(st_sym_out[2]), .D3(st_sym_out[3]), .D4(st_sym_out[4]),
        .D5(st_sym_out[5]), .D6(st_sym_out[6]), .D7(st_sym_out[7]), .D8(st_sym_out[8]), .D9(st_sym_out[9]),
        .PCLK(txclk_100m), .FCLK(txclk_500m), .RESET(~st_rstn));
`endif
`ifndef USB_HOST
    ELVDS_OBUF u_st_obuf(.I(st_serial), .O(o_selftest_p), .OB(o_selftest_n));
`endif

    trace_capture #(
        .ADDR_BITS    (14),                 // 16Ki entries ({K,byte})
        .DATA_BITS    (12),
        .MAX_WIDTH    (64)
    ) u_capture(
        .pclk       (pclk_rx),
        .prst       (rx_reset),
        .in_valid   (cap_valid),
        .in_data    (cap_data),
        .rec_valid  (rec_valid),
        .rec_data   (rec_data),
        .i_desc_ver    (desc_ver),
        .i_desc_width  (desc_width),
        .i_desc_tsbits (desc_tsbits),
        .i_desc_flags  (desc_flags),
        .i_desc_hash   (desc_hash),
        .i_map_wr(map_wr), .i_map_addr(map_addr), .i_map_data(map_data), .i_map_len(map_len),
        .clk_sys    (clk_sys),
        .rst_sys    (rst_sys),
        .h_rx_valid (h_rx_valid),
        .h_rx_data  (h_rx_data),
        .h_tx_valid (h_tx_valid),
        .h_tx_data  (h_tx_data),
        .h_tx_ready (h_tx_ready),
        .o_fwd_valid (fwd_valid),
        .o_fwd_data  (fwd_data),
        .o_pulse_req (pulse_req),
        .o_diag_req  (diag_req),
        .i_diag_done (diag_done),
        .i_diag_data (diag_data),
        .o_raw_mode  (raw_mode),
        .o_inj_wr_valid (inj_wr_valid),
        .o_inj_wr_idx   (inj_wr_idx),
        .o_inj_wr_data  (inj_wr_data),
        .o_inj_set      (inj_set),
        .o_inj_mode     (inj_mode),
        .o_inj_len      (inj_len)
    );

    assign o_dat_lock    = rx_align & act_ok;
    assign o_dat_err     = err_pulse;
    assign o_dat_err_num = err_num;
    assign O_ERROR       = decerr_sticky;
    assign dout_flag_xor = k_flag;

endmodule
