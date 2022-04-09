open_project fft
add_files -cflags {-I../../external/gcem/include} src/fft_hls.cpp

open_solution solution1
set_part virtexuplusHBM
create_clock -period 10ns
set_top run_fft

csynth_design
close_project