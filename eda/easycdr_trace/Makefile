PROJECT_NAME := easycdr_trace

TARGET ?= tangprimer25k

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) \
        ../../rtl/displayport/src/encoder_8b10b.sv project.tcl

include ../build_gowin.mk
