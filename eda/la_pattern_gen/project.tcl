set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART
set_option -verilog_std sysv2017
set_option -top_module top
set_option -use_cpu_as_gpio 1

set DIV [expr {[info exists ::env(DIV)] && $::env(DIV) ne "" ? $::env(DIV) : 2}]
set fh [open defines_gen.v w]; puts $fh "`define PATTERN_DIV ${DIV}"
# STATIC=1: fixed levels instead of the pattern (wiring check)
if {[info exists ::env(STATIC)] && $::env(STATIC) eq "1"} { puts $fh "`define PATTERN_STATIC" }
close $fh
add_file -type verilog [file normalize defines_gen.v]
add_file -type verilog [file normalize ${SRC_DIR}/top.v]
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
run all
