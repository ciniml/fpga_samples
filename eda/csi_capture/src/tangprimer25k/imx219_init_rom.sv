// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file imx219_init_rom.sv
 * @brief IMX219 (Raspberry Pi Camera v2) power-up register sequence.
 *
 * Mode A (bring-up): 640x480 RAW10, 2x2 analog binning of the centre
 * 1280x960, 2 lanes at 456 Mbps/lane, ~60 fps, streaming.
 * Derived from the Linux imx219 driver (common regs, 2-lane PLL table,
 * 640x480 mode, set_framefmt) with one change: PLL_OP_MPY 114 -> 57,
 * i.e. the output PLL at 456 MHz = 456 Mbps per lane instead of 912
 * (the IMX219 output PLL range is 432..916 MHz, so this is about the
 * lowest rate it can do). The video-timing side keeps the driver's
 * 182.4 Mpix/s; with 2x2 binning the output needs 91.2 Mpix/s, which is
 * exactly what 2 lanes x 456 Mbps / 10 bit carry (datasheet 9-1: the FIFO
 * absorbs pix rate > data rate when binning).
 * Entry: {addr[15:0], data[7:0]}; addr 0xFFFF = wait data ms,
 * 0xFFFE = end. The host (host/csictl.py) can rewrite any of it.
 */
`default_nettype none
module imx219_init_rom (
    input  wire  [6:0]  i_idx,
    output logic [23:0] o_entry
);
    always_comb begin
        case (i_idx)
            7'd0:  o_entry = {16'h0100, 8'h00};    // standby
            7'd1:  o_entry = {16'hFFFF, 8'd10};    // 10 ms
            // access to 0x3000-0x5fff
            7'd2:  o_entry = {16'h30EB, 8'h05};
            7'd3:  o_entry = {16'h30EB, 8'h0C};
            7'd4:  o_entry = {16'h300A, 8'hFF};
            7'd5:  o_entry = {16'h300B, 8'hFF};
            7'd6:  o_entry = {16'h30EB, 8'h05};
            7'd7:  o_entry = {16'h30EB, 8'h09};
            // undocumented (Linux driver)
            7'd8:  o_entry = {16'h455E, 8'h00};
            7'd9:  o_entry = {16'h471E, 8'h4B};
            7'd10: o_entry = {16'h4767, 8'h0F};
            7'd11: o_entry = {16'h4750, 8'h14};
            7'd12: o_entry = {16'h4540, 8'h00};
            7'd13: o_entry = {16'h47B4, 8'h14};
            7'd14: o_entry = {16'h4713, 8'h30};
            7'd15: o_entry = {16'h478B, 8'h10};
            7'd16: o_entry = {16'h478F, 8'h10};
            7'd17: o_entry = {16'h4793, 8'h10};
            7'd18: o_entry = {16'h4797, 8'h0E};
            7'd19: o_entry = {16'h479B, 8'h0E};
            7'd20: o_entry = {16'h0170, 8'h01};    // X_ODD_INC
            7'd21: o_entry = {16'h0171, 8'h01};    // Y_ODD_INC
            7'd22: o_entry = {16'h0128, 8'h00};    // DPHY_CTRL: timing auto
            7'd23: o_entry = {16'h012A, 8'h18};    // EXCK_FREQ 24 MHz
            7'd24: o_entry = {16'h012B, 8'h00};
            // PLL (2 lanes)
            7'd25: o_entry = {16'h0301, 8'h05};    // VTPXCK_DIV
            7'd26: o_entry = {16'h0303, 8'h01};    // VTSYCK_DIV
            7'd27: o_entry = {16'h0304, 8'h03};    // PREPLLCK_VT_DIV
            7'd28: o_entry = {16'h0305, 8'h03};    // PREPLLCK_OP_DIV
            7'd29: o_entry = {16'h0306, 8'h00};    // PLL_VT_MPY = 57
            7'd30: o_entry = {16'h0307, 8'h39};
            7'd31: o_entry = {16'h030B, 8'h01};    // OPSYCK_DIV
            7'd32: o_entry = {16'h030C, 8'h00};    // PLL_OP_MPY = 57 (456 Mbps/lane)
            7'd33: o_entry = {16'h030D, 8'h39};
            7'd34: o_entry = {16'h0114, 8'h01};    // CSI_LANE_MODE: 2 lanes
            // 640x480: centre 1280x960, 2x2 analog binning
            7'd35: o_entry = {16'h0164, 8'h03};    // X_ADD_STA 1000
            7'd36: o_entry = {16'h0165, 8'hE8};
            7'd37: o_entry = {16'h0166, 8'h08};    // X_ADD_END 2279
            7'd38: o_entry = {16'h0167, 8'hE7};
            7'd39: o_entry = {16'h0168, 8'h02};    // Y_ADD_STA 752
            7'd40: o_entry = {16'h0169, 8'hF0};
            7'd41: o_entry = {16'h016A, 8'h06};    // Y_ADD_END 1711
            7'd42: o_entry = {16'h016B, 8'hAF};
            7'd43: o_entry = {16'h0174, 8'h03};    // BINNING_MODE_H: x2 analog
            7'd44: o_entry = {16'h0175, 8'h03};    // BINNING_MODE_V
            7'd45: o_entry = {16'h016C, 8'h02};    // X_OUTPUT_SIZE 640
            7'd46: o_entry = {16'h016D, 8'h80};
            7'd47: o_entry = {16'h016E, 8'h01};    // Y_OUTPUT_SIZE 480
            7'd48: o_entry = {16'h016F, 8'hE0};
            7'd49: o_entry = {16'h0624, 8'h02};    // TP_WINDOW_WIDTH 640
            7'd50: o_entry = {16'h0625, 8'h80};
            7'd51: o_entry = {16'h0626, 8'h01};    // TP_WINDOW_HEIGHT 480
            7'd52: o_entry = {16'h0627, 8'hE0};
            7'd53: o_entry = {16'h018C, 8'h0A};    // CSI_DATA_FORMAT RAW10
            7'd54: o_entry = {16'h018D, 8'h0A};
            7'd55: o_entry = {16'h0309, 8'h0A};    // OPPXCK_DIV = bpp
            // timing / exposure
            7'd56: o_entry = {16'h0162, 8'h0D};    // LINE_LENGTH_A 3560 (binned minimum)
            7'd57: o_entry = {16'h0163, 8'hE8};
            7'd58: o_entry = {16'h0160, 8'h03};    // FRM_LENGTH_A 853 (= 1707 / 2): ~60 fps
            7'd59: o_entry = {16'h0161, 8'h55};
            7'd60: o_entry = {16'h015A, 8'h03};    // exposure 0x0300 lines
            7'd61: o_entry = {16'h015B, 8'h00};
            7'd62: o_entry = {16'h0157, 8'h80};    // analog gain 2x
            7'd63: o_entry = {16'h0158, 8'h01};    // digital gain 1.0
            7'd64: o_entry = {16'h0159, 8'h00};
            7'd65: o_entry = {16'h0172, 8'h00};    // orientation
            7'd66: o_entry = {16'h0600, 8'h00};    // test pattern off
            7'd67: o_entry = {16'h0601, 8'h00};
            7'd68: o_entry = {16'h0100, 8'h01};    // streaming
            default: o_entry = {16'hFFFE, 8'h00};
        endcase
    end
endmodule
`default_nettype wire
