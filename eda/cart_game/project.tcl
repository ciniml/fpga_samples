# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_device -name $DEVICE_FAMILY $DEVICE_PART
set_option -output_base_name ${PROJECT_NAME}
set_option -top_module top
set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -use_cpu_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_mspi_as_gpio 1

add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/pll_100m_200m_50.v]
# USB (Pmod USB HS Single): PLLs and PHY from eda/usb_device, core from rtl/usb (Veryl output)
set USB_SRC [file normalize ${SRC_DIR}/../../../usb_device/src/${TARGET}]
add_file -type verilog ${USB_SRC}/pll_usb/pll_usb.v
add_file -type verilog ${USB_SRC}/pll_hs960/pll_hs960.v
add_file -type verilog [file normalize ${RTL_DIR}/usb/gowin/usb_phy_gowin_sl.v]
foreach f {usb_pkg usb_phy_rx usb_phy_tx usb_phy usb_phy_bridge usb_sie usb_descriptor_rom usb_device} {
    add_file -type verilog [file normalize ${RTL_DIR}/usb/${f}.sv]
}
add_file -type verilog [file normalize ${RTL_DIR}/oscdr/os_cdr.sv]
add_file -type verilog [file normalize ${RTL_DIR}/oscdr/bit_gearbox.sv]
foreach f {game_cart qspi_rom byte_afifo} {
    add_file -type verilog [file normalize ${RTL_DIR}/chromatic/${f}.sv]
}
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_rx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
# pins: the adapter (pins.cst) + the USB Pmod in slot USB_PMOD (pins_usb.cst, balls from pmod_ports.csv)
set PMOD [expr {[info exists ::env(USB_PMOD)] ? $::env(USB_PMOD) : "pmod1"}]
set fh [open [file normalize ${SRC_DIR}/../../../targets/${TARGET}/pmod_ports.csv] r]
array set BALL {}
foreach line [split [read $fh] "\n"] {
    if {[regexp {^(pmod[0-2]_[0-9]+),([A-Z][0-9]+)} $line -> k v]} { set BALL($k) $v }
}
close $fh
proc ball {pin} { global BALL PMOD; return $BALL(${PMOD}_${pin}) }
set fh [open ${SRC_DIR}/pins.cst r]; set cst [read $fh]; close $fh
set fh [open ${SRC_DIR}/pins_usb.cst r]; set usb [read $fh]; close $fh
append cst "\n" [string map [list \
    @DX_P@    [ball 1]  @DX_N@    [ball 7] \
    @CMP_P@   [ball 2]  @CMP_N@   [ball 8] \
    @TERM_DP@ [ball 3]  @TERM_DN@ [ball 9] \
    @PULLUP@  [ball 4]  @VBUS@    [ball 10]] $usb]
set fh [open pins_gen.cst w]; puts -nonewline $fh $cst; close $fh
puts "cart_game: Pmod USB HS Single on ${PMOD}"
add_file -type cst [file normalize pins_gen.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]
run all
