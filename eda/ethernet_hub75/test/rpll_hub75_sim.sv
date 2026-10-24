// Simulation stand-in for the Gowin rPLL (27 -> 49.5 MHz): a free-running
// 49.5 MHz clock, locked after 1 us.
`timescale 1ns/1ps
module rpll_hub75 (output logic clkout, output logic lock, input logic clkin);
    initial begin
        clkout = 1'b0;
        forever #(10.101) clkout = ~clkout;
    end
    initial begin
        lock = 1'b0;
        #1000 lock = 1'b1;
    end
endmodule
