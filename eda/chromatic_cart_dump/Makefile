# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := chromatic_cart_dump
TARGET ?= chromatic

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,cart_power.sv cart_bus.sv cart_cmd.sv)
USB_VERYL_SV := $(addprefix ../../rtl/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.sdc) \
        ../targets/$(TARGET)/chromatic.cst ../targets/$(TARGET)/chromatic_cst.tcl \
        $(CHROMATIC_VERYL_SV) $(USB_VERYL_SV) project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build
$(USB_VERYL_SV): $(wildcard ../../rtl/usb/*.veryl)
	cd ../../rtl/usb && veryl build
