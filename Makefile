SJASMPLUS ?= sjasmplus
PYTHON    ?= python3
OPENMSX   ?= openmsx

# Your own Castlevania (NES) ROM dump, used only by the *-nes targets.
NES_ROM   ?= build/nes/castlevania.nes

# Sound in the *-nes build: "placeholder" (original sounds, tools/gen_sound.py)
# or "rom" (your ROM's music and effects, converted on your machine by
# tools/convert_sound.py; the result stays in build/, never committed)
SOUND     ?= placeholder

# The debug menu at power-up (start stage, infinite health and time, sound
# test): DEBUG=0 builds the game without it
DEBUG     ?= 1

BUILD     := build
PH_GEN    := $(BUILD)/gen/placeholder
CV_GEN    := $(BUILD)/gen/converted
ROM       := $(BUILD)/cvmsx.rom
NES_OUT   := $(BUILD)/cvmsx-nes.rom

ASM_SRC   := $(wildcard src/*.asm src/*.inc)
PH_TOOLS  := tools/gen_placeholder_assets.py tools/msx_area.py tools/msx_sprites.py tools/areas_asm.py \
             tools/gen_sound.py tools/sound_out.py
CV_TOOLS  := $(PH_TOOLS) tools/convert_stage.py tools/cv_rom.py tools/convert_simon.py tools/convert_objects.py \
             tools/sprite_edit.py $(wildcard art_overrides/*.bmp) \
             tools/convert_sound.py tools/nes_sound.py tools/cpu6502.py

SJASM_FLAGS = --nologo --msg=war --fullpath --inc=src -DDEBUG_MENU=$(DEBUG)

.PHONY: all nes run run-cbios run-nes test test-nes clean

# a failed assembly must not leave a ROM behind that looks up to date
.DELETE_ON_ERROR:

# Default: original placeholder art only (no ROM needed)
all: $(ROM)

# Converted from your NES ROM (output stays in build/, never committed)
nes: $(NES_OUT)

$(PH_GEN)/.stamp: $(PH_TOOLS)
	$(PYTHON) tools/gen_placeholder_assets.py $(PH_GEN)
	$(PYTHON) tools/gen_sound.py $(PH_GEN)
	@touch $@

$(CV_GEN)/.stamp: $(PH_GEN)/.stamp $(CV_TOOLS) $(NES_ROM) $(BUILD)/.sound-$(SOUND)
	@mkdir -p $(CV_GEN)
	rm -f $(CV_GEN)/snd_bank*.bin
	cp $(PH_GEN)/*.bin $(PH_GEN)/*.inc $(PH_GEN)/sound_banks.asm $(CV_GEN)/
	$(PYTHON) tools/convert_stage.py $(NES_ROM) $(CV_GEN)
	@if [ "$(SOUND)" = rom ]; then rm -f $(CV_GEN)/snd_bank*.bin; \
	    $(PYTHON) tools/convert_sound.py $(NES_ROM) $(CV_GEN); fi
	@touch $@

# rebuild the converted set when SOUND changes
$(BUILD)/.sound-$(SOUND):
	@mkdir -p $(BUILD)
	@rm -f $(BUILD)/.sound-*
	@touch $@

# rebuild the ROMs when DEBUG changes
$(BUILD)/.debug-$(DEBUG):
	@mkdir -p $(BUILD)
	@rm -f $(BUILD)/.debug-*
	@touch $@

$(ROM): $(ASM_SRC) $(PH_GEN)/.stamp $(BUILD)/.debug-$(DEBUG)
	$(SJASMPLUS) $(SJASM_FLAGS) --inc=$(PH_GEN) \
		--raw=$@ --sym=$(@:.rom=.sym) --lst=$(@:.rom=.lst) src/main.asm
	@echo "built $@"

$(NES_OUT): $(ASM_SRC) $(CV_GEN)/.stamp $(BUILD)/.debug-$(DEBUG)
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
