set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args
set ETHERNET_DIR          [lindex $argv 6]
set ETHERNET_SERVICE_SRC  [lindex $argv 7]

#create_project -name ${PROJECT_NAME} -dir ${PROJECT_NAME} -pn $DEVICE_PART -device_version A -force

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1
set_option -top_module top
# set_option -place_option 1
# set_option -route_option 2

add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
#add_file -type verilog [file normalize ${ETHERNET_SERVICE_SRC}]
#add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll_xgbe/gowin_pll_xgbe.v]
add_file -type verilog [file normalize ${SRC_DIR}/ip/xgbe_serdes/xgbe_serdes.v]
add_file -type verilog [file normalize ${SRC_DIR}/ip/xgbe_serdes/xgbe_core/xgbe_core.v]

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all