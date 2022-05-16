PROJECT_NAME := cpu_riscv_chisel_book

CHISEL_TEMPLATE_DIR ?= ../../external/riscv-chisel-book/chisel-template

ifeq ($(TARGET),runber)
RISCV_ELABORATE := fpga.ElaborateRunber
RISCV_ELABORATE_OUTPUT_DIR := $(CHISEL_TEMPLATE_DIR)/rtl/riscv_runber
endif
ifeq ($(TARGET),tangnano9k)
RISCV_ELABORATE := fpga.ElaborateTangNano9K
RISCV_ELABORATE_OUTPUT_DIR := $(CHISEL_TEMPLATE_DIR)/rtl/riscv_tangnano9k
endif
ifeq ($(TARGET),comprocboard_9k)
RISCV_ELABORATE := fpga.ElaborateTangNano9K
RISCV_ELABORATE_OUTPUT_DIR := $(CHISEL_TEMPLATE_DIR)/rtl/riscv_tangnano9k
endif

RISCV_CORE_SRC := $(RISCV_ELABORATE_OUTPUT_DIR)/riscv.v
PROJECT_ADDITIONAL_ARGS := $(abspath $(RISCV_CORE_SRC))

SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) $(RISCV_CORE_SRC) project.tcl src/sw/bootrom.hex

include ../build_gowin.mk

$(CHISEL_TEMPLATE_DIR):
	git submodule update --init --recursive

$(RISCV_CORE_SRC): $(CHISEL_TEMPLATE_DIR)
	cd $(CHISEL_TEMPLATE_DIR) && sbt "runMain $(RISCV_ELABORATE)"

src/sw/bootrom.hex: src/sw/bootrom.c src/sw/link.ld src/sw/Makefile
	cd src/sw; make