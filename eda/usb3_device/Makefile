PROJECT_NAME := usb3_device

TARGET ?= tangconsole60k
# PLACE_OPT / ROUTE_OPT / PNR_EXTRA / TAG: PnR options (project.tcl), suffixed to the build directory when given
# REF=1: Gowin's reference device controller on the same PHY (top_ref.v, cross-check)
REF ?=
export REF
# LANE=3: SerDes Lane 3 (Console USB-A port 2P) instead of Lane 2 (port 1P)
LANE ?=
export LANE
# FORCE_TX=1: diagnostic, PHY held in P0 transmitting a fixed stream; CSR_FILE: alternative SerDes CSR (e.g. loopback)
FORCE_TX ?=
CSR_FILE ?=
FORCE_DET ?=
FD_PD ?=
# LTSSM_LOW_PD=1 RXDET_ASSUME_US=50000: LTSSM low power state P1 and assumed receiver detection (GW5AT-60 PHY)
LTSSM_LOW_PD ?=
LTSSM_RXDET_PD ?= $(LTSSM_LOW_PD)
RXDET_ASSUME_US ?= 0
POLL_LFPS_P2 ?= 1
POLL_LFPS_BLIND_US ?= 0
EI_RAW ?=
LFPS_DIAG ?=
FORCE_LFPS ?=
FREF_SEL ?=
LFPS_BURST ?=
export FREF_SEL LFPS_BURST FORCE_LFPS POLL_LFPS_P2 EI_RAW LFPS_DIAG FORCE_TX FORCE_DET FD_PD CSR_FILE LTSSM_LOW_PD LTSSM_RXDET_PD RXDET_ASSUME_US
PLACE_OPT ?=
ROUTE_OPT ?=
PNR_EXTRA ?=
TAG ?=
export PLACE_OPT ROUTE_OPT PNR_EXTRA
BUILD_SUFFIX := $(if $(filter 1,$(REF)),_ref)$(if $(filter 3,$(LANE)),_ln3)$(if $(filter 2ln,$(LANE)),_2ln)$(if $(filter 1,$(FORCE_TX)),_ftx)$(if $(filter 1,$(FORCE_DET)),_fdet)$(if $(filter 1,$(LFPS_DIAG)),_lfd)$(if $(FREF_SEL),_fref$(FREF_SEL))$(if $(filter 1,$(FORCE_LFPS)),_flf)$(if $(filter 1,$(LFPS_BURST)),_bst)$(if $(LTSSM_LOW_PD),_pd$(LTSSM_LOW_PD)r$(LTSSM_RXDET_PD)l$(POLL_LFPS_P2)$(if $(filter-out 0,$(POLL_LFPS_BLIND_US)),b$(POLL_LFPS_BLIND_US)))$(if $(EI_RAW),_eir$(EI_RAW))$(if $(PLACE_OPT),_p$(PLACE_OPT))$(if $(ROUTE_OPT),_r$(ROUTE_OPT))$(if $(TAG),_$(TAG))

USB3_VERYL_SV := $(addprefix ../../rtl/usb3/,usb3_pkg.sv usb3_crc_pkg.sv usb3_scrambler.sv usb3_rx_fifo.sv usb3_rx_parser.sv usb3_tx_framer.sv usb3_ltssm.sv usb3_link.sv usb3_top.sv usb3_descriptor_rom.sv usb3_device.sv)

SRCS := $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) \
        src/$(TARGET)/ip/serdes.v $(wildcard src/$(TARGET)/ip/*/*.v) src/$(TARGET)/ip/serdes.csr \
        $(USB3_VERYL_SV) ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(USB3_VERYL_SV): $(wildcard ../../rtl/usb3/*.veryl)
	cd ../../rtl/usb3 && veryl build
