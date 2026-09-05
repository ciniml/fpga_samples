# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
#
# NVMe/TCP bridge to the Verilated NvmeCore.
#   make            build obj_dir/nvme_tcp_bridge
#   make run        run the bridge on port 4420
#   make smoke      run the Python NVMe/TCP smoke test against the bridge

LBA_COUNT ?= 2048
PORT      ?= 4420

RTL = ../nvme_pkg.sv ../nvme_core.sv
RTL_CTRL = $(RTL) ../nvme_controller.sv

BRIDGE = obj_dir/nvme_tcp_bridge

# vfio-user bridge: needs libvfio-user (+ json-c). Point VFU_PREFIX at a
# prefix containing include/libvfio-user.h and lib/libvfio-user.a.
VFU_PREFIX ?= /usr/local
VFIO_BRIDGE = obj_vfio/nvme_vfio_bridge

VERILATOR_FLAGS = --cc --exe --build -j 8 -O2 --top-module NvmeCore \
	-GLBA_COUNT=$(LBA_COUNT) \
	-CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT)" \
	-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

.PHONY: all vfio run smoke clean

all: $(BRIDGE)

vfio: $(VFIO_BRIDGE)

$(BRIDGE): $(RTL) nvme_tcp_bridge.cpp
	verilator $(VERILATOR_FLAGS) $(RTL) nvme_tcp_bridge.cpp -o nvme_tcp_bridge

$(VFIO_BRIDGE): $(RTL_CTRL) nvme_vfio_bridge.cpp
	verilator --cc --exe --build -j 8 -O2 --top-module NvmeController --Mdir obj_vfio \
	  -GLBA_COUNT=$(LBA_COUNT) \
	  -CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT) -I$(VFU_PREFIX)/include" \
	  -LDFLAGS "$(VFU_PREFIX)/lib/libvfio-user.a $(VFU_PREFIX)/lib/libjson-c.a" \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
	  $(RTL_CTRL) nvme_vfio_bridge.cpp -o nvme_vfio_bridge

run: $(BRIDGE)
	$(BRIDGE) $(PORT)

smoke: $(BRIDGE)
	./run_smoke.sh $(PORT)

clean:
	rm -rf obj_dir obj_vfio
