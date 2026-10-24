# Simulation of the Tang Primer 20K top (Verilator, --timing).
#   make        build and run (PASS / FAIL at the end)
#   make VCD=1  also dump tb.vcd
TOP_DIR := ..
DEP     := $(TOP_DIR)/dependencies
# packages first
RTL := $(DEP)/eth_mac/crc32.sv \
       $(filter-out %/crc32.sv,$(wildcard $(DEP)/eth_mac/*.sv)) \
       $(DEP)/hub75/hub75_lanes.sv \
       $(TOP_DIR)/src/common/eth_service.sv \
       $(TOP_DIR)/src/common/udp_video_writer.sv \
       $(TOP_DIR)/src/common/ethernet_hub75_core.sv \
       $(TOP_DIR)/src/tangprimer20k/top.sv
TB := rpll_hub75_sim.sv tb_tp20k.sv

VERILATOR ?= verilator
VFLAGS := --binary --timing -j 0 -O2 --top-module tb -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
          -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

RUN_ARGS :=
ifeq ($(VCD),1)
VFLAGS += --trace
RUN_ARGS += +vcd
endif

.PHONY: all run veryl clean
all: run

veryl:
	cd $(TOP_DIR) && veryl build

obj_dir/Vtb: veryl $(TB)
	$(VERILATOR) $(VFLAGS) $(RTL) $(TB) -o Vtb 2>&1 | tee build.log | grep -E "%Error|%Warning-(LATCH|COMBDLY|IMPLICIT)" || true
	test -x obj_dir/Vtb

run: obj_dir/Vtb
	obj_dir/Vtb $(RUN_ARGS) | tee run.log
	grep -q '^PASS' run.log

clean:
	rm -rf obj_dir build.log run.log tb.vcd
