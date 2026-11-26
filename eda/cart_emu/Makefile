# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := cart_emu
TARGET ?= tangprimer25k

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,cart_emu.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(addprefix ../cart_target/src/$(TARGET)/,pll_100m_50.v pins.cst timing.sdc) \
        $(CHROMATIC_VERYL_SV) ../../rtl/uart/uart_rx.sv ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build
