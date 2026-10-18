# Logic-level test of the bring-up top (eth100_test + Eth100Phy, auto-negotiation,
# test frames with FCS both ways, UART report). Vendor primitives are not used.
R := ../../../rtl
SRCS := $(R)/oscdr/os_cdr.sv $(addprefix $(R)/eth100_phy/,eth100_tx.sv eth100_rx.sv eth100_flp.sv eth100_an.sv eth100_phy.sv) \
        $(R)/eth100_phy/test/eth100_chan.sv $(R)/uart/uart_tx.sv $(R)/uart/uart_rx.sv \
        ../src/tangprimer25k/eth100_test.sv tb_test_logic.sv

.PHONY: all clean
all: obj_dir/sim
	./obj_dir/sim

obj_dir/sim: $(SRCS)
	verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD -Wno-UNSIGNED \
	  --top-module tb_test_logic -o sim $(SRCS)

clean:
	rm -rf obj_dir
