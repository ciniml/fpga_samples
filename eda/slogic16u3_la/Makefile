PROJECT_NAME := slogic16u3_la

TARGET ?= slogic16u3
# PLACE_OPT / ROUTE_OPT / PNR_EXTRA / TAG: PnR options (project.tcl), suffixed to the build directory
PLACE_OPT ?=
ROUTE_OPT ?=
PNR_EXTRA ?=
TAG ?=
export PLACE_OPT ROUTE_OPT PNR_EXTRA
BUILD_SUFFIX := $(if $(PLACE_OPT),_p$(PLACE_OPT))$(if $(ROUTE_OPT),_r$(ROUTE_OPT))$(if $(TAG),_$(TAG))

# the USB 3.0 PHY IP and the shared top-level helpers live in ../slogic16u3_usb3
USB3_SRC := ../slogic16u3_usb3/src/$(TARGET)
USB3_VERYL_SV := $(addprefix ../../rtl/usb3/,usb3_pkg.sv usb3_crc_pkg.sv usb3_scrambler.sv usb3_rx_fifo.sv usb3_rx_parser.sv usb3_tx_framer.sv usb3_ltssm.sv usb3_link.sv usb3_top.sv usb3_descriptor_rom.sv usb3_device.sv)
LA_VERYL_SV := $(addprefix ../../rtl/la/,la_pkg.sv la_afifo.sv la_front.sv la_packer.sv la_framer.sv la_core.sv)

SRCS := $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) \
        $(USB3_SRC)/jtag_status.v $(USB3_SRC)/pll_ref125.v \
        $(wildcard $(USB3_SRC)/usb3_ln0/*.v) $(wildcard $(USB3_SRC)/usb3_ln0/*/*.v) $(USB3_SRC)/usb3_ln0/serdes.csr \
        $(USB3_VERYL_SV) $(LA_VERYL_SV) project.tcl

include ../build_gowin.mk

$(USB3_VERYL_SV): $(wildcard ../../rtl/usb3/*.veryl)
	cd ../../rtl/usb3 && veryl build
$(LA_VERYL_SV): $(wildcard ../../rtl/la/*.veryl)
	cd ../../rtl/la && veryl build

# flash application image for the official DFU tool (see README "DFU"): the built bitstream with the
# next multiboot address set to the DFU image, so that MODE still reaches DFU
DFU_OUT := build/dfu/$(PROJECT_NAME)$(BUILD_SUFFIX)
dfu: $(BITSTREAM)
	mkdir -p build/dfu
	python3 host/mkdfu.py $(BITSTREAM) $(DFU_OUT)
.PHONY: dfu
