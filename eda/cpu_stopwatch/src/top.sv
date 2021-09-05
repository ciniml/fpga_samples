/**
 * @file top.sv
 * @brief Top module for SERV SoC example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype wire
module top (
    input logic clock,

    // push switches
    input logic key_1,
    input logic key_2,
    input logic key_3,
    input logic key_4,
    input logic key_5,
    input logic key_6,
    input logic key_7,
    input logic key_8,

    // DIP switches
    input logic sw_1,
    input logic sw_2,
    input logic sw_3,
    input logic sw_4,
    input logic sw_5,
    input logic sw_6,
    input logic sw_7,
    input logic sw_8,
    
    // 4 digit 7 segment with DP LEDs
    output logic seg_a,
    output logic seg_b,
    output logic seg_c,
    output logic seg_d,
    output logic seg_e,
    output logic seg_f,
    output logic seg_g,
    output logic seg_dp,
    output logic seg_dig1,
    output logic seg_dig2,
    output logic seg_dig3,
    output logic seg_dig4,

    // single color LEDs
    output logic [7:0] led_out,
    
    // RGB LEDs
    output logic g_led1,
    output logic b_led1,
    output logic r_led1,
    output logic g_led2,
    output logic b_led2,
    output logic r_led2,
    output logic g_led3,
    output logic b_led3,
    output logic r_led3,
    output logic g_led4,
    output logic b_led4,
    output logic r_led4
);

localparam int CLOCK_HZ = 12_000_000;
localparam int IMEM_SIZE_BYTES = 512;
localparam int DMEM_SIZE_BYTES = 64;
localparam int UPDATE_FREQ_HZ = 1000;
localparam int DEBOUNCE_SAMPLING_HZ = 200;

// Timer counter for generate sampling timing.
logic debounce_sampling_trigger;
timer_counter #(
    .MAX_COUNTER_VALUE(CLOCK_HZ/DEBOUNCE_SAMPLING_HZ)
) debounce_timer_inst (
    .clock(clock),
    .reset(1'b0),

    .enable(1'b1),
    .top_value(CLOCK_HZ/DEBOUNCE_SAMPLING_HZ),
    .compare_value(1'b0),

    .counter_value(),

    .overflow(debounce_sampling_trigger),
    .compare_match()
);

// The instance of debouncing filter.
logic [8:1] raw_keys;
assign raw_keys[8:1] = ~{key_8, key_7, key_6, key_5, key_4, key_3, key_2, key_1};
logic [8:1] keys;
logic [8:1] keys_pressed;
for(genvar i = 1; i <= 8; i++) begin: gen_debounce
    debounce #(
        .FILTER_COUNTER_MAX(3)
    ) key_debounce_inst (
        .clock(clock),
        .reset(1'b0),

        .sampling_trigger(debounce_sampling_trigger),
        .async_in(raw_keys[i]),
        .sync_out(keys[i])
    );

    logic key_prev = 0;
    assign keys_pressed[i] = !key_prev && keys[i];
    always_ff @(posedge clock) begin
        key_prev <= keys[i];
    end
end

// Reset generator
logic reset = 1;
logic [15:0] reset_reg = '1;
always_ff @(posedge clock) begin
    reset_reg <= {1'b0, reset_reg[15:1]};
    reset <= |reset_reg;
end

// Timer counter for generate digit selection timing.
logic reflesh_trigger;
timer_counter #(
    .MAX_COUNTER_VALUE(CLOCK_HZ/UPDATE_FREQ_HZ)
) digit_refresh_timer_inst (
    .clock(clock),
    .reset(1'b0),

    .enable(1'b1),
    .top_value(CLOCK_HZ/UPDATE_FREQ_HZ),
    .compare_value(1'b0),

    .counter_value(),

    .overflow(reflesh_trigger),
    .compare_match()
);

// Segment LED driver
logic [5:0] digits [0:3];
logic [7:0] segment_out;
logic [3:0] digit_selector_out;

always_comb begin    
    seg_a  = segment_out[0];
    seg_b  = segment_out[1];
    seg_c  = segment_out[2];
    seg_d  = segment_out[3];
    seg_e  = segment_out[4];
    seg_f  = segment_out[5];
    seg_g  = segment_out[6];
    seg_dp = segment_out[7];
    seg_dig1 = digit_selector_out[0];
    seg_dig2 = digit_selector_out[1];
    seg_dig3 = digit_selector_out[2];
    seg_dig4 = digit_selector_out[3];
end

seven_segment_with_dp segment_led_inst (
    .reset(1'b0),
    .next_segment(reflesh_trigger),
    .*
);

// Color LEDs
logic [2:0] color_leds[3:0];
always_comb begin
    r_led1 = ~color_leds[0][0];
    g_led1 = ~color_leds[0][1];
    b_led1 = ~color_leds[0][2];
    r_led2 = ~color_leds[1][0];
    g_led2 = ~color_leds[1][1];
    b_led2 = ~color_leds[1][2];
    r_led3 = ~color_leds[2][0];
    g_led3 = ~color_leds[2][1];
    b_led3 = ~color_leds[2][2];
    r_led4 = ~color_leds[3][0];
    g_led4 = ~color_leds[3][1];
    b_led4 = ~color_leds[3][2];
end

// picorv32
logic        mem_valid;
logic        mem_instr;
logic        mem_ready;
logic [31:0] mem_addr;
logic [31:0] mem_wdata;
logic [ 3:0] mem_wstrb;
logic [31:0] mem_rdata;

// Pico Co-Processor Interface (PCPI)
logic        pcpi_valid;
logic [31:0] pcpi_insn = 0;
logic [31:0] pcpi_rs1;
logic [31:0] pcpi_rs2;
logic        pcpi_wr = 0;
logic [31:0] pcpi_rd = 0;
logic        pcpi_wait = 0;
logic        pcpi_ready = 0;

// IRQ Interface
logic [31:0] irq = 0;
logic [31:0] eoi;

picorv32 #(
    .PROGADDR_RESET(32'h0800_0000)
) picorv_inst (
    .clk(clock),
    .resetn(!reset),
    
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .pcpi_valid(pcpi_valid),
    .pcpi_insn(pcpi_insn),
    .pcpi_rs1(pcpi_rs1),
    .pcpi_rs2(pcpi_rs2),
    .pcpi_wr(pcpi_wr),
    .pcpi_rd(pcpi_rd),
    .pcpi_wait(pcpi_wait),
    .pcpi_ready(pcpi_ready),
    .irq(irq),
    .eoi(eoi)
);

// Free running counter
logic [31:0] free_running_counter = 0;
always_ff @(posedge clock) begin
    if( reset ) begin
        free_running_counter <= 0;
    end
    else begin
        free_running_counter <= free_running_counter + 1;
    end
end

// Bus access
localparam bit[3:0] DBUS_REG_SPACE  = 4'h3;  // 32'h3000_0000 ~ 32'h3fff_ffff
localparam bit[5:0] REG_ID          = 8'h00;
localparam bit[5:0] REG_LED         = 8'h01;
localparam bit[5:0] REG_KEY         = 8'h02;
localparam bit[5:0] REG_SWITCH      = 8'h03;
localparam bit[5:0] REG_COLOR_LED_0 = 8'h04;
localparam bit[5:0] REG_COLOR_LED_1 = 8'h05;
localparam bit[5:0] REG_COLOR_LED_2 = 8'h06;
localparam bit[5:0] REG_COLOR_LED_3 = 8'h07;
localparam bit[5:0] REG_SEG_LED_0   = 8'h08;
localparam bit[5:0] REG_SEG_LED_1   = 8'h09;
localparam bit[5:0] REG_SEG_LED_2   = 8'h0a;
localparam bit[5:0] REG_SEG_LED_3   = 8'h0b;
localparam bit[5:0] REG_COUNTER     = 8'h0c;
localparam bit[5:0] REG_CLOCK_HZ    = 8'h0d;

localparam bit[31:0] REG_ID_VALUE = 32'h01234567;

localparam int IMEM_ADDR_BITS = $clog2(IMEM_SIZE_BYTES);
localparam int DMEM_ADDR_BITS = $clog2(DMEM_SIZE_BYTES);
logic [31:0] imem [0:IMEM_SIZE_BYTES/4-1];
logic [31:0] dmem [0:DMEM_SIZE_BYTES/4-1];
logic mem_read;
assign mem_read = ~|mem_wstrb;
always_ff @(posedge clock) begin
    if( reset ) begin
        mem_ready <= 0;
    end
    else begin
        mem_ready <= 0;
        if( mem_valid ) begin
            mem_ready <= 1;
            if( mem_read ) begin
                if( mem_instr ) begin
                    mem_rdata <= imem[mem_addr[IMEM_ADDR_BITS-1:2]];
                end
                else begin
                    if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // Peripheral reg access
                        case (mem_addr[7:2])
                            REG_ID:          mem_rdata <= REG_ID_VALUE;
                            REG_KEY:         mem_rdata <= {24'b0, keys};
                            REG_SWITCH:      mem_rdata <= {24'b0, sw_8, sw_7, sw_6, sw_5, sw_4, sw_3, sw_2, sw_1};
                            REG_LED:         mem_rdata <= {24'b0, led_out};
                            REG_COLOR_LED_0: mem_rdata <= {29'b0, color_leds[0]};
                            REG_COLOR_LED_1: mem_rdata <= {29'b0, color_leds[1]};
                            REG_COLOR_LED_2: mem_rdata <= {29'b0, color_leds[2]};
                            REG_COLOR_LED_3: mem_rdata <= {29'b0, color_leds[3]};
                            REG_SEG_LED_0:   mem_rdata <= {26'b0, digits[0]};
                            REG_SEG_LED_1:   mem_rdata <= {26'b0, digits[0]};
                            REG_SEG_LED_2:   mem_rdata <= {26'b0, digits[0]};
                            REG_SEG_LED_3:   mem_rdata <= {26'b0, digits[0]};
                            REG_COUNTER:     mem_rdata <= free_running_counter;
                            REG_CLOCK_HZ:    mem_rdata <= CLOCK_HZ;
                            default:         mem_rdata <= 0;
                        endcase
                    end
                    else begin
                        mem_rdata <= dmem[mem_addr[DMEM_ADDR_BITS-1:2]];
                    end
                end
            end
            else begin
                if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // Peripheral reg access
                    case (mem_addr[7:2])
                        REG_LED: led_out <= mem_wdata[7:0];
                        REG_COLOR_LED_0: color_leds[0] <= mem_wdata[2:0];
                        REG_COLOR_LED_1: color_leds[1] <= mem_wdata[2:0];
                        REG_COLOR_LED_2: color_leds[2] <= mem_wdata[2:0];
                        REG_COLOR_LED_3: color_leds[3] <= mem_wdata[2:0];
                        REG_SEG_LED_0: digits[0] <= mem_wdata[5:0];
                        REG_SEG_LED_1: digits[1] <= mem_wdata[5:0];
                        REG_SEG_LED_2: digits[2] <= mem_wdata[5:0];
                        REG_SEG_LED_3: digits[3] <= mem_wdata[5:0];
                    endcase
                end
                else begin
                    if( mem_wstrb[0] ) dmem[mem_addr[DMEM_ADDR_BITS-1:2]][ 7: 0] <= mem_wdata[ 7: 0];
                    if( mem_wstrb[1] ) dmem[mem_addr[DMEM_ADDR_BITS-1:2]][15: 8] <= mem_wdata[15: 8];
                    if( mem_wstrb[2] ) dmem[mem_addr[DMEM_ADDR_BITS-1:2]][23:16] <= mem_wdata[23:16];
                    if( mem_wstrb[3] ) dmem[mem_addr[DMEM_ADDR_BITS-1:2]][31:24] <= mem_wdata[31:24];
                end
            end
        end
    end
end

initial begin
    $readmemh("src/sw/bootrom.hex", imem);
end

endmodule