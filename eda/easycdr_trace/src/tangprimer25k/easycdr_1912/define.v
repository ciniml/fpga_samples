`define MODULE_NAME EasyCDR_Top
`define OUTPUT10BIT
`define WORD_ALI
`define DECODE_8B10B
`define K_28_5
`define DELAY_0 0
`ifdef RATE_DELAY1
`define DELAY_1 `RATE_DELAY1   // quarter-UI tap count for the RATE variant (project.tcl)
`else
`define DELAY_1 21
`endif
`define DELAY_2 0
`define DELAY_3 0
`define SHARED_LOGIC
