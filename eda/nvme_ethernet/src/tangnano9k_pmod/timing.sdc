// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/SET}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/D}]
