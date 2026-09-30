PROJECT_NAME := dvi_hub75

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

# PANEL=<W>x<H> (64 / 128 each, default 128x128)
# BITS=<n> BCM bit planes per colour (default 6), HUB75_CLKDIV=<n> (default 0)
# HUB75_CLKLOW=<n> extra CLK-low ticks per pixel (default 1; CLKDIV=0 CLKLOW=1 -> 16.7 MHz)
BUILD_SUFFIX :=
ifneq ($(PANEL),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(PANEL)
export PANEL
endif
ifneq ($(BITS),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_b$(BITS)
export BITS
endif
ifneq ($(HUB75_CLKDIV),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_div$(HUB75_CLKDIV)
export HUB75_CLKDIV
endif
ifneq ($(HUB75_CLKLOW),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_low$(HUB75_CLKLOW)
export HUB75_CLKLOW
endif

CAPTURE_DIR := ../dvi_capture/src/$(TARGET)
LOOP_DIR    := ../dvi_loopback/src/$(TARGET)

# Veryl sources: the generated .sv are not tracked, build them first
VERYL_SV := $(RTL_DIR)/dvi_in/dvi_in.sv $(RTL_DIR)/hub75/hub75.sv \
            $(RTL_DIR)/ddc_edid/ddc_edid.sv $(RTL_DIR)/ddc_edid/edid_rom.sv $(RTL_DIR)/ddc_edid/edid_rom_1080p.sv

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl $(VERYL_SV) \
        $(CAPTURE_DIR)/iser10_lane.sv $(CAPTURE_DIR)/dvi_in_phy.sv $(CAPTURE_DIR)/reset_seq.sv \
        $(LOOP_DIR)/frame_sum.sv $(LOOP_DIR)/loop_check.sv $(LOOP_DIR)/loop_report.sv

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(RTL_DIR)/dvi_in/dvi_in.sv: $(RTL_DIR)/dvi_in/dvi_in.veryl $(RTL_DIR)/dvi_in/Veryl.toml
	cd $(RTL_DIR)/dvi_in && veryl build
$(RTL_DIR)/hub75/hub75.sv: $(RTL_DIR)/hub75/hub75.veryl $(RTL_DIR)/hub75/Veryl.toml
	cd $(RTL_DIR)/hub75 && veryl build
$(RTL_DIR)/ddc_edid/ddc_edid.sv $(RTL_DIR)/ddc_edid/edid_rom.sv $(RTL_DIR)/ddc_edid/edid_rom_1080p.sv: $(RTL_DIR)/ddc_edid/ddc_edid.veryl $(RTL_DIR)/ddc_edid/edid_rom.veryl $(RTL_DIR)/ddc_edid/edid_rom_1080p.veryl $(RTL_DIR)/ddc_edid/Veryl.toml
	cd $(RTL_DIR)/ddc_edid && veryl build

# Panel-model simulation (all panel sizes)
.PHONY: sim
sim: $(RTL_DIR)/hub75/hub75.sv
	$(MAKE) -C test
