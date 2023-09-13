.PHONY: all clean test view

all: test

clean: 
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil

xelab.pb: tb.sv ../axis_to_mii.sv ../mii_to_axis.sv ../prepend_preamble.sv
	xvlog -work work --sv tb.sv ../axis_to_mii.sv ../mii_to_axis.sv ../prepend_preamble.sv
	xelab -L work tb -debug all

compile: xelab.pb

test: xelab.pb
	xsim tb --onfinish quit --tclbatch ./test.tcl --wdb test.wdb | tee test.log
	if grep Error test.log; then echo "Error."; exit 1; fi
view: test.wdb
	vivado ./test.wdb&
