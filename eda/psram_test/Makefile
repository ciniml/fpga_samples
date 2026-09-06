# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := psram_test

TARGET ?= tangnano9k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
PSRAM_DIR := $(RTL_DIR)/gowin_psram
UART_DIR := $(RTL_DIR)/uart

PSRAM_SV := $(PSRAM_DIR)/gowin_psram.sv $(PSRAM_DIR)/psram_test.sv

PROJECT_ADDITIONAL_ARGS := $(abspath $(PSRAM_DIR)) $(abspath $(UART_DIR))

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
	$(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/ip/*/*.v) \
	project.tcl $(PSRAM_SV) $(UART_DIR)/uart_tx.sv

include ../build_gowin.mk

# generated from Veryl
$(PSRAM_SV) &: $(wildcard $(PSRAM_DIR)/*.veryl)
	cd $(PSRAM_DIR) && veryl build
