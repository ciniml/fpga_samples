# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set TARGET_DIR [file normalize ${SRC_DIR}/../../../targets/${TARGET}]

set_device -name $DEVICE_FAMILY $DEVICE_PART -device_version A
set_option -output_base_name ${PROJECT_NAME}
set_option -top_module top
set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -multi_boot 0

add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/pll_60m_24.v]
foreach f {cart_power cart_bus mbc7_eeprom flash_engine cart_cmd} {
    add_file -type verilog [file normalize ${RTL_DIR}/chromatic/${f}.sv]
}
# USB core (rtl/usb, Veryl output)
foreach f {usb_pkg usb_phy_rx usb_phy_tx usb_phy usb_sie usb_descriptor_rom usb_device} {
    add_file -type verilog [file normalize ${RTL_DIR}/usb/${f}.sv]
}
source ${TARGET_DIR}/chromatic_cst.tcl
add_file -type cst [chromatic_cst ${SRC_DIR}/top.sv pins_gen.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
