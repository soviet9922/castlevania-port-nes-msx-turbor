SJASMPLUS ?= sjasmplus
PYTHON    ?= python3
OPENMSX   ?= openmsx

# Your own Castlevania (NES) ROM dump, used only by the *-nes targets.
NES_ROM   ?= build/nes/castlevania.nes

BUILD     := build
PH_GEN    := $(BUILD)/gen/placeholder
CV_GEN    := $(BUILD)/gen/converted
ROM       := $(BUILD)/cvmsx.rom
NES_OUT   := $(BUILD)/cvmsx-nes.rom

ASM_SRC   := $(wildcard src/*.asm src/*.inc)
PH_TOOLS  := tools/gen_placeholder_assets.py tools/msx_area.py tools/msx_sprites.py tools/areas_asm.py
CV_TOOLS  := $(PH_TOOLS) tools/convert_stage.py tools/cv_rom.py tools/convert_simon.py tools/convert_objects.py \
             tools/sprite_edit.py $(wildcard art_overrides/*.bmp)

SJASM_FLAGS = --nologo --msg=war --fullpath --inc=src

.PHONY: all nes run run-cbios run-nes test test-nes clean

# Default: original placeholder art only (no ROM needed)
all: $(ROM)

# Converted from your NES ROM (output stays in build/, never committed)
nes: $(NES_OUT)

$(PH_GEN)/.stamp: $(PH_TOOLS)
	$(PYTHON) tools/gen_placeholder_assets.py $(PH_GEN)
	@touch $@

$(CV_GEN)/.stamp: $(PH_GEN)/.stamp $(CV_TOOLS) $(NES_ROM)
	@mkdir -p $(CV_GEN)
	cp $(PH_GEN)/*.bin $(PH_GEN)/*.inc $(CV_GEN)/
	$(PYTHON) tools/convert_stage.py $(NES_ROM) $(CV_GEN)
	@touch $@

$(ROM): $(ASM_SRC) $(PH_GEN)/.stamp
	$(SJASMPLUS) $(SJASM_FLAGS) --inc=$(PH_GEN) \
		--raw=$@ --sym=$(@:.rom=.sym) --lst=$(@:.rom=.lst) src/main.asm
	@echo "built $@"

$(NES_OUT): $(ASM_SRC) $(CV_GEN)/.stamp
	$(SJASMPLUS) $(SJASM_FLAGS) --inc=$(CV_GEN) \
		--raw=$@ --sym=$(@:.rom=.sym) --lst=$(@:.rom=.lst) src/main.asm
	@echo "built $@"

# Real turbo R (needs the machine's system ROMs installed in openMSX)
run: $(ROM)
	$(OPENMSX) -machine Panasonic_FS-A1GT -cart $< -romtype ASCII16

# Free C-BIOS MSX2+ machine (V9958, Z80 at 3.58 MHz) - works out of the box
run-cbios: $(ROM)
	$(OPENMSX) -machine C-BIOS_MSX2+ -cart $< -romtype ASCII16

run-nes: $(NES_OUT)
	$(OPENMSX) -machine C-BIOS_MSX2+ -cart $< -romtype ASCII16

test: $(ROM)
	$(PYTHON) tests/run_smoke.py $<

test-nes: $(NES_OUT)
	$(PYTHON) tests/run_smoke.py $<

clean:
	rm -rf $(BUILD)/gen $(BUILD)/test $(BUILD)/*.rom $(BUILD)/*.sym $(BUILD)/*.lst
