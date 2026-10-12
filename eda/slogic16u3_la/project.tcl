set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

# As ../slogic16u3_usb3/project.tcl: the GW5AT-15 SerDes quad takes its static configuration from a CSR
# file, which gw_sh only passes to PnR as the "RES.serdes.csr" result file of a saved project - create
# the project here, write .gprj.user, and run the flow in a child gw_sh that opens it.
create_project -name ${PROJECT_NAME} -dir gprj -pn $DEVICE_PART -device_version A -force
set gdir [pwd]

set_option -output_base_name ${PROJECT_NAME}
set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option [expr {[info exists ::env(PLACE_OPT)] && $::env(PLACE_OPT) ne "" ? $::env(PLACE_OPT) : 3}]
set_option -route_option [expr {[info exists ::env(ROUTE_OPT)] && $::env(ROUTE_OPT) ne "" ? $::env(ROUTE_OPT) : 2}]
if {[info exists ::env(PNR_EXTRA)]} {
    foreach kv $::env(PNR_EXTRA) { lassign [split $kv =] k v; set_option -$k $v }
}
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_sspi_as_gpio 1
set_device -name $DEVICE_FAMILY $DEVICE_PART

set USB3_SRC [file normalize ${SRC_DIR}/../../../slogic16u3_usb3/src/${TARGET}]
set IPDIR ${USB3_SRC}/usb3_ln0

# JTAG_STATUS=1: the status register over JTAG ER1 (host/la_status.py; ~200 FF + 160 LUT, off by default)
set defs ""
if {[info exists ::env(JTAG_STATUS)] && $::env(JTAG_STATUS) eq "1"} { append defs "`define LA_JTAG_STATUS\n" }
# LA_TIMEOUT: LaFramer's partial-block timeout in pclk (default 2500 = 20 us). Gowin's PnR has no seed; a
# slightly different value changes the netlist a little and so the placement, the way to look for a
# build that meets 125 MHz
if {[info exists ::env(LA_TIMEOUT)] && $::env(LA_TIMEOUT) ne ""} { append defs "`define LA_TIMEOUT $::env(LA_TIMEOUT)\n" }
set fh [open defines_gen.v w]; puts -nonewline $fh $defs; close $fh
add_file -type verilog [file normalize defines_gen.v]
add_file -type verilog [file normalize ${SRC_DIR}/top.v]
add_file -type verilog [file normalize ${SRC_DIR}/pll_la400.v]
add_file -type verilog ${USB3_SRC}/pll_ref125.v
add_file -type verilog ${USB3_SRC}/jtag_status.v
# USB 3.0 core and the logic analyzer core (Veryl output: run `veryl build` in rtl/usb3 / rtl/la after edits)
foreach f {usb3_pkg usb3_crc_pkg usb3_scrambler usb3_rx_fifo usb3_rx_parser usb3_tx_framer usb3_ltssm usb3_link usb3_top usb3_descriptor_rom usb3_device} {
    add_file -type verilog [file normalize ${RTL_DIR}/usb3/${f}.sv]
}
foreach f {la_pkg la_afifo la_front la_packer la_framer la_trig la_slice la_core} {
    add_file -type verilog [file normalize ${RTL_DIR}/la/${f}.sv]
}
add_file -type verilog ${IPDIR}/serdes.v
foreach f [glob -nocomplain ${IPDIR}/*/*.v] { if {![string match *_tmp.v $f]} { add_file -type verilog $f } }
set GW_JTAG_V [file normalize [file join [file dirname [info nameofexecutable]] .. data ipcores gw_jtag.v]]
add_file -type verilog $GW_JTAG_V
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
# timing.sdc, without the JTAG clock (tck) unless JTAG_STATUS=1
set fh [open ${SRC_DIR}/timing.sdc r]; set sdc [read $fh]; close $fh
if {[string first LA_JTAG_STATUS $defs] < 0} { set sdc [join [lsearch -all -inline -not [split $sdc "\n"] {*tck*}] "\n"] }
set fh [open timing_gen.sdc w]; puts -nonewline $fh $sdc; close $fh
add_file -type sdc [file normalize timing_gen.sdc]

set CSR ${IPDIR}/serdes.csr
set fh [open $gdir/${PROJECT_NAME}.gprj.user w]
puts $fh "<?xml version=\"1\" encoding=\"UTF-8\"?>\n<!DOCTYPE ProjectUserData>\n<UserConfig>\n    <Version>1.0</Version>"
puts $fh "    <ResultFileList>\n        <ResultFile ResultFileType=\"RES.serdes.csr\" ResultFilePath=\"$CSR\"/>\n    </ResultFileList>\n</UserConfig>"
close $fh
set fh [open $gdir/run_csr.tcl w]; puts $fh "open_project $gdir/${PROJECT_NAME}.gprj\nrun all"; close $fh
exec [info nameofexecutable] $gdir/run_csr.tcl >@ stdout 2>@ stderr
file mkdir $gdir/../../impl
file delete -force $gdir/../../impl/pnr
file copy -force $gdir/impl/pnr $gdir/../../impl/pnr
