// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// ModRetro Chromatic template: blink the RGB status LED, buttons pick the colour.
// Every board signal that matters for safety is driven to a defined state:
// cartridge slot unpowered (bus Low on newer boards), ESP32 held in reset,
// audio codec in reset, LCD backlight off, IR LED off, USB pull-up off.
module top (
    input  wire        CLK_FPGA,        // 33.554432 MHz
    input  wire        POWER_ON_FPGA,   // 1: switch OFF (USB powered)
    input  wire        VERSION_DET,

    input  wire        BTN_A,
    input  wire        BTN_B,
    input  wire        BTN_START,
    input  wire        BTN_SEL,
    input  wire        BTN_DPAD_UP,
    input  wire        BTN_DPAD_DOWN,
    input  wire        BTN_DPAD_LEFT,
    input  wire        BTN_DPAD_RIGHT,
    input  wire        BTN_MENU,        // active Low

    output wire        FPGA_LED_EN,
    output wire        FPGA_LED_R,      // active Low
    output wire        FPGA_LED_G,
    output wire        FPGA_LED_B,

    // cartridge slot (kept unpowered by this template)
    output wire [15:0] CART_A,
    inout  wire [7:0]  CART_D,
    output wire        CART_CLK,
    output wire        CART_RD,
    output wire        CART_WR,
    output wire        CART_CS,
    inout  wire        CART_RST,
    output wire        CART_DATA_DIR_E,
    output wire        CART_CTRL_OE,
    output wire        CART_PWR_EN,
    input  wire        CART_DET,

    // board housekeeping
    output wire        CHG_EN_FPGA,
    output wire        SDIO_LS,
    inout  wire        POWER_DOWN_IO,
    output wire        ADC_SEL,
    output wire        ESP32_EN,
    output wire        ESP32_IO0,
    output wire        LCD_PWM,
    output wire        LCD_RESET,
    output wire        AUD_RESET,
    output wire        IR_LED,
    output wire        LINK_CLK_DIR_LV,
    output wire        LINK_SD_DIR_LV,

    // USB SoftPHY pins: released (no pull-up, no termination)
    input  wire        usb_rxdp_i,
    input  wire        usb_rxdn_i,
    inout  wire        usb_dxp_io,
    inout  wire        usb_dxn_io,
    inout  wire        usb_term_dp_io,
    inout  wire        usb_term_dn_io,
    output wire        usb_pullup_en_o
);
    // ---- power-on reset ----
    logic [7:0] por = '0;
    wire rst = ~por[7];
    always_ff @(posedge CLK_FPGA) if (!por[7]) por <= por + 8'd1;

    // ---- housekeeping (same levels as the upstream design) ----
    assign CHG_EN_FPGA     = 1'b1;
    assign SDIO_LS         = 1'b1;
    assign POWER_DOWN_IO   = 1'bz;
    assign ADC_SEL         = 1'b0;
    assign ESP32_EN        = 1'b0;      // ESP32 stays in reset while this design runs
    assign ESP32_IO0       = 1'b1;
    assign LCD_PWM         = 1'b0;
    assign LCD_RESET       = 1'b0;
    assign AUD_RESET       = 1'b0;
    assign IR_LED          = 1'b0;
    assign LINK_CLK_DIR_LV = 1'b0;      // connector -> FPGA
    assign LINK_SD_DIR_LV  = 1'b0;
    assign usb_dxp_io      = 1'bz;
    assign usb_dxn_io      = 1'bz;
    assign usb_term_dp_io  = 1'bz;
    assign usb_term_dn_io  = 1'bz;
    assign usb_pullup_en_o = 1'b0;

    // ---- cartridge slot: power never requested ----
    wire cart_legacy, cart_ready, cart_drive_low;
    CartPower #(.CLK_HZ(33554432)) u_cart_power (
        .i_clk(CLK_FPGA), .i_rst(rst),
        .i_enable(1'b0), .i_version_det(VERSION_DET),
        .o_legacy(cart_legacy), .o_ready(cart_ready),
        .o_pwr_en(CART_PWR_EN), .o_ctrl_oe(CART_CTRL_OE), .o_drive_low(cart_drive_low)
    );
    // newer board, slot off: every line Low. Legacy board (slot powered with the console): bus idle.
    assign CART_A          = 16'h0000;
    assign CART_D          = cart_drive_low ? 8'h00 : 8'hzz;
    assign CART_CLK        = ~cart_drive_low;
    assign CART_RD         = ~cart_drive_low;
    assign CART_WR         = ~cart_drive_low;
    assign CART_CS         = ~cart_drive_low;
    assign CART_DATA_DIR_E = ~cart_drive_low;   // 1: cartridge -> FPGA (data not driven)
    assign CART_RST        = cart_drive_low ? 1'b0 : 1'bz;

    // ---- demo ----
    wire led_r, led_g, led_b;
    ChromaticBlink #(.CLK_HZ(33554432)) u_blink (
        .i_clk(CLK_FPGA), .i_rst(rst),
        .i_btn_a(BTN_A), .i_btn_b(BTN_B), .i_btn_start(BTN_START), .i_btn_sel(BTN_SEL),
        .i_btn_up(BTN_DPAD_UP), .i_btn_down(BTN_DPAD_DOWN),
        .i_btn_left(BTN_DPAD_LEFT), .i_btn_right(BTN_DPAD_RIGHT),
        .i_btn_menu(~BTN_MENU),
        .o_led_r(led_r), .o_led_g(led_g), .o_led_b(led_b)
    );
    assign FPGA_LED_EN = ~POWER_ON_FPGA;
    assign FPGA_LED_R  = ~led_r;
    assign FPGA_LED_G  = ~led_g;
    assign FPGA_LED_B  = ~led_b;
endmodule
