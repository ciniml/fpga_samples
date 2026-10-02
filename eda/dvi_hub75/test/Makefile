# Video -> crop_to_hub75 -> async FIFO -> Hub75 -> panel model.
# Targets: <W>x<H>[_b<bits>][_d<clkdiv>][_l<clk low extra>][_g<gamma x10>],
# e.g. 128x128_b6_d0_l1_g22 (colour tables start as gamma 2.2).
SRC  := ../src/tangprimer25k
RTL  := ../../../rtl
SRCS := tb_hub75_crop.sv $(SRC)/crop_to_hub75.sv $(SRC)/async_fifo.sv $(RTL)/hub75/hub75.sv
CONFIGS := 128x128 64x64 128x64 64x128 128x128_b6 64x64_b6 128x128_b6_d0 128x128_b6_d0_l1 128x128_b6_d0_l1_g22 128x128_b6_l1 128x128_b6_d0_l2 128x128_b6_d0_l3

.PHONY: all clean $(CONFIGS)
all: $(CONFIGS)

# $(call field,<config>,<prefix>,<default>)
field = $(or $(patsubst $(2)%,%,$(filter $(2)%,$(subst _, ,$(1)))),$(3))
size  = $(subst x, ,$(word 1,$(subst _, ,$(1))))

# gamma x10 from the _g field (22 -> 2.2), empty without one
gamma = $(if $(call field,$(1),g,),$(shell echo $(call field,$(1),g,) | sed 's/\(.\)$$/.\1/'))

$(CONFIGS):
	$(if $(call gamma,$@),python3 ../gen_lut_init.py --gamma $(call gamma,$@) --bits $(call field,$@,b,5) --out obj_$@_lut_init_rom.sv)
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --Mdir obj_$@ -o simv \
	    -DDISP_W=$(word 1,$(call size,$@)) -DDISP_H=$(word 2,$(call size,$@)) \
	    -DCB=$(call field,$@,b,5) -DCLKDIV=$(call field,$@,d,1) -DCLKLOW=$(call field,$@,l,0) \
	    $(if $(call gamma,$@),-DLUT_INIT_GAMMA -DGAMMA_REAL=$(call gamma,$@) obj_$@_lut_init_rom.sv) \
	    --top-module tb_hub75_crop $(SRCS) > obj_$@.log 2>&1 || (tail -20 obj_$@.log; false)
	./obj_$@/simv

clean:
	rm -rf obj_* *.log
