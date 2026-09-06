# gowin_psram — HyperRAM controller for Gowin FPGAs (Veryl)

`GowinPsram` drives one HyperRAM die (HyperBus, e.g. the on-package PSRAM
of the Tang Nano 9K / GW1NR-9, Winbond W955D8MBYA) using only the Gowin
`ODDR`/`IDDR` primitives. No encrypted Gowin IP, fully simulatable.

## Interface (per die)

| port | dir | description |
|---|---|---|
| `i_clk`, `i_clk_p` | in | controller clock and a +90° copy (PLL `CLKOUTP`, `PSDA_SEL=4`) for CK |
| `i_ck_delay[1:0]` | in | extra cycles the CK enable lags DQ/CS# (0 nominal; runtime knob for bring-up) |
| `o_ready` | out | init done (tVCS wait + CR0 write) |
| `i_cmd_valid/o_cmd_ready`, `i_cmd_write`, `i_cmd_reg`, `i_cmd_addr`, `i_cmd_len` | | command: byte address, `len` = words − 1, `reg` = register space |
| `i_wr_valid/o_wr_ready`, `i_wr_data[15:0]`, `i_wr_mask[1:0]` | | write stream, one word per `o_wr_ready` strobe (source must keep up; `valid=0` masks the word) |
| `o_rd_valid`, `o_rd_data[15:0]`, `o_rd_last` | out | read stream (no back-pressure) |
| `o_psram_ck`, `o_psram_cs_n`, `o_psram_reset_n`, `io_psram_dq[7:0]`, `io_psram_rwds` | | HyperRAM pins |

Parameters: `CLK_HZ` (init timer), `LATENCY` (3 ≤ 83MHz, 4 ≤ 104, 5 ≤ 133,
6 ≤ 166), `ADDR_BITS` (22 = 4MiB), `LEN_BITS` (burst length field, 7 = 128
words; keep CS# low < tCSM 4µs).

Byte order: `data[7:0]` is the even address byte, `[15:8]` the odd one
(rising-edge byte on the bus). Register space byte addresses: 0x0000 ID0,
0x0002 ID1, 0x1000 CR0, 0x1002 CR1.

## Design notes

- Fixed (2×) initial latency is configured in CR0 at init so the RWDS
  additional-latency indication never has to be sampled; reads are
  self-timed on the RWDS strobe captured by the IDDR (either alignment of
  the strobe relative to the sample edges is handled).
- The CK enable goes through a falling-edge register before the `i_clk_p`
  ODDR: the direct path would only have a quarter period of budget. With
  it, CK lines up with DQ/CS# at `i_ck_delay = 0` per the Gowin primitive
  simulation models.
- `PsramTest` (`psram_test.veryl`) is the board bring-up driver used by
  `eda/psram_test`: sweeps `i_ck_delay`, reads ID0/CR0, writes/reads 1MiB,
  prints one UART line per pass.

## Simulation

```console
$ make test        # extracts ODDR/IDDR models from the Gowin IDE into test/gen/, then veryl test
```

`test/hyperram_model.sv` is a behavioral HyperRAM die (CA decode, linear
bursts, registers, fixed/variable latency, RWDS mask, tCKD output delay).
