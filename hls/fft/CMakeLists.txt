cmake_minimum_required(VERSION 3.16)
enable_language(CXX)
set(CXX_STANDARD 17)
set(CXX_STANDARD_REQUIRED ON)

project(fft)

add_executable(fft src/fft_main.cpp)
target_include_directories(fft PRIVATE ../../external/gcem/include test)

project(ntt)

add_executable(ntt src/ntt_main.cpp)
target_compile_options(ntt PUBLIC -g)
target_include_directories(ntt PRIVATE ../../external/gcem/include test)
