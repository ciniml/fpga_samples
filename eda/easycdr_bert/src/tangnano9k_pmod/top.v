// Tang Nano 9K BERT pattern source (TX only): PRBS7 at 999Mbps from the
// 27MHz crystal (rPLL 27x37/2 = 499.5MHz serializer clock, CLKDIV/5 =
// 99.9MHz parallel clock, OSER10). Drives ExtEasyCDR lane L1 on pmod0
// pins 2/8 so a standard Type-C cable delivers it to the far module's
// lane L0 (the Tang Primer 25K BERT receiver on pmod2).
//
// The -1000ppm rate offset against the 25K's 1Gbps receiver makes this a
// plesiochronous test of the own CDR (rtl/oscdr): about 4 pointer slips
// per 1000 UI must be absorbed without bit errors.
//
// S2 injects one bit error per press (debounced); S1 is reset.
// pmod pin 2 (module L1_P) is the B-side pad of the IOB8 pair while the
// tools put o_serial_p on the A side, so the serial data is inverted at
// the OSER10 inputs (GW1N: OSER output must go straight to the OBUF).
module top(
    input  wire clk_in,      // 27MHz crystal (pin 52)
    input  wire rst_btn_n,   // S1, active low (pin 4)
    input  wire trace_btn_n, // S2, active low (pin 3) - inject one error
    output wire o_serial_p,  // pmod0 pin 2 (lane L1_P)
    output wire o_serial_n,  // pmod0 pin 8 (lane L1_N)
    output wire led_lock_n,  // PLL locked (LED, active low)
    output wire led_beat_n   // heartbeat
    );
    wire pll_lock;
    wire txclk_ser;   // 499.5MHz
    wire txclk_par;   // 99.9MHz
    pll_tx_4995 u_pll(.clkout(txclk_ser), .lock(pll_lock), .clkin(clk_in));
    CLKDIV u_clkdiv(.HCLKIN(txclk_ser), .RESETN(rst_btn_n), .CALIB(1'b0), .CLKOUT(txclk_par));
    defparam u_clkdiv.DIV_MODE = "5";
    wire tx_rstn = rst_btn_n & pll_lock;
    wire tx_rst  = ~tx_rstn;

    // S2: synchronise, debounce (~10ms), one inject pulse per press
    reg [1:0]  btn_sync;
    reg [19:0] db_cnt;
    reg        btn_db, btn_db_q;
    always @(posedge txclk_par or posedge tx_rst) begin
        if (tx_rst) begin
            btn_sync <= 2'b11; db_cnt <= 20'd0; btn_db <= 1'b1; btn_db_q <= 1'b1;
        end else begin
            btn_sync <= {btn_sync[0], trace_btn_n};
            if (btn_sync[1] == btn_db) db_cnt <= 20'd0;
            else if (&db_cnt) begin btn_db <= btn_sync[1]; db_cnt <= 20'd0; end
            else db_cnt <= db_cnt + 1'b1;
            btn_db_q <= btn_db;
        end
    end
    wire inject = btn_db_q & ~btn_db;   // falling edge (press)

    wire [9:0] tx_word;
    PrbsGen #(.WIDTH(10)) u_gen(
        .i_clk(txclk_par), .i_rst(tx_rst),
        .i_enable(1'b1), .i_mode(prbs_pkg::GenMode_Prbs), .i_sel(prbs_pkg::PrbsSel_Prbs7), .i_fixed(16'hec92),
        .i_invert(1'b0), .i_inject(inject), .o_data(tx_word));

    wire o_serial_data;
    OSER10 u_OSER10(
        .Q(o_serial_data),
        .D0(~tx_word[0]), .D1(~tx_word[1]), .D2(~tx_word[2]), .D3(~tx_word[3]), .D4(~tx_word[4]),
        .D5(~tx_word[5]), .D6(~tx_word[6]), .D7(~tx_word[7]), .D8(~tx_word[8]), .D9(~tx_word[9]),
        .PCLK(txclk_par), .FCLK(txclk_ser), .RESET(tx_rst));
    ELVDS_OBUF u_tx(.I(o_serial_data), .O(o_serial_p), .OB(o_serial_n));

    reg [26:0] beat;
    always @(posedge txclk_par) beat <= beat + 1'b1;
    assign led_lock_n = ~pll_lock;
    assign led_beat_n = ~beat[26];
endmodule
