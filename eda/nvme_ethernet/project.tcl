# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args
set ETHERNET_DIR  [lindex $argv 6]
set NVME_DIR      [lindex $argv 7]
set PSRAM_DIR     [lindex $argv 8]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option 1
set_option -route_option 2

if {${TARGET} == "tangnano9k"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangnano9k_pmod"} {
    set_option -use_sspi_as_gpio 1
}

# verified RMII MAC (rtl/ethernet, mii_mac/crc_mac.sv is the 8-bit CRC)
add_file -type verilog [file normalize ${ETHERNET_DIR}/util/simple_fifo.v]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/axis_to_rmii.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/rmii_to_axis.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/mii_to_axis.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/axis_to_mii.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_axis/prepend_preamble.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/append_crc.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/remove_crc.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/axis_mux.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/crc_mac.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/mii_mac_rx.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/mii_mac/mii_mac_tx.sv]
add_file -type verilog [file normalize ${ETHERNET_DIR}/rmii_mac/rmii_mac.sv]

# NVMe-oF stack (generated from Veryl: veryl build in rtl/nvme)
add_file -type verilog [file normalize ${NVME_DIR}/nvme_pkg.sv]
add_file -type verilog [file normalize ${NVME_DIR}/nvme_tcp_pkg.sv]
add_file -type verilog [file normalize ${NVME_DIR}/nvme_core.sv]
add_file -type verilog [file normalize ${NVME_DIR}/nvme_tcp_target.sv]
add_file -type verilog [file normalize ${NVME_DIR}/eth_ip.sv]
add_file -type verilog [file normalize ${NVME_DIR}/eth_tx_mux.sv]
add_file -type verilog [file normalize ${NVME_DIR}/tcp_engine.sv]

if {${TARGET} == "tangnano9k_pmod"} {
    # PSRAM namespace (generated from Veryl: veryl build in rtl/gowin_psram)
    add_file -type verilog [file normalize ${PSRAM_DIR}/gowin_psram.sv]
    add_file -type verilog [file normalize ${PSRAM_DIR}/psram_dword_cache.sv]
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_rpll_psram/gowin_rpll_psram.v]
    add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
}
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
