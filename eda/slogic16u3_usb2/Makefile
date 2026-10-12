PROJECT_NAME := slogic16u3_usb2

TARGET ?= slogic16u3
# DX=K|P: K3/K2 or P2/P1 as the SoftPHY dx (data) pair, the other pair is the termination pair
DX ?= K
export DX
# HS=1: high-speed capable build (usb_phy_gowin_sl)
HS ?=
export HS
# CMP1=1 (with HS=1): 7-pin variant, D+ comparator only (usb_phy_gowin_sl CMP1)
CMP1 ?=
export CMP1
BUILD_SUFFIX := _dx$(shell echo $(DX) | tr A-Z a-z)$(if $(filter 1,$(HS)),_hs)$(if $(filter 1,$(CMP1)),_c1)

USB_VERYL_SV := $(addprefix ../../rtl/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)

SRCS := $(wildcard src/$(TARGET)/*.v) src/$(TARGET)/pins.cst src/$(TARGET)/timing.sdc \
        src/$(TARGET)/serdes/serdes.v src/$(TARGET)/serdes/serdes.csr $(USB_VERYL_SV) project.tcl \
        src/$(TARGET)/timing_hs.sdc ../../rtl/usb/gowin/usb_phy_gowin_sl.v

include ../build_gowin.mk

$(USB_VERYL_SV): $(wildcard ../../rtl/usb/*.veryl)
	cd ../../rtl/usb && veryl build
