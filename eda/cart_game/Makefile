# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := cart_game
TARGET ?= tangprimer25k

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,game_cart.sv qspi_rom.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) \
        ../cart_target/src/$(TARGET)/timing.sdc $(CHROMATIC_VERYL_SV) ../../rtl/uart/uart_rx.sv ../../rtl/uart/uart_tx.sv project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build
