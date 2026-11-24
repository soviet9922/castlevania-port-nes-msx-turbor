SJASMPLUS ?= sjasmplus
PYTHON    ?= python3
OPENMSX   ?= openmsx

BUILD     := build
GEN       := $(BUILD)/gen
ROM       := $(BUILD)/cvmsx.rom

ASM_SRC   := $(wildcard src/*.asm src/*.inc)
GEN_INC   := $(GEN)/assets.inc

.PHONY: all run run-cbios test clean

all: $(ROM)

$(GEN_INC): tools/gen_placeholder_assets.py
	$(PYTHON) tools/gen_placeholder_assets.py $(GEN)

$(ROM): $(ASM_SRC) $(GEN_INC)
	@mkdir -p $(BUILD)
	$(SJASMPLUS) --nologo --msg=war --fullpath \
		--inc=src --inc=$(GEN) \
		--raw=$(ROM) --sym=$(BUILD)/cvmsx.sym --lst=$(BUILD)/cvmsx.lst \
		src/main.asm
	@echo "built $(ROM) ($$(stat -c %s $(ROM)) bytes)"

# Real turbo R (needs the machine's system ROMs installed in openMSX)
run: $(ROM)
	$(OPENMSX) -machine Panasonic_FS-A1GT -cart $(ROM) -romtype ASCII16

# Free C-BIOS MSX2+ machine (V9958, Z80 at 3.58 MHz) - works out of the box
run-cbios: $(ROM)
	$(OPENMSX) -machine C-BIOS_MSX2+ -cart $(ROM) -romtype ASCII16

test: $(ROM)
	$(PYTHON) tests/run_smoke.py

clean:
	rm -rf $(BUILD)
