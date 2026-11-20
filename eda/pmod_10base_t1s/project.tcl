# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -print_all_synthesis_warning 1
set_option -top_module top
set_option -place_option 1
set_option -route_option 2

if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    # B2 / C2 (status LEDs) are dual-purpose configuration pins.
    set_option -use_i2c_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_sspi_as_gpio 1
}

# --- Veryl-generated core and bring-up logic (`veryl build` in rtl/t1s_phy; the Makefile does) ---
foreach f {t1s_pma_tx.sv t1s_pma_rx.sv t1s_pcs_tx.sv t1s_pcs_rx.sv t1s_plca.sv t1s_phy.sv t1s_bringup.sv} {
    add_file -type verilog [file normalize ${RTL_DIR}/t1s_phy/${f}]
}

# --- board ---
foreach f {pll_t1s.v top.sv} {
    add_file -type verilog [file normalize ${SRC_DIR}/${f}]
}
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
