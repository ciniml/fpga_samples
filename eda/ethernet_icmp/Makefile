PROJECT_NAME := ethernet_icmp

TARGET ?= tangprimer20k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
ETHERNET_DIR ?= $(ROOT_DIR)/external/ebaz4205_ethernet

MII_MAC_SRC := $(wildcard $(ETHERNET_DIR)/mii_mac/*.sv) $(wildcard $(ETHERNET_DIR)/mii_axis/*.sv) $(ETHERNET_DIR)/util/simple_fifo.v
ETHERNET_SERVICE_SRC := $(RTL_DIR)/chisel/ethernet_system/ethernet_system.v

PROJECT_ADDITIONAL_ARGS := $(abspath $(ETHERNET_DIR)) $(abspath $(ETHERNET_SERVICE_SRC))

SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl $(MII_MAC_SRC) $(ETHERNET_SERVICE_SRC)

include ../build_gowin.mk