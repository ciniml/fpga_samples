.PHONY: all clean

TARGET := bootrom-rs

all: $(TARGET).bin $(TARGET).dump $(TARGET).hex $(TARGET)-board.hex $(TARGET)-4lane.hex

$(TARGET).bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release  -- -O binary $@

$(TARGET).dump: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objdump --bin $(TARGET) --release -- -dSC > $@


# Board bring-up firmware (Tang Primer 25K): same binary built with the
# `board` cargo feature, which selects the 800x600@60 video profile.
$(TARGET)-board.bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release --features board -- -O binary $@

# 4-lane sim firmware (small raster, 12/11 rate ratio, tu_active=44).
$(TARGET)-4lane.bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release --features lanes4 -- -O binary $@

%.hex: %.bin
	od -An -tx4 -w4 -v $< > $@

clean:
	-@$(RM) $(TARGET).bin $(TARGET)-board.bin $(TARGET).lst $(TARGET)*.hex