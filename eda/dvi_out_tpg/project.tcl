set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1

# set_option -place_option 1
# set_option -route_option 2

if {${TARGET} == "comprocboard_9k"} {
    set_option -use_sspi_as_gpio 1
}

add_file -type verilog [file normalize ${RTL_DIR}/dvi_out/dvi_out.sv]
add_file -type verilog [file normalize ${RTL_DIR}/video/test_pattern_generator.sv]
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_rpll/gowin_rpll.v]
add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_rpll_ser/gowin_rpll_ser.v]
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all