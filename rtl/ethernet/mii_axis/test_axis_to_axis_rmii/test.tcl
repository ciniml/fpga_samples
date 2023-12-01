open_vcd
log_vcd [get_object /tb/dut_rmii_to_axis/*]

add_wave -recursive *
run all

close_vcd