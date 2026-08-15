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
set_option -top_module top
set_option -place_option 1
set_option -route_option 2
# Plain-text post-PnR simulation netlist; used by the loopback simulation flow.
set_option -gen_verilog_sim_netlist 1

if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    set_option -use_i2c_as_gpio 1
}

add_file -type verilog [file normalize ${SRC_DIR}/top.v]
add_file -type vhdl [file normalize ${SRC_DIR}/prbs_top.vhd]
add_file -type verilog [file normalize ${SRC_DIR}/pll_rx_300m_4ph/pll_rx_300m_4ph.v]
add_file -type verilog [file normalize ${SRC_DIR}/pll_tx_600m/pll_tx_600m.v]

# EasyCDR IP from the IDE 1.9.12 templates, configured BEYOND_1G + 32-bit for
# 1.2Gbps (delay taps 0/17/30/47 per the IP GUI formula for R=1.2).
# EasyCDR_Top.v must come before EasyCDR.v: it includes easycdr_1912/define.v
# whose macros the encrypted core relies on.
set_option -include_path [file normalize ${SRC_DIR}/easycdr_1912]
add_file -type verilog [file normalize ${SRC_DIR}/easycdr_1912/EasyCDR_Top.v]
add_file -type verilog [file normalize ${SRC_DIR}/easycdr_1912/EasyCDR.v]

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
