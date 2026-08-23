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
// Trace inputs of the demo: an 8-bit counter advancing every 2.56us plus
// button S2, so pressing S2 produces timestamped events on the host.
module top(
    input  wire clk_in,      // 27MHz crystal (pin 52)
    input  wire rst_btn_n,   // S1, active low (pin 4)
    input  wire trace_btn_n, // S2, active low (pin 3) - demo trace input
    output wire o_serial_p,  // pmod0 pin 2 (lane L1_P)
    output wire o_serial_n,  // pmod0 pin 8 (lane L1_N)
    output wire led_lock_n,  // PLL locked (LED, active low)
    output wire led_beat_n   // heartbeat from the demo counter
    );

    //------------------------------------------------------------------
    // TX clocking: 499.5MHz + /5 = 99.9MHz
    //------------------------------------------------------------------
    wire pll_lock;
    wire txclk_ser;   // 499.5MHz
    wire txclk_par;   // 99.9MHz

    pll_tx_4995 u_pll(
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
    // Demo trace source: slow counter + button S2
    //------------------------------------------------------------------
    reg [7:0] demo_div, demo_cnt;
    reg [1:0] btn_sync;
    always @(posedge txclk_par or negedge tx_rstn) begin
        if (!tx_rstn) begin
            demo_div <= 8'd0;
            demo_cnt <= 8'd0;
            btn_sync <= 2'b11;
        end else begin
            demo_div <= demo_div + 1'b1;
            if (&demo_div) demo_cnt <= demo_cnt + 1'b1;
            btn_sync <= {btn_sync[0], trace_btn_n};
        end
    end
    wire [15:0] trace_sig = {7'b0, ~btn_sync[1], demo_cnt};

    //------------------------------------------------------------------
    // Frontend + link core + serializer
    //------------------------------------------------------------------
    wire       fe_valid, fe_is_k, fe_ready;
    wire [7:0] fe_data;
    trace_frontend u_frontend(
        .clk     (txclk_par),
        .rstn    (tx_rstn),
        .sig     (trace_sig),
        .o_valid (fe_valid),
        .o_is_k  (fe_is_k),
        .o_data  (fe_data),
        .i_ready (fe_ready)
    );

    wire [9:0] tx_symbol;
    easycdr_trace_tx_core #(.FRAME_LEN(16)) u_tx_core(
        .clk      (txclk_par),
        .rstn     (tx_rstn),
        .i_valid  (fe_valid),
        .i_is_k   (fe_is_k),
        .i_data   (fe_data),
        .o_ready  (fe_ready),
        .o_symbol (tx_symbol)
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
