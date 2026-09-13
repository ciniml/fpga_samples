PROJECT_NAME := easycdr_trace

TARGET ?= tangprimer25k

# Variants (Nano9K): CTRL_PULSE=1 = PulseResetRx only (reset, no registers);
# TRACE_WIDTH=32 etc. = demo trace width. Each gets its own build directory.
BUILD_SUFFIX :=
ifeq ($(CTRL_PULSE),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_pulse
export CTRL_PULSE
endif
ifneq ($(TRACE_WIDTH),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_w$(TRACE_WIDTH)
export TRACE_WIDTH
endif

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) $(wildcard src/common/*.v) \
        ../../rtl/displayport/src/encoder_8b10b.sv $(wildcard ../../rtl/manchester/*.sv) project.tcl

include ../build_gowin.mk
