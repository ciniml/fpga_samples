# ethernet_hub75: Gowin project script (called by ../build_gowin.mk).
set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args
set FILELIST      [lindex $argv 6]
set TOP_MODULE    [lindex $argv 7]
set HUB75_IMPL    [lindex $argv 8]
set PHY_DELAY     [lindex $argv 9]
set TXC_SHIFTED   [lindex $argv 10]
set RX_DELAY      [lindex $argv 11]
set PANEL_ROWS    [lindex $argv 12]
set CONN_ID       [lindex $argv 13]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module ${TOP_MODULE}
# GW_PLACE_OPTION / GW_ROUTE_OPTION in the environment override the defaults
set place_opt 1
set route_opt 2
if {${TARGET} == "dk_led_rxcard_gw3a20"} {
    # 125 MHz closes with option 2 for both HUB75_IMPL (1 / 3 miss by ~1 ns)
    set place_opt 2
}
if {[info exists ::env(GW_PLACE_OPTION)]} { set place_opt $::env(GW_PLACE_OPTION) }
if {[info exists ::env(GW_ROUTE_OPTION)]} { set route_opt $::env(GW_ROUTE_OPTION) }
set_option -place_option $place_opt
set_option -route_option $route_opt

if {${TARGET} == "tangprimer20k"} {
    set_option -use_sspi_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
}

# Build configuration for the top (HUB75_IMPL: 0 soft, 1 GMT; PANEL_ROWS
# and the RGMII delay options are used by the DK_LED-RXCARD top only)
set fp [open ethernet_hub75_cfg.sv w]
puts $fp "package ethernet_hub75_cfg;"
puts $fp "    localparam int unsigned HUB75_IMPL = ${HUB75_IMPL};"
puts $fp "    localparam int unsigned RX_DELAY = ${RX_DELAY};"
puts $fp "    localparam int unsigned PANEL_ROWS = ${PANEL_ROWS};"
puts $fp "    localparam bit CONN_ID = 1'b${CONN_ID};"
puts $fp "    localparam bit TXC_SHIFTED = 1'b${TXC_SHIFTED};"
puts $fp "    localparam bit \[15:0\] PHY_DELAY_BITS = 16'h${PHY_DELAY};"
puts $fp "endpackage"
close $fp
add_file -type verilog [file normalize ethernet_hub75_cfg.sv]

# Veryl output (packages first: the filelist is in dependency order except
# for Crc32Pkg). Board tops of the other targets are left out.
set fp [open $FILELIST r]
set files [split [string trim [read $fp]] "\n"]
close $fp
set board_files {}
foreach f $files {
    set n [file normalize $f]
    if {[string match "*/ethernet_hub75/src/*" $n] && ![string match "*/src/common/*" $n] && ![string match "*/src/${TARGET}/*" $n]} {
        continue
    }
    lappend board_files $n
}
foreach f $board_files {
    if {[string match "*crc32.sv" $f]} { add_file -type verilog $f }
}
foreach f $board_files {
    if {![string match "*crc32.sv" $f]} { add_file -type verilog $f }
}
foreach f [glob -nocomplain ${SRC_DIR}/ip/*.v] {
    add_file -type verilog [file normalize $f]
}

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
if {${TXC_SHIFTED} == 1 && [file exists ${SRC_DIR}/timing_txc_shifted.sdc]} {
    # one file: Gowin does not see the clocks of another SDC file
    set fp [open timing.sdc w]
    foreach f [list ${SRC_DIR}/timing.sdc ${SRC_DIR}/timing_txc_shifted.sdc] {
        set fi [open $f r]
        puts $fp [read $fi]
        close $fi
    }
    close $fp
    add_file -type sdc [file normalize timing.sdc]
} else {
    add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]
}

run all
