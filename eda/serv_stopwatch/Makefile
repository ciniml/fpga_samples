BITSTREAM := impl/pnr/i2c_slave.fs
SRCS := $(wildcard src/*.cst) \
		$(wildcard src/*.sdc) \
		$(wildcard src/*.sv) \
		$(wildcard ../../rtl/serv_soc/*.sv) \
		$(wildcard ../../external/serv/rtl/*.v) \
		src/top.sv \
		project.tcl
DEVICE ?= GW1N-4B

include ../build_gowin.mk