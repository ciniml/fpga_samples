.PHONY: all clean compile test view

MODULES_tb_dds_core := ../src/dds_core.sv
TESTCASES_tb_dds_core := default sine

TESTBENCHES := tb_dds_core
VERILATOR := verilator
#VERILATOR := docker run -it -e CCACHE_DIR=/tmp/ccache -v `realpath ${PWD}/../..`:`realpath ${PWD}/../..` -v ${PWD}:/work --user $(id -u):$(id -g) verilator/verilator:latest


all: $(addsuffix -all,$(addprefix test-, $(TESTBENCHES)))
	@echo "Done."

clean: 
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil
	-@$(RM) -r run-*

$(MODULES_tb_dds_core): $(wildcard ../src/*.veryl)
	cd ..; veryl build

define testbench-rule
test-$1-all: $(addprefix test-$1-, $(TESTCASES_$1))
	@echo "Done."
endef

define testcase-rule
run-$1-$2/obj_dir/test_bin: $1.sv $(MODULES_$1)
	$(info Compiling $1 $2)
	mkdir -p run-$1-$2
	cd run-$1-$2; $(VERILATOR) --binary --top-module tb_$2 --assert --trace-fst --trace-params --trace-structs --trace-underscore $(abspath $1.sv) $(foreach module,$(MODULES_$1),$(abspath $(module))) -o test_bin

compile-$1-$2: run-$1-$2/obj_dir/test_bin

test-$1-$2: run-$1-$2/obj_dir/test_bin
	cd run-$1-$2; ./obj_dir/test_bin | tee test.log
	@if grep Error run-$1-$2/test.log; then echo "Error."; exit 1; fi

view-$1-$2: run-$1-$2/trace.fst
	gtkwave run-$1-$2/trace.fst&
endef

$(foreach testbench,$(TESTBENCHES),$(eval $(call testbench-rule,$(testbench))))
$(foreach testbench,$(TESTBENCHES),$(foreach testcase,$(TESTCASES_$(testbench)),$(eval $(call testcase-rule,$(testbench),$(testcase)))))