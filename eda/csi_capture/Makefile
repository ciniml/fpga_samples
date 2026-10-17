PROJECT_NAME := csi_capture

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

# Veryl sources: the generated .sv are not tracked, build them first
CSI2_MODS := csi2_pkg csi2_edge_sampler csi2_lane_aligner csi2_lane_merge csi2_packet csi2_rx
VERYL_SV := $(addprefix $(RTL_DIR)/csi2/,$(addsuffix .sv,$(CSI2_MODS)))
VERYL_SRC := $(wildcard $(RTL_DIR)/csi2/*.veryl) $(RTL_DIR)/csi2/Veryl.toml

SRCS := $(wildcard src/$(TARGET)/*.sv) src/$(TARGET)/pins.cst src/$(TARGET)/timing.sdc project.tcl $(VERYL_SV) \
        ../easycdr_bert/src/$(TARGET)/pll_rx_500m_4ph/pll_rx_500m_4ph.v

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(VERYL_SV) &: $(VERYL_SRC)
	cd $(RTL_DIR)/csi2 && veryl build
