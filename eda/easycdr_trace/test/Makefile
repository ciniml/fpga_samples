# Verilator end-to-end test of the control path (no device primitives).
RTL := ../../../rtl
SRCS := e2e_ctrl_tb.sv trace_map_rom.v \
        $(RTL)/trace/easycdr_trace_tx.sv $(RTL)/trace/tx_link_core.sv \
        $(RTL)/trace/trace_cdc.sv $(RTL)/trace/trace_afifo.sv \
        $(RTL)/trace/trace_frontend.sv $(RTL)/trace/trace_link_tx.sv \
        $(RTL)/manchester/pulse_reset_tx.sv \
        $(RTL)/trace/trace_rx_decoder.sv $(RTL)/trace/trace_capture.sv \
        $(RTL)/trace/trace_link_diag.sv \
        $(RTL)/displayport/src/encoder_8b10b.sv $(RTL)/displayport/src/decoder_8b10b.sv \
        $(RTL)/manchester/manchester_tx.sv $(RTL)/manchester/manchester_rx.sv \
        $(RTL)/manchester/ctrl_frame_rx.sv $(RTL)/manchester/trace_ctrl_regs.sv

VFLAGS := --binary --timing --assert -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	  -Wno-CASEINCOMPLETE -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-PINMISSING \
	  -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM -Wno-MULTITOP \
	  --top-module e2e_ctrl_tb

# sample clock 27MHz (Nano9K demo) and 100MHz (same rate as the link clock)
trace_map_rom.v: ../maps/nano9k_demo.map ../host/tracemap.py
	python3 ../host/tracemap.py ../maps/nano9k_demo.map --rom $@

TRACE_VERYL_SV := $(RTL)/trace/tx_link_core.sv $(RTL)/trace/trace_link_tx.sv $(RTL)/trace/trace_frontend.sv \
                  $(RTL)/trace/trace_cdc.sv $(RTL)/trace/trace_afifo.sv $(RTL)/trace/easycdr_trace_tx.sv \
                  $(RTL)/trace/trace_rx_decoder.sv $(RTL)/trace/trace_link_diag.sv $(RTL)/trace/trace_sym_inject.sv $(RTL)/trace/trace_capture.sv
$(TRACE_VERYL_SV): $(wildcard $(RTL)/trace/*.veryl)
	cd $(RTL)/trace && veryl build

test: trace_map_rom.v $(TRACE_VERYL_SV)
	verilator $(VFLAGS) --Mdir obj_dir -o simv $(SRCS)
	./obj_dir/simv
	verilator $(VFLAGS) -GSCLK_PERIOD=10.0 --Mdir obj_dir_s100 -o simv $(SRCS)
	./obj_dir_s100/simv
	verilator $(VFLAGS) -GTX_WIDTH=32 --Mdir obj_dir_w32 -o simv $(SRCS)
	./obj_dir_w32/simv

clean:
	rm -rf obj_dir obj_dir_s100 obj_dir_w32 trace_map_rom.v
