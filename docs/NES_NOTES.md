# Castlevania (NES) reverse-engineering notes

These notes describe formats and addresses only. No game data is reproduced.
Everything was found in a user-supplied dump (iNES, mapper 2,
128 KB PRG, CHR-RAM; PRG+CHR CRC32 `A93527E2`). Bank 7 is fixed at
`$C000`; banks 0–6 are switched in at `$8000`.

## PRG bank contents

| Bank | Contents |
|---|---|
| 0 | code, PPU buffer flush (`$800A`), HUD/title data |
| 1 | CHR graphics: title logo, font, Simon and common sprites, … |
| 2 | CHR graphics: enemies and stage tiles |
| 3 | CHR graphics: stage tiles, bosses, fonts |
| 4 | stage layout data for block 1 (stages 1–3): maps and 4x4 blocks |
| 5–6 | code / data (not yet studied) |
| 7 | fixed bank: reset `$C052`, NMI `$C008`, IRQ `$C0BF`, loaders |

## CHR-RAM loader

- `$FD2A`: A = graphics set number. It reads a pointer from `$FDC2 + 2·A`.
- Each set is a list of 7-byte records, terminated by `$FF`:
  `bank, src.lo, src.hi, ppu_dst.lo, ppu_dst.hi, len.lo, len.hi`
- `$FD85` performs the copy (source `$00/$01`, PPU address `$02/$03`,
  length `$04/$05`).
- Set 0 is loaded at power-on (title screen), set 1 at the title/demo, and
  **set 3 when a game starts**. Sets 4–10 are stage-specific swaps.
- Replaying set 3 reproduces the background pattern table (`$1000-$1FFF`)
  exactly as the emulator shows it in Stage 1. The sprite table differs only
  in Simon's animation tiles, which the game updates at runtime.

## Stage layouts (bank 4)

```
$8000  header: 5 little-endian words ($7FF2, $8082, $8292, $81A2, $8202)
$800A  map: courtyard (stage 1 opening), 20 columns
$8082  map: castle gate + entrance hall, 48 columns
$81A2  map: 16 columns   (not identified yet)
$8202  map: 24 columns   (not identified yet)
$830A  block table
```

- **Map:** one byte per 32x32-pixel block, **6 blocks per column**, top to
  bottom, columns left to right. The top block row sits under the HUD and
  only its lower half is visible (NES nametable rows 4–27).
- **Block:** 17 bytes, at `$830A + 17·n`:
  - byte 0: attribute byte (2 bits of palette per 16x16 quadrant, standard NES order)
  - bytes 1–16: 4x4 tile numbers, row-major, from pattern table `$1000`
- Checked against the emulator: every fully visible block on screen, tiles
  and attributes, matches.

## Palettes

Stored in the fixed bank as `$3F $00 <16 colour bytes> $FE` strings.
The courtyard background palette is at `$CE28`; the next string (at `$CE3B`)
is believed to be the hall's. The table that selects them is not found yet.

## Still unknown

- Collision. The port currently treats 16x16 cells that contain the ground
  tiles (`$60`, `$68`) as solid, which is right for the flat courtyard. The
  real collision data (and stairs) still has to be found. The `$0600-$06FF`
  RAM area turned out to be object data, not collision.
- The meaning of the `$7FF2` header word and the sections at `$81A2` / `$8202`.
- Object/enemy placement, sprite assembly tables for Simon, music.

## Tools

| Tool | Purpose |
|---|---|
| `tools/nes_rom_tool.py` | header check, bank split, tile viewer |
| `tools/dis6502.py` | 6502 disassembler and byte-pattern search |
| `tools/cv_rom.py` | readers for the formats above |
| `tools/convert_stage.py` | ROM → MSX area (palette, per-band tiles, map, collision) |
| `tools/nes_probe/dump_stage.lua` | FCEUX script: start a game and dump PPU/RAM state (ground truth) |

To run the probe (needs FCEUX; writes to `build/nes/probe`):

```bash
PROBE_OUT=$PWD/build/nes/probe xvfb-run -a fceux --no-config 1 --sound 0 --loadlua tools/nes_probe/dump_stage.lua build/nes/castlevania.nes
```
