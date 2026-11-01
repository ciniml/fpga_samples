// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// TAP=1 (phy_tap.v): the clocks at the boundary between the USB 3.0 PHY soft IP and the GTR12 quad, as
// synthesis merges them (project.tcl renames the rx_clk / drp_clk nets of timing.sdc to tap_clk[2] / [0]):
//   tap_clk[1] lane0_fabric_tx (the transmit data) = tap_clk[3] pcs_tx_o_fabric = pclk
//   tap_clk[4] pcs_rx_o_fabric = tap_clk[2] lane0_fabric_rx = rx_clk (recovered, into the IP's elastic buffer)
//   tap_clk[5] cm_life = tap_clk[0] = drp_clk
// No further clocks are needed.
