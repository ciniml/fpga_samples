.PHONY: all clean

WAVEDROM_SVGS := $(patsubst %.json5,%.svg,$(wildcard figure/*.json5))

all: $(WAVEDROM_SVGS)

figure/%.svg: figure/%.json5
	$(shell npm bin)/wavedrom-cli -i $< -s $@


clean:
	-@$(RM) *.svg