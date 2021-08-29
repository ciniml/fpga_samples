set_option -output_base_name blink
set_device -name GW1N-4B GW1N-LV4LQ144C6/I5

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1

add_file -type verilog [file normalize ../../rtl/blink/blink_all.sv]
add_file -type cst [file normalize src/runber.cst]

run all