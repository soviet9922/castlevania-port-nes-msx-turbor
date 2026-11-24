# Castlevania (NES) → MSX turbo R

A fan project to port the NES game *Castlevania* (Konami, 1986) to the
MSX turbo R, written in Z80/R800 assembly.

![engine skeleton running in openMSX](docs/img/milestone0.png)

**Status: milestones 1-3 in progress.** The engine scrolls a level with a
fixed HUD at 60 fps and has a controllable 3-colour character. From your
own NES ROM, the build converts **Stage 1: the courtyard and, through the
castle gate, the entrance hall**: graphics, layout, palette and the NES's own
collision rule. **Simon** is converted too:
his graphics, walk animation, jump arc and whip (timing identical to the NES,
frame by frame). **Braziers and wall candles** are placed from the ROM's data. Whip them
and they burst and drop their items (hearts, whip upgrade, dagger), which you can collect.
Simon can climb the hall's **stairs**, which come from the ROM's stair table.
**Zombies** and **black panthers** appear where the ROM's enemy data puts them.
They hurt Simon (health bar, knock-back, blinking invincibility) and die to the whip.
The screenshot above shows the ROM-free build, which uses only original
placeholder art. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Legal

*Castlevania* is © Konami. This repository contains only original code
and placeholder art. Game data (graphics, levels, music) will be
converted at build time from a ROM image you own; it must never be
committed here. `*.nes` files and `build/` are git-ignored.

## Building

Requirements:

- [sjasmplus](https://github.com/z00m128/sjasmplus) 1.20 or newer
- Python 3.8+
- [openMSX](https://openmsx.org/) to run and test

```bash
make
```

This creates `build/cvmsx.rom` (placeholder art only), a 128 KB **ASCII16** MegaROM.

To build with the stage converted from your own ROM, put the dump at
`build/nes/castlevania.nes` (git-ignored) or pass `NES_ROM=`:

```bash
make nes NES_ROM=path/to/castlevania.nes
```

This creates `build/cvmsx-nes.rom`. It contains converted Konami data, so
it is for your own use only: don't commit or distribute it.

## Running

On the free C-BIOS MSX2+ machine (V9958 with a 3.58 MHz Z80, no system ROMs needed):

```bash
make run-cbios
```

On a real turbo R configuration (you'll need the FS-A1GT system ROMs installed in openMSX):

```bash
make run
```

For the converted build:

```bash
make run-nes
```

### Emulator compatibility

The ROM is an ASCII16 MegaROM. Emulators and flash-cartridge loaders detect
this automatically (the code is written so that the detection is unambiguous),
but if one asks, choose **ASCII16**.

| Emulator | Status |
|---|---|
| openMSX | works (recommended; used by the automated tests) |
| fMSX 6.0 | runs, but the playfield doesn't scroll: fMSX ignores the V9958 horizontal scroll registers in Screen 4, so Simon appears to hit an invisible wall |

Controls: cursor keys or joystick to walk, DOWN to crouch, SPACE or button A to jump,
M, X or button B to whip. UP at the foot of a staircase climbs it, and DOWN at its top goes down.
Jumps are committed, like in the original: you can't steer in mid-air.

## Testing

```bash
make test
```

To test the converted build:

```bash
make test-nes
```

This boots the ROM headless in openMSX (using `xvfb-run` if there is no display),
walks, jumps and turns. It checks the game state in RAM (60 fps main
loop, line-interrupt split, scrolling, physics) and saves screenshots to `build/test/`.

## Layout

```
src/        Z80 / R800 assembly (engine)
  main.asm      ROM header, init, main loop, bank layout
  vdp.asm       V9958 setup and VRAM helpers
  irq.asm       VBLANK + line interrupt (HUD/playfield scroll split)
  scroll.asm    column streaming, camera, tile collision
  player.asm    player physics, animation, sprites
  hud.asm       status bar
tools/
  gen_placeholder_assets.py   original placeholder art and test level
  msx_area.py                 level image -> Screen 4 tiles, map, collision
  convert_stage.py            NES stage -> MSX area (from YOUR ROM)
  cv_rom.py                   Castlevania ROM format readers
  dis6502.py                  6502 disassembler / pattern search
  nes_rom_tool.py             inspect / split / tile-view YOUR NES ROM
  nes_probe/                  FCEUX Lua probes (ground-truth dumps)
tests/
  run_smoke.py  headless openMSX test
docs/
  DESIGN.md     how NES features map to the MSX turbo R
  NES_NOTES.md  reverse-engineering notes (formats and addresses)
  ROADMAP.md    milestones
```

## Working with your NES ROM

```bash
python3 tools/nes_rom_tool.py info castlevania.nes
```

```bash
python3 tools/nes_rom_tool.py split castlevania.nes build/nes
```

```bash
python3 tools/nes_rom_tool.py tiles castlevania.nes build/nes/bank1.png --bank 1
```
