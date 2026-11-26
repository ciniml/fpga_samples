# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# make unit   : directed SV test (tb_cart_unit)
# make boot   : GameCart AUTO_BOOT with QspiRom and a flash model (tb_game_boot)
# make boot_cam: the same with a camera cartridge and GbCamera (a shot from the console side)
# make camera : GbCamera shots against gb_camera_ref.py (tb_gb_camera)
# make simexe : Verilator model with a stdin/stdout byte stream, for util/chromatic_cart_dump --sim
#               (MBC / ROM_CODE / MBC1M / BAD_HDR / RAM_CODE / EEP_WORDS select the cartridge)
VERYL_SV := ../cart_power.sv ../cart_bus.sv ../mbc7_eeprom.sv ../flash_engine.sv ../cart_cmd.sv
VFLAGS := --timing -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-INITIALDLY -Wno-UNOPTFLAT
MBC ?= 5
ROM_CODE ?= 5
MBC1M ?= 0
BAD_HDR ?= 0
RAM_CODE ?= 0
EEP_WORDS ?= 128
FLASH ?= 0
SIMDIR := obj_sim_mbc$(MBC)_r$(ROM_CODE)_m$(MBC1M)_h$(BAD_HDR)_s$(RAM_CODE)$(if $(filter-out 128,$(EEP_WORDS)),_e$(EEP_WORDS))$(if $(filter 1,$(FLASH)),_f)

.PHONY: unit boot boot_cam camera simexe clean
unit: $(VERYL_SV)
	verilator --binary $(VFLAGS) --verilate-jobs 1 --build-jobs 0 --top-module tb_cart_unit -Mdir obj_unit $(VERYL_SV) gb_cart_model.sv cart_sim_top.sv tb_cart_unit.sv
	./obj_unit/Vtb_cart_unit

boot: ../game_cart.sv ../qspi_rom.sv
	verilator --binary $(VFLAGS) --verilate-jobs 1 --build-jobs 0 --top-module tb_game_boot -Mdir obj_boot ../game_cart.sv ../qspi_rom.sv tb_game_boot.sv
	./obj_boot/Vtb_game_boot

boot_cam: ../game_cart.sv ../qspi_rom.sv ../gb_camera.sv
	verilator --binary $(VFLAGS) --verilate-jobs 1 --build-jobs 0 +define+CAMERA --top-module tb_game_boot -Mdir obj_boot_cam ../game_cart.sv ../qspi_rom.sv ../gb_camera.sv tb_game_boot.sv
	./obj_boot_cam/Vtb_game_boot

camera: ../gb_camera.sv
	python3 gb_camera_ref.py gen cam_in.hex
	verilator --binary $(VFLAGS) --verilate-jobs 1 --build-jobs 0 --top-module tb_gb_camera -Mdir obj_camera ../gb_camera.sv tb_gb_camera.sv
	./obj_camera/Vtb_gb_camera
	python3 gb_camera_ref.py check cam_in.hex cam_out.hex

simexe: $(VERYL_SV)
	verilator --cc --exe --build -O2 $(VFLAGS) --verilate-jobs 1 --build-jobs 0 --top-module cart_sim_top -Mdir $(SIMDIR) \
	  -GMBC=$(MBC) -GROM_CODE=$(ROM_CODE) -GMBC1M=$(MBC1M) -GBAD_HDR=$(BAD_HDR) -GRAM_CODE=$(RAM_CODE) -GEEP_WORDS=$(EEP_WORDS) -GFLASH=$(FLASH) \
	  $(VERYL_SV) gb_cart_model.sv cart_sim_top.sv sim_main.cpp -o cart_sim
	@echo "$(SIMDIR)/cart_sim"

$(VERYL_SV) ../game_cart.sv ../qspi_rom.sv ../gb_camera.sv: $(wildcard ../*.veryl)
	cd .. && veryl build

clean:
	rm -rf obj_unit obj_boot obj_boot_cam obj_camera obj_sim_*
