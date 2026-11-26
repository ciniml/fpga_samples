# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := cart_target
TARGET ?= tangprimer25k

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,bt_pkg.sv cart_target.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) \
        $(wildcard src/$(TARGET)/*.sdc) $(CHROMATIC_VERYL_SV) ../../rtl/uart/uart_rx.sv ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build
