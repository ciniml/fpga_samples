PROJECT_NAME := easycdr_bert

TARGET ?= tangprimer25k

# variants get their own build directory
BUILD_SUFFIX :=
ifeq ($(USE_EASYCDR_IP),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_ip
export USE_EASYCDR_IP
endif
ifeq ($(DYN_DLY1),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_dyn1
export DYN_DLY1
endif
ifeq ($(DYN_DLY0),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_dyn0
export DYN_DLY0
endif
ifeq ($(ADAPT_DLY1),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_adapt1
export ADAPT_DLY1
endif
ifeq ($(IODLY_TEST),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_iodly
export IODLY_TEST
ifeq ($(IODLY_DYN),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)dyn
export IODLY_DYN
endif
ifneq ($(IODLY_STATIC),)
BUILD_SUFFIX := $(BUILD_SUFFIX)s$(IODLY_STATIC)
export IODLY_STATIC
endif
endif

SRCS := src/$(TARGET)/pins.cst $(wildcard src/$(TARGET)/*.sdc) \
        $(wildcard src/$(TARGET)/*.v) $(wildcard src/$(TARGET)/*/*.v) \
        $(wildcard ../../rtl/bert/*.sv) $(wildcard ../../rtl/oscdr/*.sv) project.tcl

include ../build_gowin.mk
