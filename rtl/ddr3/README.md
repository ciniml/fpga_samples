# rtl/ddr3 — DDR3 namespace for the NVMe/TCP target (Tang Primer 20K)

Veryl project (`omit_project_prefix`, modules emit unprefixed).

| file | origin | role |
|---|---|---|
| `ddr3_ctrl.veryl` | copied from `~/repos/riscv-veryl` (commit 78e2537) | `Ddr3Ctrl`: x16 BL8 closed-page DDR3 controller, 16-byte `LineBusIf` slave, CPU-clock/pclk CDC inside, read auto-calibration |
| `ddr3_phy_gw2a.veryl` | copied (same) | `Ddr3PhyGw2a`: GW2A IOLOGIC PHY (OSER8/IDES8), no Gowin DDR3 IP |
| `bus_if.veryl`, `line_bus_if.veryl` | copied (same) | `BusIf` (32-bit control), `LineBusIf` (128-bit line bus) |
| `gowin_sim_models.veryl` | copied (same) | OSER8/IDES8/IOBUF stubs so Verilator can elaborate the PHY |
| `test/ddr3_model.sv` | copied from `sim/ddr3/` (same) | behavioural DDR3 model with timing checks |
| `line_dword_cache.veryl` | new | `LineDwordCache`: NvmeCore's dword RAM contract (addr/wen/ren/rdata + ready) over a 512-byte write-back line in four 32-bit lane RAMs; a miss walks the line as 32 line-bus beats (write-back, then fetch) |
| `test/line_dword_cache_tb.sv` | new | cache + `Ddr3Ctrl` + model, sequential blocks / random dwords vs a reference, cycles per miss |

Keep the copied files in sync with riscv-veryl; local fixes belong upstream.

## Numbers (simulation, `veryl test --verbose`)

348 line misses, **722.7 user-clock cycles per 512-byte miss** (14.5 us at
50 MHz, write-back + fetch included) - roughly 35 MB/s of line traffic,
about 3x the 100BASE-TX wire rate, so the DRAM is not the bottleneck.
DDR3 init (200 us + 500 us power-up timing, MRS, ZQ, calibration) takes
~741 us of simulated time.

## Board integration

`eda/nvme_ethernet/src/tangprimer20k`: rPLL 27 MHz x 11 = 297 MHz fclk,
CLKDIV /4 = 74.25 MHz pclk (`PCLK_PS` 13468), memory-side reset held until
the PLL locks; `Ddr3Ctrl.i_clk_cpu` is the 50 MHz RMII clock so the
controller does the only clock crossing. The namespace is 262143 blocks
(128 MiB minus the last block, whose last 16 bytes are the controller's
calibration scratch). DDR3 pins follow Sipeed's DDR-test constraints.
Synthesis: RMII clock Fmax 58 MHz, pclk 85 MHz, Logic 56 %, BSRAM 68 %.

Verified on the board (2026-09-12): smoke 7/7, data-integrity probe clean at
low, middle and top-of-namespace LBAs (out-of-range LBA rejected), a 20 s
mixed-load soak, SPDK reads 8.0-8.2 MiB/s (same as the BRAM namespace),
writes 3.7-5.6 MiB/s (dirty-line swap per 512-byte block). The upstream
board-measured read-capture fallbacks (RD_SEL 44 / RD_LAT 12) and the
auto-calibration worked first time.
