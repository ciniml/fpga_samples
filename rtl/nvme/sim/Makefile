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

# vfio-user bridge: needs libvfio-user (built from source; json-c comes
# from the system). Point VFU_PREFIX at its install prefix - both the
# plain and the meson (include/vfio-user, lib/<multiarch>) layouts work.
VFU_PREFIX ?= $(HOME)/opt/vfu
VFU_INC := $(firstword $(wildcard $(VFU_PREFIX)/include/vfio-user $(VFU_PREFIX)/include))
VFU_LIB := $(firstword $(wildcard $(VFU_PREFIX)/lib/x86_64-linux-gnu/libvfio-user.a $(VFU_PREFIX)/lib/libvfio-user.a))
VFIO_BRIDGE = obj_vfio/nvme_vfio_bridge

VERILATOR_FLAGS = --cc --exe --build -j 8 -O2 --top-module NvmeCore \
	-GLBA_COUNT=$(LBA_COUNT) \
	-CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT)" \
	-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

RTL_TCP = $(RTL) ../nvme_tcp_pkg.sv ../nvme_tcp_target.sv
TCP_RTL_BRIDGE = obj_tcp/nvme_tcp_rtl_bridge

.PHONY: all vfio tcp_rtl run smoke clean

all: $(BRIDGE)

vfio: $(VFIO_BRIDGE)

tcp_rtl: $(TCP_RTL_BRIDGE)

$(TCP_RTL_BRIDGE): $(RTL_TCP) nvme_tcp_rtl_bridge.cpp
	verilator --cc --exe --build -j 8 -O2 --top-module NvmeTcpTarget --Mdir obj_tcp \
	  -GLBA_COUNT=$(LBA_COUNT) \
	  -CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT)" \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
	  $(RTL_TCP) nvme_tcp_rtl_bridge.cpp -o nvme_tcp_rtl_bridge

$(BRIDGE): $(RTL) nvme_tcp_bridge.cpp
	verilator $(VERILATOR_FLAGS) $(RTL) nvme_tcp_bridge.cpp -o nvme_tcp_bridge

$(VFIO_BRIDGE): $(RTL_CTRL) nvme_vfio_bridge.cpp
	verilator --cc --exe --build -j 8 -O2 --top-module NvmeController --Mdir obj_vfio \
	  -GLBA_COUNT=$(LBA_COUNT) \
	  -CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT) -I$(VFU_INC)" \
	  -LDFLAGS "$(VFU_LIB) -ljson-c" \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
	  $(RTL_CTRL) nvme_vfio_bridge.cpp -o nvme_vfio_bridge

run: $(BRIDGE)
	$(BRIDGE) $(PORT)

smoke: $(BRIDGE)
	./run_smoke.sh $(PORT)

clean:
	rm -rf obj_dir obj_vfio obj_tcp
