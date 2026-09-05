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

BRIDGE = obj_dir/nvme_tcp_bridge

VERILATOR_FLAGS = --cc --exe --build -j 8 -O2 --top-module NvmeCore \
	-GLBA_COUNT=$(LBA_COUNT) \
	-CFLAGS "-O2 -DSIM_LBA_COUNT=$(LBA_COUNT)" \
	-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

.PHONY: all run smoke clean

all: $(BRIDGE)

$(BRIDGE): $(RTL) nvme_tcp_bridge.cpp
	verilator $(VERILATOR_FLAGS) $(RTL) nvme_tcp_bridge.cpp -o nvme_tcp_bridge

run: $(BRIDGE)
	$(BRIDGE) $(PORT)

smoke: $(BRIDGE)
	./run_smoke.sh $(PORT)

clean:
	rm -rf obj_dir
