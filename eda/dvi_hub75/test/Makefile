# Video -> crop_to_hub75 -> async FIFO -> Hub75 -> panel model, for each panel size.
SRC  := ../src/tangprimer25k
RTL  := ../../../rtl
SRCS := tb_hub75_crop.sv $(SRC)/crop_to_hub75.sv $(SRC)/async_fifo.sv $(RTL)/hub75/hub75.sv
SIZES := 128x128 64x64 128x64 64x128

.PHONY: all clean $(SIZES)
all: $(SIZES)

$(SIZES):
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --Mdir obj_$@ -o simv \
	    -DDISP_W=$(word 1,$(subst x, ,$@)) -DDISP_H=$(word 2,$(subst x, ,$@)) \
	    --top-module tb_hub75_crop $(SRCS) > obj_$@.log 2>&1 || (tail -20 obj_$@.log; false)
	./obj_$@/simv

clean:
	rm -rf obj_* *.log
