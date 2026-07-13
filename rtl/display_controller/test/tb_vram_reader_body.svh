// NOTE: this file is included verbatim via `include (inline, ...)`, so
// Veryl's \{ identifier \} resolution does not apply here; the generated
// (mangled) names are written out directly.
`timescale 1ns/1ps

import display_controller_vram_reader_pkg::*;

module tb #(
    parameter string TEST_MODE = "single_pixel",
    parameter int SCREEN_WIDTH = 320,
    parameter int SCREEN_HEIGHT = 240,
    parameter int PIXEL_BITS = 8,
    parameter int READY_RATE = 8,
    parameter int MAX_TEST_COMMANDS = 10,
    parameter int TIMEOUT_CYCLES = 10000
)();
    logic clock /*verilator clocker*/;
    logic reset_n;

    // Command interface (AXI4-Stream)
    logic [63:0] axis_command_tdata;
    logic        axis_command_tvalid;
    logic        axis_command_tready;
    
    // Data output interface (AXI4-Stream)
    logic [31:0] axis_data_tdata;
    logic        axis_data_tvalid;
    logic        axis_data_tready;
    logic        axis_data_tlast;
    logic        axis_data_tuser;

    localparam int VRAM_ADDR_BITS = $clog2(SCREEN_WIDTH * SCREEN_HEIGHT - 1);
    typedef logic[VRAM_ADDR_BITS-1:0] num_pixels_t;

    // VRAM interface
    logic [VRAM_ADDR_BITS-1:0] vram_addr;
    logic                      vram_en;
    logic [PIXEL_BITS-1:0]     vram_data;

    // interfaces
    axi4s___axi4s_if__64__false__0 axis_command_in ();
    axi4s___axi4s_if__32__true__1 axis_data_out ();
    display_controller_vram_read_if #(
        .SCREEN_WIDTH(SCREEN_WIDTH),
        .SCREEN_HEIGHT(SCREEN_HEIGHT)
    ) vram_read ();

    // DUT instantiation
    display_controller_vram_reader #(
        .SCREEN_WIDTH(SCREEN_WIDTH),
        .SCREEN_HEIGHT(SCREEN_HEIGHT),
        .PIXEL_BITS(PIXEL_BITS)
    ) dut (
        .clock(clock),
        .reset(!reset_n),
        .axis_command_in(axis_command_in),
        .axis_data_out(axis_data_out),
        .vram_read(vram_read)
    );

    // interface signal connection
    always_comb begin
        axis_command_in.tdata = axis_command_tdata;
        axis_command_in.tvalid = axis_command_tvalid;
        axis_command_tready = axis_command_in.tready;

        axis_data_tdata = axis_data_out.tdata;
        axis_data_tvalid = axis_data_out.tvalid;
        axis_data_out.tready = axis_data_tready;
        axis_data_tlast = axis_data_out.tlast;
        axis_data_tuser = axis_data_out.tuser[0];

        vram_addr = vram_read.addr;
        vram_en = vram_read.en;
        vram_read.data = vram_data;
    end

    // VRAM memory model
    logic [PIXEL_BITS-1:0] vram_memory [0:SCREEN_WIDTH*SCREEN_HEIGHT-1];
    
    // VRAM read response (combinational)
    always_comb begin
        if (vram_en && vram_addr < num_pixels_t'(SCREEN_WIDTH * SCREEN_HEIGHT)) begin
            $info("VRAM read: addr=%0h, data=%0h", vram_addr, vram_memory[vram_addr]);
            vram_data = vram_memory[vram_addr];
        end else begin
            vram_data = {PIXEL_BITS{1'b0}};
        end
    end

    // Test variables
    int timeout_counter = 0;
    int command_index = 0;
    int receive_index = 0;
    logic test_complete = 0;
    
    // Test patterns
    display_controller_vram_reader_pkg::vram_reader_cmd_t test_commands[MAX_TEST_COMMANDS-1:0];
    logic [PIXEL_BITS-1:0] expected_data[];
    logic expected_last[];
    logic expected_sof[];
    int command_count;
    int expected_data_count;
    
    // Initialize VRAM memory with test pattern
    initial begin
        for (int i = 0; i < SCREEN_WIDTH * SCREEN_HEIGHT; i++) begin
            // Create a simple test pattern: pixel value = (y * SCREEN_WIDTH + x) & 8'hFF
            automatic int x = i % SCREEN_WIDTH;
            automatic int y = i / SCREEN_WIDTH;
            vram_memory[i] = 8'((y * SCREEN_WIDTH + x) & ((1 << PIXEL_BITS) - 1));
        end
        $display("VRAM initialized with test pattern");
    end

    // Initialize test patterns based on test mode
    initial begin
        case (TEST_MODE)
            "single_pixel": begin
                command_count = 1;
                test_commands[0] = '{x: 10, y: 20, w_minus_1: 0, h_minus_1: 0};
                
                expected_data = new[1];
                expected_last = new[1];
                expected_sof = new[1];
                
                expected_data[0] = vram_memory[20 * SCREEN_WIDTH + 10];
                expected_last[0] = 1'b1;
                expected_sof[0] = 1'b1;
                expected_data_count = 1;
                
                $display("Test mode: single_pixel at (%0d,%0d)", test_commands[0].x, test_commands[0].y);
            end
            "single_line": begin
                command_count = 1;
                test_commands[0] = '{x: 5, y: 10, w_minus_1: 9, h_minus_1: 0}; // 10 pixels horizontally
                
                expected_data = new[10];
                expected_last = new[10];
                expected_sof = new[10];
                expected_data_count = 10;
                
                for (int i = 0; i < 10; i++) begin
                    expected_data[i] = vram_memory[10 * SCREEN_WIDTH + 5 + i];
                    expected_last[i] = (i == 9) ? 1'b1 : 1'b0;
                    expected_sof[i] = (i == 0) ? 1'b1 : 1'b0;
                end
                
                $display("Test mode: single_line from (%0d,%0d) width=%0d", 
                        test_commands[0].x, test_commands[0].y, test_commands[0].w_minus_1 + 1);
            end
            "rectangle": begin
                automatic int data_idx = 0;
                
                command_count = 1;
                test_commands[0] = '{x: 100, y: 50, w_minus_1: 3, h_minus_1: 2}; // 4x3 rectangle
                
                expected_data = new[12]; // 4x3 = 12 pixels
                expected_last = new[12];
                expected_sof = new[12];
                expected_data_count = 12;
                
                for (int row = 0; row < 3; row++) begin
                    for (int col = 0; col < 4; col++) begin
                        automatic int vram_idx = (50 + row) * SCREEN_WIDTH + (100 + col);
                        expected_data[data_idx] = vram_memory[vram_idx];
                        expected_last[data_idx] = (col == 3) ? 1'b1 : 1'b0;
                        expected_sof[data_idx] = (row == 0 && col == 0) ? 1'b1 : 1'b0;
                        $display("Expected data[%0d] = %0h, last = %0b, sof = %0b, vram_idx = %0h, (col = %0d, row = %0d)", 
                                 data_idx, expected_data[data_idx], expected_last[data_idx], expected_sof[data_idx], vram_idx, col + 100, row + 50);
                        data_idx++;
                    end
                end
                
                $display("Test mode: rectangle from (%0d,%0d) size=4x3", 
                        test_commands[0].x, test_commands[0].y);
            end
            "multiple_commands": begin
                automatic int data_idx = 0;
                
                command_count = 3;
                test_commands[0] = '{x: 0, y: 0, w_minus_1: 0, h_minus_1: 0};     // Single pixel
                test_commands[1] = '{x: 10, y: 5, w_minus_1: 4, h_minus_1: 0};   // 5-pixel line
                test_commands[2] = '{x: 50, y: 25, w_minus_1: 1, h_minus_1: 1};  // 2x2 square
                
                expected_data = new[8]; // 1 + 5 + 2*2 = 8 pixels total
                expected_last = new[8];
                expected_sof = new[8];
                expected_data_count = 8;
                
                
                // Command 0: Single pixel at (0,0)
                expected_data[data_idx] = vram_memory[0];
                expected_last[data_idx] = 1'b1;
                expected_sof[data_idx] = 1'b1;
                data_idx++;
                
                // Command 1: 5-pixel line at (10,5)
                for (int i = 0; i < 5; i++) begin
                    expected_data[data_idx] = vram_memory[5 * SCREEN_WIDTH + 10 + i];
                    expected_last[data_idx] = (i == 4) ? 1'b1 : 1'b0;
                    expected_sof[data_idx] = (i == 0) ? 1'b1 : 1'b0;
                    $display("Expected data[%0d] = %0h, last = %0b, sof = %0b", 
                             data_idx, expected_data[data_idx], expected_last[data_idx], expected_sof[data_idx]);
                    data_idx++;
                end
                
                // Command 2: 2x2 square at (50,25)
                for (int row = 0; row < 2; row++) begin
                    for (int col = 0; col < 2; col++) begin
                        automatic int vram_idx = (25 + row) * SCREEN_WIDTH + (50 + col);
                        expected_data[data_idx] = vram_memory[vram_idx];
                        expected_last[data_idx] = (col == 1) ? 1'b1 : 1'b0;
                        expected_sof[data_idx] = (row == 0 && col == 0) ? 1'b1 : 1'b0;
                        data_idx++;
                    end
                end
                
                $display("Test mode: multiple_commands (%0d commands)", command_count);
            end
            default: begin
                command_count = 1;
                test_commands[0] = '{x: 0, y: 0, w_minus_1: 0, h_minus_1: 0};
                
                expected_data = new[1];
                expected_last = new[1];
                expected_sof = new[1];
                
                expected_data[0] = vram_memory[0];
                expected_last[0] = 1'b1;
                expected_sof[0] = 1'b1;
                expected_data_count = 1;
                
                $display("Test mode: default (single_pixel at origin)");
            end
        endcase
        $display("Test data prepared: %0d commands, %0d expected data", command_count, expected_data_count);
    end

    // Command driver process
    initial begin
        axis_command_tvalid = 1'b0;
        axis_command_tdata = 64'h0;
        command_index = 0;
        
        // Wait for reset_n deassertion
        wait(reset_n);
        repeat(10) @(posedge clock);

        // Send commands
        for (int i = 0; i < command_count; i++) begin
            // Pack command into 64-bit data
            logic [15:0] x = test_commands[i].x;
            logic [15:0] y = test_commands[i].y;
            logic [15:0] w = test_commands[i].w_minus_1;
            logic [15:0] h = test_commands[i].h_minus_1;
            
            axis_command_tdata = {x, y, w, h};
            axis_command_tvalid = 1'b1;
            
            $display("T=%0t: Sending command %0d: x=%0d, y=%0d, w_minus_1=%0d, h_minus_1=%0d, start address=%0h", 
                     $time, i, x, y, w, h, 32'(x) + y*SCREEN_WIDTH);
            
            // Wait for command to be accepted
            @(posedge clock);
            while (!axis_command_tready) @(posedge clock);
            axis_command_tvalid = 1'b0;
            command_index++;
            
            // Small delay between commands
            repeat(10) @(posedge clock);
        end
        
        // Wait for all data to be received
        while (receive_index < expected_data_count) begin
            @(posedge clock);
        end
        
        test_complete = 1;
    end

    // Data output ready driver (with random ready)
    always_ff @(negedge clock) begin
        if (reset_n) begin
            axis_data_tready <= 1'b0;
        end else begin
            axis_data_tready <= $urandom_range(0, 10) < READY_RATE;
        end
    end

    // Data output checker
    always_ff @(posedge clock) begin
        if (reset_n) begin
            receive_index <= 0;
        end else begin
            if (receive_index < expected_data_count) begin
                if (axis_data_tvalid && axis_data_tready) begin
                    $display("T=%0t: Received data[%0d]: 0x%02h, tlast=%b, sof=%b", 
                             $time, receive_index, axis_data_tdata[PIXEL_BITS-1:0], axis_data_tlast, axis_data_tuser);
                    
                    // Check data
                    if (axis_data_tdata[PIXEL_BITS-1:0] != expected_data[receive_index]) begin
                        $error("Data mismatch at index %0d: expected 0x%02h, got 0x%02h", 
                               receive_index, expected_data[receive_index], axis_data_tdata[PIXEL_BITS-1:0]);
                    end
                    
                    // Check tlast
                    if (axis_data_tlast != expected_last[receive_index]) begin
                        $error("TLAST mismatch at index %0d: expected %b, got %b", 
                               receive_index, expected_last[receive_index], axis_data_tlast);
                    end
                    
                    // Check SOF (tuser)
                    if (axis_data_tuser != expected_sof[receive_index]) begin
                        $error("SOF mismatch at index %0d: expected %b, got %b", 
                               receive_index, expected_sof[receive_index], axis_data_tuser);
                    end
                    
                    receive_index <= receive_index + 1;
                end
            end
        end
    end

    // Timeout counter
    always_ff @(posedge clock) begin
        if (reset_n) begin
            timeout_counter <= 0;
        end else begin
            timeout_counter <= timeout_counter + 1;
        end
    end
    
    // Clock generation (10ns period = 100MHz)
    always #5 clock = ~clock;
    
    initial begin
        clock = 0;
        $dumpfile("trace.fst");
        $dumpvars(0, tb);

        // Reset sequence
        reset_n = 1'b1;
        repeat(4) @(negedge clock);
        reset_n = 1'b0;
        $display("T=%0t: Reset released", $time);

        // Wait for test completion or timeout
        while (!test_complete && timeout_counter < TIMEOUT_CYCLES) begin
            @(posedge clock);
        end
        
        if (timeout_counter >= TIMEOUT_CYCLES) begin
            $error("Test timeout after %0d cycles", TIMEOUT_CYCLES);
        end else begin
            $display("Test completed successfully after %0d cycles", timeout_counter);
        end
        
        // Additional cycles to observe final behavior
        repeat(50) @(posedge clock);
        $finish;
    end
endmodule
