PROJECT_NAME := dvi_loopback

TARGET ?= tangprimer25k

# RATE=720P: 1280x720p60 variant (74.25 MHz / 742.5 Mbps) to check the loopback itself
# TX_IO=<IO_TYPE>_<DRIVE> (default LVPECL33E_16), CTLE=OFF|LOW|MEDIUM|HIGH (default HIGH),
# TX_SLOT=PMOD1 (default PMOD2)
BUILD_SUFFIX :=
ifneq ($(RATE),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(shell echo $(RATE) | tr A-Z a-z)
export RATE
endif
ifneq ($(TX_IO),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(shell echo $(TX_IO) | tr A-Z a-z)
export TX_IO
endif
ifneq ($(TX_SLOT),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_tx$(shell echo $(TX_SLOT) | tr A-Z a-z)
export TX_SLOT
endif
ifneq ($(TX_CLK),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_clk$(shell echo $(TX_CLK) | tr A-Z a-z)
export TX_CLK
endif
ifneq ($(RX_TERM),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_term$(shell echo $(RX_TERM) | tr A-Z a-z)
export RX_TERM
endif
LANE_CTLE := $(foreach v,CTLE_CLK CTLE_D0 CTLE_D1 CTLE_D2,$(if $($(v)),_$(shell echo $(v)$($(v)) | tr A-Z a-z | sed 's/ctle_//')))
ifneq ($(LANE_CTLE),)
BUILD_SUFFIX := $(BUILD_SUFFIX)$(subst $(eval) ,,$(LANE_CTLE))
export CTLE_CLK CTLE_D0 CTLE_D1 CTLE_D2
endif
ifneq ($(CTLE),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_ctle$(shell echo $(CTLE) | tr A-Z a-z)
export CTLE
endif

# Shared Tang Primer 25K RX PHY (IODELAY + IDES10 + dvi_in wrapper)
CAPTURE_DIR := ../dvi_capture/src/$(TARGET)

# Veryl sources: the generated .sv are not tracked, build them first
VERYL_SV := ../../rtl/dvi_in/dvi_in.sv ../../rtl/dvi_out/dvi_out.sv

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) \
        $(wildcard src/$(TARGET)/ip/*.v) $(wildcard src/$(TARGET)/ip/*/*.v) \
        $(CAPTURE_DIR)/iser10_lane.sv $(CAPTURE_DIR)/dvi_in_phy.sv $(CAPTURE_DIR)/reset_seq.sv \
        $(VERYL_SV) ../../rtl/uart/uart_tx.sv ../../rtl/uart/uart_rx.sv project.tcl

include ../build_gowin.mk

# (after the include so that `all` stays the default goal)
../../rtl/dvi_in/dvi_in.sv: ../../rtl/dvi_in/dvi_in.veryl ../../rtl/dvi_in/Veryl.toml
	cd ../../rtl/dvi_in && veryl build
../../rtl/dvi_out/dvi_out.sv: ../../rtl/dvi_out/dvi_out.veryl ../../rtl/dvi_out/Veryl.toml
	cd ../../rtl/dvi_out && veryl build

# Logic-level loopback simulation (no vendor primitives)
.PHONY: sim
sim: $(VERYL_SV)
	$(MAKE) -C test
