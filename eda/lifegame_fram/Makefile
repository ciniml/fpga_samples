TARGET ?= tangnano1k
SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) ../../rtl//chisel/lifegame_fram/lifegame_fram.v project.tcl
BITSTREAM := build/$(TARGET)/impl/pnr/lifegame_fram.fs
SRC_DIR := $(abspath src/$(TARGET))
RTL_DIR := $(abspath ../../rtl)

include src/$(TARGET)/target.mk
include ../build_gowin.mk

clean:
	-@$(RM) -rf build/$(TARGET)