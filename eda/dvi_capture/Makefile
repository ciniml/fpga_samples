PROJECT_NAME := dvi_capture

TARGET ?= tangprimer25k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl

include ../build_gowin.mk
