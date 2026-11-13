# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# ModRetro Chromatic (GW5A-EV25UG256CC1/I0). JTAG through the GWU2X bridge behind the USB-C port
# (console power switch ON). See README.md in this directory.
DEVICE_FAMILY := GW5A-25A
DEVICE_PART := GW5A-EV25UG256CC1/I0
OPENFPGA_LOADER_TARGET := --cable gwu2x
# The upstream design is built with Gowin 1.9.12.03
ifeq ($(strip $(GW_SH)),)
GW_SH := $(wildcard $(HOME)/gowin/1.9.12.03/IDE/bin/gw_sh)
endif
# make deploy: verified write, then reconfigure from flash; guarded by chromatic-flash-check (rules.mk)
OPENFPGA_LOADER_FLASH_OPTS := --verify --reset
DEPLOY_PREREQ := chromatic-flash-check
