set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option 1
set_option -route_option 2

if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    # B2 / C2 (status LEDs) are dual-purpose configuration pins.
    set_option -use_i2c_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_sspi_as_gpio 1
}

# --- Veryl-generated cores (run `veryl build` in rtl/oscdr and rtl/eth100_phy; the Makefile does) ---
add_file -type verilog [file normalize ${RTL_DIR}/oscdr/os_cdr.sv]
foreach f {eth100_tx.sv eth100_rx.sv eth100_flp.sv eth100_an.sv eth100_phy.sv} {
    add_file -type verilog [file normalize ${RTL_DIR}/eth100_phy/${f}]
}
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_rx.sv]

# --- board ---
foreach f {pll_eth100.v eth100_phy_gw5a.v eth100_test.sv top.sv} {
    add_file -type verilog [file normalize ${SRC_DIR}/${f}]
}
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
