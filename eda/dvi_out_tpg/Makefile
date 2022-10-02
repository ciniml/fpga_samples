PROJECT_NAME := dvi_out_tpg

TARGET ?= tangnano9k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

PROJECT_ADDITIONAL_ARGS := $(abspath src/cq_logo.hex)

SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) project.tcl $(RTL_DIR)/dvi_out/dvi_out.sv $(RTL_DIR)/video/test_pattern_generator.sv

include ../build_gowin.mk