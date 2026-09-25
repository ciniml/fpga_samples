PROJECT_NAME := easycdr_bert

TARGET ?= tangprimer25k

# variants get their own build directory
BUILD_SUFFIX :=
ifeq ($(USE_EASYCDR_IP),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_ip
export USE_EASYCDR_IP
endif
# RATE=1200M / 1400M / 1487M5 / 1600M: line-rate variants of the IP receiver (BER vs rate)
ifneq ($(RATE),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_$(shell echo $(RATE) | tr A-Z a-z)
export RATE
endif
# DELAY1=<taps>: override the IP DELAY_1 (with USE_EASYCDR_IP=1), e.g. a sweep at one RATE
ifneq ($(DELAY1),)
BUILD_SUFFIX := $(BUILD_SUFFIX)_d$(DELAY1)
export DELAY1
endif
# TX_TLVDS=1: true LVDS (TLVDS_OBUF / LVDS25) on the serial output instead of emulated LVPECL33E
# TX_DIRECT=1: serial output on pmod0 pins 1/7 (F5/G5), direct wire to pmod2 (no modules / USB-C)
ifeq ($(TX_DIRECT),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_direct
export TX_DIRECT
endif
ifeq ($(TX_TLVDS),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)_tlvds
export TX_TLVDS
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
ifeq ($(IODLY_ADAPT),1)
BUILD_SUFFIX := $(BUILD_SUFFIX)adapt
export IODLY_ADAPT
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
