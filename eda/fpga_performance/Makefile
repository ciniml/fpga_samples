PROJECT_NAME := fpga_performance

TARGET ?= tangprimer20k
ROOT_DIR ?= $(abspath ../..)
RTL_DIR ?= $(ROOT_DIR)/rtl

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) $(wildcard src/*.sv) project.tcl

ifeq ($(TARGET),tangmega138k_10gbe)
PROJECT_TCL := $(abspath src/$(TARGET)/project.tcl)
endif

include ../build_gowin.mk