# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := t1s_direct

TARGET ?= tangprimer25k

# Veryl sources: the generated .sv are not tracked, build them first
T1S_SV := $(addprefix ../../rtl/t1s_phy/,t1s_pma_tx.sv t1s_pma_rx.sv t1s_pcs_tx.sv t1s_pcs_rx.sv t1s_plca.sv t1s_phy.sv t1s_bringup.sv)

SRCS := src/$(TARGET)/pins.cst src/$(TARGET)/timing.sdc $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) \
        $(T1S_SV) project.tcl

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(T1S_SV) &: $(wildcard ../../rtl/t1s_phy/*.veryl) ../../rtl/t1s_phy/Veryl.toml
	cd ../../rtl/t1s_phy && veryl build

# PHY simulation (Verilator, no vendor primitives)
.PHONY: sim
sim:
	cd ../../rtl/t1s_phy && veryl test
