.PHONY: all clean

TEST ?= test-uart
SRCS := uart_rx.sv uart_tx.sv test_uart.sv
OPTS := -g2012

all: $(TEST)

test-%.elf: $(SRCS)
	iverilog $(OPTS) -s test_$(patsubst test-%.elf,%,$@) -o $@ $(SRCS) 

test-%: test-%.elf
	./$<

clean:
	-@$(RM) *.elf
	-@$(RM) *.vcd