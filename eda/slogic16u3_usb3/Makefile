PROJECT_NAME := slogic16u3_usb3

TARGET ?= slogic16u3
# SERDES_IP=<dir under src/$(TARGET)>: GUI-generated SerDes IP
#   usb3_ln0 (default): USB 3.0 PHY, Q0 lane 0 -> the USB 3.0 device (top.v)
#   serdes_4ln: Customized PHY, Q0 lanes 0..3 at 5 Gb/s -> lane probe (top_lanes.v)
SERDES_IP ?= usb3_ln0
export SERDES_IP
# REF=1: Gowin's reference device controller on the same PHY (top_ref.v, cross-check)
REF ?=
export REF
BUILD_SUFFIX := _$(SERDES_IP)$(if $(filter 1,$(REF)),_ref)

USB3_VERYL_SV := $(addprefix ../../rtl/usb3/,usb3_pkg.sv usb3_crc_pkg.sv usb3_scrambler.sv usb3_rx_fifo.sv usb3_rx_parser.sv usb3_tx_framer.sv usb3_ltssm.sv usb3_link.sv usb3_top.sv usb3_descriptor_rom.sv usb3_device.sv)

SRCS := $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/$(SERDES_IP)/*.v) $(wildcard src/$(TARGET)/$(SERDES_IP)/*/*.v) \
        src/$(TARGET)/$(SERDES_IP)/serdes.csr $(USB3_VERYL_SV) project.tcl

include ../build_gowin.mk

$(USB3_VERYL_SV): $(wildcard ../../rtl/usb3/*.veryl)
	cd ../../rtl/usb3 && veryl build
