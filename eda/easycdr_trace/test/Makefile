# Verilator end-to-end test of the control path (no device primitives).
RTL := ../../../rtl
SRCS := e2e_ctrl_tb.sv \
        ../src/common/easycdr_trace_tx.v ../src/common/tx_link_core.v \
        ../src/common/trace_cdc.v ../src/common/trace_afifo.v \
        ../src/common/trace_frontend.v ../src/common/trace_link_tx.v \
        $(RTL)/manchester/pulse_reset_tx.sv \
        ../src/tangprimer25k/trace_rx_decoder.v ../src/tangprimer25k/trace_capture.v \
        $(RTL)/displayport/src/encoder_8b10b.sv $(RTL)/displayport/src/decoder_8b10b.sv \
        $(RTL)/manchester/manchester_tx.sv $(RTL)/manchester/manchester_rx.sv \
        $(RTL)/manchester/ctrl_frame_rx.sv $(RTL)/manchester/trace_ctrl_regs.sv

VFLAGS := --binary --timing --assert -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	  -Wno-CASEINCOMPLETE -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-PINMISSING \
	  -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM -Wno-MULTITOP \
	  --top-module e2e_ctrl_tb

# sample clock 27MHz (Nano9K demo) and 100MHz (same rate as the link clock)
test:
	verilator $(VFLAGS) --Mdir obj_dir -o simv $(SRCS)
	./obj_dir/simv
	verilator $(VFLAGS) -GSCLK_PERIOD=10.0 --Mdir obj_dir_s100 -o simv $(SRCS)
	./obj_dir_s100/simv
	verilator $(VFLAGS) -GTX_WIDTH=32 --Mdir obj_dir_w32 -o simv $(SRCS)
	./obj_dir_w32/simv

clean:
	rm -rf obj_dir obj_dir_s100 obj_dir_w32
