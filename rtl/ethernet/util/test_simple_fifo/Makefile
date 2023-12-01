.PHONY: all clean compile test view

MODULES := ../simple_fifo.v ../axis_if.sv

all: test

clean: 
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil

xelab.pb: tb.sv $(MODULES)
	xvlog -work work --sv tb.sv $(MODULES)
	xelab -L work tb -debug all

compile: xelab.pb

test: xelab.pb
	xsim tb --onfinish quit --tclbatch ./test.tcl --wdb test.wdb | tee test.log
	if grep Error test.log; then echo "Error."; exit 1; fi

view: test.wdb
	vivado ./test.wdb&
