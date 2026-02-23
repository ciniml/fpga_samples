cmake_minimum_required(VERSION 3.12)

# Pull in SDK (must be before project)
include(pico_sdk_import.cmake)

project(display_controller_host C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(display_controller_host
        display_controller_host.cpp
        )

target_link_libraries(display_controller_host pico_stdlib hardware_spi hardware_dma)
pico_add_extra_outputs(display_controller_host)
