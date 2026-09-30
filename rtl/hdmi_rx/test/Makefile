# HDMI audio path: word stream -> dvi_in -> packets -> audio -> delta-sigma.
RTL  := ../..
SRCS := tb_hdmi_audio.sv $(RTL)/dvi_in/dvi_in.sv $(RTL)/dvi_out/dvi_out.sv \
        ../hdmi_packet_rx.sv ../hdmi_audio_rx.sv ../delta_sigma_dac.sv

.PHONY: all sim clean
all: sim

sim: $(SRCS) analyze.py
	verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style --Mdir obj_dir -o simv \
	    --top-module tb_hdmi_audio $(SRCS) > obj_dir.log 2>&1 || (tail -30 obj_dir.log; false)
	./obj_dir/simv
	python3 analyze.py dac_left.txt

$(RTL)/dvi_in/dvi_in.sv: $(RTL)/dvi_in/dvi_in.veryl
	cd $(RTL)/dvi_in && veryl build
$(RTL)/dvi_out/dvi_out.sv: $(RTL)/dvi_out/dvi_out.veryl
	cd $(RTL)/dvi_out && veryl build

clean:
	rm -rf obj_dir obj_dir.log dac_left.txt
