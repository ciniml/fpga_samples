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

if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    # B2 / C2 (status LEDs) are dual-purpose configuration pins.
    set_option -use_i2c_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_sspi_as_gpio 1
}

# --- Veryl-generated dvi_in core ---
add_file -type verilog [file normalize ${RTL_DIR}/dvi_in/dvi_in.sv]

# --- Veryl-generated DDC / EDID / HPD side channel ---
add_file -type verilog [file normalize ${RTL_DIR}/ddc_edid/ddc_edid.sv]
add_file -type verilog [file normalize ${RTL_DIR}/ddc_edid/edid_rom.sv]

# --- Tang Primer 25K PHY wrappers ---
add_file -type verilog [file normalize ${SRC_DIR}/iser10_lane.sv]
add_file -type verilog [file normalize ${SRC_DIR}/dvi_in_phy.sv]

# --- Diagnostics UART (checker / reporter shared with eda/dvi_loopback) ---
set LOOP_DIR [file normalize ${SRC_DIR}/../../../dvi_loopback/src/${TARGET}]
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_rx.sv]
add_file -type verilog ${LOOP_DIR}/frame_sum.sv
add_file -type verilog ${LOOP_DIR}/loop_check.sv
add_file -type verilog ${LOOP_DIR}/loop_report.sv

# --- Top + reset ---
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]

# --- Clock recovery PLL (PLLA, CLKIN = recovered 74.25 MHz cable clock,
# CLKOUT0 = 74.25 MHz pclk, CLKOUT1 = 371.25 MHz fclk).
if {${TARGET} == "tangprimer25k"} {
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll_dvi/gowin_pll_dvi.v]
}

# RX equalizer from the environment: CTLE = HIGH (default) | MEDIUM | LOW | OFF
# (HIGH / MEDIUM give the widest error-free phase window with a notebook PC
#  source; the 1080p loopback also needs HIGH)
set CTLE [expr {[info exists ::env(CTLE)] && $::env(CTLE) ne "" ? $::env(CTLE) : "HIGH"}]
set fh [open ${SRC_DIR}/pins.cst r]; set cst [read $fh]; close $fh
set cst [string map [list "CTLE=OFF" "CTLE=${CTLE}"] $cst]
set fh [open pins_gen.cst w]; puts -nonewline $fh $cst; close $fh
add_file -type cst [file normalize pins_gen.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
