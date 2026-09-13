PROJECT_NAME := easycdr_bert

TARGET ?= tangprimer25k

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) \
        $(wildcard ../../rtl/bert/*.sv) $(wildcard ../../rtl/oscdr/*.sv) project.tcl

include ../build_gowin.mk
