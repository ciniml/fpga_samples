// SPDX-License-Identifier: BSL-1.0 AND MIT
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// The register values are from Digilent's Zybo Z7 Pcam 5C demo
// (github.com/Digilent/Zybo-Z7-SW, branch 20/Pcam-5C/master,
// src/Zybo-Z7-20-pcam-5c/src/ov5640/OV5640.h: cfg_init_, cfg_720p_60fps_,
// cfg_advanced_awb_), under this licence:
//
//   MIT License
//
//   Copyright (c) 2026 Digilent
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy
//   of this software and associated documentation files (the "Software"), to deal
//   in the Software without restriction, including without limitation the rights
//   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//   copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all
//   copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//   SOFTWARE.
/**
 * @file ov5640_720p30_init_rom.sv
 * @brief OV5640 (Digilent Pcam 5C) power-up register sequence for the
 *        display lock of eda/camera_dvi: ov5640_init_rom.sv with a 16:9
 *        window (1460 rows skipped to 730), the line length of a CEA 720p30 line
 *        (HTS 2489) and its 750 lines (VTS), and the auto exposure set for
 *        that line (band steps, exposure limit). Up to 256 entries.
 *
 * The order of the demo (OV5640::init, set_mode, set_awb): clock from the
 * pad, software reset, cfg_init_ (2-lane MIPI, continuous clock: 0x4800 =
 * 0x14, ends in software power down), cfg_720p_60fps_ (1280x720 RAW10,
 * binned, HTS 1896 / VTS 984), the advanced AWB, then power up = stream.
 * The demo's power cycle on PWUP is not possible here (the adapter pulls
 * PWUP high); the software reset stands in for it. The demo waits 1 s after
 * the reset, 100 ms is used here.
 * Measured on the hardware (2026-11-16): 280 Mbps per lane (continuous
 * clock), 30 fps (not the 60 of the demo's name), 720 lines of RAW10
 * WC 1600, no CRC / ECC errors over 2 minutes, error-free sample offsets
 * 3..13 of 16.
 * Entry: {addr[15:0], data[7:0]}; addr 0xFFFF = wait data ms,
 * 0xFFFE = end. The host (host/csictl.py) can rewrite any of it.
 */
`default_nettype none
module ov5640_720p30_init_rom (
    input  wire  [7:0]  i_idx,
    output logic [23:0] o_entry
);
    always_comb begin
        case (i_idx)
            8'd0:   o_entry = {16'hFFFF, 8'd50}; // wait 50 ms (PWUP high to SCCB access >= 50 ms)
            8'd1:   o_entry = {16'h3103, 8'h11}; // system clock from the pad (before the reset)
            8'd2:   o_entry = {16'h3008, 8'h82}; // software reset
            8'd3:   o_entry = {16'hFFFF, 8'd100}; // wait 100 ms
            // Digilent cfg_init_ (ends in software power down)
            8'd4:   o_entry = {16'h3008, 8'h42};
            8'd5:   o_entry = {16'h3103, 8'h03};
            8'd6:   o_entry = {16'h3017, 8'h00};
            8'd7:   o_entry = {16'h3018, 8'h00};
            8'd8:   o_entry = {16'h3034, 8'h18};
            8'd9:   o_entry = {16'h3035, 8'h11};
            8'd10:  o_entry = {16'h3036, 8'h38};
            8'd11:  o_entry = {16'h3037, 8'h11};
            8'd12:  o_entry = {16'h3108, 8'h01};
            8'd13:  o_entry = {16'h303D, 8'h10};
            8'd14:  o_entry = {16'h303B, 8'h19};
            8'd15:  o_entry = {16'h3630, 8'h2E};
            8'd16:  o_entry = {16'h3631, 8'h0E};
            8'd17:  o_entry = {16'h3632, 8'hE2};
            8'd18:  o_entry = {16'h3633, 8'h23};
            8'd19:  o_entry = {16'h3621, 8'hE0};
            8'd20:  o_entry = {16'h3704, 8'hA0};
            8'd21:  o_entry = {16'h3703, 8'h5A};
            8'd22:  o_entry = {16'h3715, 8'h78};
            8'd23:  o_entry = {16'h3717, 8'h01};
            8'd24:  o_entry = {16'h370B, 8'h60};
            8'd25:  o_entry = {16'h3705, 8'h1A};
            8'd26:  o_entry = {16'h3905, 8'h02};
            8'd27:  o_entry = {16'h3906, 8'h10};
            8'd28:  o_entry = {16'h3901, 8'h0A};
            8'd29:  o_entry = {16'h3731, 8'h02};
            8'd30:  o_entry = {16'h3600, 8'h37};
            8'd31:  o_entry = {16'h3601, 8'h33};
            8'd32:  o_entry = {16'h302D, 8'h60};
            8'd33:  o_entry = {16'h3620, 8'h52};
            8'd34:  o_entry = {16'h371B, 8'h20};
            8'd35:  o_entry = {16'h471C, 8'h50};
            8'd36:  o_entry = {16'h3A13, 8'h43};
            8'd37:  o_entry = {16'h3A18, 8'h00};
            8'd38:  o_entry = {16'h3A19, 8'hF8};
            8'd39:  o_entry = {16'h3635, 8'h13};
            8'd40:  o_entry = {16'h3636, 8'h06};
            8'd41:  o_entry = {16'h3634, 8'h44};
            8'd42:  o_entry = {16'h3622, 8'h01};
            8'd43:  o_entry = {16'h3C01, 8'h34};
            8'd44:  o_entry = {16'h3C04, 8'h28};
            8'd45:  o_entry = {16'h3C05, 8'h98};
            8'd46:  o_entry = {16'h3C06, 8'h00};
            8'd47:  o_entry = {16'h3C07, 8'h08};
            8'd48:  o_entry = {16'h3C08, 8'h00};
            8'd49:  o_entry = {16'h3C09, 8'h1C};
            8'd50:  o_entry = {16'h3C0A, 8'h9C};
            8'd51:  o_entry = {16'h3C0B, 8'h40};
            8'd52:  o_entry = {16'h503D, 8'h00};
            8'd53:  o_entry = {16'h3820, 8'h46};
            8'd54:  o_entry = {16'h300E, 8'h45};
            8'd55:  o_entry = {16'h4800, 8'h14};
            8'd56:  o_entry = {16'h302E, 8'h08};
            8'd57:  o_entry = {16'h4300, 8'h6F};
            8'd58:  o_entry = {16'h501F, 8'h01};
            8'd59:  o_entry = {16'h4713, 8'h03};
            8'd60:  o_entry = {16'h4407, 8'h04};
            8'd61:  o_entry = {16'h440E, 8'h00};
            8'd62:  o_entry = {16'h460B, 8'h35};
            8'd63:  o_entry = {16'h460C, 8'h20};
            8'd64:  o_entry = {16'h3824, 8'h01};
            8'd65:  o_entry = {16'h5000, 8'h07};
            8'd66:  o_entry = {16'h5001, 8'h03};
            // Digilent cfg_720p_60fps_: 1280x720 RAW10 (binned); 30 fps measured (PCLK 56 MHz, HTS 1896 x VTS 984)
            8'd67:  o_entry = {16'h3008, 8'h42}; // software power down while configuring
            8'd68:  o_entry = {16'h3035, 8'h21};
            8'd69:  o_entry = {16'h3036, 8'h46};
            8'd70:  o_entry = {16'h3037, 8'h05};
            8'd71:  o_entry = {16'h3108, 8'h11};
            8'd72:  o_entry = {16'h3034, 8'h1A};
            8'd73:  o_entry = {16'h3800, 8'h00};
            8'd74:  o_entry = {16'h3801, 8'h00};
            8'd75:  o_entry = {16'h3802, 8'h00}; // Y start 242: a 16:9 crop of the 1944 rows (1460 rows, 730 read) so that
            8'd76:  o_entry = {16'h3803, 8'hF2}; // the frame fits in 750 lines (the full 1940 rows need VTS > 970)
            8'd77:  o_entry = {16'h3804, 8'h0A};
            8'd78:  o_entry = {16'h3805, 8'h3B};
            8'd79:  o_entry = {16'h3806, 8'h06}; // Y end 1701. A multiple of 4 rows (the 1 / 3 row skip): 1458 rows
            8'd80:  o_entry = {16'h3807, 8'hA5}; // flipped the colour row parity every frame (yellow / blue)
            8'd81:  o_entry = {16'h3810, 8'h00};
            8'd82:  o_entry = {16'h3811, 8'h00};
            8'd83:  o_entry = {16'h3812, 8'h00};
            8'd84:  o_entry = {16'h3813, 8'h04}; // V offset 4 (even): 720 of the 730 rows
            8'd85:  o_entry = {16'h3808, 8'h05};
            8'd86:  o_entry = {16'h3809, 8'h00};
            8'd87:  o_entry = {16'h380A, 8'h02};
            8'd88:  o_entry = {16'h380B, 8'hD0};
            8'd89:  o_entry = {16'h380C, 8'h09}; // HTS 2489: one line = 44.444 us = a 720p30 display line (PCLK 56.0008 MHz measured)
            8'd90:  o_entry = {16'h380D, 8'hB9};
            8'd91:  o_entry = {16'h380E, 8'h02}; // VTS 750 = the display lines; the genlock rewrites 0x380F every frame
            8'd92:  o_entry = {16'h380F, 8'hEE};
            8'd93:  o_entry = {16'h3814, 8'h31};
            8'd94:  o_entry = {16'h3815, 8'h31};
            8'd95:  o_entry = {16'h3821, 8'h01};
            8'd96:  o_entry = {16'h4837, 8'h24};
            8'd97:  o_entry = {16'h3618, 8'h00};
            8'd98:  o_entry = {16'h3612, 8'h59};
            8'd99:  o_entry = {16'h3708, 8'h64};
            8'd100: o_entry = {16'h3709, 8'h52};
            8'd101: o_entry = {16'h370C, 8'h03};
            8'd102: o_entry = {16'h4300, 8'h00};
            8'd103: o_entry = {16'h501F, 8'h03};
            // Digilent cfg_advanced_awb_
            8'd104: o_entry = {16'h3406, 8'h00};
            8'd105: o_entry = {16'h5192, 8'h04};
            8'd106: o_entry = {16'h5191, 8'hF8};
            8'd107: o_entry = {16'h518D, 8'h26};
            8'd108: o_entry = {16'h518F, 8'h42};
            8'd109: o_entry = {16'h518E, 8'h2B};
            8'd110: o_entry = {16'h5190, 8'h42};
            8'd111: o_entry = {16'h518B, 8'hD0};
            8'd112: o_entry = {16'h518C, 8'hBD};
            8'd113: o_entry = {16'h5187, 8'h18};
            8'd114: o_entry = {16'h5188, 8'h18};
            8'd115: o_entry = {16'h5189, 8'h56};
            8'd116: o_entry = {16'h518A, 8'h5C};
            8'd117: o_entry = {16'h5186, 8'h1C};
            8'd118: o_entry = {16'h5181, 8'h50};
            8'd119: o_entry = {16'h5184, 8'h20};
            8'd120: o_entry = {16'h5182, 8'h11};
            8'd121: o_entry = {16'h5183, 8'h00};
            8'd122: o_entry = {16'h5001, 8'h03};
            // auto exposure for the 720p30 line (banding filter, exposure limit)
            8'd123: o_entry = {16'h3A08, 8'h00}; // AEC band steps for the 44.444 us line: 50 Hz 10 ms = 225 lines
            8'd124: o_entry = {16'h3A09, 8'hE1};
            8'd125: o_entry = {16'h3A0A, 8'h00}; // 60 Hz 8.33 ms = 188 lines
            8'd126: o_entry = {16'h3A0B, 8'hBC};
            8'd127: o_entry = {16'h3A0D, 8'h03}; // max bands in a frame: 3 (60 Hz) / 3 (50 Hz)
            8'd128: o_entry = {16'h3A0E, 8'h03};
            8'd129: o_entry = {16'h3A02, 8'h02}; // max exposure 744 lines (60 Hz / 50 Hz): with the demo's values the
            8'd130: o_entry = {16'h3A03, 8'hE8}; // exposure ran to 1770 lines (> VTS): a whole-frame exposure that
            8'd131: o_entry = {16'h3A14, 8'h02}; // beats with the 100 / 120 Hz light flicker (frame-to-frame brightness
            8'd132: o_entry = {16'h3A15, 8'hE8}; // changes on the monitor)
            8'd133: o_entry = {16'h3008, 8'h02}; // power up: streaming
            default: o_entry = {16'hFFFE, 8'h00};
        endcase
    end
endmodule
`default_nettype wire
