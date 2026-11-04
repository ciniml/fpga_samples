# Ddr2Ctrl unit test (Verilator --timing): make [CL=3|4|5|6] [VCD=1]
TOP_DIR := ..
CL ?= 4
OBJ := obj_cl$(CL)

VERILATOR ?= verilator
VFLAGS := --binary --timing -j 0 -O2 --top-module tb -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
          -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE

RUN_ARGS :=
ifeq ($(VCD),1)
VFLAGS += --trace
RUN_ARGS += +vcd
endif

.PHONY: all veryl clean
all: $(OBJ)/Vtb
	$(OBJ)/Vtb $(RUN_ARGS) | tee run_cl$(CL).log
	grep -q '^PASS' run_cl$(CL).log && ! grep -q 'MODEL FAIL' run_cl$(CL).log

veryl:
	cd $(TOP_DIR) && veryl build

$(OBJ)/Vtb: veryl ddr2_model.sv tb_ddr2.sv
	$(VERILATOR) $(VFLAGS) -GCL=$(CL) --Mdir $(OBJ) $(TOP_DIR)/ddr2_ctrl.sv ddr2_model.sv tb_ddr2.sv -o Vtb 2>&1 | tee build_cl$(CL).log | grep -E "%Error|%Warning-(LATCH|COMBDLY|IMPLICIT)" || true
	test -x $(OBJ)/Vtb

clean:
	rm -rf obj_* *.log *.vcd
