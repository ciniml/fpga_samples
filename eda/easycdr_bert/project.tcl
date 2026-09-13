set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_option -output_base_name ${PROJECT_NAME}
set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option 1
set_option -route_option 2
set_option -gen_verilog_sim_netlist 1
set_device -name $DEVICE_FAMILY $DEVICE_PART
if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    set_option -use_i2c_as_gpio 1
}

# USE_EASYCDR_IP=1 in the environment builds the Gowin-IP receiver variant
set USE_IP [expr {[info exists ::env(USE_EASYCDR_IP)] && $::env(USE_EASYCDR_IP) == "1"}]
if {${USE_IP}} {
    add_file -type verilog [file normalize ${SRC_DIR}/defines_ip.v]
}
add_file -type verilog [file normalize ${SRC_DIR}/top.v]

# BERT core (rtl/bert, Veryl output - run `veryl build` there after edits)
add_file -type verilog [file normalize ${RTL_DIR}/bert/prbs_pkg.sv]
add_file -type verilog [file normalize ${RTL_DIR}/bert/prbs_gen.sv]
add_file -type verilog [file normalize ${RTL_DIR}/bert/prbs_chk.sv]
add_file -type verilog [file normalize ${RTL_DIR}/bert/bert_counters.sv]
add_file -type verilog [file normalize ${RTL_DIR}/bert/bert_core.sv]
add_file -type verilog [file normalize ${RTL_DIR}/bert/bert_host.sv]

if {${TARGET} == "tangprimer25k"} {
    # Own CDR (rtl/oscdr, Veryl output) + GW5A PHY wrapper
    add_file -type verilog [file normalize ${RTL_DIR}/oscdr/os_cdr.sv]
    add_file -type verilog [file normalize ${RTL_DIR}/oscdr/bit_gearbox.sv]
    add_file -type verilog [file normalize ${SRC_DIR}/oscdr_phy_gw5a.v]
    add_file -type verilog [file normalize ${SRC_DIR}/ip_phy_gw5a.v]

    add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
    add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_rx.sv]
    add_file -type verilog [file normalize ${SRC_DIR}/pll_rx_500m_4ph/pll_rx_500m_4ph.v]
    add_file -type verilog [file normalize ${SRC_DIR}/pll_tx_500m/pll_tx_500m.v]

    # EasyCDR IP (only used with `define USE_EASYCDR_IP): raw 16-bit, 1Gbps
    set_option -include_path [file normalize ${SRC_DIR}/easycdr_1912]
    add_file -type verilog [file normalize ${SRC_DIR}/easycdr_1912/EasyCDR_Top.v]
    add_file -type verilog [file normalize ${SRC_DIR}/easycdr_1912/EasyCDR.v]
}
if {${TARGET} == "tangnano9k_pmod"} {
    # TX-only PRBS source (999Mbps from the 27MHz crystal)
    add_file -type verilog [file normalize ${SRC_DIR}/pll_tx_4995/pll_tx_4995.v]
}

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
if {${USE_IP}} {
    add_file -type sdc [file normalize ${SRC_DIR}/timing_ip.sdc]
} else {
    add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]
}

run all
