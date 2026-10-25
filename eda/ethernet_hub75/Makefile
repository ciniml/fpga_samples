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
# DK_LED-RXCARD RGMII timing options (for bring-up; see README):
#   PHY_DLY     on (RTL8211E RX / TX delays forced on, default) | strap
#               (left to the strap resistors) | off (forced off) | 4 hex
#               digits for ext 0xa4 reg 0x1c bits 13:11 (3000 / 2800: one
#               of the two delays only)
#   TXC_SHIFTED 1: TXD / TX_CTL from the PLL 270° output (TXC 2 ns after
#               the data, for a PHY with its TX delay off)
#   RX_DELAY    IODELAY steps (12.5 ps) on RXD / RX_CTL, 0..255
# Non-default values are appended to the build directory name.
PHY_DLY ?= on
TXC_SHIFTED ?= 0
RX_DELAY ?= 0
PHY_DELAY_HEX_on := 3800
PHY_DELAY_HEX_strap := 0000
PHY_DELAY_HEX_off := 2000
PHY_DELAY_HEX := $(or $(PHY_DELAY_HEX_$(PHY_DLY)),$(PHY_DLY))
ifneq ($(PHY_DLY),on)
BUILD_SUFFIX := $(BUILD_SUFFIX)_phy$(PHY_DLY)
endif
ifneq ($(TXC_SHIFTED),0)
BUILD_SUFFIX := $(BUILD_SUFFIX)_txc90
endif
ifneq ($(RX_DELAY),0)
BUILD_SUFFIX := $(BUILD_SUFFIX)_rxd$(RX_DELAY)
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

PROJECT_ADDITIONAL_ARGS := $(FILELIST) $(TOP_MODULE) $(HUB75_IMPL_NUM) $(PHY_DELAY_HEX) $(TXC_SHIFTED) $(RX_DELAY)

SRCS := project.tcl src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/ip/*.v) $(FILELIST)

include ../build_gowin.mk

$(FILELIST): $(VERYL_SRCS)
	veryl build
	touch $@

.PHONY: sim
sim:
	$(MAKE) -C test
