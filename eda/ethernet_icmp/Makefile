PROJECT_NAME := ethernet_icmp

TARGET ?= tangprimer20k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl
ETHERNET_DIR ?= $(ROOT_DIR)/external/ebaz4205_ethernet

MII_MAC_SRC := $(wildcard $(ETHERNET_DIR)/mii_mac/*.sv) $(wildcard $(ETHERNET_DIR)/mii_axis/*.sv) $(ETHERNET_DIR)/util/simple_fifo.v

ifeq ($(TARGET),tangnano9k_pmod)
# Use asynchronous version of EthernetSystem
ETHERNET_SERVICE_SRC := $(RTL_DIR)/chisel/ethernet_system/ethernet_system_async.v
else
ETHERNET_SERVICE_SRC := $(RTL_DIR)/chisel/ethernet_system/ethernet_system.v
endif

PROJECT_ADDITIONAL_ARGS := $(abspath $(ETHERNET_DIR)) $(abspath $(ETHERNET_SERVICE_SRC))

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl $(MII_MAC_SRC) $(ETHERNET_SERVICE_SRC)

PMOD_PORT_OFFSET ?= 0
PMOD_TARGETS := tangnano9k_pmod tangprimer20k_hub75

# Check if the target contains PMOD ports
USE_PMOD := 0
ifneq (,$(filter $(TARGET),$(PMOD_TARGETS)))
USE_PMOD := 1
PROJECT_ADDITIONAL_CLEAN += src/$(TARGET)/pins.cst
endif
include ../build_gowin.mk

ifeq ($(TARGET),tangnano9k_pmod)
# Add Pmod Ethernet module
PMOD_MODULES += $(MOD_DIR)/pmod_ethernet/pmod_pins.csv
endif
PMOD_MODULES += $(MOD_DIR)/pmod_hub75/pmod_pins.csv

ifeq ($(USE_PMOD),1)
# Generate CST file from template.
src/$(TARGET)/pins.cst: src/$(TARGET)/pins.cst.template $(TARGET_DEF_DIR)/pmod_ports.csv $(PMOD_MODULES) $(MAPPMOD)
	echo Generating pin definition from Pmod pin map.
	echo // This file is automatically generated by build script. DO NOT EDIT THIS FILE. > $@
	cat src/$(TARGET)/pins.cst.template >> $@
	$(MAPPMOD) --pmod-port-def $(TARGET_DEF_DIR)/pmod_ports.csv $(addprefix --pmod ,$(PMOD_MODULES)) --port-offset $(PMOD_PORT_OFFSET) --direction right-to-left >> $@
else
src/$(TARGET)/pins.cst:
	echo Use pre-generated pin definition.
endif