PROJECT_NAME := dvi_capture

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

# CTLE=OFF|LOW|MEDIUM|HIGH: RX equalizer variant (default HIGH)
ifneq ($(CTLE),)
BUILD_SUFFIX := _ctle$(shell echo $(CTLE) | tr A-Z a-z)
export CTLE
endif

LOOP_DIR := ../dvi_loopback/src/$(TARGET)

# Veryl sources: the generated .sv are not tracked, build them first
VERYL_SV := $(RTL_DIR)/dvi_in/dvi_in.sv $(RTL_DIR)/ddc_edid/ddc_edid.sv $(RTL_DIR)/ddc_edid/edid_rom.sv

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl $(VERYL_SV) \
        $(LOOP_DIR)/frame_sum.sv $(LOOP_DIR)/loop_check.sv $(LOOP_DIR)/loop_report.sv

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(RTL_DIR)/dvi_in/dvi_in.sv: $(RTL_DIR)/dvi_in/dvi_in.veryl $(RTL_DIR)/dvi_in/Veryl.toml
	cd $(RTL_DIR)/dvi_in && veryl build
$(RTL_DIR)/ddc_edid/ddc_edid.sv $(RTL_DIR)/ddc_edid/edid_rom.sv: $(RTL_DIR)/ddc_edid/ddc_edid.veryl $(RTL_DIR)/ddc_edid/edid_rom.veryl $(RTL_DIR)/ddc_edid/Veryl.toml
	cd $(RTL_DIR)/ddc_edid && veryl build
