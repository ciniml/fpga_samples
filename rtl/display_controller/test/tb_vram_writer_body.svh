// NOTE: this file is included verbatim via `include (inline, ...)`, so
// Veryl's \{ identifier \} resolution does not apply here; the generated
// (mangled) names are written out directly.
`timescale 1ns/1ps

import display_controller_vram_writer_pkg::*;

module tb #(
    parameter string TEST_MODE = "single_pixel",
    parameter int SCREEN_WIDTH = 320,
    parameter int SCREEN_HEIGHT = 240,
    parameter int PIXEL_BITS = 8,
    parameter int VALID_RATE = 8,
    parameter int MAX_TEST_COMMANDS = 10,
    parameter int TIMEOUT_CYCLES = 10000
)();
    logic clock /*verilator clocker*/;
    logic reset_n;

    // Command interface (AXI4-Stream)
    logic [63:0] axis_command_tdata;
    logic        axis_command_tvalid;
    logic        axis_command_tready;
    
    // Data input interface (AXI4-Stream)
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

    // Complete
    logic complete;

    // interfaces
    axi4s___axi4s_if__64__false__0 axis_command_in ();
    axi4s___axi4s_if__32__true__1 axis_data_in ();
    display_controller_vram_write_if #(
        .SCREEN_WIDTH(SCREEN_WIDTH),
        .SCREEN_HEIGHT(SCREEN_HEIGHT)
    ) vram_write ();

    // DUT instantiation
    display_controller_vram_writer #(
        .SCREEN_WIDTH(SCREEN_WIDTH),
        .SCREEN_HEIGHT(SCREEN_HEIGHT),
        .PIXEL_BITS(PIXEL_BITS)
    ) dut (
        .clock(clock),
        .reset(reset_n),
        .axis_command_in(axis_command_in),
        .axis_data_in(axis_data_in),
        .vram_write(vram_write),
        .complete(complete)
    );

    // interface signal connection
    always_comb begin
        axis_command_in.tdata = axis_command_tdata;
        axis_command_in.tvalid = axis_command_tvalid;
        axis_command_tready = axis_command_in.tready;

        axis_data_in.tdata = axis_data_tdata;
        axis_data_in.tvalid = axis_data_tvalid;
        axis_data_tready = axis_data_in.tready;
        axis_data_in.tlast = axis_data_tlast;
        axis_data_in.tuser[0] = axis_data_tuser;

        vram_addr = vram_write.addr;
        vram_en = vram_write.en;
        vram_data = vram_write.data;
    end

    // VRAM write access recording (only when en=1)
    logic [VRAM_ADDR_BITS-1:0] recorded_addr [];
    logic [PIXEL_BITS-1:0]     recorded_data [];
    logic [VRAM_ADDR_BITS-1:0] expected_addr [];
    logic [PIXEL_BITS-1:0]     expected_data [];
    int recorded_count = 0;
    int expected_count = 0;
    
    // VRAM write access monitor
    always_ff @(posedge clock) begin
        if (!reset_n) begin
            recorded_count <= 0;
        end else begin
            if (vram_en) begin
                if (vram_addr < num_pixels_t'(SCREEN_WIDTH * SCREEN_HEIGHT)) begin
                    $info("VRAM write: addr=%0h, data=%0h", vram_addr, vram_data);
                    recorded_addr = new[recorded_count + 1](recorded_addr);
                    recorded_data = new[recorded_count + 1](recorded_data);
                    recorded_addr[recorded_count] = vram_addr;
                    recorded_data[recorded_count] = vram_data;
                    recorded_count <= recorded_count + 1;
                end
                else begin
                    $warning("VRAM write error: out of range - addr=%0h, data=%0h", vram_addr, vram_data);
                end
            end
        end
    end

    // Test variables
    int timeout_counter = 0;
    int command_index = 0;
    int send_index = 0;
    logic test_complete = 0;
    logic data_generation_complete = 0;
    
    // Test patterns
    display_controller_vram_writer_pkg::vram_writer_cmd_t test_commands[MAX_TEST_COMMANDS-1:0];
    logic [PIXEL_BITS-1:0] test_data[];
    logic test_last[];
    logic test_sof[];
    int command_count;
    int test_data_count;
    
    // Initialize recording arrays
    initial begin
        recorded_addr = new[0];
        recorded_data = new[0];
        expected_addr = new[0];
        expected_data = new[0];
        $display("Write access recording initialized");
    end

    // Initialize test patterns based on test mode
    initial begin
        case (TEST_MODE)
            "single_pixel": begin
                command_count = 1;
                test_commands[0] = '{x: 10, y: 20, w_minus_1: 0, h_minus_1: 0};
                
                test_data = new[1];
                test_last = new[1];
                test_sof = new[1];
                
                test_data[0] = 8'hAB;
                test_last[0] = 1'b1;
                test_sof[0] = 1'b1;
                test_data_count = 1;
                
                // Set expected write sequence
                expected_count = 1;
                expected_addr = new[1];
                expected_data = new[1];
                expected_addr[0] = VRAM_ADDR_BITS'(20 * SCREEN_WIDTH + 10);
                expected_data[0] = 8'hAB;
                
                $display("Test mode: single_pixel at (%0d,%0d) with data=0x%02h", 
                        test_commands[0].x, test_commands[0].y, test_data[0]);
            end
            "single_line": begin
                command_count = 1;
                test_commands[0] = '{x: 5, y: 10, w_minus_1: 9, h_minus_1: 0}; // 10 pixels horizontally
                
                test_data = new[10];
                test_last = new[10];
                test_sof = new[10];
                test_data_count = 10;
                
                // Set expected write sequence
                expected_count = 10;
                expected_addr = new[10];
                expected_data = new[10];
                
                for (int i = 0; i < 10; i++) begin
                    test_data[i] = 8'h10 + i[0 +: 8]; // Sequential pattern
                    test_last[i] = (i == 9) ? 1'b1 : 1'b0;
                    test_sof[i] = (i == 0) ? 1'b1 : 1'b0;
                    
                    // Set expected write sequence
                    expected_addr[i] = VRAM_ADDR_BITS'(10 * SCREEN_WIDTH + 5 + i);
                    expected_data[i] = test_data[i];
                end
                
                $display("Test mode: single_line from (%0d,%0d) width=%0d", 
                        test_commands[0].x, test_commands[0].y, test_commands[0].w_minus_1 + 1);
            end
            "rectangle": begin
                automatic int data_idx = 0;
                automatic int start_x = SCREEN_WIDTH*2/3;
                automatic int start_y = SCREEN_HEIGHT*2/3;
                command_count = 1;
                test_commands[0] = '{x: 16'(start_x), y: 16'(start_y), w_minus_1: 3, h_minus_1: 2}; // 4x3 rectangle

                test_data = new[12]; // 4x3 = 12 pixels
                test_last = new[12];
                test_sof = new[12];
                test_data_count = 12;
                
                // Set expected write sequence
                expected_count = 12;
                expected_addr = new[12];
                expected_data = new[12];
                
                for (int row = 0; row < 3; row++) begin
                    for (int col = 0; col < 4; col++) begin
                        automatic int vram_idx = (start_y + row) * SCREEN_WIDTH + (start_x + col);
                        test_data[data_idx] = 8'h80 + data_idx[0 +: 8]; // Pattern: 0x80, 0x81, 0x82, ...
                        test_last[data_idx] = (col == 3) ? 1'b1 : 1'b0;
                        test_sof[data_idx] = (row == 0 && col == 0) ? 1'b1 : 1'b0;
                        
                        // Set expected write sequence
                        expected_addr[data_idx] = VRAM_ADDR_BITS'(vram_idx);
                        expected_data[data_idx] = test_data[data_idx];

                        $display("Test data[%0d] = 0x%02h, last = %0b, sof = %0b, vram_idx = %0h, (col = %0d, row = %0d)",
                                 data_idx, test_data[data_idx], test_last[data_idx], test_sof[data_idx], vram_idx, col + start_x, row + start_y);
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
                
                test_data = new[8]; // 1 + 5 + 2*2 = 8 pixels total
                test_last = new[8];
                test_sof = new[8];
                test_data_count = 8;
                
                // Set expected write sequence
                expected_count = 8;
                expected_addr = new[8];
                expected_data = new[8];
                
                // Command 0: Single pixel at (0,0)
                test_data[data_idx] = 8'hFF;
                test_last[data_idx] = 1'b1;
                test_sof[data_idx] = 1'b1;
                expected_addr[data_idx] = 0;
                expected_data[data_idx] = test_data[data_idx];
                data_idx++;
                
                // Command 1: 5-pixel line at (10,5)
                for (int i = 0; i < 5; i++) begin
                    test_data[data_idx] = 8'h20 + i[0 +: 8];
                    test_last[data_idx] = (i == 4) ? 1'b1 : 1'b0;
                    test_sof[data_idx] = (i == 0) ? 1'b1 : 1'b0;
                    expected_addr[data_idx] = VRAM_ADDR_BITS'(5 * SCREEN_WIDTH + 10 + i);
                    expected_data[data_idx] = test_data[data_idx];
                    $display("Test data[%0d] = 0x%02h, last = %0b, sof = %0b", 
                             data_idx, test_data[data_idx], test_last[data_idx], test_sof[data_idx]);
                    data_idx++;
                end
                
                // Command 2: 2x2 square at (50,25)
                for (int row = 0; row < 2; row++) begin
                    for (int col = 0; col < 2; col++) begin
                        automatic int vram_idx = (25 + row) * SCREEN_WIDTH + (50 + col);
                        test_data[data_idx] = 8'('h30 + row * 2 + col);
                        test_last[data_idx] = (col == 1) ? 1'b1 : 1'b0;
                        test_sof[data_idx] = (row == 0 && col == 0) ? 1'b1 : 1'b0;
                        expected_addr[data_idx] = VRAM_ADDR_BITS'(vram_idx);
                        expected_data[data_idx] = test_data[data_idx];
                        data_idx++;
                    end
                end
                
                $display("Test mode: multiple_commands (%0d commands)", command_count);
            end
            default: begin
                command_count = 1;
                test_commands[0] = '{x: 0, y: 0, w_minus_1: 0, h_minus_1: 0};
                
                test_data = new[1];
                test_last = new[1];
                test_sof = new[1];
                
                test_data[0] = 8'hDD;
                test_last[0] = 1'b1;
                test_sof[0] = 1'b1;
                test_data_count = 1;
                
                // Set expected write sequence
                expected_count = 1;
                expected_addr = new[1];
                expected_data = new[1];
                expected_addr[0] = 0;
                expected_data[0] = test_data[0];
                
                $display("Test mode: default (single_pixel at origin)");
            end
        endcase
        $display("Test data prepared: %0d commands, %0d test data", command_count, test_data_count);
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
            
            @(negedge clock);
            
            axis_command_tdata = {x, y, w, h};
            axis_command_tvalid = 1'b1;
            
            $display("T=%0t: Sending command %0d: x=%0d, y=%0d, w_minus_1=%0d, h_minus_1=%0d, start address=%0h", 
                     $time, i, x, y, w, h, 32'(x) + y*SCREEN_WIDTH);
            
            // Wait for command to be accepted
            @(posedge clock);
            while (!axis_command_tready) @(posedge clock);
            @(negedge clock);
            axis_command_tvalid = 1'b0;
            command_index++;
            
            // Small delay between commands
            repeat(5) @(posedge clock);
        end
        
        // Wait for all data to be sent
        while (!data_generation_complete) begin
            @(posedge clock);
        end
        
        // Wait additional cycles for all writes to complete
        repeat(50) @(posedge clock);
        
        test_complete = 1;
    end

    // Data input driver (with random valid)
    logic axis_data_tready_reg;
    always_ff @(posedge clock) begin
        if (!reset_n) begin
            axis_data_tready_reg <= 1'b0;
        end else begin
            axis_data_tready_reg <= axis_data_tready;
        end
    end
    always_ff @(negedge clock) begin
        if (!reset_n) begin
            axis_data_tvalid <= 1'b0;
            axis_data_tdata <= 32'h0;
            axis_data_tlast <= 1'b0;
            axis_data_tuser <= 1'b0;
            send_index <= 0;
            data_generation_complete <= 1'b0;
        end else begin
            if ( axis_data_tvalid && axis_data_tready_reg ) begin
                axis_data_tvalid <= 1'b0;
            end
            if (send_index < test_data_count && !data_generation_complete) begin
                if (!axis_data_tvalid || axis_data_tready_reg) begin
                    // Random valid generation based on VALID_RATE
                    if ($urandom_range(0, 10) < VALID_RATE) begin
                        axis_data_tvalid <= 1'b1;
                        axis_data_tdata <= {24'h0, test_data[send_index]};
                        axis_data_tlast <= test_last[send_index];
                        axis_data_tuser <= test_sof[send_index];
                        
                        $display("T=%0t: Sending data[%0d]: 0x%02h, tlast=%b, sof=%b", 
                                 $time, send_index, test_data[send_index], test_last[send_index], test_sof[send_index]);
                        
                        send_index <= send_index + 1;
                        
                        if (send_index + 1 >= test_data_count) begin
                            data_generation_complete <= 1'b1;
                        end
                    end else begin
                        axis_data_tvalid <= 1'b0;
                    end
                end
            end
        end
    end

    // Write access sequence checker (runs after test completion)
    initial begin
        wait(test_complete);
        repeat(10) @(posedge clock);
        
        $display("Checking write access sequence...");
        $display("Recorded %0d writes, expected %0d writes", recorded_count, expected_count);
        
        // Check write count
        if (recorded_count != expected_count) begin
            $error("Write count mismatch: expected %0d writes, got %0d writes", expected_count, recorded_count);
        end else begin
            // Check each write access
            for (int i = 0; i < recorded_count; i++) begin
                if (recorded_addr[i] != expected_addr[i]) begin
                    automatic int exp_x = int'(expected_addr[i]) % SCREEN_WIDTH;
                    automatic int exp_y = int'(expected_addr[i]) / SCREEN_WIDTH;
                    automatic int got_x = int'(recorded_addr[i]) % SCREEN_WIDTH;
                    automatic int got_y = int'(recorded_addr[i]) / SCREEN_WIDTH;
                    $error("Write %0d address mismatch: expected %0h (x=%0d,y=%0d), got %0h (x=%0d,y=%0d)", 
                           i, expected_addr[i], exp_x, exp_y, recorded_addr[i], got_x, got_y);
                end
                if (recorded_data[i] != expected_data[i]) begin
                    $error("Write %0d data mismatch: expected 0x%02h, got 0x%02h", 
                           i, expected_data[i], recorded_data[i]);
                end
            end
        end
        
        $display("Write access sequence check completed");
    end

    // Timeout counter
    always_ff @(posedge clock) begin
        if (!reset_n) begin
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
        reset_n = 1'b0;
        repeat(4) @(negedge clock);
        reset_n = 1'b1;
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
