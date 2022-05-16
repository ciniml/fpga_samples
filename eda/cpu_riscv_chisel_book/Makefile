PROJECT_NAME := cpu_riscv_chisel_book
SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) ../../external/riscv-chisel-book/chisel-template/rtl/riscv/riscv.v project.tcl src/sw/bootrom.hex

include ../build_gowin.mk

../../external/riscv-chisel-book/chisel-template:
	git submodule update --init --recursive

../../external/riscv-chisel-book/chisel-template/rtl/riscv/riscv.v: ../../external/riscv-chisel-book/chisel-template
	cd ../../external/riscv-chisel-book/chisel-template && sbt "runMain fpga.Elaborate"

src/sw/bootrom.hex: src/sw/bootrom.c src/sw/link.ld src/sw/Makefile
	cd src/sw; make