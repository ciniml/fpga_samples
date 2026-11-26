# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Digilent Pcam 5C (OV5640) variant of eda/csi_capture: the same sources
# (../csi_capture/src/$(TARGET)) built with CSI_SENSOR_OV5640.
PROJECT_NAME := csi_capture_pcam5c

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
CSI_DIR := ../csi_capture/src/$(TARGET)

# Veryl sources: the generated .sv are not tracked, build them first
CSI2_MODS := csi2_pkg csi2_edge_sampler csi2_lane_aligner csi2_lane_merge csi2_packet csi2_rx
VERYL_SV := $(addprefix $(RTL_DIR)/csi2/,$(addsuffix .sv,$(CSI2_MODS)))
VERYL_SRC := $(wildcard $(RTL_DIR)/csi2/*.veryl) $(RTL_DIR)/csi2/Veryl.toml

SRCS := $(wildcard src/$(TARGET)/*.v) $(wildcard $(CSI_DIR)/*.sv) $(CSI_DIR)/pins.cst $(CSI_DIR)/timing.sdc \
        project.tcl $(VERYL_SV) ../easycdr_bert/src/$(TARGET)/pll_rx_500m_4ph/pll_rx_500m_4ph.v

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(VERYL_SV) &: $(VERYL_SRC)
	cd $(RTL_DIR)/csi2 && veryl build
