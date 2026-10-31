# Simulation of the board tops (Verilator, --timing).
#   make                        Tang Primer 20K (PASS / FAIL at the end)
#   make rxcard [IMPL=soft|gmt|ddr] DK_LED-RXCARD (GW3A), soft / GMT HUB75
#               stage or the DDR2 frame buffer (slot-level DDR2 model)
#               [TXS=1]         with TXC_SHIFTED (PHY model without TX delay)
#               [PROWS=2]       4 panels (128x128) instead of 6 (128x192)
#   make VCD=1                  also dump tb.vcd
TOP_DIR := ..
DEP     := $(TOP_DIR)/dependencies
# packages first
RTL := $(DEP)/eth_mac/crc32.sv \
       $(filter-out %/crc32.sv,$(wildcard $(DEP)/eth_mac/*.sv)) \
       $(DEP)/hub75/hub75_lanes.sv \
       $(DEP)/hub75/hub75_planes.sv \
       $(DEP)/hub75/hub75_row_lanes.sv \
       $(TOP_DIR)/src/common/eth_service.sv \
       $(TOP_DIR)/src/common/udp_video_writer.sv \
       $(TOP_DIR)/src/common/gmt_corner_turn.sv \
       $(TOP_DIR)/src/common/fb_afifo.sv \
       $(TOP_DIR)/src/common/ddr_fb.sv \
       $(TOP_DIR)/src/common/ethernet_hub75_core.sv
TB := gw3a_sim.sv rpll_hub75_sim.sv $(TOP_DIR)/src/tangprimer20k/top.sv tb_tp20k.sv

IMPL ?= soft
TXS ?= 0
PROWS ?= 3
RXCARD_OBJ := obj_rxcard_$(IMPL)$(if $(filter 1,$(TXS)),_txs)$(if $(filter 2,$(PROWS)),_4p)
RXCARD_G   := $(if $(filter gmt,$(IMPL)),1,$(if $(filter ddr,$(IMPL)),2,0))
# the DDR2 PHY is replaced by ddr2_phy_sim.sv (slot-level model)
RXCARD_TB  := ethernet_hub75_cfg.sv gw3a_sim.sv \
              $(DEP)/ddr2/ddr2_ctrl.sv $(TOP_DIR)/../../rtl/ddr2/test/ddr2_model.sv ddr2_phy_sim.sv \
              $(TOP_DIR)/src/dk_led_rxcard_gw3a20/rtl8211e_init.sv \
              $(TOP_DIR)/src/dk_led_rxcard_gw3a20/top.sv tb_rxcard.sv

VERILATOR ?= verilator
VFLAGS := --binary --timing -j 0 -O2 --top-module tb -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
          -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

RUN_ARGS :=
ifeq ($(VCD),1)
VFLAGS += --trace
RUN_ARGS += +vcd
endif

.PHONY: all run rxcard veryl clean
all: run

veryl:
	cd $(TOP_DIR) && veryl build

obj_dir/Vtb: veryl $(TB)
	$(VERILATOR) $(VFLAGS) $(RTL) $(TB) -o Vtb 2>&1 | tee build.log | grep -E "%Error|%Warning-(LATCH|COMBDLY|IMPLICIT)" || true
	test -x obj_dir/Vtb

run: obj_dir/Vtb
	obj_dir/Vtb $(RUN_ARGS) | tee run.log
	grep -q '^PASS' run.log

$(RXCARD_OBJ)/Vtb: veryl $(RXCARD_TB)
	$(VERILATOR) $(VFLAGS) -GIMPL=$(RXCARD_G) -GTXS=$(TXS) -GPROWS=$(PROWS) --Mdir $(RXCARD_OBJ) $(RTL) $(RXCARD_TB) -o Vtb 2>&1 | tee build_rxcard_$(IMPL).log | grep -E "%Error|%Warning-(LATCH|COMBDLY|IMPLICIT)" || true
	test -x $(RXCARD_OBJ)/Vtb

rxcard: $(RXCARD_OBJ)/Vtb
	$(RXCARD_OBJ)/Vtb $(RUN_ARGS) | tee run_$(RXCARD_OBJ).log
	grep -q '^PASS' run_$(RXCARD_OBJ).log

clean:
	rm -rf obj_dir obj_rxcard_* build*.log run*.log tb.vcd
