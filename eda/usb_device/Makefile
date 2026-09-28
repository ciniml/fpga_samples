PROJECT_NAME := usb_device

TARGET ?= tangprimer25k

# USB_PMOD_A / USB_PMOD_B: Dock slots (pmod0 | pmod1 | pmod2) of the Pmod USB connectors A (RX side) and B (TX side)
USB_PMOD_A ?= pmod1
USB_PMOD_B ?= pmod2
export USB_PMOD_A USB_PMOD_B
BUILD_SUFFIX := _$(USB_PMOD_A)$(USB_PMOD_B)

USB_VERYL_SV := $(addprefix ../../rtl/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) \
        $(USB_VERYL_SV) ../../rtl/usb/gowin/usb_phy_gowin.v ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(USB_VERYL_SV): $(wildcard ../../rtl/usb/*.veryl)
	cd ../../rtl/usb && veryl build
