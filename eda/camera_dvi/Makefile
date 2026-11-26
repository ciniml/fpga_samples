# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := camera_dvi

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
CSI_DIR := ../csi_capture/src/$(TARGET)
LOOP_DIR := ../dvi_loopback/src/$(TARGET)

# RES=1080P: 1920x1080p30 (default 1280x720p30)
BUILD_SUFFIX :=
ifneq ($(RES),)
BUILD_SUFFIX := _$(shell echo $(RES) | tr A-Z a-z)
export RES
endif

# Veryl sources: the generated .sv are not tracked, build them first
CSI2_MODS := csi2_pkg csi2_edge_sampler csi2_lane_aligner csi2_lane_merge csi2_packet csi2_rx
CSI2_SV := $(addprefix $(RTL_DIR)/csi2/,$(addsuffix .sv,$(CSI2_MODS)))
ISP_MODS := isp_video_timing isp_raw10_unpack isp_line_ring isp_gamma isp_display isp_genlock
ISP_SV := $(addprefix $(RTL_DIR)/camera_isp/,$(addsuffix .sv,$(ISP_MODS)))

SRCS := $(wildcard src/$(TARGET)/*.sv) src/$(TARGET)/pins.cst src/$(TARGET)/timing.sdc project.tcl \
        $(wildcard $(CSI_DIR)/*.sv) $(CSI2_SV) $(ISP_SV) $(RTL_DIR)/dvi_out/dvi_out.sv \
        ../easycdr_bert/src/$(TARGET)/pll_rx_500m_4ph/pll_rx_500m_4ph.v \
        $(LOOP_DIR)/ip/gowin_pll_27.v $(LOOP_DIR)/ip/pll_tx_1080p/pll_tx_1080p.v

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(CSI2_SV) &: $(wildcard $(RTL_DIR)/csi2/*.veryl) $(RTL_DIR)/csi2/Veryl.toml
	cd $(RTL_DIR)/csi2 && veryl build
$(ISP_SV) &: $(wildcard $(RTL_DIR)/camera_isp/*.veryl) $(RTL_DIR)/camera_isp/Veryl.toml
	cd $(RTL_DIR)/camera_isp && veryl build
$(RTL_DIR)/dvi_out/dvi_out.sv: $(RTL_DIR)/dvi_out/dvi_out.veryl $(RTL_DIR)/dvi_out/Veryl.toml
	cd $(RTL_DIR)/dvi_out && veryl build

.PHONY: sim
sim:
	$(RTL_DIR)/camera_isp/test/run.sh
