set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args
set ETHERNET_DIR          [lindex $argv 6]
set ETHERNET_SERVICE_SRC  [lindex $argv 7]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1
set_option -top_module top
# set_option -place_option 1
# set_option -route_option 2

if {${TARGET} == "comprocboard_9k"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangnano9k"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangnano9k_matrix_led"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangprimer20k"} {
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
}
if {${TARGET} == "tangprimer20k_hub75"} {
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
}

add_file -type verilog [file normalize ${ETHERNET_DIR}/util/simple_fifo.v]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/axis_to_rmii.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/rmii_to_axis.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/prepend_preamble.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/append_crc.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/remove_crc.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/axis_mux.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/crc_mac.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/mii_mac_rx.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/mii_mac_tx.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/rmii_mac/rmii_mac.sv]
add_file -type verilog [file normalize ${ETHERNET_SERVICE_SRC}]
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all