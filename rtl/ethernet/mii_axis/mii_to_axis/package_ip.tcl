set project_name mii_to_axis
set vendor_name fugafuga.org
set library_name fugafuga.org
set taxonomy /Network
set display_name "MII to AXI Stream"
set supported_families "*"
set core_version 1.0
set core_revision 1

create_project $project_name.xpr -in_memory
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
#lappend source_files {../axis_to_mii.sv}
lappend source_files {../mii_to_axis.sv}

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

# Set basic properties.
set_property NAME $project_name $ipcore
set_property DISPLAY_NAME $display_name $ipcore
set_property SUPPORTED_FAMILIES $supported_families $ipcore
set_property VERSION $core_version $ipcore
set_property CORE_REVISION $core_revision $ipcore

# Generate other files and save IP core.
ipx::create_xgui_files $ipcore
ipx::update_checksums $ipcore
ipx::save_core $ipcore

# Finalize project
close_project
