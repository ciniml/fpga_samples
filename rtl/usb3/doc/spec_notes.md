# USB 3.2 Gen1x1 (SuperSpeed, 5 Gbps) device-side link/protocol digest

Scope: upstream port (peripheral device), Gen 1x1 only, PIPE 3.x PHY (32-bit @ 125 MHz,
8b/10b inside the PHY). Everything SuperSpeedPlus / Gen2 / x2 / hub / host-only is omitted
except where the device must tolerate it. Section numbers refer to USB 3.2 Rev 1.1 (June 2022)
unless prefixed "PIPE" (PIPE spec v5.1 text, "pipe31.txt").

Conventions: "shall" = normative must; "may" = optional. Offsets of packet fields are given as
`DW:bit` = DWORD index : LSB bit index, as in the spec tables (little-endian; byte 0 of DW0 is
on the wire first, 7.1). Timer accuracy for all link-layer timers is 0 to +50 % (7.5).

Known text-extraction defect in the source file: the micro sign is lost in several tables
("0.6 s" = 0.6 us). Values below are restored from context; where a μ was lost it is noted.

---------------------------------------------------------------------------------------------

## 1. Symbols, framing, SKP, Logical Idle

### 1.1 K-codes used in Gen 1 (Table 6-2, byte values from Appendix A)

| Name  | K-code | 8-bit | Role |
|-------|--------|-------|------|
| SKP   | K28.1  | 0x3C  | clock compensation, SKP OS = SKP SKP |
| SDP   | K28.2  | 0x5C  | start of Data Packet Payload (DPPSTART) |
| EDB   | K28.3  | 0x7C  | end of nullified packet (DPPABORT); also BERC in loopback BERT |
| SUB   | K28.4  | 0x9C  | substituted by 8b/10b decoder on decode error (6.3.1.4) |
| COM   | K28.5  | 0xBC  | comma / symbol alignment, resets scrambler |
| (rsvd)| K28.6  | 0xDC  | reserved |
| SHP   | K27.7  | 0xFB  | start header packet (HPSTART) |
| END   | K29.7  | 0xFD  | end of DPP (DPPEND) |
| SLC   | K30.7  | 0xFE  | start link command (LCSTART) |
| EPF   | K23.7  | 0xF7  | end packet framing (4th symbol of every framing OS) |
| BRST  | K28.7  | 0xFC  | only in loopback BERT (Table 6-24) and CP5/CP6 |

Data symbols used by training: D10.2 = 0x4A, D5.2 = 0x45, D0.0 = 0x00, D21.5 = 0xB5 (what
D10.2 looks like under polarity inversion, 6.4.2.1).

### 1.2 Framing ordered sets (4 symbols each, one-symbol error tolerant)

| OS        | Symbols              | Ref |
|-----------|----------------------|-----|
| HPSTART   | SHP SHP SHP EPF      | 7.2.1.1.1 |
| DPPSTART  | SDP SDP SDP EPF      | 7.2.1.2.1 |
| DPPEND    | END END END EPF      | 7.2.1.2.1 |
| DPPABORT  | EDB EDB EDB EPF      | 7.2.1.2.1 |
| LCSTART   | SLC SLC SLC EPF      | 7.2.2.1 |
| SKP OS    | SKP SKP              | Table 6-12 |

Receiver rule (7.3.4.1 Table 7-9, 7.3.5 Table 7-10): a framing OS / LCSTART **shall** be
declared when at least 3 of the 4 symbols in 4 consecutive symbol periods are the correct
symbols in the correct positions (any one of the four may be corrupt, including EPF). Two or
more corrupt symbols = framing missed = header packet missing (detected later via Rx Header
Sequence Number error or PENDING_HP_TIMER) or DPP missing.

Header packet = HPSTART + 12 header bytes + CRC-16 (2) + Link Control Word (2) = 20 symbols
(7.2.1.1). Data packet = DPH (20 symbols) immediately followed by DPP = DPPSTART + 0..1024
data bytes + CRC-32 (4) + DPPEND/DPPABORT (7.2.1.2). **No symbols at all between DPH and DPP**
(7.2.1.2.3), not even SKP or link commands.

### 1.3 SKP ordered set rules (6.4.3, 6.4.3.1)

- SKP OS = two K28.1. Transmitter keeps count Y of symbols sent since last SKP OS; Y is reset
  on entry to Polling.Active. Insert floor(Y/354) SKP OS "immediately after each transmitted
  TS1, TS2 OS, LMP, TP, Data Packet Payload, or Logical Idle"; keep the fractional remainder.
  During training only, transmitter may wait until floor(Y/354) reaches 2 and send 2 SKP OS.
- Never inside a packet (header, DPH-DPP gap, or DPP). Never during TSEQ (6.4.1.1.1). Never
  inside a TS1/TS2 (only between them). Up to 4 SKP OS may be buffered.
- Transmitter may pad up to 8 Idle Symbols before a scheduled SKP OS.
- Link commands shall not be sent until all scheduled SKP OS have been sent (7.2.2.3).
- Receiver elasticity buffer: at least 8 symbols of buffering/starving (6.4.3). Frequency
  budget: ±300 ppm per side plus SSC -5000 ppm, total -5300..+300 ppm.
- SKP OS do not break "consecutive" detection of TS1/TS2 (6.4.3.1 last bullet).
- Scrambler is **not advanced** on SKP symbols (6.3.1.3 rule 2).
- With a PIPE PHY the PHY adds/removes whole SKP OS (nominal-half-full) or removes all SKPs
  and uses RxDataValid (nominal-empty); see §12.

### 1.4 Logical Idle (7.2.3, Table 7-6)

Idle Symbol IS = D0.0 (0x00) **scrambled**; transmitted whenever in U0 and nothing else is
being sent. (Because it is scrambled, the on-wire stream is the LFSR output; Appendix B table
reproduced in §3.)

---------------------------------------------------------------------------------------------

## 2. Training ordered sets (Gen 1)

All training OS are 8b/10b encoded, **never scrambled** (6.4.1.1), and the LFSR is reset by
every COM they contain. TS1/TS2 are sent back-to-back, interruptible only by SKP OS between
whole ordered sets (6.4.1.1, 6.4.1.1.1).

### 2.1 TSEQ (Table 6-3) - 32 symbols, repeated 65 536 times in Polling.RxEQ

| Sym | Value | Sym | Value |
|-----|-------|-----|-------|
| 0 | COM K28.5 | 8 | D2.4 0x82 |
| 1 | D31.7 0xFF | 9 | D18.3 0x72 |
| 2 | D23.0 0x17 | 10 | D14.3 0x6E |
| 3 | D0.6 0xC0 | 11 | D8.1 0x28 |
| 4 | D20.0 0x14 | 12 | D6.5 0xA6 |
| 5 | D18.5 0xB2 | 13 | D30.5 0xBE |
| 6 | D7.7 0xE7 | 14 | D13.3 0x6D |
| 7 | D2.0 0x02 | 15 | D31.5 0xBF |
| 16-31 | D10.2 0x4A ×16 | | |

Note symbols 1..15 are exactly the scrambled-zero sequence after an LFSR reset (Appendix B):
FF 17 C0 14 B2 E7 02 82 72 6E 28 A6 BE 6D BF. No SKP OS during the whole TSEQ period
(6.4.1.1.1). The receiver uses the D10.2 run to detect polarity inversion (seen as D21.5),
and must fix polarity before using symbols 1-15 (6.4.2.1). A receiver that does not use TSEQ
may check polarity on the D10.2 of TS1 instead.

### 2.2 TS1 (Table 6-4) and TS2 (Table 6-5) - 16 symbols

| Sym | TS1 | TS2 |
|-----|-----|-----|
| 0-3 | COM COM COM COM | COM COM COM COM |
| 4 | D0.0 (reserved) | D0.0 (reserved) |
| 5 | Link Functionality (Table 6-6) | Link Functionality |
| 6-15 | D10.2 ×10 (0x4A) | D5.2 ×10 (0x45) |

### 2.3 Link configuration byte, symbol 5 (Table 6-6)

| Bit | Meaning |
|-----|---------|
| 0 | 1 = Reset (Hot Reset). Set by the host (downstream port) only; an upstream port sets it only while in Hot Reset.Active (7.5.4.9.1, 7.5.12.3.1) |
| 1 | reserved, 0 |
| 2 | 1 = Loopback: receiving component becomes loopback slave |
| 3 | 1 = Disable Scrambling: receiving component disables scrambling (decoded only in Polling.Idle / Recovery.Idle; ignored in Hot Reset.Active, 7.5.12.3.1) |
| 4 | 1 = local loopback in repeater (ignore) |
| 5 | 1 = bit-level re-timer Tx compliance mode (hosts/devices ignore) |
| 6:7 | reserved, 0 |

If bit 0 and bit 2 are both 1 the receiver **shall ignore all** training control bits
(6.4.1.1.2). If the two ports request different things, the downstream port's TS2 wins; e.g.
Hot Reset overrides Loopback (7.3.14).

### 2.4 "Eight consecutive" reception rules

- Polling.Active -> Polling.Configuration: 8 consecutive **and identical** TS1 **or** TS2
  received (7.5.4.8.2). (TS2 count too, because the partner may already be ahead.)
- Polling.Configuration -> Polling.Idle: 8 consecutive identical TS2 received **and** 16 TS2
  sent after receiving the first of those 8 (7.5.4.9.2).
- Recovery.Active / Recovery.Configuration: same numbers (7.5.10.3.2, 7.5.10.4.2).
- Polling.Idle / Recovery.Idle / Hot Reset.Exit -> U0: 8 consecutive Idle Symbols received and
  16 Idle Symbols sent after receiving one (7.5.4.10.2, 7.5.10.5.2, 7.5.12.4.2).
- Hot Reset.Active -> Hot Reset.Exit: >=16 TS2(Reset=1) sent, 2 consecutive TS2(Reset=0)
  received, 4 consecutive TS2(Reset=0) sent after receiving one (7.5.12.3.2).
- SKP OS in between do not break consecutiveness (6.4.3.1).

SDS ordered set: Gen 2 only (Table 6-2); **not used in Gen 1**.

---------------------------------------------------------------------------------------------

## 3. Scrambling (6.3.1.3, Appendix B)

| Item | Value |
|------|-------|
| Polynomial | G(X) = X^16 + X^5 + X^4 + X^3 + 1 |
| Seed | 0xFFFF |
| Reset | whenever COM (K28.5) is transmitted (Tx LFSR) / received (Rx LFSR). Also by BRST in loopback BERT |
| Advance | 8 serial shifts per symbol, for every symbol **except SKP** (K28.1); advance happens after the XOR. K-codes other than SKP (SHP, EPF, SDP, END, EDB, SLC, SUB, COM) **do advance** the LFSR but are not XORed |
| Scrambled | all D-codes except those inside TSEQ/TS1/TS2 (and compliance patterns other than CP0). Includes header bytes, CRC-16, LCW, link command words, DPP data, CRC-32, Idle Symbols |
| Not scrambled | all K-codes; TSEQ/TS1/TS2 D-codes |
| Applied | Tx: before 8b/10b encode; Rx: after 8b/10b decode (so with a PIPE PHY the MAC does it on TxData/RxData) |
| Disable | if Disable Scrambling bit seen in TS2 during Polling.Configuration / Recovery.Configuration, scrambling off from Polling.Idle / Recovery.Idle (7.5.4.10.1, 7.5.10.5.1); otherwise on |

Bit mapping (Appendix B): data bit i (LSB first) is XORed with LFSR bit (15-i), i.e. D0^lfsr[15],
D1^lfsr[14], ... D7^lfsr[8]. Parallel 8-step advance (lfsr bit indices, b = current):

```
out[0]=b8  out[1]=b9  out[2]=b10 out[3]=b11^b8  out[4]=b12^b9^b8  out[5]=b13^b10^b9^b8
out[6]=b14^b11^b10^b9  out[7]=b15^b12^b11^b10  out[8]=b0^b13^b12^b11  out[9]=b1^b14^b13^b12
out[10]=b2^b15^b14^b13 out[11]=b3^b15^b14 out[12]=b4^b15 out[13]=b5 out[14]=b6 out[15]=b7
```

Reference LFSR values after reset (first 16 advances): FFFF E817 0328 284B 4DE8 E755 404F 4140
4E79 761E 1466 6574 7DBD B6E5 FDA6 B165. Scrambled zeros (= Logical Idle on the wire after a
COM): FF 17 C0 14 B2 E7 02 82 72 6E 28 A6 BE 6D BF 8D BE 40 A7 E6 2C D3 E2 B2 07 02 77 2A CD
34 BE E0 ... (Appendix B table; 2^16-1 period). Descrambler is the identical function.

Important consequence: after link-up there is **no COM in U0 traffic** (COM only appears in
TS1/TS2/TSEQ), so Tx and Rx LFSRs stay in sync purely by counting symbols; a missed/extra
symbol on the Rx side (elastic buffer error) desynchronizes the descrambler until the next
Recovery (which sends COMs).

---------------------------------------------------------------------------------------------

## 4. Link commands (7.2.2, 7.2.4)

### 4.1 Structure (7.2.2.1, Table 7-3, 7.2.2.2)

8 symbols: `SLC SLC SLC EPF  LCW[7:0] LCW[15:8]  LCW[7:0] LCW[15:8]` - the 16-bit Link Command
Word is sent twice (little-endian, low byte first). LCW[10:0] = command information,
LCW[15:11] = CRC-5 computed over bits 0..10 exactly as for the Link Control Word (§5.2).
Scrambled (they are D-codes).

Valid link command (7.3.5): LCSTART detected (3-of-4 rule), both words identical, both carry
a defined encoding (Table 7-4) and both pass CRC-5. Otherwise "invalid link command" - **shall
be ignored**, no Recovery.

### 4.2 Encodings (Table 7-4), bits [10:9]=class, [8:7]=type, [6:4]=000, [3:0]=subtype

| Command | class | type | subtype | LCW[10:0] |
|---------|-------|------|---------|-----------|
| LGOOD_n | 00 | 00 | 0nnn (n = 0..7, bit3 reserved) | 0x000 + n |
| LCRD_A/B/C/D | 00 | 01 | 00xx (xx = 00 A, 01 B, 10 C, 11 D) | 0x080..0x083 |
| LRTY | 00 | 10 | 0000 | 0x100 |
| LBAD | 00 | 11 | 0000 | 0x180 |
| LGO_U1 / U2 / U3 | 01 | 00 | 0001 / 0010 / 0011 | 0x201 / 0x202 / 0x203 |
| LAU | 01 | 01 | 0000 | 0x280 |
| LXU | 01 | 10 | 0000 | 0x300 |
| LPMA | 01 | 11 | 0000 | 0x380 |
| LUP | 10 | 00 | 0000 | 0x400 |
| LDN | 10 | 11 | 0000 | 0x580 |
| reserved | 11 | - | - | - |

### 4.3 Placement (7.2.2.3)

- Not inside a header packet, not inside a DPP, not between DPH and DPP.
- May be placed before/after any header packet; several back-to-back allowed.
- Not until all scheduled SKP OS have been sent.
- So the receiver only needs to look for LCSTART in the idle/inter-packet stream, never while
  inside a 20-symbol header or a DPP.

### 4.4 Meaning summary (Table 7-5)

| Cmd | Sender/meaning |
|-----|----------------|
| LGOOD_n | header packet with HSN n received properly; also the Header Sequence Number Advertisement on U0 entry |
| LBAD | header packet with bad CRC-5/CRC-16 received; partner must retry everything unacknowledged |
| LRTY | "I am about to resend", sent once before the first retried header packet in response to LBAD |
| LCRD_x | one Rx Header Buffer Credit returned; x cycles A,B,C,D,A,... |
| LGO_U1/U2 | request low-power state; either side may send. LGO_U3: host only, **device shall accept** |
| LAU / LXU | accept / reject (LXU only for U1/U2) |
| LPMA | sent by requester after receiving LAU, then it enters Ux |
| LUP | device-present keep-alive, sent by upstream port every 10 us of idle |
| LDN | host-present keep-alive, sent by downstream port every 10 us of idle |

### 4.5 State a device must keep (7.2.4.1.1)

| Variable | Init on U0 entry from Polling/Hot Reset | Init on U0 entry from Recovery |
|----------|------------------------------------------|-------------------------------|
| Tx Header Sequence Number (next HSN to assign to a new HP) | 0 | unchanged from before Recovery |
| ACK Tx Header Sequence Number (next LGOOD_n expected) | set from advertisement (+1) | set from advertisement (+1) |
| Rx Header Sequence Number (HSN expected in next received HP) | 0 | next expected HSN |
| Local Rx Header Buffer Credit Count | 4 | number of free Rx header buffers |
| Remote Rx Header Buffer Credit Count | 0 (then incremented by received LCRD_x) | 0 |
| Tx credit index (next LCRD_x letter to send) | A | A |
| Rx credit index (next LCRD_x letter expected) | A | A |
| Tx Header Buffers | 4 (must hold up to 4 unacknowledged HPs) | retained; flushed per advertisement |
| Rx Header Buffers | 4 | - |

### 4.6 U0 entry sequence (7.2.4.1.1), in this order

1. Start PENDING_HP_TIMER (10 us) and CREDIT_HP_TIMER (5 ms), expecting the partner's
   advertisements.
2. Send Header Sequence Number Advertisement = `LGOOD_(RxHSN - 1 mod 8)` (so LGOOD_7 after
   Polling/Hot Reset).
3. Send Rx Header Buffer Credit Advertisement = LCRD_A, LCRD_B, LCRD_C, LCRD_D (as many as
   Local Rx credits; 4 after Polling/Hot Reset).
4. On receiving the partner's LGOOD_n advertisement: ACK Tx HSN := n+1 mod 8; stop
   PENDING_HP_TIMER; flush Tx Header Buffers: all of them if entered from Polling/Hot Reset;
   if from Recovery flush those with HSN <= n (modulo window), keep and later retransmit those
   with HSN > n (example in spec: LGOOD_1 received -> flush 1,0,7,6).
5. Each received LCRD_x: Remote credit++ (max 4), restart/stop CREDIT_HP_TIMER.
6. No header packet may be sent until the partner's LGOOD_n advertisement has been received
   **and** Remote credit > 0. No LGO_Ux may be sent until both advertisements have been sent
   and received.
7. Errors (7.3.7, 7.3.8 -> Recovery): PENDING_HP_TIMER expires without advertisement; a header
   packet arrives before we sent our LGOOD_n advertisement; LCRD_x or LGO_Ux arrives before we
   received the LGOOD_n advertisement; CREDIT_HP_TIMER expires with no LCRD_x; a header packet
   arrives before we sent LCRD_x; LGO_Ux arrives before we received LCRD_x.
8. After Recovery, LBAD/LRTY pairing from before Recovery is cancelled: don't expect LRTY
   before retried packets and don't send LRTY before retrying (7.2.4.1.1 last bullets).
9. Unexpected commands (LBAD/LRTY/LAU/LXU/LPMA before advertisements, LRTY without LBAD, LAU
   without LGO_Ux, LPMA without LAU ...): behaviour undefined, recommended **ignore** (7.3.14).

### 4.7 Transmitting header packets (7.2.4.1.3, 7.2.4.1.12, 7.2.4.1.13)

- Put Tx HSN in LCW, compute CRC-5, send; Tx HSN++ mod 8; Remote credit--; keep a copy in a Tx
  Header Buffer until LGOOD_n for it arrives.
- Start PENDING_HP_TIMER if no other HP is outstanding; restart it on each LGOOD_n while
  others remain outstanding; stop when all acked or on LBAD.
- CREDIT_HP_TIMER: started when any HP (or retried HP) is sent or on U0 entry; active while
  Remote credit < 4; reset on each valid LCRD_x, restarted if still < 4.
- On LGOOD_n (7.2.4.1.10): must equal ACK Tx HSN, else -> Recovery (ACK Tx HSN unchanged).
  Flush that buffer, ACK Tx HSN++ mod 8.
- On LCRD_x (7.2.4.1.11): must be the expected letter, else -> Recovery. Remote credit++.
- On LBAD (7.2.4.1.12): send a single LRTY, then resend **all** unacknowledged HPs in order
  with their original HSNs (retransmission does not consume a Tx buffer, does not change Tx
  HSN, does not change Remote credit). Host/device may set the DL (Delayed) bit in the LCW of
  retried HPs and must then recompute CRC-5 (CRC-16 unchanged); hubs must. If the retried HP
  is a DPH and DL is clear, the DPP must follow it again. If nothing is unacknowledged, still
  send one LRTY. PENDING_HP_TIMER restarts when the oldest HP is retransmitted.
- Timeout -> Recovery, but only after the HP currently being transmitted (or the DPP, with
  DPPEND or DPPABORT) is complete (graceful). 4th consecutive PENDING_HP_TIMER timeout (i.e.
  three Recoveries for that cause) -> eSS.Inactive (7.5.6.2).
- Response time budget (Table 7-7 note 1, 7.5.6.1): partner must return LGOOD/LBAD within
  3.0 us; tDHPResponse (first bit HP in -> first bit LGOOD/LBAD out) < 2540 ns for Gen 1x1;
  recommended 400 ns when nothing else is queued; link command processing within 200 ns.

### 4.8 Receiving header packets (7.2.4.1.5, 7.2.4.1.7)

Checks in order: (1) CRC-5, (2) CRC-16, (3) HSN == Rx HSN, (4) an Rx Header Buffer is free.
- All pass -> "received properly": send one LGOOD_n (n = Rx HSN), Rx HSN++ mod 8, Local credit--.
  Later, when the packet has been consumed: send one LCRD_x (next letter), Local credit++.
- CRC-5 or CRC-16 fails (or a K-code inside the 16 bytes prevents the check, 7.3.4.2): send one
  LBAD; **ignore every subsequent header packet until LRTY is received** (or Recovery).
  Continue to send LCRD_x for buffers that free up. If the receive fails 3 consecutive times,
  do **not** send the 3rd LBAD; go to Recovery.
- HSN mismatch or no buffer -> Recovery (7.3.4.3).
- A packet with reserved field values is still acknowledged / credited, then ignored (8.3.1.1).

### 4.9 Link command keep-alive and U0 timers (7.5.6.1, 7.5.6.2)

| Timer | Value | Rule |
|-------|-------|------|
| tU0LTimeout | 10 us | reset when the first symbol of any link command/packet is sent, restarted after its last symbol; on expiry an upstream port sends one LUP (downstream port: LDN) |
| tU0RecoveryTimeout | 1 ms | restarted every time a link command is received; upstream port -> Recovery if no link command **or packet** received within 1 ms |

A device therefore must send LUP every 10 us of logical idle and must see LDN (or anything
else) from the host at least once per 1 ms.

### 4.10 Low-power link states from the device side (7.2.4.2)

Timers (Table 7-8, x1): PM_LC_TIMER 4 us, PM_ENTRY_TIMER 8 us, Ux_EXIT_TIMER 6 ms,
U1_MIN_RESIDENCY_TIMER 3 us.

Receiving LGO_U1/LGO_U2 (7.2.4.2.2): send **LAU** if Force_LinkPM_Accept is set (Set Link
Function LMP) or if all of: every received packet has been LGOOD+LCRD'd, every transmitted
packet has been LGOOD+LCRD'd, no pending packets, higher layer does not object (e.g. device
waiting for an ACK TP for a sent DP, or waiting after a PING). Otherwise send **LXU** and stay
in U0. Respond within tDHPResponse. Receiving LGO_U3: **shall** send LAU (abort any
unacknowledged packet processing); device cannot refuse U3.

After sending LAU: start PM_ENTRY_TIMER; send nothing more. Enter Ux on LPMA, or on
PM_ENTRY_TIMER expiry if neither LPMA nor TS1 seen. If a TS1 is seen before expiry -> Recovery
(partner thinks LAU was lost). If Ux-exit LFPS is seen before expiry (LPMA was lost and the
partner already wants to exit), finish the entry first, then respond to the exit.

Device-initiated U1/U2 entry (optional; only when U1_ENABLE/U2_ENABLE set, 9.4.9): send one
LGO_Ux, start PM_LC_TIMER, send no packets until LXU received or back in U0 (keep receiving).
LAU -> send one LPMA, enter Ux. LXU -> stay in U0. Timeout without LAU/LXU -> Recovery. If a
TS1 arrives meanwhile -> Recovery. Concurrent requests: if the device sent LGO_U1/U2 and also
receives LGO_U1/U2/U3, wait until it has received the host's LXU, then answer the host's
request with LAU/LXU (LAU for LGO_U3) (7.2.4.2.5). U1 -> U2 directly on U2 inactivity timer
expiry (U2 Inactivity Timeout LMP, Table 10-17: 00h disabled, N*256 us, FFh infinite).

Exit (7.2.4.2.7): either side sends Ux exit LFPS (U1/U2/U3 LFPS handshake, §9); on a
successful handshake both go to Recovery. A device initiating U1/U2 exit starts Ux_EXIT_TIMER
(6 ms); on tNoLFPSResponseTimeout (2 ms) with no handshake, or 6 ms without reaching U0 ->
eSS.Inactive. U3 wakeup: no Ux_EXIT_TIMER; on 10 ms timeout stay in U3, may retry after
tU3WakeupRetryDelay 100 ms. Don't start U1 exit before U1_MIN_RESIDENCY_TIMER (3 us from
LPMA sent/received).

---------------------------------------------------------------------------------------------

## 5. Header packet format

### 5.1 CRC-16 (7.2.1.1.2, Table 7-1)

| Item | Value |
|------|-------|
| Polynomial | 0x100B (x^16+x^12+x^3+x+1; **not** the USB 2.0 CRC-16) |
| Init | 0xFFFF |
| Data | the 12 header bytes, byte 0 first, bit 0 (LSB) of each byte first |
| Final | complement the remainder |
| Mapping | CRC result bit i goes to CRC field bit (15-i) (Table 7-1), i.e. bit-reversed into the 16-bit field, which is then sent little-endian as bytes 12,13 |
| Residual | 0xF6AA when the receiver runs the same CRC over header+CRC bytes |

### 5.2 Link Control Word (7.2.1.1.3, Table 8-2) - bytes 14,15 of the header packet

| Bits (within 16-bit LCW; DW3 bit = 16+i) | Field |
|---|---|
| 2:0 | Header Sequence Number 0..7 |
| 5:3 | reserved (0) |
| 8:6 | Hub Depth (0..4), only meaningful with DF; device sends 0 |
| 9 | DL Delayed - may be set when an HP is re-sent or delayed (host/device optional, hub mandatory) |
| 10 | DF Deferred - hubs only; device never sets it, but **must handle receiving it** (§10.9) |
| 15:11 | CRC-5 |

CRC-5: polynomial 00101b (x^5+x^2+1), init 11111b, over LCW bits 0..10 starting at bit 0,
remainder complemented, MSb of remainder -> bit 11, ..., LSb -> bit 15. Residual 01100b. The
same CRC-5 is used in the Link Command Word.

### 5.3 Header DW0 common fields (8.3.1.2, Table 8-1)

| Field | Offset | Width |
|-------|--------|-------|
| Type | 0:0 | 5: 00000 LMP, 00100 TP, 01000 DPH, 01100 ITP; others reserved |
| Route String / reserved | 0:5 | 20 (TP/DP only; device sends 0) |
| Device Address | 0:25 | 7 (TP/DP only) |
| CRC-16 | 3:0 | 16 |
| Link Control Word | 3:16 | 16 |

Reserved fields: transmit 0, ignore on receive; a packet with a *defined* field at a reserved
value is acknowledged (LGOOD/LCRD) but otherwise ignored (8.3.1.1).

---------------------------------------------------------------------------------------------

## 6. Data Packet Payload (7.2.1.2, 7.2.4.1.9, 8.6)

| Item | Value |
|------|-------|
| Structure | DPPSTART, 0..1024 data bytes, CRC-32 (4 bytes), DPPEND (or DPPABORT) |
| Spacing | none between DPH and DPP; DPP starts in the symbol right after the LCW |
| CRC-32 | polynomial 0x04C11DB7, init 0xFFFFFFFF, over data bytes only (byte 0 bit 0 first), remainder complemented, result bit i -> field bit (31-i) (Table 7-2), sent little-endian; residual 0xC704DD7B |
| Zero-length | allowed and must still carry CRC-32 (8.6); DPP = DPPSTART, 4 CRC bytes, DPPEND. With no data the remainder is the init value 0xFFFFFFFF, complemented = 0x00000000 (verify against a model) |
| Abort | any premature termination **shall** end with DPPABORT (EDB EDB EDB EPF) |
| Babble | DPP longer than sDataSymbolsBabble = 1030 symbols after DPPSTART with no DPPEND/DPPABORT -> invalid (Table 10-19) |
| Data Length in DPH | number of data bytes excluding CRC-32 (8.6) |

Receiver rules (7.2.4.1.9): start DPP processing only if the DPH was received properly **and**
a valid DPPSTART immediately follows. Completed on valid DPPEND. Aborted on DPPABORT, on any
K-symbol not part of a valid DPPEND/DPPABORT (then ignore the eventual DPPEND/DPPABORT), or
on babble. Drop the DPP if the DPH was corrupt or the DPP does not immediately follow. A
dropped/aborted/CRC-bad DPP is a *protocol-layer* event (ACK TP with rty, §10.6), not a link
error; the DPH was still LGOOD'ed.

On retry after LBAD a host/device may drop the DPP by setting DL in the retried DPH
(7.2.4.1.12 rule 2) - so a device receiving a retried DPH with DL=1 must not wait for a DPP.

---------------------------------------------------------------------------------------------

## 7. Link error rules (7.3)

Error-tolerance design: framing and LCSTART tolerate one bad symbol; link command words are
duplicated; headers have CRC-16+CRC-5; DPP has CRC-32 (7.3.1, BER target < 1e-12).

| Error (7.3.x) | Detection | Action (Gen 1 device) |
|---|---|---|
| Missing HP framing | not detectable directly | partner's PENDING_HP_TIMER (10 us) or our Rx HSN error -> Recovery |
| Header packet error (7.3.4.2) | CRC-5/CRC-16 fail, or K-code inside header | send LBAD, ignore HPs until LRTY; 3rd consecutive -> Recovery (no 3rd LBAD) |
| Rx HSN error (7.3.4.3) | HSN != Rx HSN on an otherwise good HP | Recovery |
| ACK Tx HSN error (7.3.6) | LGOOD_n with n != ACK Tx HSN (not an advertisement) | Recovery |
| Invalid link command (7.3.5) | LCSTART ok but words differ / bad CRC-5 / undefined | ignore |
| Missing LGOOD_n / LCRD_x (7.3.5) | out-of-order n or letter; or timers | Recovery |
| Missing LGO_Ux/LAU/LXU | PM_LC_TIMER 4 us expiry without LAU/LXU | Recovery |
| Missing LPMA | PM_ENTRY_TIMER 8 us expiry | no Recovery - just enter Ux |
| Missing LDN (upstream port) | tU0RecoveryTimeout 1 ms without any link command/packet | Recovery |
| HSN / credit advertisement errors (7.3.7, 7.3.8) | see §4.6 item 7 | Recovery |
| Training Sequence error (7.3.10) | timeout in Polling.Active/Configuration or Recovery.Active/Configuration | Polling: peripheral -> **eSS.Disabled**; Recovery: upstream port -> **eSS.Inactive** |
| 8b/10b decode/disparity error (7.3.11, 6.3.1.2) | PHY reports; SUB (K28.4) substituted | optional: LBAD if inside HP, ignore if inside link command, drop DPP if inside DPP. Never directly causes Recovery |

Counters: Link Error Count (increments per U0->Recovery for error; reset by PowerOn/Hot/Warm
Reset) is mandatory only for downstream ports (7.3.3.1); Soft Error Count is SSP-only. A device
needs neither, but GetPortErrorCount is a hub request, not a device one.

Recovery entry triggers from U0 (7.5.6.2): any of the Recovery errors above; receipt of a TS1
OS; directed; PENDING/CREDIT timer expiry (graceful). Inband reset handling (7.4.2): Hot Reset
= TS2 with Reset bit, device enters Hot Reset state, afterwards port configuration info is
**kept**, PM timers / U1,U2 timeouts reset, LTSSM -> U0; Warm Reset = long LFPS (tReset), device
-> Rx.Detect -> Polling, port configuration info reset to defaults, Rx EQ retrained.

---------------------------------------------------------------------------------------------

## 8. LTSSM for an upstream (device) port (7.5)

### 8.1 Timer table (Table 7-12, device-relevant subset; accuracy 0/+50 %)

| Name | From | To | Value |
|------|------|----|-------|
| teSSInactiveQuietTimeout | eSS.Inactive.Quiet | eSS.Inactive.Disconnect.Detect | 12 ms |
| tRxDetectQuietTimeoutUFP | Rx.Detect.Quiet | Rx.Detect.Active | 12 ms |
| tPollingLFPSTimeout | Polling.LFPS | Compliance / eSS.Disabled | 360 ms |
| tPollingSCDLFPSTimeout | Polling.LFPS | Polling.RxEQ | 60 us (SSP ports only) |
| tPollingActiveTimeout | Polling.Active | eSS.Disabled (peripheral) | 12 ms |
| tPollingConfigurationTimeout | Polling.Configuration | eSS.Disabled (peripheral) | 12 ms |
| tPollingIdleTimeout | Polling.Idle | eSS.Disabled (peripheral) | 2 ms |
| tU0RecoveryTimeout | U0 | Recovery | 1 ms |
| tU0LTimeout | U0 | U0 (send LUP) | 10 us |
| tNoLFPSResponseTimeout | U1 / U2 | eSS.Inactive | 2 ms |
| tNoLFPSResponseTimeout | U3 | U3 | 10 ms |
| PORT_U2_TIMEOUT | U1 | U2 | from U2 Inactivity Timeout LMP |
| tRecoveryActiveTimeout | Recovery.Active | eSS.Inactive | 12 ms |
| tRecoveryConfigurationTimeout | Recovery.Configuration | eSS.Inactive | 6 ms |
| tRecoveryIdleTimeout | Recovery.Idle | eSS.Inactive | 2 ms |
| tLoopbackExitTimeout | Loopback.Exit | eSS.Inactive | 2 ms |
| tHotResetActiveTimeout | Hot Reset.Active | eSS.Inactive | 12 ms |
| tHotResetExitTimeout | Hot Reset.Exit | eSS.Inactive | 2 ms |
| tU3WakeupRetryDelay | U3 | U3 | 100 ms |
| (tU1PingTimeout 300 ms, tRxDetectQuietTimeoutDFP, tU2/U3RxdetDelay are downstream-port only) |

Other: tPortConfiguration 20 us (Table 8-36, μ lost in text) - LMP exchange after U0 entry.
tResetDelay (Warm Reset declaration) 18..50 ms (6.9.3). tDisabledCount limit 3 (7.5.1.2.2).

### 8.2 State-by-state (upstream port of a peripheral)

**PowerOn Reset (7.4.1)**: while reset / VBUS invalid: Rx termination high-Z, Tx holds DC
common mode. When done and VBUS valid: LTSSM := Rx.Detect, Rx termination on (R_RX-DC) and kept
on in every state except eSS.Disabled.

**eSS.Disabled (7.5.1, peripheral has .Default and .Error substates)**
- Rx termination removed (high-Z), LFPS Tx/Rx and SS Tx/Rx disabled. Logical power-off for a
  self-powered device. VBUS may be present.
- Entered: VBUS invalid; Polling timeouts (peripheral); tPortConfiguration expiry without Port
  Capability/Configuration LMP; 8 Rx.Detect failures; directed.
- tDisabledCount: reset on invalid VBUS or successful port configuration; ++ on entry to
  .Default. .Default -> Rx.Detect when VBUS becomes valid, on a USB 2.0 bus reset with count < 3,
  or directed. Count == 3 -> .Error, which only exits on PowerOn reset (or to .Default on VBUS
  invalid for self-powered). I.e. the device tries SuperSpeed on at most 3 USB 2.0 resets.

**eSS.Inactive (7.5.2)**: link failed, software (host) intervention needed. VBUS present, Rx
termination on. Two substates: .Quiet (12 ms timer, detect disabled) -> .Disconnect.Detect (run
far-end Rx detect; termination absent -> Rx.Detect, present -> .Quiet). Upstream port exits only
on Warm Reset or far-end termination removed -> Rx.Detect. (With a PIPE PHY: P2, TxDetectRx.)

**Rx.Detect (7.5.3)**: substates .Reset, .Active, .Quiet. Rx termination maintained, Tx common
mode not required.
- .Reset: if entered because of Warm Reset, stay until LFPS Warm Reset is no longer received,
  then .Active; otherwise go to .Active immediately.
- .Active: do far-end receiver termination detection (6.11; PIPE TxDetectRx in P2/P3). Count
  detection events. Detected -> Polling. Not detected and count < 8 -> .Quiet; count == 8 ->
  eSS.Disabled (allows fallback to USB 2.0 after ~80 ms on a 2.0-only port). Note 2 of Figure
  10-26: if Rx.Detect was entered from eSS.Disabled (USB 2.0 reset retry), give up on the
  **first** failed detect.
- .Quiet: detection disabled, 12 ms timer -> .Active.

**Polling (7.5.4)**: substates LFPS, (LFPSPlus/PortMatch/PortConfig: SSP only), RxEQ, Active,
Configuration, Idle. Rx termination maintained.

- **Polling.LFPS (7.5.4.3)**: enable LFPS receiver; establish LFPS operating point within
  80 us; start 360 ms timer; transmit Polling.LFPS bursts (tBurst 0.6-1.4 us, tRepeat 6-14 us,
  §9). Exit to Polling.RxEQ when (a) >= 16 Polling.LFPS bursts sent **and** (b) handshake done:
  2 consecutive Polling.LFPS bursts received and 4 consecutive bursts sent after receiving one.
  An upstream port shall have its Compliance Mode path enabled after PowerOn Reset; on the
  360 ms timeout **if Polling.LFPS has never succeeded since PowerOn Reset** -> Compliance Mode;
  the path is disabled once a handshake succeeds (or Compliance entered). If it has trained
  before, timeout -> eSS.Disabled. Warm Reset -> Rx.Detect. A SS receiver may optionally be
  enabled already here to start RxEQ training on the partner's TSEQ.
  SSP hosts send SCD1 (Polling.LFPS with tRepeat varying 6-9 us = '0' / 11-14 us = '1', pattern
  0010 LSB first, 6.9.4) then fall back to plain Polling.LFPS; a Gen 1 device just counts the
  bursts (6.9.4.1 guard band 9-11 us) - it works either way per Figure 7-18.
- **Polling.RxEQ (7.5.4.7)**: enable polarity detection/correction (6.4.2.1). Transmit TSEQ
  65 536 times (= 2 097 152 symbols, ~4.2 ms); exit to Polling.Active after they are all sent.
  Complete Rx equalizer training by exit (PIPE PHY does this internally). Beware of training on
  your own TSEQ via NEXT - may ignore the first ~30 us.
- **Polling.Active (7.5.4.8)**: 12 ms timer. Transmit TS1 continuously (SKP OS allowed
  between). Receiver trains on TS1 or TS2. Exit to Polling.Configuration on 8 consecutive
  identical TS1 **or** TS2 received. Timeout (peripheral) -> eSS.Disabled.
- **Polling.Configuration (7.5.4.9)**: 12 ms timer. Transmit TS2 (Reset bit 0; Loopback /
  Disable Scrambling bits only if directed). Exit to Polling.Idle when 8 consecutive identical
  TS2 received and 16 TS2 sent after receiving the first of those. Timeout -> eSS.Disabled.
- **Polling.Idle (7.5.4.10)**: 2 ms timer. Decode the TS2 link configuration field: Reset
  bit -> Hot Reset; Loopback bit -> Loopback (as slave); Disable Scrambling bit -> scrambling
  off, else on. Reset port configuration info to defaults. Transmit Idle Symbols (scrambled
  D0.0, with SKP OS per Y/354). Exit to U0 when 8 consecutive Idle Symbols received and 16 Idle
  Symbols sent after receiving one. Must be able to receive the partner's LGOOD_n advertisement
  already in this state (partner may reach U0 first). Timeout -> eSS.Disabled.

**Compliance Mode (7.5.5)**: entered by an upstream port only from the very first Polling.LFPS
timeout after PowerOn Reset (passive test load case). Transmit CP0 (scrambled D0.0, no SKP),
advance to CP1.. on each Ping.LFPS, wrap after the last; exit only on Warm Reset -> Rx.Detect.
"Shall" for an upstream port (7.5.4.3.2), but a minimal device can implement CP0 only and
treat Ping.LFPS as "stay in CP0"; it is unreachable in a real host connection.

**U0 (7.5.6)**: see §4.9 timers. Transition to Recovery on: any 7.3 error listed, TS1
received, directed, 1 ms without link command/packet. 4th consecutive PENDING_HP_TIMER
timeout -> eSS.Inactive. Warm Reset -> Rx.Detect. VBUS off (self-powered) -> eSS.Disabled.
After U0 entry from Polling (directly or via Hot Reset) both ports must exchange Port
Capability LMPs within tPortConfiguration (20 us); if not received the upstream port is
directed to eSS.Disabled (7.5.6.2, 8.4.5).

**U1 (7.5.7)**: Tx DC common mode kept, Rx termination on, LFPS exit detector on. U2
inactivity timer enabled if non-zero. **Upstream port shall transmit Ping.LFPS** (Table 6-30:
tBurst 40-200 ns, tRepeat 160-240 ms) while in U1. Exit: U1 LFPS handshake -> Recovery;
2 ms tNoLFPSResponseTimeout failure -> eSS.Inactive; U2 inactivity timeout -> U2; Warm Reset ->
Rx.Detect. (The host side distinguishes a Ping from an exit by length: < 300 ns = Ping.)
**U2 (7.5.8)**: like U1 but Tx common mode may be dropped, no Ping. Exit via U2 LFPS
handshake (tBurst >= 80 us) -> Recovery, 2 ms failure -> eSS.Inactive.
**U3 (7.5.9)**: suspend. Ping detection disabled; U3 wakeup detector on. Exit via U3 wakeup
LFPS handshake (tBurst >= 80 us, tNoLFPSResponseTimeout 10 ms) -> Recovery; failure -> stay in
U3, retry after 100 ms if remote wake still wanted. Warm Reset -> Rx.Detect. The device
performs Function Wake notification after reaching U0 (9.2.5.2).

**Recovery (7.5.10)**: no Rx EQ retraining; keep header buffers (§4.6).
- Recovery.Active: 12 ms timer; transmit TS1 (Reset bit 0). Exit to Recovery.Configuration on 8
  consecutive identical TS1 or TS2. Timeout or Ux_EXIT_TIMER -> eSS.Inactive.
- Recovery.Configuration: 6 ms timer; transmit TS2 (set Loopback/Disable Scrambling only if
  directed; Reset only in Hot Reset.Active). Exit to Recovery.Idle on 8 identical TS2 received +
  16 sent after the first. Timeout -> eSS.Inactive.
- Recovery.Idle: 2 ms timer; decode TS2 bits (Reset -> Hot Reset, Loopback -> Loopback slave,
  scrambling on/off); send Idle Symbols; -> U0 on 8 Idle received + 16 sent after one. Must
  accept the LGOOD_n advertisement here. Timeout -> eSS.Inactive.

**Hot Reset (7.5.12)**: entered from Polling.Idle/Recovery.Idle when the received TS2 has
Reset=1.
- Hot Reset.Active: 12 ms timer. Send >= 16 TS2 with Reset=1 while performing the reset (reset
  PM timers and U1/U2 timeouts; port configuration info is kept; Link Error Count is a DFP
  thing). Then send TS2 with Reset=0. Exit to Hot Reset.Exit when >= 16 TS2(Reset=1) sent, 2
  consecutive TS2(Reset=0) received, 4 TS2(Reset=0) sent after receiving one. Ignore the Disable
  Scrambling bit here. Timeout -> eSS.Inactive.
- Hot Reset.Exit: 2 ms timer; send Idle Symbols; -> U0 on the 8/16 idle handshake. Afterwards
  device is in the Default USB state (address 0), HSN/credits re-advertised from 0/4.
  Sequence: host sends TS2(Reset=1); device answers TS2(Reset=1) while resetting; device then
  sends TS2(Reset=0); host answers TS2(Reset=0); both -> .Exit.

**Loopback (7.5.11)**: device becomes slave if TS2 Loopback bit set. Slave retransmits
received symbols (10b or 8b domain), may handle BERT (optional). Exit when the master's
Loopback-exit LFPS handshake is detected -> Loopback.Exit (2 ms) -> Rx.Detect. "Shall" for
transition when the bit is seen; the BERT part is "may". Not reachable with a normal host.

**Warm Reset detection (6.9.3, 7.4.2)**: LFPS burst of tReset 80-120 ms from the host; an
upstream port must detect it in every state except eSS.Disabled and declare it within
tResetDelay 18-50 ms; then go to Rx.Detect.Reset and stay until the LFPS stops; keep
"asserting" reset until LFPS ends. If the device was in U1/U2/U3 or Loopback.Active when the
LFPS started it must first treat it as an exit handshake (respond with LFPS), go to Recovery /
Rx.Detect, and the Warm Reset detection later redirects it to Rx.Detect (note in 6.9.2).

### 8.3 Which states a minimal device may skip

Required "shall" for a peripheral: eSS.Disabled (both substates), eSS.Inactive, Rx.Detect
(all 3), Polling.LFPS/RxEQ/Active/Configuration/Idle, U0, U3 (host-initiated, cannot refuse),
Recovery (all 3), Hot Reset (both), Warm Reset detection, Compliance Mode entry (but only
reachable without a real host), Loopback entry (only if a host sets the bit; "shall transition
to Loopback as slave" 7.5.4.10.2). U1/U2 acceptance can be refused with LXU forever (legal:
higher-layer condition), so U1/U2 states are needed only if the device ever sends LAU. Device-
initiated U1/U2 entry and Function Wake are optional.

---------------------------------------------------------------------------------------------

## 9. LFPS (6.9)

Electrical (Table 6-29): tPeriod 20-100 ns, duty 40-60 %, 800-1200 mVpp (400-600 mV low
power). With PIPE the PHY generates it: see §12.

Table 6-30 (SuperSpeed designs; μ restored):

| Signal | tBurst min | typ | max | tRepeat min | typ | max |
|--------|-----------|-----|-----|-------------|-----|-----|
| Polling.LFPS | 0.6 us | 1.0 us | 1.4 us | 6 us | 10 us | 14 us |
| Ping.LFPS (Gen1x1) | 40 ns (>= 2 cycles) | - | 200 ns | 160 ms | 200 ms | 240 ms |
| Warm Reset tReset | 80 ms | 100 ms | 120 ms | single burst | | |
| U1 Exit | 900 ns | - | 2 ms | single burst | | |
| U2 / Loopback Exit | 80 us | - | 2 ms | single burst | | |
| U3 Wakeup | 80 us | - | 10 ms | single burst | | |

Notes: only Ping has a minimum-cycles rule; a port must still *detect* U1 exit at 300 ns, the
extra up to 900 ns is guard band; U2/U3 need >= 80 us because the common mode may be
re-establishing.

Handshake (6.9.2, Table 6-31; LP1 = initiator starts at t10, LP2 detects and replies at t11,
LP1 stops at t12, LP2 stops at t13):

| | U1 exit min / max | U2/Loopback exit | U3 wakeup |
|---|---|---|---|
| t11-t10 (response latency) | 0.3 us / 2.0 us (2 ms if U2-inactivity enabled) | 0.3 us / 2 ms | 0.3 us / 10 ms |
| t12-t10 (initiator burst) | 0.9 us / 2 ms | 80 us / 2 ms | 80 us / 10 ms |
| t13-t11 (responder burst) | 0.9 us / 1.2 us (2 ms) | 80 us / 2 ms | 80 us / 10 ms |
| t12-t11 | 0.6 us / 2.0 us | 0.6 us / 2 ms | 0.6 us / 10 ms |
| t13-t10 | 1.2 us / 2 ms | - / 2 ms | - / 20 ms |
| tNoLFPSResponseTimeout | 2 ms | 2 ms | 10 ms |

Success for LP1: LFPS received from LP2 within tNoLFPSResponseTimeout, and LP1 is ready to send
TS1 within 20 ns of stopping its LFPS. Success for LP2: it has transmitted its minimum burst
and is ready to send TS1 within 20 ns. Both ports should send >= 900 ns on U1 exit to cover
simultaneous exit. Failure -> declared by each side independently.

Distinguishing received LFPS in the device: duration < ~300 ns = Ping (only a DFP receives
Pings; a device in U1 *sends* them); 0.3 us .. a few ms continuous = Ux exit/wakeup; keeps
going past tResetDelay (18-50 ms) = Warm Reset. Polling.LFPS = repeated ~1 us bursts every
~10 us. The device must always react to a continuous burst as an exit first, then reclassify
as Warm Reset when it lasts long enough (6.9.2 note).

Receiver detection (6.11): Tx-side common-mode step; presence judged from RC time constant.
Only in positive direction. Device must keep Rx high-Z while its power is unstable so the host
does not detect it early; in U1/U2/U3 termination must stay on.

---------------------------------------------------------------------------------------------

## 10. Protocol layer (ch 8) - device view

### 10.1 Common TP/DP header layout (Figure 8-2, Table 8-13; "DW:bit")

| Field | Offset | Width | Notes |
|-------|--------|-------|-------|
| Type | 0:0 | 5 | TP 00100, DPH 01000 |
| Route String | 0:5 | 20 | device sends 0 |
| Device Address | 0:25 | 7 | host->device: target; device->host: own address |
| SubType | 1:0 | 4 | TP only (Table 8-12); DP uses 1:0 for Seq Num |
| rsvd | 1:4 | 2 | |
| rty | 1:6 | 1 | Retry Data Packet (ACK) |
| D (Direction) | 1:7 | 1 | 0 host->device (OUT), 1 device->host (IN); **always 0 for control EP traffic** |
| Ept Num | 1:8 | 4 | |
| TT | 1:12 | 3 | reserved (0) in SuperSpeed mode |
| HE | 1:15 | 1 | Host Error (host ACK only) |
| NumP | 1:16 | 5 | number of DP buffers available / requested |
| Seq Num | 1:21 | 5 | next expected DP sequence number (0..31) |
| rsvd | 1:26 | 5 | |
| TPF | 1:31 | 1 | reserved in SS |
| Stream ID | 2:0 | 16 | 0 unless bulk streams |
| rsvd | 2:16 | 8 | |
| SSI/WPA/DBI | 2:24..2:26 | 1 each | deprecated/reserved |
| PP | 2:27 | 1 | Packets Pending, host only |
| NBI | 2:28 | 4 | deprecated |
| CRC-16 | 3:0 | 16 | |
| LCW | 3:16 | 16 | |

TP SubTypes (Table 8-12): 0001 ACK, 0010 NRDY, 0011 ERDY, 0100 STATUS, 0101 STALL, 0110
DEV_NOTIFICATION, 0111 PING, 1000 PING_RESPONSE.

| TP | Fields beyond common (differences from ACK) |
|----|---------------------------------------------|
| NRDY (8.5.2) | device only, non-iso EPs; 1:4 rsvd(3), 1:12..31 reserved (so no NumP/Seq), 2:27 reserved |
| ERDY (8.5.3) | device only; NumP at 1:16 (OUT: buffers available; IN: packets it can send, informative), rest reserved |
| STATUS (8.5.4) | host only, to control EP; 1:12.. reserved |
| STALL (8.5.5) | device only |
| DEV_NOTIFICATION (8.5.6) | Notification Type 1:4 (4): 0001 FUNCTION_WAKE (Interface at 1:8, 8 bits), 0010 LTM, 0011 BIA, 0101 SUBLINK_SPEED (optional in SS). Not from an endpoint |
| PING (8.5.7) | host only; device copies D and Ept Num into PING_RESPONSE without validating, within tPingResponse 400 ns; keep link in U0 until next packet or tPingTimeout |
| PING_RESPONSE (8.5.8) | D at 1:7, Ept at 1:8 copied; one per PING |

### 10.2 DP header (Table 8-25, differences from ACK)

| Field | Offset | Width |
|-------|--------|-------|
| Seq Num | 1:0 | 5 (wraps at 31) |
| rsvd | 1:5 | 1 |
| EOB / LPF | 1:6 | 1 - IN non-iso: last packet of burst; OUT/control: 0 |
| D | 1:7 | 1 |
| Ept Num | 1:8 | 4 |
| TT | 1:12 | 3 (0 in SS) |
| S (Setup) | 1:15 | 1, host only |
| Data Length | 1:16 | 16 - bytes in DPP excluding CRC-32 |
| Stream ID | 2:0 | 16 |
| PP | 2:27 | 1, host only |

Delayed (DL) ITPs should be ignored for timing (7.2.4.1.2); a device "shall not respond to an
ITP" (8.7) - just LGOOD/LCRD it like any header packet.

### 10.3 LMPs (8.4; Type 00000; SubType at 0:5, 4 bits, Table 8-3)

| SubType | LMP | Device role |
|---------|-----|-------------|
| 0001 | Set Link Function: 0:9 7 bits, bit1 = Force_LinkPM_Accept | receive; while asserted accept every LGO_U1/U2 with LAU |
| 0010 | U2 Inactivity Timeout: 0:9 8 bits (Table 10-17 encoding) | receive; sets U1->U2 timer |
| 0011 | Vendor Device Test: 0:9 8 bits code, 1:0 64 bits data | may ignore |
| 0100 | Port Capability | **send and receive** |
| 0101 | Port Configuration | receive (host->device) |
| 0110 | Port Configuration Response | **send** |
| 0111 | PTM / LDM | optional, ignore |

Port Capability LMP (Table 8-7):

| Field | Offset | Width | Device value |
|-------|--------|-------|--------------|
| SubType | 0:5 | 4 | 0100 |
| Link Speed | 0:9 | 7 | bit0 = 1 (Gen1) -> 0000001 |
| rsvd | 0:16 | 16 | 0 |
| Num HP Buffers | 1:0 | 8 | **4** (only legal value) |
| rsvd | 1:8 | 8 | 0 |
| Direction | 1:16 | 2 | bit0 = DFP capable, bit1 = UFP capable -> device 10b (= 2) |
| OTG | 1:18 | 1 | 0 |
| rsvd | 1:19 | 1 | 0 |
| Tiebreaker | 1:20 | 4 | 0 (only when both direction bits set) |
| rsvd | 1:24 | 40 | 0 |

=> DW0 = 0x0000_0280, DW1 = 0x0002_0004, DW2 = 0. Sent "immediately upon entering U0" after
link initialization (advertisements), within tPortConfiguration = 20 us, after every entry to
U0 from Polling (directly or via Hot Reset); if a Recovery interrupted an incomplete exchange,
continue it (7.5.6.2). Not re-sent after a plain Recovery once configuration completed. Reset
to defaults (unconfigured) by Warm Reset and Polling.Idle, kept across Hot Reset (7.4.2).

Port Configuration LMP from host (Table 8-9): SubType 0101, Link Speed 0:9 with exactly one
bit set (bit0 = Gen1); rest reserved. Device answers Port Configuration Response (Table 8-10):
SubType 0110, Response Code 0:9 bit0 = 1 (accepted) -> DW0 = 0x0000_02C0, DW1 = DW2 = 0. If the
device never receives Port Configuration within tPortConfiguration it shall go to eSS.Disabled
and try USB 2.0 (8.4.6). Successful configuration resets tDisabledCount.

### 10.4 Addressing (8.8)

Address defaults to 0 at reset/power-up; host assigns 1..127 with SET_ADDRESS. Device
Address field (0:25) in every TP/DP from the host must match the current address or the packet
is invalid (ignored at protocol level but still LGOOD/LCRD'd at link level). Device puts its
own address in packets it sends. The address changes only **after** the Status stage of
SET_ADDRESS completes (ACK TP sent in response to STATUS TP) (9.2.6.3, 9.4.6); within 50 ms.
Up to 15 IN + 15 OUT endpoints plus EP0.

### 10.5 Flow control, bursts, sequence numbers (8.10, 8.12.1)

- DP sequence numbers are per endpoint+direction, 0..31 wrap, reset to 0 by Set Configuration,
  Set Interface, ClearFeature(ENDPOINT_HALT) (and Hot/Warm Reset, Table 9-10). Control Data
  stage always starts at 0 and SETUP always uses 0.
- Burst limit = min(bMaxBurst+1, NumP of last ACK/ERDY) minus packets already sent since the
  acknowledged one. Every DP in a burst except the last must be wMaxPacketSize bytes.
- NumP may go up at any time (<= max burst); may go down by at most 1 per ACK except: receiver
  can't accept more -> NumP=0; host answers a short/EOB DP with NumP=0 (or non-zero if it has
  another transfer); rty ACK may carry any NumP.
- Short packet (Data Length < wMaxPacketSize) ends the transfer; IN device stops sending.
  If an exact-multiple transfer is shorter than wLength, a control pipe sends a ZLP (8.12.2.2).
- IN flow-control condition: device answered NRDY, or sent a DP with EOB=1. OUT: device answered
  NRDY, or ACK with NumP=0. An endpoint in flow control **shall send ERDY** when ready; an IN
  EP must wait for the ACK of its last DP before sending NRDY, STALL or ERDY. Host ignores ERDY
  from endpoints not in flow control; host may resume anyway, device re-evaluates.
- EOB rule (Table 8-25): set when returning fewer packets than NumP and this one is not short,
  or when tMaxBurstInterval (100 ns between DPs) can't be met. Re-evaluate EOB on retry.
- PP (Packets Pending) is host-only info for link PM decisions.
- tERDYTimeout 500 ms: after sending ERDY the device may initiate/accept U1/U2 only after this.

### 10.6 Response tables (8.11)

Invalid TP/DPH (ignore at protocol level): wrong Device Address; EP/direction not in current
configuration; unexpected sequence number; (DP) Data Length > wMaxPacketSize. Invalid SETUP
DPH additionally: not a control EP, Seq != 0, Data Length != 8. DPP error = bad CRC-32,
DPPABORT, DPP missing, or Data Length != actual payload length.

Device response to ACK TP requesting IN data (Table 8-27):

| invalid | DF set | halted | ready | action |
|---|---|---|---|---|
| yes | - | - | - | ignore |
| no | yes | yes | - | ERDY |
| no | yes | no | no | nothing; ERDY when ready |
| no | yes | no | yes | ERDY |
| no | no | yes | - | STALL |
| no | no | no | no | NRDY |
| no | no | no | yes | send DPs from the requested Seq Num |

Device response to OUT DP (Table 8-29):

| invalid | DF | halted | DPP err | can accept | action |
|---|---|---|---|---|---|
| yes | - | - | - | - | discard |
| no | yes | yes | - | - | ERDY |
| no | yes | no | - | no | nothing; ERDY when ready |
| no | yes | no | - | yes | ERDY |
| no | no | yes | - | - | STALL |
| no | no | no | - | no | discard, NRDY |
| no | no | no | yes | yes | discard, ACK with Seq = expected (same), rty=1, NumP = buffers |
| no | no | no | no | yes | ACK with Seq = next expected, NumP = buffers |

Device response to SETUP DP (Table 8-30): invalid -> discard; DF set -> ERDY; DPP error -> ACK
Seq=0, rty=1, NumP=1; good -> ACK Seq=1 (NumP=0 to flow-control the next stage, then ERDY to
resume; NumP=1 otherwise).

Host response to device IN DPs (Table 8-28): good -> ACK Seq=next, NumP>=0; DPP error -> ACK
rty=1 Seq=bad one (NumP 0..n); host can't accept -> ACK rty=1 HE=1. Device must resend from
the Seq Num in a rty ACK, even if later packets of the burst were fine (8.12.1.2).

Timing (Table 8-36): tNRDYorSTALLResponse, tDPResponse, tACKResponse, tPingResponse all
<= 400 ns from last framing symbol received to first framing symbol sent (when nothing else
queued); tHostACKResponse 3 us; tMaxBurstInterval 100 ns; tHostTransactionTimeout 7.6-25 ms
(host halts the EP if the device never answers); tPortConfiguration 20 us; tERDYTimeout 500 ms;
tNotification 2500 ms (repeat Function Wake); tPingTimeout 2 service intervals.

### 10.7 Transfer sequences

Control (8.12.2): SETUP DP (S=1, Seq 0, Data Length 8, D=0) -> ACK(Seq=1). Data stage (if
wLength>0): same as bulk but D=0 always, Seq starts at 0, burst = 1 (bMaxBurst=0 for control),
512-byte packets. Control-IN data: host ACK(Seq=0,NumP=1) -> device DP(Seq 0) -> host ACK(Seq=1,
NumP=0 or 1) ... ; Control-OUT data: host DP(Seq 0) -> device ACK(Seq=1,NumP=1). Status:
host STATUS TP (treated as an OUT transaction) -> device ACK (NumP **= 0**, not a flow-control
condition) / NRDY (then ERDY later; host re-sends STATUS) / STALL. A STALL in Data or Status
stage persists until the next SETUP; more data than wLength -> STALL; STALL in data stage ->
no status stage. If DF is set in STATUS -> send ERDY. Request Error -> STALL in data or
status stage (9.2.7); control pipes have no functional halt.

Bulk IN (8.12.1.2): host ACK(Seq=n, NumP=k) -> device sends up to k DPs Seq n, n+1, ...
without waiting; each DP is answered by host ACK(Seq=next, NumP=remaining or more); error ->
ACK rty Seq=first bad; device resends from there. Device without k packets sets EOB on its
last DP (not needed if that DP is short). Transfer ends on short DP; next transfer starts
with host ACK carrying the next Seq.

Bulk OUT (8.12.1.3): host sends DPs Seq 0,1,2..; device ACKs each (Seq=next, NumP=free
buffers); NRDY if no buffer (then ERDY); ACK rty on DPP error. Host restarts a burst after a
short DP. Interrupt (8.12.4): same as bulk, burst <= 3 DPs per service interval, host's final
ACK of the interval has NumP=0.

Isochronous and streams: not needed; ITP: ignore content (but still link-ack it).

---------------------------------------------------------------------------------------------

## 11. Chapter 9 deltas for a SuperSpeed device

| Item | Requirement | Ref |
|------|-------------|-----|
| bcdUSB | **0x0310** for an Enhanced SuperSpeed device (0x0210 when running at USB 2.0 speeds); 0x0300 is what the text calls "version 3.0" and 0x0320 is not mandated - the spec says 3.1 (0310H) | 9.6.1 |
| bMaxPacketSize0 | **0x09** (2^9 = 512), the only legal value at Gen X | 9.6.1 |
| wMaxPacketSize | control 512; bulk 1024; interrupt/iso 1024 if bMaxBurst>0 else 1..1024 | 9.6.6 |
| bInterval | interrupt/iso: 1..16, period 2^(bInterval-1) × 125 us; reserved for bulk/control | 9.6.6 |
| BOS descriptor | mandatory (GetDescriptor(BOS), type 15): bLength 5, type 0x0F, wTotalLength, bNumDeviceCaps; must contain USB 2.0 Extension + SuperSpeed USB Device Capability; Container ID optional | 9.6.2 |
| Endpoint Companion | type 0x30 (48), 6 bytes, follows every endpoint descriptor (not EP0) | 9.6.7 |
| Descriptor type codes | DEVICE 1, CONFIGURATION 2, STRING 3, INTERFACE 4, ENDPOINT 5, INTERFACE_ASSOCIATION 11, BOS 15, DEVICE CAPABILITY 16, SS_ENDPOINT_COMPANION 48 | Table 9-6 |

USB 2.0 Extension (Table 9-15): bLength 7, bDescriptorType 0x10, bDevCapabilityType 0x02,
bmAttributes (4 bytes) bit1 LPM = **1** (shall), others 0.

SuperSpeed USB Device Capability (Table 9-16): bLength 10, type 0x10, bDevCapabilityType 0x03,
bmAttributes (1 byte) bit1 = LTM capable (0 for minimal), wSpeedsSupported (2 bytes) bit0 LS,
bit1 FS, bit2 HS, bit3 **Gen1** (e.g. 0x000E or 0x0008), bFunctionalitySupport = bit *index* (from wSpeedsSupported) of the lowest speed at which all
functionality is available (0 LS, 1 FS, 2 HS, 3 Gen1; e.g. 1 if everything works from full speed up),
bU1DevExitLat (1 byte, 0x00..0x0A = "< N us"), wU2DevExitLat (2 bytes, 0..0x07FF = "< N us").
A device that will always LXU can still report e.g. 0x0A / 0x07FF.

SuperSpeed Endpoint Companion (Table 9-28): bLength 6, bDescriptorType 0x30, bMaxBurst 0..15
(burst = bMaxBurst+1; control: 0), bmAttributes (bulk: bits 4:0 MaxStreams log2, 0 = none;
control/interrupt: 0; iso: bits 1:0 Mult), wBytesPerInterval (periodic EPs only; 0 for
bulk/control).

Standard requests (Table 9-4/9-5; new vs 2.0 in bold): GET_STATUS 0, CLEAR_FEATURE 1,
SET_FEATURE 3, SET_ADDRESS 5, GET_DESCRIPTOR 6, SET_DESCRIPTOR 7, GET_CONFIGURATION 8,
SET_CONFIGURATION 9, GET_INTERFACE 10, SET_INTERFACE 11, SYNCH_FRAME 12, **SET_SEL 48**,
**SET_ISOCH_DELAY 49**. Setup packet layout unchanged (bmRequestType, bRequest, wValue, wIndex,
wLength).

| Request | Fields | Device must |
|---------|--------|-------------|
| SET_ISOCH_DELAY (9.4.11) | bmRequestType 0x00, bRequest 49, wValue = delay ns 0..65535, wIndex 0, wLength 0 | accept (ACK status) in Default/Address/Configured; value may be ignored by non-iso devices |
| SET_SEL (9.4.12) | 0x00, bRequest 48, wValue 0, wIndex 0, wLength 6, data: U1SEL(1) U1PEL(1) U2SEL(2) U2PEL(2) in us | accept 6-byte OUT data stage and ACK status in Address/Configured; may store and ignore |
| SET/CLEAR_FEATURE U1_ENABLE (48) / U2_ENABLE (49) | recipient device, wIndex 0 | Configured state only; Address state -> Request Error (STALL). Enables *device-initiated* U1/U2 entry; a device that never initiates may simply latch the bits and report them in GET_STATUS |
| SET/CLEAR_FEATURE LTM_ENABLE (50) | device | only if LTM capable; else STALL |
| SET_FEATURE FUNCTION_SUSPEND (0, recipient interface, wIndex low byte = first interface of function, high byte = suspend options bit0 low-power suspend, bit1 function remote wake enable) | interface | Configured only; accept; remember remote-wake enable |
| ENDPOINT_HALT (0, recipient endpoint) | wIndex = EP addr | halt bulk/interrupt EPs; ClearFeature always resets the EP's sequence number to 0 and un-halts |
| DEVICE_REMOTE_WAKEUP (1), TEST_MODE (2) | - | ignored / not used by SS devices (9.2.5.4) |

GET_STATUS (9.4.5) returns 2 bytes: device: D0 Self Powered, D1 reserved (0; "Remote Wakeup"
is 2.0-only), D2 U1 Enable, D3 U2 Enable, D4 LTM Enable. Interface (first interface of a
function): D0 Function Remote Wake Capable, D1 Function Remote Wakeup enabled. Endpoint: D0
Halt. wValue low byte = Status Type (00 standard, 01 PTM).

Device states (9.1.1): Attached -> Powered (Far-end Rx Termination / Link Training substates)
-> Default (link in U0, address 0) -> Address -> Configured; Suspended (link in U3) from
Default/Address/Configured; Error when the link exits Recovery by timeout (eSS.Inactive). Warm
Reset, or termination removal, returns to Powered. Hot Reset returns to Default (address 0,
configuration cleared, Table 9-10). Link Recovery does not change USB state. Port
Configuration failure -> USB 2.0 device states.

Table 9-10 effects: Warm Reset / Hot Reset / SetAddress(0) reset: address, configuration,
alt settings, SELs, halts, function remote wake, isoch delay, U2 inactivity timeout,
Force_LinkPM_Accept, U1/U2/LTM enable, DP sequence numbers, hub depth. SetConfiguration
resets alt settings, halts, remote wake, sequence numbers. ClearFeature(ENDPOINT_HALT) resets
that EP's halt and sequence number. Port Configuration Information resets only on Warm Reset.

Request timing (9.2.6): no-data requests complete status within 50 ms; data-IN first packet
within 500 ms; SET_ADDRESS within 50 ms; descriptor requests must be answered before an
address is assigned.

Remote wake (optional, 9.2.5.2-9.2.5.4): device drives U3 wakeup LFPS, reaches U0, sends
DEV_NOTIFICATION(FUNCTION_WAKE, interface); repeat every tNotification 2.5 s until accessed.
Only if some function has Function Remote Wake enabled via SET_FEATURE(FUNCTION_SUSPEND).
U3 is entered on host LGO_U3 and always accepted (7.2.4.2.4); device state kept per Table 9-2
(address, config, HSN, SELs, etc.).

---------------------------------------------------------------------------------------------

## 12. PIPE 3.x notes for the USB mode (pipe31.txt = PIPE 5.1)

Signals used (PIPE 6.1, 6.3; 32-bit original PIPE): TxData[31:0] (byte 0 = bits 7:0 sent
first, bit 0 first on the wire), TxDataK[3:0] (1 = K-code per byte), TxDataValid (keep 1 in
Gen 1), TxElecIdle, TxDetectRx/Loopback, PowerDown[1:0] (P0 00, P1 01, P2 10, P3 11 in USB
mode), Rate (0 = 5 GT/s), Width (2 = 32 bit), PCLK Rate (0 = 125 MHz), RxTermination (1 =
terminations present; required for USB PHYs), RxStandby, RxPolarity, Reset#, RxEIDetectDisable
(optional); outputs RxData[31:0], RxDataK[3:0], RxValid (symbol lock), RxDataValid (nominal-
empty EB), RxElecIdle (asynchronous; low = LFPS/signal present), RxStatus[2:0], PhyStatus,
PowerPresent (VBUS). TxCompliance/TxOnesZeros are PCIe-only; the compliance patterns for USB
are ordinary data (CP0 = scrambled zeros) or LFPS.

Control decode in USB mode (PIPE 8.23):

| PowerDown | TxDetectRx/Loopback | TxElecIdle | PHY does |
|-----------|---------------------|------------|----------|
| P0 | 0 | 0 | transmit TxData |
| P0 | 0 | 1 | electrical idle (data already handed over is flushed first) |
| P0 | 1 | 0 | loopback |
| P0 | 1 | 1 | **transmit LFPS** |
| P1 | x | 0 | transmit LFPS |
| P1 | x | 1 | electrical idle |
| P2/P3 | 0 | 1 | idle |
| P2/P3 | 1 | 1 | receiver detection |
| P2/P3 | x | 0 | not allowed |

- Reset (PIPE 8.2): hold Reset# until power/CLK stable; during reset keep TxDetectRx=0,
  TxElecIdle=1, PowerDown=P2, Rate=5 GT/s (or highest), RxTermination implementation-specific.
  PhyStatus deassertion after Reset# release = PCLK valid; no operations before that.
- Power states (PIPE 8.4): P0 = U0/Polling/Recovery/etc., P1 = U1 (idle tx/rx only, PCLK on),
  P2 = U2, Rx.Detect, eSS.Inactive (PCLK on, common mode off, can do Rx detect and receive
  LFPS), P3 = eSS.Disabled and U3 (PCLK off, async PhyStatus handshake). Legal transitions:
  P0->P1, P0->P2, P0->P3, P1->P0, P2->P0, P3->P0, P1->P2. PhyStatus pulses once per completed
  transition; wait for it before the next operation. U1 exit budget: RxElecIdle reflects LFPS
  within 120 ns, P1->P0 within 300 ns, LFPS tx latency 100 ns.
- Rate/width change (PIPE 8.6.2): only in P0 or P2 with TxElecIdle and RxStandby asserted;
  not needed for Gen1-only.
- Receiver detect (PIPE 8.9): in P2 or P3, assert TxDetectRx/Loopback, wait for PhyStatus
  pulse, read RxStatus = 011 (present) / 000 (absent), then deassert TxDetectRx before anything
  else. In P3 PhyStatus/RxStatus stay asserted until TxDetectRx is dropped.
- LFPS transmit (PIPE 8.11): in P0 assert TxElecIdle **and** TxDetectRx/Loopback for the burst
  duration (Polling.LFPS, exits in U0 context); in P1 deassert TxElecIdle for the burst and
  reassert before going to P0. PHY completes a full LFPS period before switching to SS data and
  may drop SS data if the requests overlap - leave a gap.
- LFPS receive (PIPE 8.13): RxElecIdle low while LFPS present (in P0-P3); a 2-cycle Ping gives
  at most 200 ns low; detect latency <= 120 ns in P0-P2, up to 10 us in P3. The MAC measures the
  low time to classify Polling/exit/Warm Reset (§9).
- Elastic buffer (PIPE 8.14): half-full mode - PHY adds/removes whole SKP OS (USB 5 GT/s),
  flagged by RxStatus 001 (added) / 010 (removed) for one cycle; nominal-empty mode - PHY
  removes **all** SKPs and deasserts RxDataValid when empty (recommended). In half-full mode
  the PHY only adds/removes SKPs at positions where a SKP OS was received, and the link partner
  never transmits SKP OS inside a packet, so the MAC still sees SKP OS only between packets /
  between training ordered sets; it must simply tolerate 0, 2, 4, ... SKP symbols there and
  must not treat a SKP OS as breaking "consecutive" TS1/TS2/Idle counts (6.4.3.1).
- Errors (PIPE 8.15): RxStatus 100 = 8b/10b decode (byte replaced by SUB K28.4), 101 = EB
  overflow (symbol dropped), 110 = EB underflow (SUB inserted), 111 = disparity error
  (optional in USB mode; may be folded into 100). Error signalling has priority over SKP
  add/remove on the same cycle. Elastic Buffer Reset via message-bus register (optional).
- Polarity (PIPE 8.17): assert RxPolarity when D21.5 (0xB5) is seen where D10.2 (0x4A) is
  expected in TSEQ/TS1; inverted data appears within 20 PCLKs. Only valid in P0.
- Rx disparity note (6.3.1.2): first symbol after electrical idle may use any disparity;
  disparity errors do not retrain the link.

---------------------------------------------------------------------------------------------

## 13. Implementation checklist / gotchas distilled

1. TSEQ is 32 symbols (not 16) and is sent 65 536 times with **no SKP OS at all** during
   that ~4.2 ms; the PHY elastic buffer must cope (nominal-empty PHYs are fine).
2. Scrambler advances on every non-SKP symbol including K-codes; it is reset only by COM, so
   nothing resets it during U0. LFSR seed FFFF, poly x^16+x^5+x^4+x^3+1, data bit i XOR
   lfsr[15-i].
3. CRC-16 poly 0x100B (not 0x8005), CRC-5 poly 0x05, CRC-32 0x04C11DB7; all three: init all
   ones, complement, bit-reverse into the field; residuals F6AA / 01100b / C704DD7B.
4. Link command word = 11 bits + CRC-5 in bits 15:11, sent twice; both copies must match and
   pass CRC-5 or the command is silently ignored.
5. On U0 entry, before sending anything: send LGOOD_7 (or LGOOD_(RxHSN-1)) then LCRD_A..D;
   wait for the host's LGOOD_n and >= 1 LCRD before the first header packet; then send Port
   Capability LMP within 20 us. Missing Port Capability/Configuration -> eSS.Disabled.
6. Every received header packet - including ITPs, LMPs for other purposes, packets with
   wrong device address or reserved values - must be LGOOD'ed and LCRD'ed; only the protocol
   layer drops them.
7. Send LUP every 10 us of idle; expect LDN within 1 ms or go to Recovery. Both LUP/LDN are
   ordinary 8-symbol link commands and reset tU0LTimeout like any other transmission.
8. Device response latency targets: LGOOD/LBAD within 2.54 us (400 ns recommended), ACK/NRDY/
   STALL/DP/PING_RESPONSE within 400 ns of the last framing symbol.
9. Control EP: D=0 in all TPs/DPs of all stages; SETUP Seq=0 answered with ACK Seq=1; STATUS
   answered with ACK NumP=0; EP0 is 512 bytes; bcdUSB 0x0310; bMaxPacketSize0 = 9; BOS with
   USB 2.0 Ext (LPM=1) and SS capability; endpoint companions; accept SET_SEL and
   SET_ISOCH_DELAY; U1/U2_ENABLE only in Configured state.
10. LGO_U3 can never be refused; LGO_U1/U2 may always be refused with LXU unless the host has
    sent Set Link Function(Force_LinkPM_Accept). After LAU nothing may be transmitted; enter Ux
    on LPMA or 8 us timeout; TS1 instead -> Recovery.
11. Polling timeouts on a peripheral go to eSS.Disabled (then USB 2.0 fallback); Recovery
    timeouts go to eSS.Inactive (needs Warm Reset from the host). PENDING_HP_TIMER expiring 4
    times in a row also -> eSS.Inactive.
12. Compliance Mode is entered after the first 360 ms Polling.LFPS timeout after power-on
    (never once a handshake has succeeded); a device on a real host port never gets there, but
    the rule means a device that powers up with the cable attached to an unpowered/absent host
    receiver sits in Compliance until Warm Reset or VBUS removal.
13. Warm Reset must be detected in every link state except eSS.Disabled, including U3 (so the
    LFPS detector must stay alive in P3), and must first be treated as a Ux exit.
14. Hot Reset keeps port configuration (no new Port Capability exchange is needed per 7.4.2,
    yet 7.5.6.2 scenario 2 says entry to U0 "indirectly from Polling through Hot Reset" does
    need it) - implement: re-exchange only if the configuration was never completed.
