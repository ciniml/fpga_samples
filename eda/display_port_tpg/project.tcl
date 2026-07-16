set SRC_DIR       [lindex $argv 0]
set RTL_DIR       [lindex $argv 1]
set TARGET        [lindex $argv 2]
set DEVICE_FAMILY [lindex $argv 3]
set DEVICE_PART   [lindex $argv 4]
set PROJECT_NAME  [lindex $argv 5]
# Additional args
set FEMTORV_DIR   [lindex $argv 6]

set_option -output_base_name ${PROJECT_NAME}
set_device -name $DEVICE_FAMILY $DEVICE_PART

set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1
set_option -top_module top
# set_option -place_option 1
# set_option -route_option 2

if {${TARGET} == "comprocboard_9k"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangnano9k"} {
    set_option -use_sspi_as_gpio 1
}
if {${TARGET} == "tangprimer20k"} {
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
}
if {${TARGET} == "tangprimer25k"} {
    set_option -use_cpu_as_gpio 1
    # Higher place/route effort: the 162 MHz link domain closes only
    # with these enabled.
    set_option -place_option 1
    set_option -route_option 2
}

# --- DisplayPort source IP (Veryl-generated SystemVerilog) ---
# AUX CH subsystem (Phase A)
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/aux_ch_tx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/aux_ch_rx.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/aux_ch_peripheral.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/aux_ch_subsystem.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/femtorv_wrap.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/hpd_detect.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/cdc_sync.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/stream_memory_access.sv]
# Main link PHY building blocks (Phase B)
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/scrambler.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/encoder_8b10b.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/serializer_10to1.sv]
# Training pattern + lane controller (Phase C)
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/training_pattern_gen.sv]
# Video framer (Phase D)
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/pixel_fifo.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/msa_generator.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/tu_packer.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/video_framer.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/main_link_data_mux.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/main_link_tx_lane.sv]
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/main_link_tx.sv]
# Top
add_file -type verilog [file normalize ${RTL_DIR}/displayport/src/dp_source_top.sv]

# --- Common helpers ---
add_file -type verilog [file normalize ${RTL_DIR}/uart/uart_tx.sv]
add_file -type verilog [file normalize ${FEMTORV_DIR}/femtorv32_gracilis.v]

# --- Test pattern generator + AXI-Stream adapter (board-local) ---
add_file -type verilog [file normalize ${RTL_DIR}/video/test_pattern_generator.sv]
add_file -type verilog [file normalize ${SRC_DIR}/tpg_to_axis.sv]

# --- OSER10 wrapper for lane 0 ---
add_file -type verilog [file normalize ${SRC_DIR}/oser10_lane.sv]

# --- Top + reset ---
add_file -type verilog [file normalize ${SRC_DIR}/top.sv]
add_file -type verilog [file normalize ${SRC_DIR}/reset_seq.sv]
if {${TARGET} == "tangprimer25k"} {
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll_27/gowin_pll_27.v]
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_pll/gowin_pll.v]
} else {
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_rpll_dvi/gowin_rpll_dvi.v]
    add_file -type verilog [file normalize ${SRC_DIR}/ip/gowin_rpll_ser/gowin_rpll_ser.v]
}

add_file -type cst [file normalize ${SRC_DIR}/pins.cst]
add_file -type sdc [file normalize ${SRC_DIR}/timing.sdc]

run all