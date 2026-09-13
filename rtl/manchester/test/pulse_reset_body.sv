// PulseResetTx -> wire model -> PulseResetRx test body.
//   MODE 0 : direct wire            MODE 1 : inverted wire
//   MODE 2 : AC-coupled comparator (tau = 1ms), idle output 0
//   MODE 3 : same, comparator offset the other way -> idle output 1
`timescale 1ns/1ps
module pulse_reset_body #(
    parameter int MODE = 0,
    parameter bit RUN  = 0
) ();
    localparam real TX_PERIOD = 20.0;   // 50MHz host FPGA
    localparam real RX_PERIOD = 10.0;   // 100MHz target FPGA
    localparam int  TX_HALF   = 1000;   // 20us per level
    localparam int  HALVES    = 4;
    localparam int  RX_MIN    = 1500;   // 15us
    localparam int  RX_MAX    = 3000;   // 30us
    localparam int  RESET_CYC = 64;
    localparam real TAU_NS    = 1.0e6;  // 100nF x 10k

    logic tclk = 0, rclk = 0, rst = 1;
    always #(TX_PERIOD/2) tclk = ~tclk;
    always #(RX_PERIOD/2) rclk = ~rclk;

    logic req = 0, busy, ptxd;
    PulseResetTx #(.HALF_CYCLES(TX_HALF), .HALVES(HALVES), .IDLE_HALF(25)) tx (
        .i_clk(tclk), .i_rst(rst), .i_req(req), .o_busy(busy), .o_txd(ptxd));

    // Manchester source sharing the wire (host side mux: burst wins)
    logic       m_valid = 0, m_ready;
    logic [7:0] m_data = 0;
    logic       mtxd;
    ManchesterTx #(.BIT_CYCLES(25)) mtx (
        .i_clk(tclk), .i_rst(rst), .i_valid(m_valid), .i_data(m_data), .o_ready(m_ready), .o_txd(mtxd));

    logic use_manchester = 0;
    logic force_en = 0, force_lvl = 0;
    wire  line = force_en ? force_lvl : busy ? ptxd : use_manchester ? mtxd : ptxd;

    // wire model
    real  avg = 0.0, diff;
    real  offset = (MODE == 3) ? -0.02 : 0.02;
    logic rxd_ac = 0;
    always @(posedge rclk) begin
        avg    <= avg + (real'(line) - avg) * (RX_PERIOD / TAU_NS);
        diff    = real'(line) - avg;
        rxd_ac <= (diff > offset);
    end
    wire rxd = (MODE == 0) ? line : (MODE == 1) ? ~line : rxd_ac;

    logic o_reset;
    PulseResetRx #(.HALF_MIN(RX_MIN), .HALF_MAX(RX_MAX), .COUNT(2), .RESET_CYCLES(RESET_CYC)) rx (
        .i_clk(rclk), .i_rst(rst), .i_rxd(rxd), .o_reset(o_reset));

    // reset monitor
    int resets = 0, width = 0, last_width = -1;
    logic prev = 0;
    always @(posedge rclk) begin
        if (o_reset && !prev) begin resets++; width = 0; end
        if (o_reset) width++;
        if (!o_reset && prev) last_width = width;
        prev <= o_reset;
    end

    int errors = 0;
    task automatic check(input string name, input bit cond, input int a, input int b);
        if (!cond) begin $display("ERROR: %s (%0d vs %0d)", name, a, b); errors++; end
        else $display("ok: %s (%0d)", name, a);
    endtask

    task automatic burst();
        @(negedge tclk); req = 1; @(negedge tclk); req = 0;   // one-clock request
        wait (busy); wait (!busy);
        #(TX_PERIOD * TX_HALF * 3);   // let the last level settle, RX hold expire
    endtask

    task automatic send_byte(input logic [7:0] b);
        @(negedge tclk); m_valid = 1; m_data = b;
        do @(posedge tclk); while (!m_ready);
        @(negedge tclk); m_valid = 0;
    endtask

    initial if (RUN) begin
        int r0;
        #(RX_PERIOD * 20); rst = 0;
        #(4.0e6);                                       // 4ms: comparator idle level settles (both modes)
        check("no reset at idle", resets == 0, resets, 0);

        // 1. five bursts -> five resets
        repeat (5) burst();
        check("5 bursts -> 5 resets", resets == 5, resets, 5);
        check("reset width", last_width == RESET_CYC, last_width, RESET_CYC);

        // 2. a single step (one edge each way, TX_HALF long) must not trigger
        r0 = resets;
        force_en = 1; force_lvl = 1; #(TX_PERIOD * TX_HALF); force_lvl = 0; force_en = 0;
        #(5.0e6);                                       // AC decay may add one late edge
        check("single step ignored", resets == r0, resets, r0);

        // 3. Manchester traffic (idle square wave + bytes) must not trigger
        use_manchester = 1;
        #(TX_PERIOD * 25 * 40);
        repeat (40) send_byte($urandom());
        #(TX_PERIOD * 25 * 40);
        check("manchester ignored", resets == r0, resets, r0);

        // 4. burst straight after Manchester idle
        burst();
        check("burst after manchester", resets == r0 + 1, resets, r0 + 1);
        use_manchester = 0;
        #(1.0e6);

        // 5. random chatter, runs shorter than HALF_MIN
        r0 = resets;
        force_en = 1;
        repeat (400) begin
            force_lvl = ~force_lvl;
            #(RX_PERIOD * (1 + $urandom() % 1400));
        end
        force_en = 0;
        #(1.0e6);
        check("chatter ignored", resets == r0, resets, r0);

        // 6. still alive
        burst();
        check("burst after chatter", resets == r0 + 1, resets, r0 + 1);

        if (errors != 0) $fatal(1, "FAILED: %0d errors", errors);
        $display("PASS pulse_reset MODE=%0d", MODE);
        $finish;
    end
endmodule
