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

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module ${TOP_MODULE}
set_option -place_option 1
set_option -route_option 2

if {${TARGET} == "tangprimer20k"} {
    set_option -use_sspi_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
}

# Veryl output (packages first: the filelist is in dependency order except
# for Crc32Pkg)
set fp [open $FILELIST r]
set files [split [string trim [read $fp]] "\n"]
close $fp
foreach f $files {
    if {[string match "*crc32.sv" $f]} { add_file -type verilog [file normalize $f] }
}
foreach f $files {
    if {![string match "*crc32.sv" $f]} { add_file -type verilog [file normalize $f] }
}
foreach f [glob -nocomplain ${SRC_DIR}/ip/*.v] {
    add_file -type verilog [file normalize $f]
}

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
