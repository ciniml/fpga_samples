.PHONY: all clean compile test view

MODULES := ../align_frame.sv \
			../append_crc.sv \
			../prepend_preamble.sv \
			../remove_crc.sv \
			../xg_mac_rx.sv \
			../xg_mac_tx.sv \
			../../xgmii_axis/axis_to_xgmii.v \
			../../xgmii_axis/axis_to_xgmii_preamble.sv \
			../../xgmii_axis/xgmii_to_axis.v \
			../../util/simple_fifo.v \
			../../crc/crc_mac.v \
			../../util/axis_if.sv

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
