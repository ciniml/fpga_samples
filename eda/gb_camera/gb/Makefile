# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Viewfinder ROM for eda/gb_camera (GBDK-2020, CGB only), a Game Boy Camera style cartridge:
# cartridge type FCh (mapper 6 of GameCart), 32 KiB ROM, 32 KiB RAM.
#
#   make        build/gbcam.gbc
#   make run    SameBoy (it emulates the camera with a noise image when there is no webcam)
#   make shot   headless SameBoy, PNG screenshots in shots/
GBDEV_HOME ?= $(HOME)/opt/gbdev
GBDK_HOME  ?= $(GBDEV_HOME)/gbdk/
LCC        := $(GBDK_HOME)bin/lcc
SAMEBOY    ?= $(GBDEV_HOME)/bin/sameboy
GBSHOT     ?= $(GBDEV_HOME)/bin/gbshot

LCCFLAGS := -Wm-yC -Wl-yt0xFC -Wl-ya4 -Wm-yn"GBCAMERA" -Wf--opt-code-speed
ROM      := build/gbcam.gbc
SRC      := $(wildcard src/*.c)

SHOT_FRAMES ?= 600
SHOT_AT     ?= 120,300,560
SHOT_INPUT  ?= 200:UP;204:;250:A;254:;400:START;404:

all: $(ROM)
$(ROM): $(SRC) $(wildcard src/*.h)
	@mkdir -p build
	$(LCC) $(LCCFLAGS) -o $@ $(SRC)
run: $(ROM)
	$(SAMEBOY) $(ROM)
shot: $(ROM)
	@mkdir -p shots
	$(GBSHOT) --frames $(SHOT_FRAMES) --shot $(SHOT_AT) --input "$(SHOT_INPUT)" -o shots/cgb $(ROM)
clean:
	rm -rf build shots
.PHONY: all run shot clean
