PROJECT_NAME := usb3_device

TARGET ?= tangconsole60k
# M1=1: board bring-up build (UART status, MS5351 programming, clock counter) without the USB core
ifeq ($(M1),1)
BUILD_SUFFIX := _m1
export M1
endif

USB3_VERYL_SV := $(addprefix ../../rtl/usb3/,usb3_pkg.sv usb3_scrambler.sv usb3_rx_fifo.sv usb3_rx_parser.sv usb3_tx_framer.sv usb3_ltssm.sv usb3_link.sv usb3_top.sv usb3_descriptor_rom.sv usb3_device.sv)

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/ip/*.v) $(wildcard src/$(TARGET)/ip/*/*.v) \
        $(USB3_VERYL_SV) ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(USB3_VERYL_SV): $(wildcard ../../rtl/usb3/*.veryl)
	cd ../../rtl/usb3 && veryl build
