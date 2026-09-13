// EasyCDR trace-link TX-only design for Tang Nano 9K (GW1NR-9C).
//
// Demonstrates the "cheap target FPGA -> GW5A host" asymmetric setup: this
// design only transmits (EasyCDR is the receiver-side IP on the host).
//
//   line rate : 27MHz x 37/2 x 2 = 999Mbps (-1000ppm vs the host's 1Gbps
//               setting; well within the EasyCDR +/-5000ppm CDR tolerance)
//   TX clocks : 499.5MHz serializer (rPLL) + 99.9MHz parallel (CLKDIV /5)
//   TX pins   : pmod0 pins 2/8 = ExtEasyCDR lane L1 (IOB8 true pair), so a
//               standard Type-C cable's TX2<->RX2 cross wiring delivers the
//               stream to the host module's lane L0 (G11/G10).
//
// The physical positive line (PMOD pin 2 = module L1_P) is the B-side pad
// of the IOB8 pair, while the tools always place o_serial_p on the A-side
// pad, so the serial data is inverted before the output buffer to restore
// the wire polarity.
//
// Trace inputs of the demo: an 8-bit counter advancing every 9.5us plus
// button S2, so pressing S2 produces timestamped events on the host. The
// demo (and the trace sample clock) runs on the 27MHz crystal, the link on
// 99.9MHz: the trace core crosses the domains internally.
//
// Reverse control channel (pmod0 pins 1/7 = ExtEasyCDR lane L0): 2Mbps
// Manchester from the host FPGA -> ManchesterRx -> CtrlFrameRx ->
// TraceCtrlRegs (rtl/manchester). Provides soft reset, trace enable,
// ignore mask and descriptor request without any extra cable.
// Built with CTRL_PULSE=1 (make CTRL_PULSE=1 TARGET=tangnano9k_pmod) the
// receiver is PulseResetRx only: remote reset, no registers (~1/3 of the
// control-channel logic).
module top(
    input  wire clk_in,      // 27MHz crystal (pin 52)
    input  wire rst_btn_n,   // S1, active low (pin 4)
    input  wire trace_btn_n, // S2, active low (pin 3) - demo trace input
    output wire o_serial_p,  // pmod0 pin 2 (lane L1_P)
    output wire o_serial_n,  // pmod0 pin 8 (lane L1_N)
    input  wire i_ctrl_p,    // pmod0 pin 1 (lane L0_P) - reverse control channel
    input  wire i_ctrl_n,    // pmod0 pin 7 (lane L0_N)
    output wire led_lock_n,  // PLL locked (LED, active low)
    output wire led_beat_n   // heartbeat from the demo counter
    );

`ifndef TRACE_WIDTH
`define TRACE_WIDTH 16
`endif
    localparam TRACE_WIDTH = `TRACE_WIDTH;   // make TRACE_WIDTH=32 ... (multiple of 8, >= 16)
`ifdef RATE_742M5
    localparam CTRL_BIT_CYCLES = 37;         // 74.25MHz / 37 = 2.007Mbps Manchester (+0.34%)
    localparam PULSE_HALF_MIN = 1114, PULSE_HALF_MAX = 2228;   // 15..30us at 74.25MHz
`else
    localparam CTRL_BIT_CYCLES = 50;         // 99.9MHz / 50 = 1.998Mbps
    localparam PULSE_HALF_MIN = 1500, PULSE_HALF_MAX = 3000;
`endif

    //------------------------------------------------------------------
    // TX clocking: 499.5MHz + /5 = 99.9MHz
    //------------------------------------------------------------------
    wire pll_lock;
    wire txclk_ser;   // 499.5MHz
    wire txclk_par;   // 99.9MHz

`ifdef RATE_742M5
    pll_tx_3712 u_pll(          // 742.5Mbps variant: 371.25MHz serializer, 74.25MHz parallel
`else
    pll_tx_4995 u_pll(
`endif
        .clkout (txclk_ser),
        .lock   (pll_lock),
        .clkin  (clk_in)
    );

    CLKDIV u_clkdiv(
        .HCLKIN (txclk_ser),
        .RESETN (rst_btn_n),
        .CALIB  (1'b0),
        .CLKOUT (txclk_par)
    );
    defparam u_clkdiv.DIV_MODE = "5";

    wire tx_rstn = rst_btn_n & pll_lock;

    //------------------------------------------------------------------
    // Reverse control channel: TLVDS input -> Manchester RX -> frame
    // parser -> control registers (all in the txclk_par domain).
    // TX side sends 2Mbps; BIT_CYCLES=50 @99.9MHz = 1.998Mbps (-0.1%),
    // well inside the receiver's tolerance.
    //------------------------------------------------------------------
    // PnR places i_ctrl_p on the pair's A pad = FPGA pin 27 = pmod0 pin 7 =
    // lane L0_N (see build pin report), so the received line is inverted.
    localparam CTRL_INVERT = 1'b1;

    wire ctrl_rxd_raw;
    TLVDS_IBUF u_ctrl_ibuf(
        .O  (ctrl_rxd_raw),
        .I  (i_ctrl_p),
        .IB (i_ctrl_n)
    );
    wire ctrl_rxd = CTRL_INVERT ? ~ctrl_rxd_raw : ctrl_rxd_raw;

    wire ctrl_rst = ~tx_rstn;
    wire        soft_reset, trace_en, desc_req, arm, periodic_en, change_dis;
    wire [TRACE_WIDTH-1:0] ignore_mask, trig_mask, trig_value;
    wire [23:0] period;
    wire [15:0] post;
`ifdef CTRL_PULSE
    // Reset-only variant (CTRL_PULSE=1): the host sends a burst of 4 x 20us
    // levels (25K PulseResetTx, host command 'P'); two bounded 15..30us
    // levels in a row assert soft_reset for 64 clocks. No registers: the
    // trace runs enabled with change detection only.
    PulseResetRx #(.HALF_MIN(PULSE_HALF_MIN), .HALF_MAX(PULSE_HALF_MAX), .COUNT(2), .RESET_CYCLES(64)) u_ctrl_rx(
        .i_clk   (txclk_par),
        .i_rst   (ctrl_rst),
        .i_rxd   (ctrl_rxd),
        .o_reset (soft_reset)
    );
    assign trace_en    = 1'b1;
    assign desc_req    = 1'b0;
    assign arm         = 1'b0;
    assign periodic_en = 1'b0;
    assign change_dis  = 1'b0;
    assign ignore_mask = {TRACE_WIDTH{1'b0}};
    assign trig_mask   = {TRACE_WIDTH{1'b0}};
    assign trig_value  = {TRACE_WIDTH{1'b0}};
    assign period      = 24'd0;
    assign post        = 16'd0;
`else
    wire       cb_valid, cb_err;
    wire [7:0] cb_data;
    ManchesterRx #(.BIT_CYCLES(CTRL_BIT_CYCLES)) u_ctrl_rx(
        .i_clk   (txclk_par),
        .i_rst   (ctrl_rst),
        .i_rxd   (ctrl_rxd),
        .o_valid (cb_valid),
        .o_data  (cb_data),
        .o_err   (cb_err),
        .o_link  ()
    );

    wire       wr_valid;
    wire [7:0] wr_addr, wr_data;
    CtrlFrameRx #(.GAP_TIMEOUT(65536)) u_ctrl_frame(   // ~0.66ms byte gap
        .i_clk      (txclk_par),
        .i_rst      (ctrl_rst),
        .i_valid    (cb_valid),
        .i_data     (cb_data),
        .i_err      (cb_err),
        .o_wr_valid (wr_valid),
        .o_wr_addr  (wr_addr),
        .o_wr_data  (wr_data),
        .o_frame_err()
    );

    TraceCtrlRegs #(.WIDTH(TRACE_WIDTH), .RESET_CYCLES(64)) u_ctrl_regs(
        .i_clk        (txclk_par),
        .i_rst        (ctrl_rst),
        .i_wr_valid   (wr_valid),
        .i_wr_addr    (wr_addr),
        .i_wr_data    (wr_data),
        .o_soft_reset (soft_reset),
        .o_enable     (trace_en),
        .o_desc_req   (desc_req),
        .o_arm        (arm),
        .o_ignore_mask(ignore_mask),
        .o_periodic_en(periodic_en),
        .o_change_dis (change_dis),
        .o_period     (period),
        .o_trig_mask  (trig_mask),
        .o_trig_value (trig_value),
        .o_post       (post)
    );
`endif

    wire trace_rstn = tx_rstn & ~soft_reset;

    //------------------------------------------------------------------
    // Demo trace source: slow counter + button S2
    //------------------------------------------------------------------
    // The demo runs on the 27MHz crystal clock = the trace sample clock
    // (sclk), independent of the 99.9MHz link clock: SYNC_STAGES=0 because
    // trace_sig is synchronous to sclk. Timestamps count 27MHz cycles.
    reg [7:0] demo_div, demo_cnt;
    reg [1:0] btn_sync;
    always @(posedge clk_in or negedge rst_btn_n) begin
        if (!rst_btn_n) begin
            demo_div <= 8'd0;
            demo_cnt <= 8'd0;
            btn_sync <= 2'b11;
        end else begin
            demo_div <= demo_div + 1'b1;
            if (&demo_div) demo_cnt <= demo_cnt + 1'b1;
            btn_sync <= {btn_sync[0], trace_btn_n};
        end
    end
    wire [TRACE_WIDTH-1:0] trace_sig = {{(TRACE_WIDTH-9){1'b0}}, ~btn_sync[1], demo_cnt};

    //------------------------------------------------------------------
    // Frontend + link core + serializer
    //------------------------------------------------------------------
    wire [9:0] tx_symbol;
    easycdr_trace_tx #(.WIDTH(TRACE_WIDTH), .TS_BITS(24), .SYNC_STAGES(0)) u_trace_tx(
        .sclk          (clk_in),
        .srstn         (rst_btn_n),
        .sig           (trace_sig),
        .clk           (txclk_par),
        .rstn          (trace_rstn),
        .i_enable      (trace_en),
        .i_ignore_mask (ignore_mask),
        .i_desc_req    (desc_req),
        .i_periodic_en (periodic_en),
        .i_change_dis  (change_dis),
        .i_period      (period),
        .i_arm         (arm),
        .i_trig_mask   (trig_mask),
        .i_trig_value  (trig_value),
        .i_post        (post),
        .o_symbol      (tx_symbol),
        .o_overflow    (),
        .o_armed       (),
        .o_triggered   (),
        .o_done        ()
    );

    wire o_serial_data;
    OSER10 u_OSER10(
        .Q     (o_serial_data),
        .D0    (~tx_symbol[0]),
        .D1    (~tx_symbol[1]),
        .D2    (~tx_symbol[2]),
        .D3    (~tx_symbol[3]),
        .D4    (~tx_symbol[4]),
        .D5    (~tx_symbol[5]),
        .D6    (~tx_symbol[6]),
        .D7    (~tx_symbol[7]),
        .D8    (~tx_symbol[8]),
        .D9    (~tx_symbol[9]),
        .PCLK  (txclk_par),
        .FCLK  (txclk_ser),
        .RESET (~tx_rstn)
    );

    // Line polarity inversion is applied at the OSER10 D inputs (GW1N
    // requires the OSER output to connect directly to the buffer).
    ELVDS_OBUF u_tx(
        .I  (o_serial_data),
        .O  (o_serial_p),
        .OB (o_serial_n)
    );

    assign led_lock_n = ~pll_lock;
    assign led_beat_n = ~demo_cnt[7];

endmodule
