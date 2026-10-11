PROJECT_NAME := slogic16u3_probe

TARGET ?= slogic16u3
# PULL=UP|DOWN|NONE: weak pull of the probe pins (each is its own bitstream)
PULL ?= UP
export PULL
# PINSET=main|cfg|la: 'la' pins or configuration pins (both do not fit in one build with
# all probe pins); la = LA + UART + configuration pins
PINSET ?= main
export PINSET
# LA_IO="<cst attributes>" overrides the 'la' rows' IO attributes; LA_TAG names that build
LA_IO ?=
LA_TAG ?=
export LA_IO
LA_VREF ?=
export LA_VREF
LA_VREF2 ?=
LA_IO2 ?=
export LA_VREF2 LA_IO2
LA_EXTRA ?=
export LA_EXTRA
BUILD_SUFFIX := _$(PINSET)_$(shell echo $(PULL) | tr A-Z a-z)$(if $(LA_TAG),_$(LA_TAG))

SRCS := src/$(TARGET)/top.v src/$(TARGET)/pins.csv src/$(TARGET)/timing.sdc project.tcl

include ../build_gowin.mk

.PHONY: all-pulls
all-pulls:
	$(MAKE) PINSET=main PULL=UP
	$(MAKE) PINSET=main PULL=DOWN
	$(MAKE) PINSET=cfg PULL=UP
	$(MAKE) PINSET=cfg PULL=DOWN

# Co-simulation of top.v with a behavioural GW_JTAG, driven by the host tool:
#   make sim SIM_PINSET=main SIM_PULL=up
#   python3 host/slogic_probe.py --sim "vvp -n sim/build/tb_main_up.vvp" ubs-read
SIM_PINSET ?= main
SIM_PULL ?= up
SIM_VVP := sim/build/tb_$(SIM_PINSET)_$(SIM_PULL).vvp
.PHONY: sim
sim: $(SIM_VVP)
$(SIM_VVP): sim/tb.v src/$(TARGET)/top.v src/$(TARGET)/pins.csv sim/gen_defines.py host/slogic_probe.py
	mkdir -p sim/build
	python3 sim/gen_defines.py $(SIM_PINSET) $(SIM_PULL) > sim/build/defines_$(SIM_PINSET)_$(SIM_PULL).v
	iverilog -g2012 -o $@ sim/build/defines_$(SIM_PINSET)_$(SIM_PULL).v sim/tb.v src/$(TARGET)/top.v
