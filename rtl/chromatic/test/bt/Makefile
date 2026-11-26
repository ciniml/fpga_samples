# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# make simexe: both ends of the cartridge bus test (bt_sim_top) as a process for util/chromatic_bustest --sim
VERYL_SV := ../../bt_pkg.sv ../../cart_power.sv ../../test_bus.sv ../../bus_test.sv ../../bt_cmd.sv ../../cart_target.sv
VFLAGS := --timing -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-INITIALDLY -Wno-UNOPTFLAT

.PHONY: simexe clean
simexe: $(VERYL_SV)
	verilator --cc --exe --build -O2 $(VFLAGS) --verilate-jobs 1 --build-jobs 0 --top-module bt_sim_top -Mdir obj_bt \
	  $(VERYL_SV) bt_sim_top.sv $(CURDIR)/bt_sim_main.cpp -o bt_sim
	@echo obj_bt/bt_sim

$(VERYL_SV): $(wildcard ../../*.veryl)
	cd ../.. && veryl build

clean:
	rm -rf obj_bt
