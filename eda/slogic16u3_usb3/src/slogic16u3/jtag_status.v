// Read-only status register on GW_JTAG ER1 (IR 0x42), the same scheme as
// eda/slogic16u3_probe: TCK / TDI are taken from the pads and oversampled by
// the internal oscillator, GW_JTAG's strobes are synchronised, so nothing is
// clocked by tck_o (that shifted bits with rust-dap's TDI timing). A scan
// shifts out cap (LSB first), latched at Capture-DR; TCK must stay below
// ~osc / 8.
// ER2 (IR 0x43, L2 bits) works the same way on cap2 and can also be written: at Update-DR, with the
// last bit shifted in (sr2[L2-1]) set, o_w2 pulses for one osc cycle with o_w2_data = sr2[L2-2 -: 31]
// (the 31 bits below it). A scan therefore returns cap2 as captured before its own write.
module jtag_status #(
    parameter integer L  = 128,
    parameter integer L2 = 128
) (
    input  wire         tck_pad_i,
    input  wire         tms_pad_i,
    input  wire         tdi_pad_i,
    output wire         tdo_pad_o,
    input  wire         osc,
    input  wire [L-1:0] cap,
    input  wire [L2-1:0] cap2,
    output reg          o_w2 = 1'b0,
    output reg  [30:0]  o_w2_data = 31'd0
);
    wire tck_c, tms_c, tdi_c, tdo_c;
    IBUF u_tck (.I(tck_pad_i), .O(tck_c));
    IBUF u_tms (.I(tms_pad_i), .O(tms_c));
    IBUF u_tdi (.I(tdi_pad_i), .O(tdi_c));
    OBUF u_tdo (.I(tdo_c), .O(tdo_pad_o));

    wire jtck, jtdi, jrst, sdc, upd, pause, en1, en2, rti1, rti2;
    wire tdo_er1, tdo_er2;
    GW_JTAG u_jtag (
        .tck_pad_i(tck_c), .tms_pad_i(tms_c), .tdi_pad_i(tdi_c), .tdo_pad_o(tdo_c),
        .tck_o(jtck), .tdi_o(jtdi), .test_logic_reset_o(jrst),
        .run_test_idle_er1_o(rti1), .run_test_idle_er2_o(rti2),
        .shift_dr_capture_dr_o(sdc), .pause_dr_o(pause), .update_dr_o(upd),
        .enable_er1_o(en1), .enable_er2_o(en2),
        .tdo_er1_i(tdo_er1), .tdo_er2_i(tdo_er2)
    );

    reg [L-1:0] sr = {L{1'b0}};
    reg [2:0] tck_s = 3'd0, sdc_s = 3'd0, en1_s = 3'd0;
    reg [1:0] tdi_s = 2'd0;
    reg       in_scan = 1'b0;
    wire tck_rise = tck_s[1] && !tck_s[2];
    always @(posedge osc) begin
        tck_s <= {tck_s[1:0], tck_c};
        tdi_s <= {tdi_s[0], tdi_c};
        sdc_s <= {sdc_s[1:0], sdc};
        en1_s <= {en1_s[1:0], en1};
        if (tck_rise) begin
            if (en1_s[2] && sdc_s[2]) begin
                in_scan <= 1'b1;
                if (!in_scan) sr <= cap;
                else          sr <= {tdi_s[1], sr[L-1:1]};
            end else begin
                in_scan <= 1'b0;
            end
        end
    end
    assign tdo_er1 = sr[0];

    reg [L2-1:0] sr2 = {L2{1'b0}};
    reg [2:0] en2_s = 3'd0, upd_s = 3'd0;
    reg       in_scan2 = 1'b0;
    always @(posedge osc) begin
        en2_s <= {en2_s[1:0], en2};
        upd_s <= {upd_s[1:0], upd};
        o_w2 <= 1'b0;
        if (tck_rise) begin
            if (en2_s[2] && sdc_s[2]) begin
                in_scan2 <= 1'b1;
                if (!in_scan2) sr2 <= cap2;
                else           sr2 <= {tdi_s[1], sr2[L2-1:1]};
            end else begin
                in_scan2 <= 1'b0;
            end
        end
        if (upd_s[1] && !upd_s[2] && en2_s[2] && sr2[L2-1]) begin
            o_w2 <= 1'b1;
            o_w2_data <= sr2[L2-2 -: 31];
        end
    end
    assign tdo_er2 = sr2[0];
endmodule
