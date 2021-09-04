.PHONY: all clean test view

all: test

clean:
	-@$(RM) *.vcd testbench

test: testbench
	./testbench

testbench: tb.sv ../i2c_slave.sv ../iobuf_sim.sv
	@echo Compiling testbench
	iverilog -g2005-sv $^ -o $@

output.vcd: testbench
	./testbench

view: output.vcd
	gtkwave output.vcd&
