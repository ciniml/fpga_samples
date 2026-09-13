// Own EasyCDR-compatible receiver PHY for GW5A: TLVDS input -> OSIDES32
// (4-phase 500MHz oversampling deserializer with two IODELAY taps) ->
// OsCdr (rtl/oscdr) -> BitGearbox. Same external behaviour as the Gowin
// EasyCDR IP in its raw 16-bit configuration:
//   o_pclk     : 125MHz parallel clock (HCLK/4)
//   o_reset    : active-high reset for the pclk domain
//   o_dout[15] : recovered bits, [0] earliest
//   o_dout_en  : word strobe (~50% duty at 1Gbps)
// plus what the IP could not do: i_freeze holds the recovered phase, so a
// TX-side phase sweep (PLLA dynamic phase shift, 125ps steps) moves the
// data eye across the fixed sampling point (BERT-based eye scan). The
// OSIDES32 taps themselves cannot be moved at run time (see below).
module oscdr_phy_gw5a #(
    parameter DLY0 = 0,    // base tap of delay 0
    parameter DLY1 = 21,   // base tap of delay 1 (= 1/4 UI later, IPUG1040 formula)
    parameter DYN1 = "FALSE",  // "TRUE": IODELAY_1 in dynamic mode (i_sdtap1 / i_value1 / i_dlystep1), experiment
    parameter DYN0 = "FALSE",  // "TRUE": IODELAY_0 dynamic as well (same controls), experiment
    parameter ADAPT1 = "FALSE" // "TRUE": IODELAY_1 adaptive mode, experiment
) (
    input  wire        clk_in,        // 50MHz reference
    input  wire        rstn_in,       // async, active low
    input  wire        i_serial_p,
    input  wire        i_serial_n,

    input  wire        i_freeze,      // pclk domain (quasi-static)
    input  wire        i_sdtap1,      // dynamic IODELAY_1 control (DYN1 = "TRUE" only)
    input  wire        i_value1,
    input  wire [7:0]  i_dlystep1,

    output wire        o_pclk,
    output wire        o_reset,
    output wire        o_pll_lock,
    output wire [15:0] o_dout,
    output wire        o_dout_en,
    output wire        o_cdr_lock,
    output wire [1:0]  o_cdr_phase,
    output wire        o_cdr_slip,
    output wire        o_dly_sat,      // IODELAY DF flags (informational)
    output wire [31:0] o_samples       // raw OSIDES32 word (debug capture)
);
    //------------------------------------------------------------------
    // 500MHz x 4 phases (PLL_T, BANK6/7 HCLK group) + /4 parallel clock
    //------------------------------------------------------------------
    wire pll_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90, rxclk_500m_180, rxclk_500m_270;
    pll_rx_500m_4ph u_pll_rx(
        .lock(pll_lock), .clkout0(rxclk_500m_0), .clkout1(rxclk_500m_90),
        .clkout2(rxclk_500m_180), .clkout3(rxclk_500m_270), .clkin(clk_in),
        .pssel(3'd0), .psdir(1'b0), .pspulse(1'b0));
    assign o_pll_lock = pll_lock;

    // reset sequencing (mirrors the IP's share logic): wait 16 reference
    // clocks after PLL lock, then release CLKDIV; the pclk-domain reset is
    // released a few pclk cycles later.
    reg [3:0] delay_cnt;
    reg       resetn_div;
    always @(posedge clk_in or negedge rstn_in) begin
        if (!rstn_in) begin
            delay_cnt  <= 4'd0;
            resetn_div <= 1'b0;
        end else if (!pll_lock) begin
            delay_cnt  <= 4'd0;
            resetn_div <= 1'b0;
        end else if (&delay_cnt) begin
            resetn_div <= 1'b1;
        end else begin
            delay_cnt <= delay_cnt + 1'b1;
        end
    end

    // The Gowin IP gates the four phase clocks with DHCE (held off during
    // reset, enabled a few reference clocks before the CLKDIV/OSIDES32 reset
    // release) - replicated here.
    reg cen;   // DHCE CEN: 1 = clock stopped
    always @(posedge clk_in or negedge rstn_in) begin
        if (!rstn_in)        cen <= 1'b1;
        else if (!pll_lock)  cen <= 1'b1;
        else if (delay_cnt >= 4'd7) cen <= 1'b0;
    end
    wire fclkp, fclkqp, fclkn, fclkqn;
    DHCE u_dhce_0  (.CLKIN(rxclk_500m_0),   .CEN(cen), .CLKOUT(fclkp));
    DHCE u_dhce_90 (.CLKIN(rxclk_500m_90),  .CEN(cen), .CLKOUT(fclkqp));
    DHCE u_dhce_180(.CLKIN(rxclk_500m_180), .CEN(cen), .CLKOUT(fclkn));
    DHCE u_dhce_270(.CLKIN(rxclk_500m_270), .CEN(cen), .CLKOUT(fclkqn));
    CLKDIV u_clkdiv(.HCLKIN(fclkp), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv.DIV_MODE = "4";
    assign o_pclk = pclk;

    reg [2:0] rst_sync;
    always @(posedge pclk or negedge resetn_div) begin
        if (!resetn_div) rst_sync <= 3'b111;
        else             rst_sync <= {rst_sync[1:0], 1'b0};
    end
    wire reset = rst_sync[2];
    assign o_reset = reset;

    //------------------------------------------------------------------
    // input buffer + oversampling deserializer
    //------------------------------------------------------------------
    wire serial_se;
    TLVDS_IBUF u_ibuf(.O(serial_se), .I(i_serial_p), .IB(i_serial_n));

    // OSIDES32 with STATIC taps, exactly like the Gowin IP: DYN_DLY_EN and
    // ADAPT_EN "FALSE", SDTAP/VALUE/DLYSTEP tied to GND. Measured: with
    // DYN_DLY_EN "TRUE" (any SDTAP/VALUE usage) the delays are inert and the
    // four phases collapse to two distinct instants per UI. With the static
    // configuration the transition classes rotate through all four
    // sample instants (~250ps apart) as the TX phase is swept.
    wire df0, df1;
    assign o_dly_sat = df0 | df1;
    wire [31:0] samples;
    assign o_samples = samples;
    OSIDES32 #(
        .C_STATIC_DLY_0(DLY0), .DYN_DLY_EN_0(DYN0), .ADAPT_EN_0("FALSE"),
        .C_STATIC_DLY_1(DLY1), .DYN_DLY_EN_1(DYN1), .ADAPT_EN_1(ADAPT1)
    ) u_osides32(
        .Q(samples), .DF0(df0), .DF1(df1),
        .D(serial_se),
        .PCLK(pclk),
        .FCLKP(fclkp), .FCLKQP(fclkqp), .FCLKN(fclkn), .FCLKQN(fclkqn),
        .RESET(reset),
        .SDTAP0(i_sdtap1), .VALUE0(i_value1), .DLYSTEP0(i_dlystep1),
        .SDTAP1(i_sdtap1), .VALUE1(i_value1), .DLYSTEP1(i_dlystep1));

    //------------------------------------------------------------------
    // CDR + gearbox
    //------------------------------------------------------------------
    wire [8:0] bits;
    wire [3:0] nbits;
    OsCdr #(.SAMPLES(32), .OSR(4)) u_cdr(
        .i_clk(pclk), .i_rst(reset), .i_samples(samples), .i_freeze(i_freeze),
        .o_bits(bits), .o_nbits(nbits), .o_phase(o_cdr_phase), .o_lock(o_cdr_lock), .o_slip(o_cdr_slip));
    BitGearbox #(.IN_MAX(9), .OUT_W(16)) u_gearbox(
        .i_clk(pclk), .i_rst(reset), .i_bits(bits), .i_nbits(nbits), .o_valid(o_dout_en), .o_word(o_dout));
endmodule
