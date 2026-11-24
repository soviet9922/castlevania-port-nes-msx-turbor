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
$800A  courtyard (internal stage 0): world column 0
$809A  entrance hall (internal stage 1): world column 0, 48 columns
$830A  block table
```

**World column 0 of a stage is at its header word + 24 bytes** (4 columns).
The 4 columns before it are drawn off-screen to the left when the stage
starts, so they overlap the end of the previous stage's map. That's why
the courtyard (`$800A`) runs 24 columns, through the gate, into
`$8082-$8099`. This was confirmed by matching the emulator's nametables
against the map at camera positions 0, 1, 11 and 100. The words `$81A2`,
`$8202` and `$8292` are probably stages 2-4.

- **Map:** one byte per 32x32-pixel block, **6 blocks per column**, top to
  bottom, columns left to right. The top block row sits under the HUD and
  only its lower half is visible (NES nametable rows 4–27).
- **Block:** 17 bytes, at `$830A + 17·n`:
  - byte 0: attribute byte (2 bits of palette per 16x16 quadrant, standard NES order)
  - bytes 1–16: 4x4 tile numbers, row-major, from pattern table `$1000`
- Checked against the emulator: every fully visible block on screen, tiles
  and attributes, matches.

## Collision

Collision is derived from the background tiles: when a column is drawn,
`$F7E8` calls `$F9DB` for each tile, and **tiles `$60-$6B` are solid**
(tile `$66` gets value 2, probably breakable blocks). The resulting 2-bit-per-tile map
is kept at `$0600-$06FF`. The port applies the same rule per 8x8 tile
when converting (`tools/convert_stage.py`).

## Stairs

Stairs are not part of the tile collision. They have their own table, read by
`$9CBD` in bank 6 when UP or DOWN is held (`$93EF`, `$9C10`):

- a word at `$FBF3 + 2*stage` points (into bank 6) to a list of 2-byte
  staircase ends, ending with 0;
- byte 0: y in the high nibble, section in bit 2, and the type in bits 0-1
  (bit 1 = top end, needs DOWN; bit 0 = the staircase rises to the left);
- byte 1: x/8 in bits 7-3, screen page in bits 0-2; a per-type adjustment
  (`$9D47`: 0, -1, +5, +2) is added;
- the ends come in pairs (foot, top). The entrance hall has 4 staircases.

Measured (`tools/nes_probe/record_stairs.lua`, run on a local ROM copy with the hall's
enemy groups zeroed so zombies don't interrupt): with UP pressed within a few
pixels of a foot, Simon walks to it (1 px per frame) and climbs one pixel
across and one up on alternating frames. The pose alternates every 8 frames
between a stair pose (`14 12` / `38 36`) and walk1. Simon lines up 2 px right of the
table's x. The game sets `$3D`/`$2D` while he is on the stairs.

## Stage 1 = two internal stages

The HUD always says STAGE 01, but the game switches the internal stage number `$28` from 0
(courtyard) to 1 (entrance hall) when Simon walks into the gate (around
screen x 195 with the camera at 512). The hall starts with the camera at 0,
Simon at world x 48, and the floor 16 px lower. Both use the palette at `$CE28`.

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
- Wall candles are object `$27`: one 8x16 sprite, tiles `$40`/`$50`
  alternating every 9 frames (palette 3). Record y is the candle's centre line.
  The entrance hall has 24 of them (stage 1, section 0 table at `$D319`), one per
  64-px chunk, alternating between floor height and mid-wall.
- Small heart: tile `$9F` (palette 3). It drifts down at 1/2 px per frame,
  swaying sideways by about 15 px, and is worth 1 heart.
- Drop codes seen in the hall: `$11`, `$21`, `$0A`, `$0B` (not identified), and
  0 on wall candles, which usually gave a small heart. One gave another item (`$C5/$C9`).
  Enemies also drop items. The NES's drop rule is not decoded yet.
- Stage 1 courtyard: 5 braziers at X 96, 224, 352, 480, 608 with drop codes
  4, 0, 0, 4, 8. Codes: 0 = whip upgrade, 4 = big heart (+5), 8 = dagger.
- Sprites use 8x16 mode, so tile bit 0 selects the pattern table. Brazier: flame
  `$97/$99` (palette 3, alternating every 8 frames) over bowl `$9B` (palette 2),
  each a mirrored pair. Burst: `$91+$70` 9 frames, `$93+$70` 7, `$93` 2, `$95` 2.
  Items: big heart `$BF` pair, whip upgrade `$C1 $C3`, dagger `$BD $BB` (palette 2).
  The upgraded whips use other tiles (`$6A $6C`, `$46-$58`, flashing palettes).
- An item hangs for 4 frames, then falls 1 px/frame (2 px from the 8th
  frame) until it lands.

## Enemies: zombies, health, getting hit

Recorded in the entrance hall (`tools/nes_probe/record_hall.lua`):

- Object id per slot: `$0434+slot` (`$01` zombie, `$28` candle); `$04C0+slot`
  is a per-object type/state (the object spawner `$EF10` stores it).
- Each 64-px chunk's first byte is an **enemy group**. It indexes the same pointer
  tables as the candle groups, and the record is `type, x, y`, loaded into one of
  6 spawner slots (`$0160-$018F`). Hall types: `$01` zombie (floor,
  y 192), `$04` bat, `$51` black panther. Zombie spawners are at chunks 1, 5, 20 and 22.
- Zombies (16x32, tiles `80 82` over `88 8A` / `84 86`, sprite palette 1):
  - they appear at the screen edges (screen x 248 / 8), alternating sides, 32 frames
    apart, at most 3 at a time, while their spawner is near;
  - they come in waves: in two hall recordings, 3 appear (frames 1520, 1552, 1584),
    then nothing until the wave is gone; the next wave starts about 100-140 frames
    after the last zombie of the previous one left (1921 after 1815, 2272 after 2135);
  - they walk straight across at 7 px every 8 frames and vanish off-screen;
  - one whip hit destroys one (burst).
- Black panther (object id `$11`, enemy record type `$51`; one per record,
  centre x = (chunk-1)*64 + x - 1, y = centre line). States in `$04C0+slot`:
  `$51` waiting, `$52` running, `$1E` leaping.
  - It waits until Simon is within about 64 px, then runs at him (2 px per frame)
    until the platform ends, and leaps. A woken panther that leaves the screen
    doesn't come back.
  - The leap is 2 px across per frame; the arc fits a start speed of -1.5 px and
    gravity of 1/8 px per frame, capped at 4 px. Measured, not yet found in the ROM.
  - After landing it runs (2 px per frame) towards the side Simon is on.
  - Sprites (32x16, palette 3): waiting `B0 B2 B4`, running `C0-C6`, `B8-BE`,
    `C8-CE` (7 frames each), leaping `B8-BE`.
- Enemy record type `$04` (y 128) at six hall chunks: no enemy appeared from it
  while walking the floor, the middle platform or the upper floor
  (`tools/nes_probe/record_upper.lua`). Not identified (bats?).
- Simon's health: `$45`, 64 at the start (16 bar segments of 4). A zombie takes 8.
- Getting hit:
  - frozen for 6 frames, then knocked back 1 px per frame away from the enemy,
    facing it, in the "hurt" pose (`3A 3C / 4C 34`);
  - the knock-back arc is the table at bank 6 `$9BA8` (17 signed steps,
    `$81`-terminated, mirrored for the fall), the same format as the jump table;
  - he lands crouched for about 17 frames, then blinks (invincible) until about
    140 frames after the hit.

## Still unknown

- The descending stair pose and the whip poses on stairs (the port reuses the
  climbing and standing poses).
- The candle drop rule (codes other than 4 and 8, and code 0 on wall candles).
- Stages 2 and up (`$81A2`, `$8202`, `$8292` in bank 4; other banks for later blocks).
- Bats, panthers and the other enemy types; enemy item drops; the score
  values; lives, death and the timer;
- Simon's sprite assembly table, the whip's exact
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
| `tools/nes_probe/record_hall.lua` | FCEUX script: walk through the gate into the entrance hall |
| `tools/nes_probe/record_upper.lua` | FCEUX script: climb to the hall's upper floor (bats/panthers) |
| `tools/nes_probe/record_stairs.lua` | FCEUX script: walk to the hall's first staircase and climb it |

To run the probe (needs FCEUX; writes to `build/nes/probe`):

```bash
PROBE_OUT=$PWD/build/nes/probe xvfb-run -a fceux --no-config 1 --sound 0 --loadlua tools/nes_probe/dump_stage.lua build/nes/castlevania.nes
```
