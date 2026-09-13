# Verilator end-to-end test of the control path (no device primitives).
RTL := ../../../rtl
SRCS := e2e_ctrl_tb.sv \
        ../src/common/easycdr_trace_tx.v ../src/common/tx_link_core.v \
        ../src/tangprimer25k/trace_rx_decoder.v ../src/tangprimer25k/trace_capture.v \
        $(RTL)/displayport/src/encoder_8b10b.sv $(RTL)/displayport/src/decoder_8b10b.sv \
        $(RTL)/manchester/manchester_tx.sv $(RTL)/manchester/manchester_rx.sv \
        $(RTL)/manchester/ctrl_frame_rx.sv $(RTL)/manchester/trace_ctrl_regs.sv

test:
	verilator --binary --timing --assert -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	  -Wno-CASEINCOMPLETE -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-PINMISSING \
	  -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM -Wno-MULTITOP \
	  --top-module e2e_ctrl_tb -o simv $(SRCS)
	./obj_dir/simv

clean:
	rm -rf obj_dir
