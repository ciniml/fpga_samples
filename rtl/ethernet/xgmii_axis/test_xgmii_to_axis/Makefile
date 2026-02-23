.PHONY: all clean test view

all: test

clean: 
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil

xelab.pb: tb.sv ../xgmii_to_axis.v
	xvlog -work work --sv tb.sv ../xgmii_to_axis.v
	xelab -L work tb -debug all

compile: xelab.pb

test: xelab.pb
	xsim tb --onfinish quit --tclbatch ./test.tcl --wdb test.wdb

view: test.wdb
	vivado ./test.wdb&
