.PHONY: all clean test view

all: test

clean: 
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil

xvlog.pb: tb.sv ../xgmii_to_axis.v ../axis_to_xgmii.v
	xvlog -work work --sv tb.sv ../axis_to_xgmii.v ../xgmii_to_axis.v

xsim.dir/work.test_shift0: xvlog.pb
	xelab -L work test_shift0 -debug all
xsim.dir/work.test_shift4: xvlog.pb
	xelab -L work test_shift4 -debug all

compile: xelab.pb

test_shift0: xsim.dir/work.test_shift0
	xsim test_shift0 --onfinish quit --tclbatch ./test.tcl --wdb test_shift0.wdb
test_shift4: xsim.dir/work.test_shift4
	xsim test_shift4 --onfinish quit --tclbatch ./test.tcl --wdb test_shift4.wdb

test: test_shift0 test_shift4

view_shift0: test_shift0.wdb
	vivado ./test_shift0.wdb&
view_shift4: test_shift4.wdb
	vivado ./test_shift4.wdb&