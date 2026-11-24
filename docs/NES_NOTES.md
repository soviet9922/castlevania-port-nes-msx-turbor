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

## Simon

Measured with `tools/nes_probe/record_simon.lua`, which records RAM and OAM every frame:

- RAM: `$3F` = Y (feet line), `$40` = X (low byte); OAM is DMA'd from `$0200`.
  Sprites are 8x16 (PPUCTRL bit 5) and come from pattern table `$0000`.
- Simon is 16x32 px: four 8x16 sprites, palette 0. The art faces left and
  is H-flipped to face right. His tiles in set 3 match the ROM exactly.
- Poses (top-left, top-right, bottom-left, bottom-right):
  stand `02 04 06 08`, walk `0A 0C 0E 10` / `12 14 16 18`,
  tucked `02 04 32 34` (jump and crouch), whip `1A 1C`, `22`, `28 2A 2C`
  (up to 24 px wide, not converted yet). The table the game builds these from has not been found;
  the converter lists the tile numbers itself (`tools/convert_simon.py`).
- Sprite palettes: `$CDE9` = `$3F $10` string; Simon uses NES colours `27 37 07`.
- Walk: 1 px per frame; animation walk1, walk2, walk1, stand, 7 frames each.
- Jump: bank 6 `$9B90`, 20 signed bytes of dy per frame while rising
  (36 px in total). The fall plays the same table in reverse with the sign
  flipped. Horizontal speed (1 px) is fixed at take-off. Standing pose for
  frames 0-2, tucked from frame 3 until 11 frames into the fall.
- Crouch: tucked pose, Y + 4 (drawn 8 px lower than standing).
- Whip (recorded with B pressed): wind-up 5 frames, swing 7, strike 9,
  recovery 1-2, then standing. Simon can't walk during a ground whip.
  The whip itself uses sprite palette 1 (`0F 23 34 0F`): tiles `1E 20`
  (wind-up, behind Simon), `24 26` (swing, above and behind), `2E 2E 30`
  (strike, 20-44 px in front, at the height of his hands).
  Simon's body: `1C 1A` / `22` / `2A 28 2C` / `2A 28` on top of the normal legs.
- The bytes after the jump table (`$9BA4`: `81 A8 9B 80`, then another
  signed table) are probably the knock-back arc.

## Objects, candles and items

Measured with `tools/nes_probe/record_courtyard.lua`, which walks through the courtyard whipping:

- Object slots are parallel arrays indexed by slot: Y at `$0354+i`, X
  (screen) at `$038C+i`; slot 0 is Simon. Simon's world X is at `$40/$41`, and
  the camera is world X minus screen X. Hearts are at `$71`, whip level at `$70`.
- **Candle placement** (fixed bank, routine around `$D132`-`$D29A`):
  - the per-stage table is the word at `$D29B + 2*stage` (`$28`), and the
    per-section table is the word at that pointer + 2*section (`$46`);
  - the section table has 2 bytes per **64-px chunk**: enemy group, candle group;
  - a candle group indexes word tables `$D6D1` (or `$D7D1` when bit 7 is set) →
    record `[$FF item] [$FE] x y` (0 = none). `$FE` spawns object `$28`
    (brazier) instead of `$27`. The item goes to `$0584+slot`.
  - Observed world X = (chunk - 1) * 64 + x; Y is the foot line.
- Stage 1 courtyard: 5 braziers at X 96, 224, 352, 480, 608 with drop codes
  4, 0, 0, 4, 8. Codes: 0 = whip upgrade, 4 = big heart (+5), 8 = dagger.
- Sprites use 8x16 mode, so tile bit 0 selects the pattern table. Brazier: flame
  `$97/$99` (palette 3, alternating every 8 frames) over bowl `$9B` (palette 2),
  each a mirrored pair. Burst: `$91+$70` 9 frames, `$93+$70` 7, `$93` 2, `$95` 2.
  Items: big heart `$BF` pair, whip upgrade `$C1 $C3`, dagger `$BD $BB` (palette 2).
  The upgraded whips use other tiles (`$6A $6C`, `$46-$58`, flashing palettes).
- An item hangs for 4 frames, then falls 1 px/frame (2 px from the 8th
  frame) until it lands.

## Still unknown

- Collision. The port currently treats 16x16 cells that contain the ground
  tiles (`$60`, `$68`) as solid, which is right for the flat courtyard. The
  real collision data (and stairs) still has to be found. The `$0600-$06FF`
  RAM area turned out to be object data, not collision.
- The meaning of the `$7FF2` header word and the sections at `$81A2` / `$8202`.
- Wall candles (object `$27`), enemy groups, Simon's sprite assembly table, the whip's exact
  hit box and damage rules, the crouching whip pose (the port draws the
  standing whip pose with the crouched legs), music.
- Falling speed after the jump arc ends, and the exact arc used when
  walking off a ledge (the port joins the arc's fall at frame 31 and caps at 5 px).

## Tools

| Tool | Purpose |
|---|---|
| `tools/nes_rom_tool.py` | header check, bank split, tile viewer |
| `tools/dis6502.py` | 6502 disassembler and byte-pattern search |
| `tools/cv_rom.py` | readers for the formats above |
| `tools/convert_stage.py` | ROM → MSX area (palette, per-band tiles, map, collision) |
| `tools/convert_simon.py` | Simon's sprites, palette and jump table → MSX |
| `tools/convert_objects.py` | candle placement and object/item sprites → MSX |
| `tools/nes_probe/dump_stage.lua` | FCEUX script: start a game and dump PPU/RAM state (ground truth) |
| `tools/nes_probe/record_simon.lua` | FCEUX script: record RAM/OAM every frame while Simon acts |
| `tools/nes_probe/record_courtyard.lua` | FCEUX script: walk the courtyard whipping every brazier |

To run the probe (needs FCEUX; writes to `build/nes/probe`):

```bash
PROBE_OUT=$PWD/build/nes/probe xvfb-run -a fceux --no-config 1 --sound 0 --loadlua tools/nes_probe/dump_stage.lua build/nes/castlevania.nes
```
