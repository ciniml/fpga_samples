# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# ModRetro Chromatic helper targets (included at the end of build_gowin.mk)
CHROMATIC_FLASH := $(TARGET_DEF_DIR)/chromatic_flash.sh
CHROMATIC_BACKUP_DIR ?= $(HOME)/chromatic-backups
CONFIRM_FLASH ?=
export CHROMATIC_BACKUP_DIR CONFIRM_FLASH

.PHONY: chromatic-detect chromatic-backup chromatic-restore chromatic-flash-check

# check that the FPGA is reachable over the GWU2X bridge
chromatic-detect:
	$(CHROMATIC_FLASH) detect

# save the current flash image (the official one, the first time) to $(CHROMATIC_BACKUP_DIR)
chromatic-backup:
	$(CHROMATIC_FLASH) backup

# write a backup image back: make chromatic-restore BACKUP=<file> CONFIRM_FLASH=yes
chromatic-restore:
	$(CHROMATIC_FLASH) restore "$(BACKUP)"

# run before "make deploy": needs CONFIRM_FLASH=yes, a backup, and a bitstream for this part
chromatic-flash-check: $(BITSTREAM)
	$(CHROMATIC_FLASH) check "$(abspath $(BITSTREAM))"
