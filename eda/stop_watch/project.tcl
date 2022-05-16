set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1

add_file -type verilog [file normalize ${RTL_DIR}/segment_led/segment_led.sv]
add_file -type verilog [file normalize ${RTL_DIR}/segment_led/seven_segment_with_dp.sv]
add_file -type verilog [file normalize ${RTL_DIR}/switch_input/debounce.sv]
add_file -type verilog [file normalize ${RTL_DIR}/switch_input/bounce_detector.sv]
add_file -type verilog [file normalize ${RTL_DIR}/util/timer_counter.sv]
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all