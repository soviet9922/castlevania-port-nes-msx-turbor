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

## The hall's exit and stage 2

Recorded with `tools/nes_probe/record_exit.lua`. The hall's floor ends at a wall
(Simon stops at world x 1519). The exit is the door on the upper floor, reached by
the last staircase. At world x 1516 (centre) the game mode `$18` goes from 5 to 8:
the door opens, the camera scrolls from 1280 to 1408, and Simon walks through to
about 1604. Then `$28` becomes 2 and `$46` (section) 1, and the HUD says STAGE 02.
Simon starts at world x 48 on the upper floor (y 96), with the camera at 0.

- **Map pointer:** `$D00F` reads the word at `$FB2A + 2*stage` (a pointer into
  the layout bank), then the word at that pointer + 2*section, into `$33/$34`.
  Stage 2 section 1 is `$81A2`, so its world column 0 is at `$81BA`, straight
  after the hall's map: 16 columns (512 px). It matched the PPU nametables exactly.
- Stage 2 section 1 uses the same palette as stage 1 (read from the PPU).
- **Stair ends without a partner:** stage 2 section 1 has two staircase tops
  (`$C7`, y `$C0`) with no foot in the same section. These are the stairs down to
  the section below. Ends are paired only when they form a foot and a top.

## Sections joined by stairs

Recorded with `tools/nes_probe/record_stage2.lua`. Stage 2 section 1 has two
staircase tops at y `$C0` with no foot in that section, and section 0 has two feet
with no top. Going down the left one, Simon's x keeps counting and his y goes from
207 (section 1) to 49 (section 0) in one frame: `$46` changes, and the screen is
redrawn around him (the camera x briefly counts up from -128 while it does). So
the sections are not scrolled vertically: they share the x axis, and y differs by
158. Section 0's map is the word at `$8004`+0 (`$8292`), so its world column 0 is
at `$82AA`: 16 columns (512 px), the waterway. It matched the PPU nametables
exactly, and it uses the same palette.

Falling into the water kills Simon, and the game restarts him at section 1's start.

## Game rules

Recorded with `tools/nes_probe/record_rules.lua` (and a local whipping variant of the
stage 2 route).

| RAM | Contents |
|---|---|
| `$42`/`$43` | timer, BCD (low, high): 0300 at the start, one step every 64 frames |
| `$7FC-$7FE` | score, BCD, low byte first (the low byte stays 00) |
| `$2A` | lives |
| `$45` | health (64) |
| `$70` | whip level: 0 leather, 1 chain, 2 morning star (one step per whip pickup) |
| `$71` | hearts (5 at the start) |
| `$15B` | sub-weapon (8 after the dagger) |

- The timer keeps running across sections and stages; it pauses at some moments.
- Points: a zombie gives 100, a panther 200.
- When time runs out (or health), the whip level drops to 0 at once, the death
  animation runs for 97 frames (falling pose `3C 3A` over `34 32`, then lying, 32 px
  wide: `6E 5E 4E 3E`), and Simon restarts at the start of the section with one life
  fewer, full health, timer 300, 5 hearts and no sub-weapon.

## Whip levels and the dagger

Recorded with `tools/nes_probe/record_weapons.lua` (RAM pokes in the courtyard).

- The whip's timing is the same at every level; only the whip tiles change.
  - Chain (level 1): held back `46 48`, raised `58 56`, extended `2C 6C 6C 6A`. It
    reaches as far as the leather whip.
  - Morning star (level 2): extended `2C 6C 6C 6C 6C 6A`, 16 px longer. Its
    palette cycles every frame, so it flashes.
- Dagger (`$15B` = 8): UP + B costs one heart at once. Simon plays the whip's arm
  poses without a whip. The dagger (tiles `BD BB`, palette 2, flipped both ways when
  flying right) leaves his hand about 18 frames after the press, at head height, and
  flies 4 px per frame until it leaves the screen.

## Candle items in stage 3

Candle item codes (the byte after `$FF` in a candle record) seen in block 1: `$04`
big heart, `$08` dagger, `$00` small heart (in stage 3 the first one gave the whip
upgrade), and `$0A`, `$0B`, `$0D`, `$0E`, `$0F`, `$11`, `$21`, not identified yet.

How a candle's item is chosen (fixed bank, `$EB8A`): the low nibble of the candle's
code indexes the table at `$EC16` (item types: `$08` -> `$17`, `$0B` -> `$44`, `$0D` ->
`$18`, `$0E` -> `$45`, ...). Code 1 is a money bag (the high nibble its value). A
sub-weapon item turns into a heart instead when Simon already holds that sub-weapon,
or while another sub-weapon item is waiting to be picked up (flag `$72`). Picking a
sub-weapon up copies the candle's code into `$15B` (`$E7C9`).

| Code | Sub-weapon | Where in block 1 | Cost |
|---|---|---|---|
| `$08` | dagger | courtyard | 1 heart |
| `$0B` | holy water | the hall's upper floor | 1 heart |
| `$0D` | axe | stage 3, the candle on the floor right of the stairs | 1 heart |
| `$0E`/`$0F` | stopwatch | stage 3 (x 192), stage 2 waterway | 5 hearts |

(Found with whipping variants of `record_stage3.lua` and a player's videos of the
NES game; `tools/nes_probe/record_subweapon.lua` throws a given sub-weapon.)

- Axe: leaves the hand about 22 frames after the press, flies forward 2 px per
  frame, up at about 4.25 px per frame with gravity 1/4 px per frame per frame, and
  turns (tiles `B7 B9`, palette 1, flipped four ways, 4 frames each). It goes on
  through what it hits and off the screen.
- Holy water: the bottle (tile `76`, palette 2) is lobbed forward 3 px every 2
  frames in a low arc; on the floor it breaks into fire (tiles `91 93 95`) for
  about 70 frames, which burns what it touches (a brazier in the recording).

## Stage 2's way out and stage 3

Recorded with `tools/nes_probe/record_stage2_end.lua`. The corridor's floor is
cut by a wall at world x 495, so the way on is through the waterway: along its
walkway (jumping two gaps), up the second staircase into the far side of section 1,
up its staircase to a ledge at y 128, then a jump onto the ledge at the top right.
There, at world x 492 (centre), a door opens, as in the hall (`$18` = 8), and the
game goes to stage 3, section 0 (HUD: STAGE 03). Simon starts at world x 48 on the
upper floor (y 96).

Stage 3's map is the word at `$8008` (`$8202`), so its world column 0 is at `$821A`:
24 columns (768 px). It has zombie records (type `$01`) and three staircases.

## The stage 3 boss

Recorded with `tools/nes_probe/record_stage3.lua` and `record_boss.lua`. Stage 3's
end is a ledge at the top right (up its last staircase from a platform reached by
a jump). The way out only opens after the boss.

- Enemy record type `$59` at chunk 10 (x `$30`, y `$40`): object `$19` hanging at
  (623, 64), asleep.
- It wakes when Simon arrives (about 80 px away), sinks 22 px, and then repeats:
  hover (about 120-190 frames), swoop at Simon (about 2 px across and 1 down per
  frame), fly back slowly (about 0.75 px per frame) to a new spot high up.
- Sprites (palette 3, symmetric): wings open `D0 D2 D4` (48 px) over `D6`; wings up
  `D8 DA` (32 px) over `DC`. They flap.
- With Simon waiting on the floor (a local variant of `record_boss.lua`), its
  swoops come right down to his height (y up to about 197) and hit him again and
  again: a swoop aims at where Simon is, on both axes.
- Fireballs: none appeared in the FCEUX recordings, where Simon was never more than
  about 100 px from it. A video of the NES fight (from the player) shows them while
  the boss hovers far from Simon (about 180 px, Simon on the ledge): a small fireball
  aimed at him, about 4 px every 3 frames. Never when he is close.
- Health in `$01A9`, 64 at the start, shown in the HUD's ENEMY bar. A whip hit
  (basic whip) takes 6.
- At 0 it burns (object `$31`, flame tile `91`) for 60 frames and becomes an orb
  (object `$2F`, tiles `5C` mirrored), which appears after about 110 frames and
  drops to the floor.

## Stage 2 enemies

Recorded with enemies on (the probe route on a ROM copy without the hall's zombies).
Enemy records in stage 2: section 1 has type `$02` at chunks 2 and 6 and `$04` at
chunks 4 and 8; section 0 has type `$03` in every chunk (y `$B8`).

- **Bat** (object id `$02`, record type `$02`): one at a time. It appears at the
  screen edge Simon faces (screen x 248), at his height (+1), and flies at him:
  9 px every 8 frames across. Vertically it dips 18 px and comes back over about
  96 frames (fitted with 9 - 9 cos). Wings: tiles `90 92`, `94 96`, `98 9A`
  (sprite palette 3, art facing left), each shown 9 frames, in the order 1 2 3 2.
  When it touches Simon it takes 8 health and dies (`$31`, then a burst).
- **Fishman** (object id `$03`, record type `$03`, one record per waterway chunk at
  x+32, y `$B8`). Recorded standing on the walkway (a local variant of `record_stage2.lua`):
  - two are about at a time; a new one jumps out a few frames after one is gone,
    away from Simon, with a splash (object `$25`, several drops);
  - the jump: 5-6 px per frame up at first, slowing (fitted: -86/16 px per frame,
    gravity 2/16), a peak about 115 px above the water. It passes through
    platforms going up and lands on one coming down, or falls back into the water;
  - it walks towards Simon, 19 px every 25 frames (fitted: 3 px every 4 frames), legs
    alternating every 25 frames (bottom tiles `A4 A6` / `A8 AA`, top `A0 A2`, sprite
    palette 3, art facing left);
  - after about 80 frames it stops (state 6, tiles `AC AE` over `8C 8E`) for 32
    frames and shoots a fireball (object `$26`, tile `68`) after 16: 7 px every 4
    frames, the way it faces. Then it turns towards Simon and walks again;
  - it walks off the end of a platform and falls; a fireball hit takes 8 health.
- Object id `$32` is the burst left by an enemy that dies or leaves.

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
