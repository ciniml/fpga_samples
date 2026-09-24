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
# TRACE_MAP=maps/<name>.map: named signal map (default maps/nano9k_demo.map)
ifneq ($(TRACE_MAP),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(basename $(notdir $(TRACE_MAP)))
export TRACE_MAP
endif
# RATE=742M5: 742.5Mbps link (both boards; e.g. to share a 720p DVI clock on the TX)
ifneq ($(RATE),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(shell echo $(RATE) | tr A-Z a-z)
export RATE
endif

# Veryl sources (rtl/trace, rtl/manchester): the generated .sv are not tracked, build them first
TRACE_VERYL_SV := ../../rtl/trace/tx_link_core.sv ../../rtl/trace/trace_link_tx.sv ../../rtl/trace/trace_frontend.sv \
                  ../../rtl/trace/trace_cdc.sv ../../rtl/trace/trace_afifo.sv ../../rtl/trace/easycdr_trace_tx.sv \
                  ../../rtl/trace/trace_rx_decoder.sv ../../rtl/trace/trace_link_diag.sv ../../rtl/trace/trace_sym_inject.sv
SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) $(wildcard src/common/*.v) \
        $(TRACE_VERYL_SV) \
        ../../rtl/displayport/src/encoder_8b10b.sv $(wildcard ../../rtl/manchester/*.sv) project.tcl \
        host/tracemap.py $(wildcard maps/*.map)

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
$(TRACE_VERYL_SV): $(wildcard ../../rtl/trace/*.veryl) ../../rtl/trace/Veryl.toml
	cd ../../rtl/trace && veryl build

