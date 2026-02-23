set project_name xg_mac
set vendor_name fixstars
set library_name fixstars
set taxonomy /Network
set display_name "10G Ethernet MAC"
set supported_families "*"
set core_version 1.0
set core_revision 1

set rtl_dir ../../rtl

create_project $project_name.xpr -force
set device_part "xcku115-flva1517-2-e"
set_property part $device_part [current_project]

# Add target files
# Create 'sources_1' fileset
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}
# Create 'constrs_1' fileset
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -srcset constrs_1
}
# Create 'sim_1' fileset
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -srcset sim_1
}

# Define source file list

set source_files {}
lappend source_files {../xgmii_axis/axis_to_xgmii.v}
lappend source_files {../xgmii_axis/axis_to_xgmii_preamble.sv}
lappend source_files {../xgmii_axis/xgmii_to_axis.v}
lappend source_files {../util/simple_fifo.v}
lappend source_files {../crc/crc_mac.v}
lappend source_files {align_frame.sv}
lappend source_files {append_crc.sv}
lappend source_files {prepend_preamble.sv}
lappend source_files {remove_crc.sv}
lappend source_files {xg_mac_tx.sv}
lappend source_files {xg_mac_rx.sv}
lappend source_files {xg_mac.sv}

set constraint_files {}

# Add source files to filesets
foreach source_file $source_files {
  set name [file tail $source_file]
  add_file -fileset [get_filesets sources_1] $source_file
}
# foreach constraint_file $constraint_files {
#   add_file -fileset [get_filesets constrs_1] $constraint_file
# }

# Package IP.
ipx::package_project -root_dir . -vendor $vendor_name -library $library_name -taxonomy $taxonomy -force
set ipcore [ipx::current_core]

## Helper interface generator functions
proc add_clock_if { name direction freq_hz associated_busif } {
  set bus_if [ipx::add_bus_interface $name [ipx::current_core]]
  set_property ABSTRACTION_TYPE_VLNV xilinx.com:signal:clock_rtl:1.0 $bus_if
  set_property BUS_TYPE_VLNV xilinx.com:signal:clock:1.0 $bus_if
  set_property INTERFACE_MODE $direction $bus_if
  ipx::add_port_map CLK $bus_if
  set_property physical_name $name [ipx::get_port_maps CLK -of_objects $bus_if]
  ipx::add_bus_parameter FREQ_HZ $bus_if
  set_property VALUE $freq_hz [ipx::get_bus_parameters FREQ_HZ -of_objects $bus_if]
  if { [string length $associated_busif] ne 0 } {
    ipx::add_bus_parameter ASSOCIATED_BUSIF $bus_if
    set_property VALUE $associated_busif [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $bus_if]
  }
}
proc add_reset_if { name direction polarity } {
  set bus_if [ipx::add_bus_interface $name [ipx::current_core]]
  set_property ABSTRACTION_TYPE_VLNV xilinx.com:signal:reset_rtl:1.0 $bus_if
  set_property BUS_TYPE_VLNV xilinx.com:signal:reset:1.0 $bus_if
  set_property INTERFACE_MODE $direction $bus_if
  ipx::add_port_map RST $bus_if
  set_property PHYSICAL_NAME $name [ipx::get_port_maps RST -of_objects $bus_if]
  ipx::add_bus_parameter POLARITY $bus_if
  set_property VALUE $polarity [ipx::get_bus_parameters POLARITY -of_objects $bus_if]
}


# Set basic properties.
set_property NAME $project_name $ipcore
set_property DISPLAY_NAME $display_name $ipcore
set_property SUPPORTED_FAMILIES $supported_families $ipcore
set_property VERSION $core_version $ipcore
set_property CORE_REVISION $core_revision $ipcore

### Add clock interfaces
## master
add_clock_if tx_clock slave 156250000 {tx_xgmii:tx_saxis}
add_clock_if rx_clock slave 156250000 {rx_xgmii:rx_maxis}

### Add reset interfaces
# tx_reset
add_reset_if tx_reset slave ACTIVE_HIGH
# rx_reset
add_reset_if rx_reset slave ACTIVE_HIGH

### Add XGMII interface
set bus_if [ipx::add_bus_interface tx_xgmii [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:display_xxv_ethernet:user_int_ports:2.0 $bus_if
set_property bus_type_vlnv xilinx.com:display_xxv_ethernet:user_ports_int:2.0 $bus_if
set_property interface_mode master $bus_if
ipx::add_port_map tx_mii_d $bus_if
set_property physical_name tx_xgmii_d [ipx::get_port_maps tx_mii_d -of_objects $bus_if]
ipx::add_port_map tx_mii_c $bus_if
set_property physical_name tx_xgmii_c [ipx::get_port_maps tx_mii_c -of_objects $bus_if]

set bus_if [ipx::add_bus_interface rx_xgmii [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:display_xxv_ethernet:user_int_ports:2.0 $bus_if
set_property bus_type_vlnv xilinx.com:display_xxv_ethernet:user_ports_int:2.0 $bus_if
set_property interface_mode slave $bus_if
ipx::add_port_map rx_mii_d $bus_if
set_property physical_name rx_xgmii_d [ipx::get_port_maps rx_mii_d -of_objects $bus_if]
ipx::add_port_map rx_mii_c $bus_if
set_property physical_name rx_xgmii_c [ipx::get_port_maps rx_mii_c -of_objects $bus_if]

### Associate XGMII interface to clock
#set bus_if [ipx::get_bus_interfaces tx_clock -of_objects [ipx::current_core]]
#set_property VALUE {tx_xgmii tx_saxis} [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $bus_if]
#set_property VALUE {tx_reset} [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $bus_if]
#set bus_if [ipx::get_bus_interfaces rx_clock -of_objects [ipx::current_core]]
#set_property VALUE {rx_xgmii rx_maxis} [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $bus_if]
#set_property VALUE {rx_reset} [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $bus_if]

# Generate other files and save IP core.
ipx::create_xgui_files $ipcore
ipx::update_checksums $ipcore
ipx::save_core $ipcore

# Finalize project
close_project
