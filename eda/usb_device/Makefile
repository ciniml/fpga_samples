PROJECT_NAME := usb_device

TARGET ?= tangprimer25k

# USB_PMOD_A / USB_PMOD_B: Dock slots (pmod0 | pmod1 | pmod2) of the Pmod USB connectors A (RX side) and B (TX side)
# The board in use: A (receivers) on pmod2, B (transmitter) on pmod1. Building with the wrong
# pair looks like a hardware fault (the host sees a device, nothing ever works) - check this first.
USB_PMOD_A ?= pmod2
USB_PMOD_B ?= pmod1
export USB_PMOD_A USB_PMOD_B
BUILD_SUFFIX := _$(USB_PMOD_A)$(USB_PMOD_B)
# USB_FS_ONLY=1: full-speed only (HS_CAPABLE=0)
ifeq ($(USB_FS_ONLY),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_fs
export USB_FS_ONLY
endif

USB_VERYL_SV := $(addprefix ../../rtl/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_phy_bridge.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) \
        $(USB_VERYL_SV) ../../rtl/oscdr/os_cdr.sv ../../rtl/oscdr/bit_gearbox.sv ../../rtl/usb/gowin/usb_phy_gowin_p.v ../../rtl/uart/uart_tx.sv ../../rtl/uart/uart_rx.sv project.tcl

include ../build_gowin.mk

$(USB_VERYL_SV): $(wildcard ../../rtl/usb/*.veryl)
	cd ../../rtl/usb && veryl build

../../rtl/oscdr/os_cdr.sv ../../rtl/oscdr/bit_gearbox.sv: $(wildcard ../../rtl/oscdr/*.veryl)
	cd ../../rtl/oscdr && veryl build
