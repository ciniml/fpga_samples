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
}

# --- Veryl-generated dvi_in core ---
add_file -type verilog [file normalize ${RTL_DIR}/dvi_in/dvi_in.sv]

# --- Tang Primer 25K PHY wrappers ---
add_file -type verilog [file normalize ${SRC_DIR}/iser10_lane.sv]
add_file -type verilog [file normalize ${SRC_DIR}/dvi_in_phy.sv]

# --- Top + reset ---
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]

# --- Clock recovery PLL (Gowin IP, 27 MHz → 162/810 MHz placeholder).
# Reuses the IP files from display_port_tpg unchanged — for a real DVI
# receiver these must be regenerated for the actual incoming F_pixel.
if {${TARGET} == "tangprimer25k"} {
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll_27/gowin_pll_27.v]
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll/gowin_pll.v]
}

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
