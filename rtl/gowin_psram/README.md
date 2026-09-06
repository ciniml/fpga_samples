# gowin_psram — HyperRAM controller for Gowin FPGAs (Veryl)

`GowinPsram` drives one HyperRAM die (HyperBus, e.g. the on-package PSRAM
of the Tang Nano 9K / GW1NR-9, Winbond W955D8MBYA) using only the Gowin
`ODDR`/`IDDR` primitives. No encrypted Gowin IP, fully simulatable.

## Interface (per die)

| port | dir | description |
|---|---|---|
| `i_clk`, `i_clk_p` | in | controller clock and a +90° copy (PLL `CLKOUTP`, `PSDA_SEL=4`) for CK |
| params | | `IN_DELAY` (input IODELAY, 100 steps = 2.5ns) |
| `o_ready` | out | init done (tVCS wait + CR0 write) |
| `i_cmd_valid/o_cmd_ready`, `i_cmd_write`, `i_cmd_reg`, `i_cmd_addr`, `i_cmd_len` | | command: byte address, `len` = words − 1, `reg` = register space |
| `i_wr_valid/o_wr_ready`, `i_wr_data[15:0]`, `i_wr_mask[1:0]` | | write stream, one word per `o_wr_ready` strobe (source must keep up; `valid=0` masks the word) |
| `o_rd_valid`, `o_rd_data[15:0]`, `o_rd_last` | out | read stream (no back-pressure) |
| `o_psram_ck`, `o_psram_cs_n`, `o_psram_reset_n`, `io_psram_dq[7:0]`, `io_psram_rwds` | | HyperRAM pins |

Parameters: `CLK_HZ` (init timer), `LATENCY` (3 ≤ 83MHz, 4 ≤ 104, 5 ≤ 133,
6 ≤ 166), `ADDR_BITS` (22 = 4MiB), `LEN_BITS` (burst length field, 6 = 64
words), `WRAP_BYTES` (CR0 burst length, 128 default), `CK_DELAY` (0; extra
cycles the CK enable lags DQ/CS#, for other boards), `IN_DELAY` (input
IODELAY, 100 steps = 2.5ns).

**Read-capture timing**: the IDDRs must share the ODDRs' `i_clk` (Gowin
pad rule), so they sample 270° after the CK edge that made the die drive a
byte — only inside the byte while tCKD exceeds a quarter period. An
IODELAY of `IN_DELAY`×25ps on each input widens that margin. On the Tang
Nano 9K the on-package PSRAM reads cleanly at ~54MHz; at 81MHz a single DQ
bit shows sporadic placement-dependent errors under a fully-loaded clock
tree (the standalone `psram_test` still passes at 81MHz).

**Burst rule**: a burst must not cross a `WRAP_BYTES` boundary. The Tang
Nano 9K die wraps at the CR0 burst length even for linear CAs (measured),
so 64 words aligned inside a 128-byte group is the largest transfer.

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
  it, CK lines up with DQ/CS# at `CK_DELAY = 0` per the Gowin primitive
  simulation models, confirmed on the Tang Nano 9K.
- Measured on the Tang Nano 9K (W955D8MBYA): with fixed latency the data
  phase starts 2 + 2×LATENCY CK cycles after the first CA clock (the count
  runs from the third CA clock); ID0 reads 0x005f; CR0[2] is read-only 1;
  bursts wrap at the CR0 burst length regardless of CA[45].
- `PsramTest` (`psram_test.veryl`) is the board test driver used by
  `eda/psram_test`: reads ID0/CR0, writes/reads 1MiB with 16/32/64-word
  bursts, prints one UART line per pass.
- `PsramDwordCache` (`psram_dword_cache.veryl`) presents a dword-addressed
  synchronous-RAM interface (address / wen / ren / rdata + a ready-stall)
  backed by GowinPsram through a one-line write-back cache; the user and
  PSRAM sides run on independent clocks (dual-clock line BRAM + toggle
  synchronisers). `LINE_BYTES` (512..4096) sizes the line. Measured in
  `test/psram_cache_test_body.sv`: a 512-byte line costs ~444 user cycles
  per miss (fetch, or write-back + fetch when dirty); a 4096-byte line
  ~6566 (it always moves the whole line), so a bigger line is only worth
  it when whole-line accesses dominate. NVMe uses the 512-byte default
  since one LBA is exactly one line.

## Simulation

```console
$ make test        # extracts ODDR/IDDR models from the Gowin IDE into test/gen/, then veryl test
```

`test/hyperram_model.sv` is a behavioral HyperRAM die (CA decode, bursts
wrapping at the CR0 length like the real die, registers, fixed/variable
latency, RWDS mask, tCKD output delay).
