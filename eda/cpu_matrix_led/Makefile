PROJECT_NAME := cpu_stopwatch
SRCS := $(wildcard src/$(TARGET)/*.cst) $(wildcard src/$(TARGET)/*.sdc) $(wildcard src/$(TARGET)/*.sv) ../../external/picorv32/picorv32.v project.tcl src/sw/bootrom.hex

include ../build_gowin.mk

src/sw/bootrom.hex: src/sw/bootrom.c src/sw/link.ld src/sw/Makefile
	cd src/sw; make