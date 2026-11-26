# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := chromatic_blink
TARGET ?= chromatic

CHROMATIC_VERYL_SV := $(addprefix ../../rtl/chromatic/,cart_power.sv chromatic_blink.sv)
SRCS := $(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/*.sdc) ../targets/$(TARGET)/chromatic.cst ../targets/$(TARGET)/chromatic_cst.tcl \
        $(CHROMATIC_VERYL_SV) project.tcl

include ../build_gowin.mk

$(CHROMATIC_VERYL_SV): $(wildcard ../../rtl/chromatic/*.veryl)
	cd ../../rtl/chromatic && veryl build
