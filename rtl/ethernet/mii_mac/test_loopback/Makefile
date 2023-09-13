.PHONY: all clean compile test view

MODULES :=  ../crc_mac.sv \
			../append_crc.sv \
			../remove_crc.sv \
			../mii_mac_rx.sv \
			../mii_mac_tx.sv \
			../../mii_axis/axis_to_mii.sv \
			../../mii_axis/prepend_preamble.sv \
			../../mii_axis/mii_to_axis.sv \
			../../util/simple_fifo.v \
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
