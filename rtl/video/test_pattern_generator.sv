// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file test_pattern_generator.sv
 * @brief Test pattern video signal generator
 */
`default_nettype none

module test_pattern_generator #(
    parameter int HSYNC = 40,
    parameter int HBACK = 220,
    parameter int HACTIVE = 1280,
    parameter int HFRONT = 110,
    parameter int VSYNC = 5,
    parameter int VBACK = 20,
    parameter int VACTIVE = 720,
    parameter int VFRONT = 5,
    parameter bit BOUNCE_LOGO = 0,
    parameter int LOGO_COLOR = 0,
    parameter     LOGO_PATH = "",
    parameter int LOGO_WIDTH = 24,
    parameter int LOGO_HEIGHT = 24
)(
    input wire clock,
    input wire reset,

    output logic  [23:0] video_data,
    output logic         video_de,
    output logic         video_hsync,
    output logic         video_vsync
);

logic  [23:0] video_data_value;

localparam int HTOTAL = HSYNC + HBACK + HACTIVE + HFRONT;
localparam int VTOTAL = VSYNC + VBACK + VACTIVE + VFRONT;
localparam int HCOUNTER_BITS = $clog2(HTOTAL);
localparam int VCOUNTER_BITS = $clog2(VTOTAL);

typedef logic [HCOUNTER_BITS-1:0] hcounter_t;
typedef logic [VCOUNTER_BITS-1:0] vcounter_t;

hcounter_t hcounter = 0;
vcounter_t vcounter = 0;

localparam int LOGO_STRIDE = (LOGO_WIDTH + 7) & ~7;
localparam int LOGO_BITS   = LOGO_STRIDE*LOGO_HEIGHT;
localparam int LOGO_BYTES  = LOGO_BITS >> 3;
typedef logic [$clog2(LOGO_BITS)-1:0] logo_address_t;
logic [7:0] logo_memory[LOGO_BYTES-1:0];

hcounter_t logo_x = 0;
vcounter_t logo_y = 0;
logic logo_dx = 0;
logic logo_dy = 0;

logo_address_t logo_address = 0;
logic [7:0] logo_pixels = 0;
logic logo_pixel = 0;
logic within_logo = 0;

if( BOUNCE_LOGO ) begin: bounce_logo_memory_load
    initial begin
        $readmemh(LOGO_PATH, logo_memory);
    end
    always_ff @(posedge clock) begin
        if( reset ) begin
        logo_pixels <= 0; 
        end
        else begin
            logo_pixels <= logo_memory[(logo_address + 1) >> 3];
        end
    end
end


always_comb begin
    logo_pixel = logo_pixels[logo_address&7];
    //logo_pixel = logo_memory[logo_address >> 3][logo_address&7];

    within_logo = HSYNC + HBACK + logo_x <= hcounter && hcounter < HSYNC + HBACK + logo_x + LOGO_WIDTH
               && VSYNC + VBACK + logo_y <= vcounter && vcounter < VSYNC + VBACK + logo_y + LOGO_HEIGHT;
end

always_ff @(posedge clock) begin
    if( reset ) begin
        hcounter <= '0;
        vcounter <= '0;
        logo_address <= '0;
        video_de <= 0;
        video_hsync <= 0;
        video_vsync <= 0;
        video_data <= 0;
    end
    else begin
        if( within_logo ) begin
            logo_address <= logo_address + 1;
        end
        //logo_pixel <= logo_pixels[(logo_address+7)&7];

        if( hcounter == HTOTAL - 1) begin
            hcounter <= '0;
            if( vcounter == VTOTAL - 1) begin
                vcounter <= '0;
                logo_address <= '0;
                // Update logo position
                if( logo_dx && logo_x == 0 || !logo_dx && logo_x == (HACTIVE - LOGO_WIDTH - 1)) begin
                    logo_dx <= !logo_dx;
                end
                if( logo_dy && logo_y == 0 || !logo_dy && logo_y == (VACTIVE - LOGO_HEIGHT - 1)) begin
                    logo_dy <= !logo_dy;
                end
                logo_x <= logo_dx ? logo_x - 1 : logo_x + 1;
                logo_y <= logo_dy ? logo_y - 1 : logo_y + 1;
            end
            else begin
                logo_address <= (logo_address + logo_address_t'(7)) & ~logo_address_t'(7);
                vcounter <= vcounter + vcounter_t'(1);
            end
        end
        else begin
            hcounter <= hcounter + hcounter_t'(1);
        end

        video_de <= HSYNC + HBACK <= hcounter && hcounter < HSYNC + HBACK + HACTIVE
                && VSYNC + VBACK <= vcounter && vcounter < VSYNC + VBACK + VACTIVE;
        video_hsync <= hcounter < HSYNC;
        video_vsync <= vcounter < VSYNC;
        
        if( BOUNCE_LOGO && within_logo && logo_pixel ) begin
            video_data <= LOGO_COLOR;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*1/7) ) begin
            video_data <= 24'hffffff;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*2/7) ) begin
            video_data <= 24'hff0000;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*3/7) ) begin
            video_data <= 24'hffff00;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*4/7) ) begin
            video_data <= 24'h00ff00;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*5/7) ) begin
            video_data <= 24'h00ffff;
        end
        else if( hcounter < HSYNC + HBACK + (HACTIVE*6/7) ) begin
            video_data <= 24'h0000ff;
        end
        else begin
            video_data <= 24'hff00ff;
        end
    end
end

endmodule
`default_nettype wire