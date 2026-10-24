PROJECT_NAME := ethernet_hub75

# make TARGET=tangprimer20k (default) | dk_led_rxcard_gw3a20
TARGET ?= tangprimer20k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

TOP_MODULE_tangprimer20k := TangPrimer20kTop
TOP_MODULE ?= $(TOP_MODULE_$(TARGET))

# Veryl: this project + rtl/eth_mac + rtl/hub75 (path dependencies). The
# generated .sv are not tracked; `veryl build` writes them and the filelist.
FILELIST := $(abspath $(PROJECT_NAME).f)
VERYL_SRCS := Veryl.toml $(wildcard src/common/*.veryl) $(wildcard src/*/*.veryl) \
              $(wildcard $(RTL_DIR)/eth_mac/*.veryl) $(wildcard $(RTL_DIR)/hub75/*.veryl)

PROJECT_ADDITIONAL_ARGS := $(FILELIST) $(TOP_MODULE)

SRCS := project.tcl src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/ip/*.v) $(FILELIST)

include ../build_gowin.mk

$(FILELIST): $(VERYL_SRCS)
	veryl build
	touch $@

.PHONY: sim
sim:
	$(MAKE) -C test
