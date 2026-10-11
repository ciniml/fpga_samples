// SLogic16U3 pin probe: a "soft boundary scan" through the Gowin user JTAG
// instruction ER1 (0x42). Every listed pin is read (level + activity flag) and the
// drivable ones can be set to Hi-Z / 0 / 1 / blink from the host
// (host/slogic_probe.py). No board clock is assumed: the JTAG side runs on TCK,
// activity detection and blinking on the internal oscillator.
//
// ER1 data register, LSB first out of TDO (L = 72 + 4*N bits since version 4):
//   [31:0]              magic 32'h534C_5031 ("SLP1")
//   [39:32]             N (number of pins)
//   [47:40]             flags: [1:0] pull mode of this build (0 none, 1 up, 2 down)
//                              [3:2] pin set (0 main, 1 cfg, 2 la, 3 mipi)
//   [55:48]             version
//   [56 +: N]           pin levels at Capture-DR
//   [56+N +: N]         activity flags (a level change seen since the last clear)
//   [56+2N +: 2N]       per-pin mode {pin i at bits 2i+1:2i}: 0 Hi-Z, 1 drive 0, 2 drive 1, 3 blink
//   [56+4N +: 16]       global: [0] fast blink (~100 kHz instead of ~1.5 Hz)
//                               [1] hold activity flags cleared
//                               [2] blink as open-drain (sink only)
//                               [6:3] blink divider: 0 = per bit 0, k = osc / 2^k (k = 1..15,
//                                     ~26 MHz .. ~1.6 kHz with the ~52 MHz oscillator)
//                               [10:8] blink duty with a divider k >= 4: 0 = 50 %,
//                                      d = d/8 high (PWM, e.g. for an RC-filtered DAC)
//                               [14:11] fine duty (VERSION >= 5): with a divider k >= 7 the
//                                       duty is {[10:8], [14:11]}/128 (0 = 50 %); [14:11] = 0
//                                       gives the same d/8 as above
//                               [15] commit (shift-in only, reads back 0)
// Update-DR always happens after a scan, so a scan only changes the mode and global
// fields when the shifted-in commit bit is 1; a read is a scan with commit 0.
// The other fields are capture-only. Pins whose CAN_DRIVE bit is 0 never drive.

// PROBE_N / PROBE_N_IO / PROBE_CAN_DRIVE / PROBE_PULL / PROBE_PINSET (and PROBE_MIPI_DPHY) come
// from defines_gen.v (written by project.tcl).
//
// With PROBE_MIPI_DPHY the last 10 pins are the M0 D-PHY pads in the order CKP CKN D0P D0N D1P
// D1N D2P D2N D3P D3N, used through MIPI_DPHY in LP mode (1.2 V): level = LPRX, drive = LPTX.
// LPTX is enabled per lane, so driving one pin of a lane also drives its partner: a Hi-Z pin
// in an enabled lane outputs 0.

module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,
    inout  wire [`PROBE_N_IO-1:0] io
`ifdef PROBE_MIPI_DPHY
    ,
    inout  wire m0_ck_p, m0_ck_n, m0_d0_p, m0_d0_n, m0_d1_p, m0_d1_n,
    inout  wire m0_d2_p, m0_d2_n, m0_d3_p, m0_d3_n
`endif
);
    localparam integer N = `PROBE_N;
    localparam integer N_IO = `PROBE_N_IO;
    localparam integer L = 72 + 4*N;
    localparam [N-1:0] CAN_DRIVE = `PROBE_CAN_DRIVE;
    localparam [31:0] MAGIC = 32'h534C_5031;
    localparam [7:0] VERSION = 8'd5;
    localparam [7:0] N8 = N;

    // ---------------------------------------------------------------- JTAG
    wire tck_c, tms_c, tdi_c, tdo_c;
    IBUF u_tck (.I(tck_pad_i), .O(tck_c));
    IBUF u_tms (.I(tms_pad_i), .O(tms_c));
    IBUF u_tdi (.I(tdi_pad_i), .O(tdi_c));
    OBUF u_tdo (.I(tdo_c), .O(tdo_pad_o));

    wire jtck, jtdi, jrst, sdc, upd, pause, en1, en2, rti1, rti2;
    wire tdo_er1;
    GW_JTAG u_jtag (
        .tck_pad_i(tck_c), .tms_pad_i(tms_c), .tdi_pad_i(tdi_c), .tdo_pad_o(tdo_c),
        .tck_o(jtck), .tdi_o(jtdi), .test_logic_reset_o(jrst),
        .run_test_idle_er1_o(rti1), .run_test_idle_er2_o(rti2),
        .shift_dr_capture_dr_o(sdc), .pause_dr_o(pause), .update_dr_o(upd),
        .enable_er1_o(en1), .enable_er2_o(en2),
        .tdo_er1_i(tdo_er1), .tdo_er2_i(1'b0)
    );

    // ---------------------------------------------------------------- pins
    reg  [2*N-1:0] mode = {2*N{1'b0}};
    reg  [15:0]    glob = 16'd0;
    wire [N-1:0]   pin_in;
    wire [N-1:0]   oe_all, out_all;
    assign pin_in[N_IO-1:0] = io;
    reg  [N-1:0]   act = {N{1'b0}};
    wire           blink;

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_pin
            wire [1:0] m  = mode[2*gi +: 2];
            wire od       = glob[2];
            wire oe_w     = CAN_DRIVE[gi] && (m == 2'd1 || m == 2'd2 || (m == 2'd3 && (!od || !blink)));
            wire out_w    = (m == 2'd2) || (m == 2'd3 && !od && blink);
            assign oe_all[gi]  = oe_w;
            assign out_all[gi] = out_w;
            if (gi < N_IO) begin : g_io
                assign io[gi] = oe_w ? out_w : 1'bz;
            end
        end
    endgenerate

`ifdef PROBE_MIPI_DPHY
    // M0 in LP mode: pins N_IO+0..9 = CKP CKN D0P D0N D1P D1N D2P D2N D3P D3N
    localparam integer M = N_IO;
    wire [9:0] lprx;
    wire [4:0] lane_en;   // CK D0 D1 D2 D3
    genvar li;
    generate
        for (li = 0; li < 5; li = li + 1) begin : g_lane
            assign lane_en[li] = oe_all[M + 2*li] | oe_all[M + 2*li + 1];
        end
    endgenerate
    assign pin_in[N-1:N_IO] = lprx;
    MIPI_DPHY u_m0 (
        .CK_P(m0_ck_p), .CK_N(m0_ck_n), .D0_P(m0_d0_p), .D0_N(m0_d0_n), .D1_P(m0_d1_p), .D1_N(m0_d1_n),
        .D2_P(m0_d2_p), .D2_N(m0_d2_n), .D3_P(m0_d3_p), .D3_N(m0_d3_n),
        .DI_LPRXCK_P(lprx[0]), .DI_LPRXCK_N(lprx[1]), .DI_LPRX0_P(lprx[2]), .DI_LPRX0_N(lprx[3]),
        .DI_LPRX1_P(lprx[4]), .DI_LPRX1_N(lprx[5]), .DI_LPRX2_P(lprx[6]), .DI_LPRX2_N(lprx[7]),
        .DI_LPRX3_P(lprx[8]), .DI_LPRX3_N(lprx[9]),
        .DO_LPTXCK_P(out_all[M+0]), .DO_LPTXCK_N(out_all[M+1]), .DO_LPTX0_P(out_all[M+2]), .DO_LPTX0_N(out_all[M+3]),
        .DO_LPTX1_P(out_all[M+4]), .DO_LPTX1_N(out_all[M+5]), .DO_LPTX2_P(out_all[M+6]), .DO_LPTX2_N(out_all[M+7]),
        .DO_LPTX3_P(out_all[M+8]), .DO_LPTX3_N(out_all[M+9]),
        .LPTXEN_LNCK(lane_en[0]), .LPTXEN_LN0(lane_en[1]), .LPTXEN_LN1(lane_en[2]),
        .LPTXEN_LN2(lane_en[3]), .LPTXEN_LN3(lane_en[4]),
        .LPRX_EN_CK(1'b1), .LPRX_EN_D0(1'b1), .LPRX_EN_D1(1'b1), .LPRX_EN_D2(1'b1), .LPRX_EN_D3(1'b1),
        .HSRX_EN_CK(1'b0), .HSRX_EN_D0(1'b0), .HSRX_EN_D1(1'b0), .HSRX_EN_D2(1'b0), .HSRX_EN_D3(1'b0),
        .HSTXEN_LN0(1'b0), .HSTXEN_LN1(1'b0), .HSTXEN_LN2(1'b0), .HSTXEN_LN3(1'b0), .HSTXEN_LNCK(1'b0),
        .PWRON_RX(1'b1), .PWRON_TX(1'b1), .RESET(1'b0), .RX_DRST_N(1'b1), .TX_DRST_N(1'b1)
    );
`endif

    // ---------------------------------------------------------------- oscillator side
    wire osc;   // ~210 MHz / 4
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));

    reg [25:0] cnt = 26'd0;
    reg [N-1:0] in_s1 = {N{1'b0}}, in_s2 = {N{1'b0}};
    reg [2:0] clr_s = 3'd0, fast_s = 3'd0;
    always @(posedge osc) begin
        cnt    <= cnt + 26'd1;
        clr_s  <= {clr_s[1:0], glob[1]};
        fast_s <= {fast_s[1:0], glob[0]};
        in_s1  <= pin_in;
        in_s2  <= in_s1;
        act    <= clr_s[2] ? {N{1'b0}} : (act | (in_s1 ^ in_s2));
    end
    wire [3:0] div  = glob[6:3];   // glob is written in this clock domain
    wire [2:0] duty = glob[10:8];
    // top 3 bits of the k-bit counter = PWM phase in eighths
    wire [2:0] phase = (div >= 4'd4) ? {cnt[div - 4'd1], cnt[div - 4'd2], cnt[div - 4'd3]} : 3'd0;
    // top 7 bits of the k-bit counter = PWM phase in 1/128 (k >= 7)
    wire [6:0]  duty7  = {glob[10:8], glob[14:11]};
    wire [25:0] cnt_sh = cnt >> (div - 4'd7);
    wire [6:0]  phase7 = cnt_sh[6:0];
    assign blink = (div == 4'd0) ? (fast_s[2] ? cnt[8] : cnt[24]) :
                   (div >= 4'd7 && duty7 != 7'd0) ? (phase7 < duty7) :
                   (div >= 4'd4 && duty != 3'd0) ? (phase < duty) : cnt[div - 4'd1];

    // ---------------------------------------------------------------- ER1 data register
    // Everything runs on the oscillator: TCK and TDI are taken from the pads (the IBUF
    // outputs also feed GW_JTAG) and oversampled, GW_JTAG's strobes are synchronised.
    // Clocking a shift register on tck_o directly sampled TDI on the wrong side of the
    // probe's TDI change (bits came in shifted / smeared with rust-dap, 2026-10-10).
    // TCK must stay below ~osc/8 (~6 MHz); the host uses 1 MHz.
    reg [L-1:0] sr = {L{1'b0}};
    wire [1:0] pull = `PROBE_PULL;
    wire [1:0] pinset = `PROBE_PINSET;
    wire [L-1:0] cap = {1'b0, glob[14:0], mode, act, pin_in, VERSION, {4'd0, pinset, pull}, N8, MAGIC};

    reg [2:0] tck_s = 3'd0, sdc_s = 3'd0, en1_s = 3'd0, upd_s = 3'd0;
    reg [1:0] tdi_s = 2'd0;
    reg       in_scan = 1'b0;
    // The TAP acts on the state it was in before the TCK edge, so the strobes are taken
    // from the older stage [2] (sampled while TCK was still low) at a rising edge seen
    // between [2] and [1]; TDI from stage [1] (just after the edge).
    wire tck_rise = tck_s[1] && !tck_s[2];
    wire upd_rise = upd_s[1] && !upd_s[2];
    always @(posedge osc) begin
        tck_s <= {tck_s[1:0], tck_c};
        tdi_s <= {tdi_s[0], tdi_c};
        sdc_s <= {sdc_s[1:0], sdc};
        en1_s <= {en1_s[1:0], en1};
        upd_s <= {upd_s[1:0], upd};
        if (tck_rise) begin
            if (en1_s[2] && sdc_s[2]) begin
                in_scan <= 1'b1;
                if (!in_scan)
                    sr <= cap;                        // Capture-DR -> Shift-DR edge
                else
                    sr <= {tdi_s[1], sr[L-1:1]};      // Shift-DR edge
            end else begin
                in_scan <= 1'b0;
            end
        end
        // Update-DR: sr does not move until the next scan, several TCK periods later
        if (upd_rise && en1_s[1] && sr[L-1]) begin
            mode <= sr[56 + 2*N +: 2*N];
            glob <= {1'b0, sr[L-16 +: 15]};
        end
    end
    assign tdo_er1 = sr[0];
endmodule
