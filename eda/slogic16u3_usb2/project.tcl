set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

# DX=K|P: which ball pair is the SoftPHY dx (data) pair - K3/K2 or P2/P1 (the other is the term pair)
set DX K
if {[info exists ::env(DX)]} { set DX [string toupper $::env(DX)] }
array set PAIRS {K {K3 K2 P2 P1} P {P2 P1 K3 K2}}
if {![info exists PAIRS($DX)]} { error "DX must be K or P (got $DX)" }
lassign $PAIRS($DX) DXP DXN TDP TDN

# The GW5AT-15 SerDes quad takes its static configuration from a CSR file, which gw_sh can only
# pass to PnR as the "RES.serdes.csr" result file of a saved project: create the project here,
# write .gprj.user, and run the flow in a child gw_sh that opens it (see slogic16u3_probe).
create_project -name ${PROJECT_NAME} -dir gprj -pn $DEVICE_PART -device_version A -force
set gdir [pwd]

set_option -output_base_name ${PROJECT_NAME}
set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option 2
set_option -route_option 2
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_sspi_as_gpio 1
set_device -name $DEVICE_FAMILY $DEVICE_PART

add_file -type verilog [file normalize ${SRC_DIR}/top.v]
add_file -type verilog [file normalize ${SRC_DIR}/jtag_status.v]
add_file -type verilog [file normalize ${SRC_DIR}/pll_60m.v]
add_file -type verilog [file normalize ${SRC_DIR}/serdes/serdes.v]
add_file -type verilog [file normalize ${SRC_DIR}/serdes/customized_phy/customized_phy.v]
# USB core (rtl/usb, Veryl output - run `veryl build` there after edits)
foreach f {usb_pkg usb_phy_rx usb_phy_tx usb_phy usb_sie usb_descriptor_rom usb_device} {
    add_file -type verilog [file normalize ${RTL_DIR}/usb/${f}.sv]
}
set GW_JTAG_V [file normalize [file join [file dirname [info nameofexecutable]] .. data ipcores gw_jtag.v]]
add_file -type verilog $GW_JTAG_V

set fh [open ${SRC_DIR}/pins.cst r]; set cst [read $fh]; close $fh
set cst [string map [list @DXP@ $DXP @DXN@ $DXN @TDP@ $TDP @TDN@ $TDN] $cst]
set fh [open pins_gen.cst w]; puts -nonewline $fh $cst; close $fh
puts "slogic16u3_usb2: dx = $DXP/$DXN, term = $TDP/$TDN"
add_file -type cst [file normalize pins_gen.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

set CSR [file normalize ${SRC_DIR}/serdes/serdes.csr]
set fh [open $gdir/${PROJECT_NAME}.gprj.user w]
puts $fh "<?xml version=\"1\" encoding=\"UTF-8\"?>\n<!DOCTYPE ProjectUserData>\n<UserConfig>\n    <Version>1.0</Version>"
puts $fh "    <ResultFileList>\n        <ResultFile ResultFileType=\"RES.serdes.csr\" ResultFilePath=\"$CSR\"/>\n    </ResultFileList>\n</UserConfig>"
close $fh
set fh [open $gdir/run_csr.tcl w]; puts $fh "open_project $gdir/${PROJECT_NAME}.gprj\nrun all"; close $fh
exec [info nameofexecutable] $gdir/run_csr.tcl >@ stdout 2>@ stderr
file mkdir $gdir/../../impl
file delete -force $gdir/../../impl/pnr
file copy -force $gdir/impl/pnr $gdir/../../impl/pnr
