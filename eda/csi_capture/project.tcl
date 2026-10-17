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

if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    # B2 / C2 (status LEDs) are dual-purpose configuration pins.
    set_option -use_i2c_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_sspi_as_gpio 1
}

# --- Veryl-generated CSI-2 receiver (rtl/csi2) ---
foreach f {csi2_pkg csi2_edge_sampler csi2_lane_aligner csi2_lane_merge csi2_packet csi2_rx} {
    add_file -type verilog [file normalize ${RTL_DIR}/csi2/${f}.sv]
}

# --- board files ---
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_rx.sv]
# 500 MHz 4-phase PLL shared with eda/easycdr_bert (defaults: 50 MHz x 20 / 2)
add_file -type verilog [file normalize ${SRC_DIR}/../../../easycdr_bert/src/${TARGET}/pll_rx_500m_4ph/pll_rx_500m_4ph.v]
foreach f {reset_seq i2c_reg16 imx219_init_rom csi_ctrl csi_stats csi_phy_gw5a top} {
    add_file -type verilog [file normalize ${SRC_DIR}/${f}.sv]
}
add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all
