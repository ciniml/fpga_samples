PROJECT_NAME := gowin_easycdr_1g2

TARGET ?= tangprimer25k

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.vhd) \
        $(wildcard src/$(TARGET)/*/*.v) project.tcl

include ../build_gowin.mk
