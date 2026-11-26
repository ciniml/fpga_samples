# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := gb_camera
TARGET ?= tangprimer25k

# USB_PMOD: Dock slot of the Pmod USB HS Single. pmod0 (the slot with F5) is the camera; Pmod_RPiCamera is wider
# than a Pmod and leaves only pmod2 free next to it, so pmod2 (pmod1 builds, but the boards do not fit together)
USB_PMOD ?= pmod2
# HOST_UART=1: the Dock USB-UART goes to GameCart (as eda/cart_game) instead of the camera's csi_ctrl
HOST_UART ?= 0
export USB_PMOD HOST_UART
BUILD_SUFFIX := $(if $(filter-out pmod2,$(USB_PMOD)),_$(USB_PMOD))$(if $(filter 1,$(HOST_UART)),_hostuart)

RTL := ../../rtl
CHROMATIC_VERYL_SV := $(addprefix $(RTL)/chromatic/,game_cart.sv qspi_rom.sv byte_afifo.sv gb_camera.sv gb_color_quant.sv)
USB_VERYL_SV := $(addprefix $(RTL)/usb/,usb_pkg.sv usb_phy_rx.sv usb_phy_tx.sv usb_phy.sv usb_phy_bridge.sv usb_sie.sv usb_descriptor_rom.sv usb_device.sv)
CSI2_SV := $(addprefix $(RTL)/csi2/,csi2_pkg.sv csi2_edge_sampler.sv csi2_lane_aligner.sv csi2_lane_merge.sv csi2_packet.sv csi2_rx.sv)
ISP_SV := $(addprefix $(RTL)/camera_isp/,isp_raw10_unpack.sv isp_gb_scale.sv)
CSI_DIR := ../csi_capture/src/$(TARGET)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.cst) src/$(TARGET)/timing.sdc project.tcl \
        ../cart_game/src/$(TARGET)/pins.cst ../cart_game/src/$(TARGET)/pins_usb.cst ../cart_game/src/$(TARGET)/pll_100m_200m_50.v \
        $(CHROMATIC_VERYL_SV) $(USB_VERYL_SV) $(CSI2_SV) $(ISP_SV) $(wildcard $(CSI_DIR)/*.sv) \
        $(RTL)/usb/gowin/usb_phy_gowin_sl.v $(RTL)/oscdr/os_cdr.sv $(RTL)/oscdr/bit_gearbox.sv \
        ../usb_device/src/$(TARGET)/pll_usb/pll_usb.v ../usb_device/src/$(TARGET)/pll_hs960/pll_hs960.v \
        ../easycdr_bert/src/$(TARGET)/pll_rx_500m_4ph/pll_rx_500m_4ph.v \
        $(RTL)/uart/uart_rx.sv $(RTL)/uart/uart_tx.sv

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV) &: $(wildcard $(RTL)/chromatic/*.veryl)
	cd $(RTL)/chromatic && veryl build
$(USB_VERYL_SV) &: $(wildcard $(RTL)/usb/*.veryl)
	cd $(RTL)/usb && veryl build
$(CSI2_SV) &: $(wildcard $(RTL)/csi2/*.veryl)
	cd $(RTL)/csi2 && veryl build
$(ISP_SV) &: $(wildcard $(RTL)/camera_isp/*.veryl)
	cd $(RTL)/camera_isp && veryl build
$(RTL)/oscdr/os_cdr.sv $(RTL)/oscdr/bit_gearbox.sv &: $(wildcard $(RTL)/oscdr/*.veryl)
	cd $(RTL)/oscdr && veryl build
