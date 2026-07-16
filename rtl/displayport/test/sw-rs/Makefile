.PHONY: all clean

TARGET := bootrom-rs

all: $(TARGET).bin $(TARGET).dump $(TARGET).hex $(TARGET)-board.hex

$(TARGET).bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release  -- -O binary $@

$(TARGET).dump: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objdump --bin $(TARGET) --release -- -dSC > $@


# Board bring-up firmware (Tang Primer 25K): same binary built with the
# `board` cargo feature, which selects the 800x600@60 video profile.
$(TARGET)-board.bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release --features board -- -O binary $@

%.hex: %.bin
	od -An -tx4 -w4 -v $< > $@

clean:
	-@$(RM) $(TARGET).bin $(TARGET)-board.bin $(TARGET).lst $(TARGET)*.hex