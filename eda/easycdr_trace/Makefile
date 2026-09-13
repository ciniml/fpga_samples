PROJECT_NAME := easycdr_trace

TARGET ?= tangprimer25k

# CTRL_PULSE=1: Nano9K reverse channel = PulseResetRx only (reset, no registers)
ifeq ($(CTRL_PULSE),1)
BUILD_SUFFIX := _pulse
export CTRL_PULSE
endif

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) $(wildcard src/common/*.v) \
        ../../rtl/displayport/src/encoder_8b10b.sv $(wildcard ../../rtl/manchester/*.sv) project.tcl

include ../build_gowin.mk
