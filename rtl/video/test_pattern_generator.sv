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
    parameter int VFRONT = 5
)(
    input wire clock,
    input wire reset,

    output logic  [23:0] video_data,
    output logic         video_de,
    output logic         video_hsync,
    output logic         video_vsync
);

localparam int HTOTAL = HSYNC + HBACK + HACTIVE + HFRONT;
localparam int VTOTAL = VSYNC + VBACK + VACTIVE + VFRONT;
localparam int HCOUNTER_BITS = $clog2(HTOTAL);
localparam int VCOUNTER_BITS = $clog2(VTOTAL);

typedef logic [HCOUNTER_BITS-1:0] hcounter_t;
typedef logic [VCOUNTER_BITS-1:0] vcounter_t;

hcounter_t hcounter = 0;
vcounter_t vcounter = 0;

always_comb begin
    video_de = HSYNC + HBACK <= hcounter && hcounter < HSYNC + HBACK + HACTIVE
             && VSYNC + VBACK <= vcounter && vcounter < VSYNC + VBACK + VACTIVE;
    video_hsync = hcounter < HSYNC;
    video_vsync = vcounter < VSYNC;

    if( hcounter < HSYNC + HBACK + (HACTIVE*1/7) ) begin
        video_data = 24'hffffff;
    end
    else if( hcounter < HSYNC + HBACK + (HACTIVE*2/7) ) begin
        video_data = 24'hff0000;
    end
    else if( hcounter < HSYNC + HBACK + (HACTIVE*3/7) ) begin
        video_data = 24'hffff00;
    end
    else if( hcounter < HSYNC + HBACK + (HACTIVE*4/7) ) begin
        video_data = 24'h00ff00;
    end
    else if( hcounter < HSYNC + HBACK + (HACTIVE*5/7) ) begin
        video_data = 24'h00ffff;
    end
    else if( hcounter < HSYNC + HBACK + (HACTIVE*6/7) ) begin
        video_data = 24'h0000ff;
    end
    else begin
        video_data = 24'hff00ff;
    end
end

always_ff @(posedge clock) begin
    if( reset ) begin
        hcounter <= 0;
        vcounter <= 0;
    end
    else begin
        if( hcounter == HTOTAL - 1) begin
            hcounter <= '0;
            if( vcounter == VTOTAL - 1) begin
                vcounter <= '0;
            end
            else begin
                vcounter <= vcounter + vcounter_t'(1);
            end
        end
        else begin
            hcounter <= hcounter + hcounter_t'(1);
        end
    end
end

endmodule
`default_nettype wire