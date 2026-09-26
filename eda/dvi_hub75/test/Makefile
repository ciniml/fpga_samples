# Video -> crop_to_hub75 -> async FIFO -> Hub75 -> panel model.
# Targets: <W>x<H>[_b<bits>][_d<clkdiv>], e.g. 128x128_b6_d0.
SRC  := ../src/tangprimer25k
RTL  := ../../../rtl
SRCS := tb_hub75_crop.sv $(SRC)/crop_to_hub75.sv $(SRC)/async_fifo.sv $(RTL)/hub75/hub75.sv
CONFIGS := 128x128 64x64 128x64 64x128 128x128_b6 64x64_b6 128x128_b6_d0

.PHONY: all clean $(CONFIGS)
all: $(CONFIGS)

# $(call field,<config>,<prefix>,<default>)
field = $(or $(patsubst $(2)%,%,$(filter $(2)%,$(subst _, ,$(1)))),$(3))
size  = $(subst x, ,$(word 1,$(subst _, ,$(1))))

$(CONFIGS):
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --Mdir obj_$@ -o simv \
	    -DDISP_W=$(word 1,$(call size,$@)) -DDISP_H=$(word 2,$(call size,$@)) \
	    -DCB=$(call field,$@,b,5) -DCLKDIV=$(call field,$@,d,1) \
	    --top-module tb_hub75_crop $(SRCS) > obj_$@.log 2>&1 || (tail -20 obj_$@.log; false)
	./obj_$@/simv

clean:
	rm -rf obj_* *.log
