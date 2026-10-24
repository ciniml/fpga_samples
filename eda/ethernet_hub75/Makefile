PROJECT_NAME := ethernet_hub75

# make TARGET=tangprimer20k (default) | dk_led_rxcard_gw3a20 [HUB75_IMPL=soft|gmt]
TARGET ?= tangprimer20k
# HUB75 output stage: soft (Hub75Lanes) or gmt (GW3A GMT hard block +
# Hub75Planes, Arora III only). gmt builds go to build/<target>_gmt.
HUB75_IMPL ?= soft
ifeq ($(HUB75_IMPL),gmt)
BUILD_SUFFIX := _gmt
HUB75_IMPL_NUM := 1
else
HUB75_IMPL_NUM := 0
endif
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

TOP_MODULE_tangprimer20k := TangPrimer20kTop
TOP_MODULE_dk_led_rxcard_gw3a20 := DkLedRxcardTop
TOP_MODULE ?= $(TOP_MODULE_$(TARGET))

# Veryl: this project + rtl/eth_mac + rtl/hub75 (path dependencies). The
# generated .sv are not tracked; `veryl build` writes them and the filelist.
FILELIST := $(abspath $(PROJECT_NAME).f)
VERYL_SRCS := Veryl.toml $(wildcard src/common/*.veryl) $(wildcard src/*/*.veryl) \
              $(wildcard $(RTL_DIR)/eth_mac/*.veryl) $(wildcard $(RTL_DIR)/hub75/*.veryl)

PROJECT_ADDITIONAL_ARGS := $(FILELIST) $(TOP_MODULE) $(HUB75_IMPL_NUM)

SRCS := project.tcl src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/ip/*.v) $(FILELIST)

include ../build_gowin.mk

$(FILELIST): $(VERYL_SRCS)
	veryl build
	touch $@

.PHONY: sim
sim:
	$(MAKE) -C test
