# GOWIN DK_LED-RXCARD_GW3A-LV20UG324S_V2.1 (Arora III GW3A-20A, LED
# receiving card). Needs Gowin EDA 1.9.12.03 (the only release with
# GW3A-20A support).
DEVICE_FAMILY := GW3A-20A
DEVICE_PART := GW3A-LV20UG324SC1/I0
DEVICE := GW3A-20A
USE_OPENFPGA_LOADER ?= 0
# gw_sh of 1.9.12.03 regardless of PATH (override with make GW_SH=...);
# IDE/lib first or it picks up the system Qt plugins and aborts.
GOWIN_GW3A_HOME ?= $(HOME)/gowin/1.9.12.03
GW_SH := env LD_LIBRARY_PATH=$(GOWIN_GW3A_HOME)/IDE/lib QT_QPA_PLATFORM=offscreen $(GOWIN_GW3A_HOME)/IDE/bin/gw_sh
PROGRAMMER_CLI_DIR := $(GOWIN_GW3A_HOME)/Programmer/bin/
# no embedded flash on GW3A: make deploy writes the external SPI flash
# (exFlash Erase,Program,Verify; the board boots from it)
PROGRAMMER_FLASH_OP_INDEX := 9
