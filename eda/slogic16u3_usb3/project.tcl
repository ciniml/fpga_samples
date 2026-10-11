set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

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

# SERDES_IP: the GUI-generated SerDes IP directory under src/slogic16u3
#   usb3_ln0   (default) USB 3.0 PHY on Q0 lane 0 -> top.v: the USB 3.0 device (rtl/usb3)
#   serdes_4ln Customized PHY on Q0 lanes 0..3 at 5 Gb/s -> top_lanes.v: which lane carries the LFPS
set SERDES_IP usb3_ln0
if {[info exists ::env(SERDES_IP)] && $::env(SERDES_IP) ne ""} { set SERDES_IP $::env(SERDES_IP) }
set IPDIR [file normalize ${SRC_DIR}/${SERDES_IP}]
set LANES [expr {$SERDES_IP eq "serdes_4ln"}]

# REF=1 (with usb3_ln0): Gowin's reference device controller instead of rtl/usb3 (top_ref.v)
set REF [expr {[info exists ::env(REF)] && $::env(REF) eq "1"}]
set REF_DIR [file normalize ${SRC_DIR}/../../../targets/tangconsole60k/doc/gowin_usb3_ref/Gowin_USB30_CDC_BULK_RefDeign/prj/src]

if {$LANES} {
    add_file -type verilog [file normalize ${SRC_DIR}/top_lanes.v]
} elseif {$REF} {
    add_file -type verilog [file normalize ${SRC_DIR}/top_ref.v]
    add_file -type verilog [file normalize ${SRC_DIR}/pll_ref125.v]
    # the reference sources are copied into the build directory with usb3_macro_define.v replaced by
    # src/slogic16u3/ref_override (EP1 buffers cut to 4 KiB for the BSRAM of the GW5AT-15): `include
    # finds the file next to the including one first, so the copy is the only way to override it
    set RS [file normalize ref_src]
    file delete -force $RS; file mkdir $RS
    foreach d {usb30_device_controller usb30_user_layer} { file copy ${REF_DIR}/$d $RS/$d }
    file copy -force [file normalize ${SRC_DIR}/ref_override/usb3_macro_define.v] $RS/usb30_device_controller/usb3_macro_define.v
    # as the reference project: the macro file and usb3_const.vh (functions at compilation-unit scope) go in first
    add_file -type verilog $RS/usb30_device_controller/usb3_macro_define.v
    add_file -type verilog $RS/usb30_device_controller/usb3_const.vh
    foreach f [concat [glob $RS/usb30_device_controller/*.v $RS/usb30_device_controller/*.sv] \
                      [glob $RS/usb30_user_layer/*.v $RS/usb30_user_layer/*.sv]] {
        if {[string match *usb3_macro_define.v $f] || [string match *usb_descrip_define.v $f]} continue
        add_file -type verilog $f
    }
    set_option -include_path "$RS/usb30_device_controller;$RS/usb30_user_layer"
} else {
    add_file -type verilog [file normalize ${SRC_DIR}/top.v]
    add_file -type verilog [file normalize ${SRC_DIR}/pll_ref125.v]
    # USB 3.0 core (rtl/usb3, Veryl output - run `veryl build` there after edits)
    foreach f {usb3_pkg usb3_crc_pkg usb3_scrambler usb3_rx_fifo usb3_rx_parser usb3_tx_framer usb3_ltssm usb3_link usb3_top usb3_descriptor_rom usb3_device} {
        add_file -type verilog [file normalize ${RTL_DIR}/usb3/${f}.sv]
    }
}
add_file -type verilog [file normalize ${SRC_DIR}/jtag_status.v]
add_file -type verilog ${IPDIR}/serdes.v
foreach f [glob -nocomplain ${IPDIR}/*/*.v] { if {![string match *_tmp.v $f]} { add_file -type verilog $f } }
set GW_JTAG_V [file normalize [file join [file dirname [info nameofexecutable]] .. data ipcores gw_jtag.v]]
add_file -type verilog $GW_JTAG_V
add_file -type cst [file normalize ${SRC_DIR}/[expr {$LANES ? "pins_lanes.cst" : "pins.cst"}]]
add_file -type sdc [file normalize ${SRC_DIR}/[expr {$LANES ? "timing_lanes.sdc" : ($REF ? "timing_ref.sdc" : "timing.sdc")}]]

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
