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

- Stopwatch (`tools/nes_probe/record_stopwatch.lua`): UP + B costs 5 hearts at once,
  without a throw. The enemies stop for about 178 frames, and the timer stops too.
- The HUD shows the sub-weapon in its box: 16x16 icons (dagger `BD BB`, holy
  water `A1 A3`, axe `B7 B9`, stopwatch `89 8B`); the pickups use the same tiles.

(Found with whipping variants of `record_stage3.lua` and a player's videos of the
NES game; `tools/nes_probe/record_subweapon.lua` throws a given sub-weapon.)

- Axe: leaves the hand about 22 frames after the press, flies forward 2 px per
  frame, up at about 4.25 px per frame with gravity 1/4 px per frame per frame, and
  turns (tiles `B7 B9`, palette 1, flipped four ways, 4 frames each). It goes on
  through what it hits and off the screen.
- Holy water: the bottle (tile `76`, palette 2) is lobbed forward 3 px every 2
  frames in a low arc; on the floor it breaks into fire for 77 frames, which
  burns what it touches (a brazier in the recording). The fire steps through
  five pictures, 8 frames each, then starts again: three small flames (tiles
  `91`, `93`, `95`) and two wide ones (`97` and `99`, each drawn with its mirror
  beside it, 16 px wide). An enemy that takes more than one hit is held in the
  fire, unable to move, and hurt each time its hit flash ends (the stage 3 boss).
- A death costs the whip upgrades and the sub-weapon.

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
- Asleep it is drawn as a small bat hanging under the ceiling: tile `DE` and its
  mirror (16x16, palette 3), at the top middle of where the big bat appears.
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
  Later probes found no boss fireball either with Simon waiting on the ledge for
  7,600 frames (the boss hovering up to 180 px away) or with its health held at
  40, 24 or 8, so what makes it shoot is still unknown. The NES's fireball
  spawner (object `$26`, 8 px above the shooter, shared with the fishmen) is
  reached through a countdown in the enemy script. The port fires whenever the
  boss hovers 80 px or more from Simon, tuned against the player's video.
- Health in `$01A9`, 64 at the start, shown in the HUD's ENEMY bar. A whip hit
  (basic whip) takes 6.
- At 0 it burns (object `$31`, flame tile `91`) for 60 frames and becomes an orb
  (object `$2F`, tiles `5C` mirrored), which appears after about 110 frames and
  drops to the floor.

## Stage clear and the timer

Recorded with a local probe that starts a game at stage 3 (writing `$28` = 3 while
the game mode `$18` is 4, before the stage loads), climbs to the boss, sets its
health to 0 and walks onto the orb.

- Taking the orb: game mode `$18` = `$0C`, sound `$48`, health back to 64 at once.
- `$19` = 1: 223 frames (the jingle).
- `$19` = 2: the timer runs down one step a frame, 10 points a step (sound `$03`
  every 8 frames).
- `$19` = 3: 56 frames, then one heart every 8 frames, 100 points each (sound `$04`).
- `$19` = 4: 8 frames after the last heart, 115 frames; then (`$19` 5-8, `$28` = 20)
  the castle map, about 415 frames, with sound `$06` every 16 frames.
- The next stage starts with 5 hearts and the timer from the table below; whip
  and sub-weapon carry on.
- **Timer table** at `$C9F6`, by internal stage (`$C9EA` loads it): hundreds
  3 3 2 1 4 3 2 5 4 3 ... It is loaded when a game starts, after a death (a death
  in stage 2 restarts at 200) and at the start of a block; between stages of a
  block the timer carries on.

## Block 2 (stages 4-6)

Recorded with a savestate made at the real start of stage 4 (after the stage 3
boss and the tally), and by reading the tables below.

- **Graphics:** CHR set 4 is loaded over set 3 when the block starts; replaying sets
  3 and 4 reproduces stage 4's pattern tables exactly (both tables).
- **Palette:** `$CE3B` for the whole block (read from the PPU in every section).
  The sprite palette is the same as block 1's.
- **Maps:** the word at `$FB2A + 2*stage` points into bank 4 at a list of section
  map words (stage 4: `$880D`, `$88FD`; stage 5: `$886D`, `$8A7D`; stage 6: `$89ED`,
  `$895D`; the lists overlap). World column 0 is the word + 24, as in block 1, and
  each map runs on to the next one's column 0. The 4x4 tile-block table is the word at
  `$FA01 + 2*stage`: `$830A` for block 1, `$8B25` for block 2. A section's map
  matched the PPU nametables exactly.
- **Start positions** (`$C9B1`, table `$CA0C`, 2 bytes per stage): byte 0 = y (bits
  7-3) and the camera's page (bits 2-0); byte 1 = screen x (bits 7-1, bit 7 also sets
  the facing: left) and the section (bit 0). Stage 4: x 320, y 192, camera 256; stage 5:
  x 720, y 96, camera 512, facing left; stage 6: x 720, y 128, camera 512, facing left.
- **The block runs right to left.** The doors are at the left end of a section, and
  the 8 map columns before a section's column 0 are the last 8 columns of the next
  stage's first section (stage 4 section 1 -> stage 5 section 0, stage 5 section 1 ->
  stage 6 section 0): that's what the screen scrolls into at the door.
- **Stage 4:** section 0 is one screen (the camera stays at 256). Its first staircase
  leads to a ledge, a jump left reaches the y 96 ledge, and the staircase from
  (336, 96) continues in section 1 to its top at (461, 128) (126 px of it in section 1).
  Section 1 scrolls (camera 0-256); a fall there restarts at stage 4's start.
- **Stairs between sections:** an end without a partner (stage 5: foot (48, 64) in
  section 0, top (93, 176) in section 1; stage 6: foot (656, 64), top (717, 160)).
- **Doors:** a 1x6-tile column of solid tiles (`$62`-`$67`) at map column 1: stage 4
  section 1 at nametable rows 8-13, stage 5 section 1 at rows 12-17.
- **Enemy records** (enemy groups, as in block 1): the spawner code (`$F382`) runs
  the handler at `$F3E9 + 2*(type & $3F)` (`JSR $CA6D` jump table). Types with bit 6
  set are single placed enemies whose object id is the type's low bits (`$51` panther,
  `$59` stage 3 boss, `$47`, `$48`, `$4E`, `$5B` Medusa); the others are spawners.
  - `$06` **Medusa heads** (bank 6 `$8435`): every 64 frames (`$0184`), up to three at
    a time (object slots 9-11), not while Simon is on the stairs. A head (object `$06`,
    tiles `E8 EA` / `EC EE`, 8 frames each, sprite palette 2, art facing left) starts at
    the screen edge Simon faces (x `$F8` or `$08`), 32 px above his y, and flies at him
    5 px every 4 frames in a wave around his y (`$04DC`): 34 px up and down, a period
    of about 100 frames, starting at the top. A whip hit kills it (300 points);
    touching Simon takes 8 health.
  - `$05`: Medusa heads too, but only when `$2B` is set (bank 6 `$8431`): the second
    quest. Nothing appears from it in the first.
  - `$48` **spear knight** (object `$08`, the zombie's tiles `80`-`8A` in block 2's
    graphics, palette 1): paces its floor at 1/2 px per frame and turns to face Simon
    every 200-260 frames. Two leather-whip hits kill it (400 points); touching it takes
    8 health.
  - `$47` **hanging bat** (object `$07`): hangs under the ceiling (tile `9C` and its
    mirror, palette 1) until Simon is about 96 px away and near its height (it didn't
    wake with Simon on the floor below it, 128 px lower). Then it flies at him 3 px
    every 2 frames, dropping about 30 px over 34 frames, with the bat's wings (`94 96`
    etc., palette 1), and dies when it touches him.
  - **Ceiling crushers** (stage 6 section 0, NES x 352, 416 and 480, 32 px wide):
    background tiles the game rewrites, recorded from the nametables. At rest (the map)
    the chain is at nametable row 14 and the spikes (`18 18 18 18`) at row 15 under a
    mount at rows 12-13. The spikes drop a row every 4 frames to their lowest row (18
    for the one at 416, 21 for the one at 480), and rise a row every 16 frames back to
    row 14; the chain (`00 1A 1B 00`) fills the rows above them. Spikes that reach
    Simon crush him (`$046C` = 8): he dies whatever his health. The records `$0D` and
    `$8D` are at two of them; `$4E` (two, left of them) is not identified yet.
  - `$5B` **Medusa**, the boss (bank 6 `$8425`, object `$1B`), recorded from a start
    patched into her room (the start table at `$CA0C`, changed in the emulator's copy
    of the ROM only). Asleep she is the statue, background tiles (nametable rows 17-19,
    x 96-127); she woke about 100 frames after Simon arrived, about 40 px away, and
    the statue's tiles became `00`. She is 32x32 (tiles `D0 D2 / D4 D6` palette 1 and
    `D8 DA / DC DE` palette 2, mirrored), drifts 7 px every 8 frames, bobbing about 9 px
    up and down, turns at the room's edges, follows Simon's height, and now and then
    stops for about 70 frames. Snakes (object `$09`, tiles `F0 F2`, palette 2) drop from
    her at intervals of 80-250 frames, fall to the floor and slide at Simon 3 px every 2
    frames. Health 64 (`$01A9`), 3 a leather-whip hit; beaten, she burns (`$31`) and
    leaves the orb (`$2F`), 3000 points. The camera stayed at 0 in her room.

## Block 3 (stages 7-9)

A savestate at the start of stage 7 was made by forcing the stage-clear mode (`$18` =
`$0C`) in Medusa's room.

- Graphics: CHR sets 3 and 5 (set 5 is loaded when the block starts); exact match with
  the PPU. Palette `$CE4E`. Tile-block table `$9156`. Music `$30`. Timer 500, 400, 300.
- Maps (word at `$FB2A + 2*stage`): stage 7 sections `$8DAE`, `$8E3E`; stage 8 `$8ECE`,
  `$8F2E`; stage 9 `$901E` (one section). Stage 8's section 0 runs 768 px, on into the
  first 256 px of section 1's map; section 1 is played from about x 480.
- Starts (`$CA0C`): stage 7 x 720, y 176, camera 512, facing left; stage 8 x 48, y 144;
  stage 9 x 48, y 112.
- Stage 7 runs left along section 0, up a staircase at x 159 into section 1 (its top at
  (66, 176) there), and right to a door at map column 94. Stage 8 runs right, up the
  staircase at x 639 into section 1 (top at (546, 144)), and right to a door at column
  158. Both doors are followed in the ROM by the next stage's first columns, as in block 1.
- Stage 9 is a bridge to a tower room at the right end, where the boss records (`$5A`,
  two of them) are.
- Enemies (savestates at the starts of stages 7, 8 and 9; sprites from CHR sets 3+5):
  - `$4C` **fleaman** (object `$0C`, tiles `7C 7E`, palette 3): waits until Simon is
    about 90 px away, then hops at him: arcs about 45 px high, about 1 px across a frame
    (the first, off its perch, flatter), resting a few frames between hops.
  - `$8D`/`$0D` outside stage 6 (bank 6 `$8588`): a **ghost** (object `$0D`, tiles
    `B0 B2`, palette 1) appears at the record's place when Simon is about 96 px away
    and floats at him, about 3 px every 4 frames on both axes. One per record.
  - `$50` **skeleton** (object `$10`, the zombie's tiles `80`-`8A`, palette 1): walks,
    jumps about (56 px), and throws bones (object `$24`, tile `92`) up and towards Simon:
    3/4 px across a frame, about 77 px up, under gravity.
  - `$4E` **bone pillar** (object `$0E`, two skulls `E0 E2` and mirrored, palette 1;
    stage 6's two `$4E` records too): stands, and every 245 frames fires two fireballs
    40 frames apart (object `$23`, tile `68`), 2 px a frame at its height, towards Simon.
  - `$4F` **raven** (object `$0F`, perched `AC AE`, flying `A0 A2` / `A4 A6` / `A8 AA`,
    palette 3): perches until Simon is about 90 px away, swoops down (3/4 px across and
    down a frame) to his head's height, hovers about 30 frames, then chases him across,
    speeding up and overshooting.
  - Not measured: the pillar's and the ghost's hit points and points, the skeleton's.
- **The mummies** (`$5A`, two, object `$1A`), recorded from a start patched in front of
  the tower (the emulator's copy of the ROM only): asleep in the tower room until the
  camera reaches it (1280), then both walk at Simon (about 3/4 px a frame), turning now
  and then, and throw bandages (object `$22`, tiles `F4 F6` / `F8 FA`, palette 1) that
  fly low at him in a wave, about 1 1/2 px a frame. 16x48, tiles `D0`-`DA` (and a second
  step `DC DE C0`-`C6`), palette 1, art facing left. The HUD's bar (`$01A9`) shows both:
  64, 1-3 a whip hit. Each is worth 3000; the first dies with the bar at 3, the second at
  0, and the second burns (`$31`) and leaves the orb (`$2F`).

## Blocks 5-7 (stages 13-18): layout

- **Camera limits per section** (`$D015`, `$D025`, from the scroll code `6:$985F` and
  `6:$9889`): `$FBB7 + stage` is the camera's last page (high nibble section 0, low
  nibble section 1); `$FBCA + stage` the least page minus 1 (`$F`: none, the camera
  stops at 0). Stage 14 section 1 also keeps the camera at page 4 or more while Simon
  is low (y `$60` or more) at page 4 (`$D037`). `$FC65 + stage` is the boss room
  (section, page) where the camera locks.
- **Start x** (`$CA0C` byte 1): bits 7-1 are the screen x, and bit 7 also sets the
  facing; stages 15-18 start at screen x 208 or 224, facing left.
- **Stages and sections** (camera range; start; exit at `$FC19`):
  - 13: section 0 camera 0 to 256 (start x 48, y 176), section 1 camera 0 to 1024 (exit
    x 1256, y 176, at the camera's end); a staircase at the left joins them. Timer 500,
    music `$36` (all of block 5).
  - 14: section 0 is one screen at camera 1024 (start x 1072, y 176), section 1 camera 0
    to 1024, run left to the exit at x 28, y 176. Timer 400.
  - 15: section 0 camera 512 to 768 (start x 976, y 176, facing left), section 1 camera
    0 to 768; Death's room is at camera 0 of section 1. Timer 300.
  - 16 (block 6, music `$33`, timer 700): one section, camera 0 to 1280, run left
    (start x 1504, y 176) along a bridge to a door at its left end (frame at x 32-56,
    on the bridge at y 112). Its map follows stage 17 section 0's in the ROM, so the
    8 columns before it are stage 17's.
  - 17: section 0 camera 0 to 512 (start x 720, y 112, facing left), section 1 camera 0
    to 512, exit at x 16, y 112 (left end). Timer 600.
  - 18 (music `$3C`, timer 500): section 0 camera 256 to 512 (start x 720, y 112,
    facing left), up a staircase to section 1 (camera 0 to 512): Dracula's room at
    camera 0.
- **Graphics:** CHR sets 3 and 7 (block 5), 3 and 8 (block 6), 3 and 9 (stage 18);
  palettes `$CE74`, `$CE87`, `$CE9A`; tile-block tables `$9ED1`, `$A537`, `$A9F4`.
- **Enemy records** (type = `$40` + object id for single enemies): new here are `$4A`
  (object `$0A`), `$58` (object `$18`, Death, at x 224 in his room), `$5E` (object
  `$1E`, a red flying creature on stage 16's bridge) and `$5D` (object `$1D`, Dracula,
  x 224 in his room). Records past a section's camera range are never reached (the
  record lists of neighbouring stages overlap).
- The red skeleton (`$53`, object `$13`) in stage 15 section 0: the port's path matched
  the NES's within 2 px for 440 frames (it then turns at random).

## Exit sequences

Recorded with a variant of `record_exit.lua` that also dumps the PPU nametables.

- **The castle gate** (game mode `$18` = 10): at the gate, control is taken away
  and Simon walks into it by himself, about 1 px every 3 frames, with the timer
  stopped; then the hall loads.
- **The doors** (mode 8; the hall's at world x 1528, stage 2's at x 504): Simon stands
  while the screen scrolls 128 px further, 1 px per frame (into the next stage's first
  columns, which follow the area's map in the ROM). The shut door is a 1x6-tile column
  of the background (nametable rows 8-13, playfield rows 2-7). It opens in two steps drawn with sprites
  (palette 3, mirrored): half open for 16 frames (the column goes dark; tiles `77 7B 7B`
  and `75 79 79` on the 2 columns to its right), then open (`87 7B 7B`, `87 7B 7B`,
  `85 7B 7B` over 3 columns) while Simon walks through at 1 px per frame; half open for
  8 frames, then shut. He walks on about 118 px with the screen following, and the
  next stage loads.
- At the castle gate Simon walks into the dark archway and goes behind the gate's right
  pillar (sprites behind the background), a player's NES video shows.

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
    then a pause. The code (6:$805D, see NES_ENEMIES.md) gives 32 frames between
    zombies and 288 after every third, counted from the spawn (not from the wave
    being gone); each spawner has its own timer and starts at once on the screen;
  - they walk straight across at 7 px every 8 frames and vanish off-screen;
  - one whip hit destroys one (burst).
  - in stage 3 their spawners are on the floor and on the upper platform (record y
    `$80`); one that walks off a platform's edge stops and drops straight down to
    the floor below (64 px in about 28 frames, faster as it falls), then walks on.
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
- Block 2's enemies and its boss; blocks 3 and up.
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
| `tools/nes_disasm.py` | the full disassembly: annotated listings of every bank (`make disasm`) |
| `tools/nes_labels.txt` | names and comments for RAM, routines and tables in the listings |
| `tools/nes_probe/trace_code.lua` | FCEUX script: a bot plays and logs every executed address (coverage) |
| `tools/nes_probe/cov_battery.sh` | runs `trace_code.lua` over many stages and savestates |

The disassembly goes to `build/disasm/` (from your ROM: never commit it). What
the object engine does, read from it, is in [NES_ENGINE.md](NES_ENGINE.md).

To run the probe (needs FCEUX; writes to `build/nes/probe`):

```bash
PROBE_OUT=$PWD/build/nes/probe xvfb-run -a fceux --no-config 1 --sound 0 --loadlua tools/nes_probe/dump_stage.lua build/nes/castlevania.nes
```


## Sound

- The sound driver is in PRG bank 0. `$8187` starts sound A (the game goes
  through `$C1A7`, which selects bank 0 and guards against re-entry); `$838A`
  is the per-frame update, called from the NMI. It keeps six channel slots in
  zero page `$80-$DF`, 16 bytes each (`$02,X` non-zero = active). The sound
  table pointer is at `$8185`.
- Stage music comes from a table at `$FB56` indexed by `$28` (stages 0-3 share
  `$2A`). The boss music is `$42`.
- Logged while playing (a hook on `$C1A7`): `$0A` whip, `$08` dagger thrown,
  `$14` whip strikes something, `$18` heart collected, `$1A` stopwatch.
  From the code around the requests: `$17` with the whip level going up,
  `$25` with an extra life. Logged later: `$48` is the stage-clear jingle (247
  frames, requested when the orb is taken), `$4E` the death tune (98 frames, with
  `$59` and `$00`), `$27` the game-start tune, `$55` stops the music, `$03` and
  `$04` tick through the stage-clear tally, `$06` steps the castle map, `$22` warns
  that time is short. Stage music: the table at `$FB56` by `$28` (`$2A` for stages
  0-3, `$2D` for 4-6, `$30` for 7-9). The others in
  `tools/convert_sound.py` (`NES_SOUNDS`) are guesses still to be checked by ear.
