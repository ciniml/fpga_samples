.PHONY: all clean test

# The legacy tb_probe.sv here predates the per-directory Veryl projects:
# it references the old `fpga_samples_` module prefix and the removed
# `fpga_samples_axi4s` interface, and it was not self-checking. It is
# superseded by the Veryl testbench (../tb_probe.veryl: probe_capture /
# probe_width_conv), which verifies the capture window, re-arming,
# trigger latching, tlast placement and the 7-bit width conversion.
# This Makefile now just delegates there.

all: test

test:
	cd .. && veryl test

clean:
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil
	-@$(RM) -r run-*
