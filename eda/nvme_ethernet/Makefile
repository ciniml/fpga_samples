# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
PROJECT_NAME := nvme_ethernet

TARGET ?= tangnano9k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
ETHERNET_DIR := $(RTL_DIR)/ethernet
NVME_DIR := $(RTL_DIR)/nvme
PSRAM_DIR := $(RTL_DIR)/gowin_psram
DDR3_DIR := $(RTL_DIR)/ddr3

MAC_SRC := $(wildcard $(ETHERNET_DIR)/mii_mac/*.sv) \
	$(wildcard $(ETHERNET_DIR)/mii_axis/*.sv) \
	$(ETHERNET_DIR)/rmii_mac/rmii_mac.sv \
	$(ETHERNET_DIR)/util/simple_fifo.v

NVME_SV := $(NVME_DIR)/nvme_pkg.sv $(NVME_DIR)/nvme_tcp_pkg.sv \
	$(NVME_DIR)/nvme_core.sv $(NVME_DIR)/nvme_tcp_target.sv \
	$(NVME_DIR)/eth_ip.sv $(NVME_DIR)/eth_tx_mux.sv $(NVME_DIR)/tcp_engine.sv

PSRAM_SV := $(PSRAM_DIR)/gowin_psram.sv $(PSRAM_DIR)/psram_dword_cache.sv
DDR3_SV := $(DDR3_DIR)/bus_if.sv $(DDR3_DIR)/line_bus_if.sv $(DDR3_DIR)/ddr3_ctrl.sv \
	$(DDR3_DIR)/ddr3_phy_gw2a.sv $(DDR3_DIR)/line_dword_cache.sv

# constraint file inside src/$(TARGET) (tangprimer20k: pins.cst = LAN8720 wired
# directly, pins_pmod2.cst = Pmod Ethernet adapter on PMOD2)
PINS_CST ?= pins.cst
PROJECT_ADDITIONAL_ARGS := $(abspath $(ETHERNET_DIR)) $(abspath $(NVME_DIR)) $(abspath $(PSRAM_DIR)) $(PINS_CST) $(abspath $(DDR3_DIR))

SRCS := src/$(TARGET)/$(PINS_CST) $(wildcard src/$(TARGET)/*.sdc) \
	$(wildcard src/$(TARGET)/*.sv) $(wildcard src/$(TARGET)/ip/*/*.v) project.tcl $(MAC_SRC) $(NVME_SV) $(PSRAM_SV) $(DDR3_SV) $(RTL_DIR)/uart/uart_tx.sv

include ../build_gowin.mk

# the NVMe stack .sv files are generated from Veryl
$(NVME_SV) &: $(wildcard $(NVME_DIR)/*.veryl)
	cd $(NVME_DIR) && veryl build

$(PSRAM_SV) &: $(wildcard $(PSRAM_DIR)/*.veryl)
	cd $(PSRAM_DIR) && veryl build

$(DDR3_SV) &: $(wildcard $(DDR3_DIR)/*.veryl)
	cd $(DDR3_DIR) && veryl build
