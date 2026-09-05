# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := nvme_ethernet

TARGET ?= tangnano9k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
ETHERNET_DIR := $(RTL_DIR)/ethernet
NVME_DIR := $(RTL_DIR)/nvme

MAC_SRC := $(wildcard $(ETHERNET_DIR)/mii_mac/*.sv) \
	$(wildcard $(ETHERNET_DIR)/mii_axis/*.sv) \
	$(ETHERNET_DIR)/rmii_mac/rmii_mac.sv \
	$(ETHERNET_DIR)/util/simple_fifo.v

NVME_SV := $(NVME_DIR)/nvme_pkg.sv $(NVME_DIR)/nvme_tcp_pkg.sv \
	$(NVME_DIR)/nvme_core.sv $(NVME_DIR)/nvme_tcp_target.sv \
	$(NVME_DIR)/eth_ip.sv $(NVME_DIR)/eth_tx_mux.sv $(NVME_DIR)/tcp_engine.sv

PROJECT_ADDITIONAL_ARGS := $(abspath $(ETHERNET_DIR)) $(abspath $(NVME_DIR))

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
	$(wildcard src/$(TARGET)/*.sv) project.tcl $(MAC_SRC) $(NVME_SV)

include ../build_gowin.mk

# the NVMe stack .sv files are generated from Veryl
$(NVME_SV) &: $(wildcard $(NVME_DIR)/*.veryl)
	cd $(NVME_DIR) && veryl build
