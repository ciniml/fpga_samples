.PHONY: all clean synthesis run deploy

BITSTREAM := impl/pnr/stop_watch.fs
SRCS := $(wildcard src/*.cst) $(wildcard src/*.sdc) project.tcl
DEVICE ?= GW1N-4B

all: synthesis

$(BITSTREAM): $(SRCS)
	gw_sh ./project.tcl

synthesis: $(BITSTREAM)

run: $(BITSTREAM)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	programmer_cli --device $(DEVICE) --run 2 --fsFile $(abspath $(BITSTREAM))

deploy: $(BITSTREAM)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	programmer_cli --device $(DEVICE) --run 6 --fsFile $(abspath $(BITSTREAM))

clean:
	-@$(RM) -r impl
	-@$(RM) *.gprj *.user