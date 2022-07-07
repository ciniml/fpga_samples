.PHONY: all clean test view

SIM_SRCS := tb.sv ./iobuf_sim.sv ../top.sv ../../../../../rtl/cpu_riscv_chisel_book_matrix/tangnano9k/riscv.v
BOOTROM := ../../sw/bootrom.hex

all: test

clean:
	-@$(RM) *.vcd testbench

test: testbench
	./testbench

testbench: $(SIM_SRCS) $(BOOTROM)
	@echo Compiling testbench
	iverilog -g2012 $(SIM_SRCS) -o $@ -D BOOTROM_PATH=\"$(abspath $(BOOTROM))\"

$(BOOTROM): ../../sw/bootrom.c
	cd ../../..; make TARGET=comprocboard_9k src/sw/bootrom.hex

output.vcd: testbench
	./testbench > /dev/null 2>&1 

view: output.vcd
	gtkwave output.vcd&
