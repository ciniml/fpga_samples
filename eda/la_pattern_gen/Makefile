PROJECT_NAME := la_pattern_gen

TARGET ?= tangprimer25k
# DIV: the pattern advances every DIV clocks of the 50 MHz oscillator (>= 2)
DIV ?= 2
STATIC ?=
export DIV STATIC
BUILD_SUFFIX := _div$(DIV)$(if $(filter 1,$(STATIC)),_static)

SRCS := $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*.cst) project.tcl

include ../build_gowin.mk
