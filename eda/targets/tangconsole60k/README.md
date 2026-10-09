# Tang Console 60K (GW5AT-LV60PG484AC1/I0)

Pins taken from the Console schematic (`doc/Tang_Mega_60K_Console_32001C__Schematics.pdf`,
sheet names in braces) and the Mega 60K dock pin file.

| Signal | Ball | Notes |
|---|---|---|
| sys_clk 50 MHz | V22 | SOM oscillator, LVCMOS33 |
| FPGA_UART.TX | U15 | BANK6, to the BL616 USB-UART |
| FPGA_UART.RX | V14 | BANK8 |
| EX_KEY.0/1/2 | AA13 / AB13 / Y12 | BANK9 is 1.5 V on the 60K |
| USR_CLK_IN | V10 | BANK9 |
| USB3-A port 1 | SerDes Q0 Lane2 (RX B10, TX B6), USB 2.0 pair M15 (D+) / M16 (D-) BANK5 | |
| USB3-A port 2 | SerDes Q0 Lane3 (RX D9, TX D7), USB 2.0 pair H13 (D+) / G13 (D-) BANK4 | |
| SerDes REFCLK1 | F10 (P) / E10 (N) | MS5351 CLK1 (P) / CLK0 (N), AC-coupled: program both to 125 MHz, CLK0 inverted |
| SerDes REFCLK0 | F6 / E6 | PCIe connector reference clock |
| MS5351 I2C | FPGA M13 (SCL) / L13 (SDA) BANK5 = DVI_DDC, 22 R to PLL_TWI which the BL616 (DBG_TWI) also drives | address 0x60 |
| Type-C (TN710 soft USB 2.0 PHY) | see eda/usb_device notes | |

Programming: `openFPGALoader --board tangconsole --write-sram <bitstream>` (idcode 0x0001481b).
The BL616 enumerates as an FT2232-compatible JTAG + UART (`/dev/ttyUSB1` is the UART).

`gw_ide.sh` launches the Gowin IDE on an X display with the Ubuntu 24.04 workarounds;
`ip_trial/` holds the IP generation trials (USB 3.0 PHY, Customized PHY, EasyCDR).
