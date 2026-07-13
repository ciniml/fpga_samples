.PHONY: all clean test view

# The legacy tb.sv here compared dvi_out against the Chisel reference
# without compensating the reference's 3-stage video pipeline latency and
# relied on iverilog's non-fatal $error to "pass" anyway. It is superseded
# by the Veryl testbench (../tb_dvi_out.veryl, test dvi_out_equivalence),
# which handles the latency skew. This Makefile now just delegates there.
# (iverilog can no longer parse the generated SV either: Veryl 0.20+ emits
# `var` on port declarations.)

all: test

clean:
	-@$(RM) *.vcd testbench
	-@$(RM) -rf obj_dir

test:
	cd .. && veryl test

view: output.vcd
	gtkwave output.vcd&
