TOP_ENTITY := mixer
TOP        := mixer
# Currently opt_main requires the top module name generated in the IR.
OPT_TOP    ?= __mixer__mixer__mixer_body_0__2_2_next

TEST_MODULE := test_$(TOP)
TEST_TOP    := $(TEST_MODULE)
TEST_OPTS := -g2012

CODEGEN_OPTS := --generator=pipeline --reset reset --delay_model=unit --clock_period_ps=10000

XLS_HOME ?= $(HOME)/.local/share/xls/xls
XLSCC := $(XLS_HOME)/contrib/xlscc/xlscc 
INTERPRETER_MAIN := $(XLS_HOME)/dslx/interpreter_main
IR_CONVERTER_MAIN := $(XLS_HOME)/dslx/ir_convert/ir_converter_main
CODEGEN_MAIN := $(XLS_HOME)/tools/codegen_main
OPT_MAIN := $(XLS_HOME)/tools/opt_main

.PHONY: run
run:
	$(INTERPRETER_MAIN) $(TOP).dslx

.PHONY: gen
gen: $(TOP).ir $(TOP).opt.ir $(TOP).v

%.ir: %.cc
	$(XLSCC) --top $(TOP_ENTITY) $< > $@.tmp
	@mv $@.tmp $@

%.ir: %.dslx
	$(IR_CONVERTER_MAIN) --top $(TOP_ENTITY) $< > $@.tmp
	@mv $@.tmp $@

%.opt.ir: %.ir
	$(OPT_MAIN) --top $(OPT_TOP) $< > $@.tmp
	@mv $@.tmp $@

%.v: %.opt.ir
	$(CODEGEN_MAIN) --use_system_verilog=false --module_name=$(TOP_ENTITY) $(CODEGEN_OPTS) $< > $@.tmp
	@mv $@.tmp $@

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
	-@$(RM) *.v *.ir *.elf *.tmp