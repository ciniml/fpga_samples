.PHONY: all clean test view

all: test

clean:
	-@$(RM) *.vcd testbench

test: testbench
	./testbench

testbench: tb.sv ../dvi_out.sv ../dviout_chisel.v
	@echo Compiling testbench
	iverilog -g2005-sv $^ -o $@

output.vcd: testbench
	./testbench

view: output.vcd
	gtkwave output.vcd&
