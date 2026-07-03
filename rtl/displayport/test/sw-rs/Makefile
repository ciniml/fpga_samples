.PHONY: all clean

TARGET := bootrom-rs

all: $(TARGET).bin $(TARGET).dump $(TARGET).hex

$(TARGET).bin: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objcopy --bin $(TARGET) --release  -- -O binary $@

$(TARGET).dump: $(wildcard src/*.rs) link.ld Cargo.toml .cargo/config.toml
	cargo objdump --bin $(TARGET) --release -- -dSC > $@


%.hex: %.bin
	od -An -tx4 -w4 -v $< > $@

clean:
	-@$(RM) $(TARGET).bin $(TARGET).lst $(TARGET)*.hex