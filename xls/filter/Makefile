TOP_ENTITY := moving_average
TOP        := moving_average

TEST_MODULE := test_$(TOP)
TEST_TOP    := $(TEST_MODULE)
TEST_OPTS := -g2012

.PHONY: run
run:
	interpreter_main $(TOP).dslx

.PHONY: gen
gen: $(TOP).ir $(TOP).opt.ir $(TOP).v

%.ir: %.dslx
	ir_converter_main --top $(TOP_ENTITY) $< > $@

%.opt.ir: %.ir
	opt_main $< > $@

%.v: %.opt.ir
	codegen_main --use_system_verilog=false --module_name=$(TOP_ENTITY) --reset reset --generator=pipeline --delay_model=unit --clock_period_ps=10000 $< > $@

.PHONY: test
test: $(TEST_MODULE).vcd

.PHONY: show
show: $(TEST_MODULE).vcd
	gtkwave $< &


$(TEST_MODULE).vcd: $(TOP).v $(TEST_MODULE).sv
	iverilog $(TEST_OPTS) -s $(TEST_TOP) $^ -o $@ $(SRCS) 
	./$(patsubst .vcd,.elf,$@)

.PHONY: clean
clean:
	-@$(RM) *.v *.ir *.elf