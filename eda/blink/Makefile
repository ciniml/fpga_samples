TARGET ?= tangnano1k
SRCS := $(wildcard ../../rtl/blink/*.cst) $(wildcard src/*.cst) $(wildcard src/*.sdc) project.tcl
BITSTREAM := build/$(TARGET)/impl/pnr/blink.fs
SRC_DIR := $(abspath src/$(TARGET))
RTL_DIR := $(abspath ../../rtl)

include src/$(TARGET)/target.mk
include ../build_gowin.mk