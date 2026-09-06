# Simulation helpers for the GowinPsram controller.
# The tests need the Gowin ODDR/IDDR simulation models, which are extracted
# from the Gowin IDE installation (not redistributed) into test/gen/.
GOWIN_SIMLIB ?= $(HOME)/gowin/1.9.10.03_edu/IDE/simlib/gw1n/prim_sim.v
PRIM_SV := test/gen/gowin_prim_sim.sv

.PHONY: all prim test clean

all: prim
	veryl build

prim: $(PRIM_SV)

$(PRIM_SV): $(GOWIN_SIMLIB)
	mkdir -p test/gen
	{ echo '// Extracted from $(GOWIN_SIMLIB) by rtl/gowin_psram/Makefile; not for redistribution.'; \
	  echo '`timescale 1ns/1ps'; \
	  sed -n '/^module IDDR(/,/^endmodule/p' $(GOWIN_SIMLIB); \
	  sed -n '/^module ODDR (/,/^endmodule/p' $(GOWIN_SIMLIB); } \
	| sed 's/GSR\.GSRO/1'"'"'b1/' \
	| awk '/always @\(gsrt\)/ {skip=1} skip==0 {print} skip==1 && /^end$$/ {skip=0}' > $@

test: prim
	veryl test

clean:
	veryl clean
	rm -rf test/gen
