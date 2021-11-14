BITSTREAM := impl/pnr/cpu_stopwatch.fs
SRCS := $(wildcard src/*.cst) $(wildcard src/*.sdc) $(wildcard src/*.sv) ../../external/picorv32/picorv32.v project.tcl src/sw/bootrom.hex
DEVICE ?= GW1N-4B

include ../build_gowin.mk

src/sw/bootrom.hex: src/sw/bootrom.c src/sw/link.ld src/sw/Makefile
	cd src/sw; make