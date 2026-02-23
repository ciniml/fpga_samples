.PHONY: all clean compile test view

MODULES_tb_vram_reader := ../vram_reader.sv ../vram_if.sv ../dependencies/axi4s/axi_stream.sv
TESTCASES_tb_vram_reader := vram_reader_default vram_reader_single_pixel vram_reader_single_line vram_reader_rectangle vram_reader_multiple_commands vram_reader_small_screen

MODULES_tb_vram_writer := ../vram_writer.sv ../vram_if.sv ../dependencies/axi4s/axi_stream.sv
TESTCASES_tb_vram_writer := vram_writer_default vram_writer_single_pixel vram_writer_single_line vram_writer_rectangle vram_writer_multiple_commands vram_writer_small_screen

MODULES_tb_video_signal_generator := ../video_signal_generator.sv ../video_io_if.sv ../dependencies/axi4s/axi_stream.sv
TESTCASES_tb_video_signal_generator := video_signal_generator_default video_signal_generator_basic_timing video_signal_generator_sync_behavior video_signal_generator_frame_timing video_signal_generator_multiplier_2x2 video_signal_generator_multiplier_h3 video_signal_generator_tuser_skip

MODULES_tb_display_controller := ../vram_writer.sv ../vram_if.sv ../dependencies/axi4s/axi_stream.sv ../dependencies/axi4s/axi_stream_demux.sv ../dependencies/axi4s/axi_stream_mux.sv ../dependencies/std/selector/selector_pkg.sv ../dependencies/std/selector/demux.sv ../dependencies/std/selector/mux.sv ../display_controller.sv 
TESTCASES_tb_display_controller := display_controller_default display_controller_version display_controller_fill_rect display_controller_write_pixel display_controller_write_raw display_controller_multiple_commands display_controller_small_screen

TESTBENCHES := tb_vram_reader tb_vram_writer tb_video_signal_generator tb_display_controller
VERILATOR := verilator
#VERILATOR := docker run -it -e CCACHE_DIR=/tmp/ccache -v `realpath ${PWD}/../..`:`realpath ${PWD}/../..` -v ${PWD}:/work --user $(id -u):$(id -g) verilator/verilator:latest

all: $(addsuffix -all,$(addprefix test-, $(TESTBENCHES)))
	@echo "Done."

clean:
	-@veryl clean
	-@$(RM) -f *.pb *.jou *.log *.wdb *.str
	-@$(RM) -rf xsim.dir .Xil
	-@$(RM) -r run-*

%.sv: %.veryl
	@echo "Veryl build"
	veryl build

define testbench-rule
test-$1-all: $(addprefix test-$1-, $(TESTCASES_$1))
	@echo "Done."
endef

define testcase-rule
run-$1-$2/obj_dir/test_bin: $1.sv $(MODULES_$1)
	$(info Compiling $1 $2)
	mkdir -p run-$1-$2
	cd run-$1-$2; $(VERILATOR) --binary --top-module display_controller_tb_$2 --assert --trace-fst --trace-params --trace-structs --trace-underscore  $(foreach module,$(MODULES_$1),$(abspath $(module))) $(abspath $1.sv) -o test_bin

compile-$1-$2: run-$1-$2/obj_dir/test_bin

test-$1-$2: run-$1-$2/obj_dir/test_bin
	cd run-$1-$2; ./obj_dir/test_bin | tee test.log
	@if grep Error run-$1-$2/test.log; then echo "Error."; exit 1; fi

view-$1-$2: run-$1-$2/trace.fst
	gtkwave run-$1-$2/trace.fst&

genvcd-$1-$2: run-$1-$2/trace.fst
	fst2vcd run-$1-$2/trace.fst > run-$1-$2/trace.vcd
endef

$(foreach testbench,$(TESTBENCHES),$(eval $(call testbench-rule,$(testbench))))
$(foreach testbench,$(TESTBENCHES),$(foreach testcase,$(TESTCASES_$(testbench)),$(eval $(call testcase-rule,$(testbench),$(testcase)))))