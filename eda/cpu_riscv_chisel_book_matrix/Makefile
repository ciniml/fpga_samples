PROJECT_NAME := cpu_riscv_chisel_book

CHISEL_TEMPLATE_DIR ?= ../../external/riscv-chisel-book/chisel-template
RTL_DIR ?= $(abspath ../../rtl)
ROOT_DIR ?= $(abspath ../..)

ifeq ($(TARGET),comprocboard_9k)
RISCV_ELABORATE := system.ElaborateCpuRiscvChiselBookMatrix_TangNano9K
RISCV_ELABORATE_OUTPUT_DIR := $(RTL_DIR)/cpu_riscv_chisel_book_matrix/tangnano9k
endif

RISCV_CORE_SRC := $(RISCV_ELABORATE_OUTPUT_DIR)/riscv.v
PROJECT_ADDITIONAL_ARGS := $(abspath $(RISCV_CORE_SRC))
PROJECT_ADDITIONAL_CLEAN := $(RISCV_CORE_SRC)

SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) $(RISCV_CORE_SRC) project.tcl src/sw/bootrom.hex

include ../build_gowin.mk

$(CHISEL_TEMPLATE_DIR):
	git submodule update --init --recursive

$(RISCV_CORE_SRC): $(CHISEL_TEMPLATE_DIR)
	cd $(ROOT_DIR) && sbt "project fpga_samples; runMain $(RISCV_ELABORATE)"

src/sw/bootrom.hex: src/sw/bootrom.c src/sw/link.ld src/sw/Makefile
	cd src/sw; make