# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := eth100_direct

TARGET ?= tangprimer25k

# Veryl sources: the generated .sv are not tracked, build them first
VERYL_SV := ../../rtl/oscdr/os_cdr.sv \
            $(addprefix ../../rtl/eth100_phy/,eth100_tx.sv eth100_rx.sv eth100_flp.sv eth100_an.sv eth100_phy.sv)

SRCS := src/$(TARGET)/pins.cst src/$(TARGET)/timing.sdc $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) \
        $(VERYL_SV) ../../rtl/uart/uart_tx.sv ../../rtl/uart/uart_rx.sv project.tcl

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
../../rtl/oscdr/os_cdr.sv: ../../rtl/oscdr/os_cdr.veryl ../../rtl/oscdr/Veryl.toml
	cd ../../rtl/oscdr && veryl build
$(filter ../../rtl/eth100_phy/%,$(VERYL_SV)) &: $(wildcard ../../rtl/eth100_phy/*.veryl) ../../rtl/eth100_phy/Veryl.toml
	cd ../../rtl/eth100_phy && veryl build

# PHY link simulation (Verilator, no vendor primitives)
.PHONY: sim
sim:
	cd ../../rtl/eth100_phy && veryl test
