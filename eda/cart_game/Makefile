# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := cart_game
TARGET ?= tangprimer25k

# USB_PMOD: Dock slot (pmod0 | pmod1 | pmod2) of the Pmod USB HS Single
USB_PMOD ?= pmod1
export USB_PMOD
BUILD_SUFFIX := $(if $(filter-out pmod1,$(USB_PMOD)),_$(USB_PMOD))

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,game_cart.sv qspi_rom.sv byte_afifo.sv)
USB_VERYL_SV := $(addprefix ../../rtl/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_phy_bridge.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) src/$(TARGET)/timing.sdc \
        $(CHROMATIC_VERYL_SV) $(USB_VERYL_SV) ../../rtl/usb/gowin/usb_phy_gowin_sl.v ../../rtl/oscdr/os_cdr.sv ../../rtl/oscdr/bit_gearbox.sv \
        ../usb_device/src/$(TARGET)/pll_usb/pll_usb.v ../usb_device/src/$(TARGET)/pll_hs960/pll_hs960.v \
        ../../rtl/uart/uart_rx.sv ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build

$(USB_VERYL_SV): $(wildcard ../../rtl/usb/*.veryl)
	cd ../../rtl/usb && veryl build

../../rtl/oscdr/os_cdr.sv ../../rtl/oscdr/bit_gearbox.sv: $(wildcard ../../rtl/oscdr/*.veryl)
	cd ../../rtl/oscdr && veryl build
