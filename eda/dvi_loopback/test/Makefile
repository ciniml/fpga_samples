# Logic-level loopback test: loop_pattern -> dvi_out -> (bit-slip model)
# -> dvi_in -> loop_check -> loop_report, UART decoded by the testbench.
SRC := ../src/tangprimer25k
RTL := ../../../rtl
SRCS := tb_loop.sv $(SRC)/loop_pattern.sv $(SRC)/frame_sum.sv $(SRC)/loop_check.sv $(SRC)/loop_report.sv \
        $(RTL)/dvi_in/dvi_in.sv $(RTL)/dvi_out/dvi_out.sv $(RTL)/uart/uart_tx.sv $(RTL)/uart/uart_rx.sv

.PHONY: all clean
all: obj_dir/simv
	./obj_dir/simv

obj_dir/simv: $(SRCS)
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN --top-module tb_loop -o simv $(SRCS)

clean:
	rm -rf obj_dir
