.PHONY: all clean synthesis run deploy

DEVICE ?= $(DEVICE_FAMILY)
PROGRAMMER_CLI_DIR ?= $(dir $(shell which programmer_cli))
PROGRAMMER_CABLE ?=
USE_OPENFPGA_LOADER ?= 0
OPENFPGA_LOADER ?= $(shell which openFPGALoader)

all: synthesis

$(BITSTREAM): $(SRCS)
	mkdir -p build/$(TARGET) && cd build/$(TARGET) && gw_sh ../../project.tcl $(SRC_DIR) $(RTL_DIR) $(TARGET) $(DEVICE_FAMILY) $(DEVICE_PART) 

synthesis: $(BITSTREAM)

scan-cables:
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli --scan-cables

scan:
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli --scan

run: $(BITSTREAM)
ifeq ($(USE_OPENFPGA_LOADER),0)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli $(PROGRAMMER_CABLE) --device $(DEVICE) --run 2 --fsFile $(abspath $(BITSTREAM))
else
	$(OPENFPGA_LOADER) $(OPENFPGA_LOADER_TARGET) --write-sram $(abspath $(BITSTREAM))
endif

deploy: $(BITSTREAM)
ifeq ($(USE_OPENFPGA_LOADER),0)
	if lsmod | grep ftdi_sio; then sudo modprobe -r ftdi_sio; fi
	cd $(PROGRAMMER_CLI_DIR); ./programmer_cli $(PROGRAMMER_CABLE) --device $(DEVICE) --run 6 --fsFile $(abspath $(BITSTREAM))
else
	$(OPENFPGA_LOADER) $(OPENFPGA_LOADER_TARGET) --write-flash $(abspath $(BITSTREAM))
endif