.PHONY: all clean synthesis run deploy

# This file is included from the project directory. 
# Please note that the relative path is based on the project directory, not the directory which contains this file.

TARGET ?= tangnano1k
BITSTREAM := build/$(TARGET)/impl/pnr/$(PROJECT_NAME).fs
SRC_DIR := $(abspath src/$(TARGET))
RTL_DIR := $(abspath ../../rtl)
UTIL_DIR := $(abspath ../../util)

MAPPMOD_DIR ?= $(UTIL_DIR)/mappmod
MAPPMOD ?= $(MAPPMOD_DIR)/target/release/mappmod

MOD_DIR := $(abspath ../../mod)
TARGETS_DIR := $(abspath ../targets)
TARGET_DEF_DIR := $(TARGETS_DIR)/$(TARGET)

GW_SH ?= $(shell which gw_sh)

include $(TARGET_DEF_DIR)/target.mk

DEVICE ?= $(DEVICE_FAMILY)
PROGRAMMER_CLI_DIR ?= $(dir $(shell which programmer_cli))
PROGRAMMER_CABLE ?=
USE_OPENFPGA_LOADER ?= 1
OPENFPGA_LOADER ?= $(shell which openFPGALoader)
PROJECT_ADDITIONAL_ARGS ?= 
PROJECT_ADDITIONAL_CLEAN ?=

PROGRAMMER_FLASH_OP_INDEX ?= 6
OPENFPGA_LOADER_DEVICE_OVERRIDE ?=

PROJECT_TCL ?= ../../project.tcl

all: synthesis

$(BITSTREAM): $(SRCS)
	mkdir -p build/$(TARGET) && cd build/$(TARGET) && $(GW_SH) $(PROJECT_TCL) $(SRC_DIR) $(RTL_DIR) $(TARGET) $(DEVICE_FAMILY) $(DEVICE_PART) $(PROJECT_NAME) $(PROJECT_ADDITIONAL_ARGS)

synthesis: $(BITSTREAM)

scan-cables:
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli --scan-cables

scan:
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli --scan

run: $(BITSTREAM)
ifeq ($(USE_OPENFPGA_LOADER),0)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli $(PROGRAMMER_CABLE) $(CABLE_INDEX_OPT) --device $(DEVICE) --run 2 --fsFile $(abspath $(BITSTREAM))
else
	$(OPENFPGA_LOADER) $(OPENFPGA_LOADER_TARGET) $(OPENFPGA_LOADER_DEVICE_OVERRIDE) --write-sram $(abspath $(BITSTREAM))
endif

deploy: $(BITSTREAM)
ifeq ($(USE_OPENFPGA_LOADER),0)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli $(PROGRAMMER_CABLE) $(CABLE_INDEX_OPT) --device $(DEVICE) --run $(PROGRAMMER_FLASH_OP_INDEX) --fsFile $(abspath $(BITSTREAM))
else
	$(OPENFPGA_LOADER) $(OPENFPGA_LOADER_TARGET) $(OPENFPGA_LOADER_DEVICE_OVERRIDE) --write-flash $(abspath $(BITSTREAM)) --unprotect-flash
endif

clean:
	-$(RM) -r build/$(TARGET)
ifneq ($(PROJECT_ADDITIONAL_CLEAN),)
	-$(RM) $(PROJECT_ADDITIONAL_CLEAN)
endif

$(MAPPMOD):
	cd $(MAPPMOD_DIR); cargo build --release