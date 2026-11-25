# Technical design

How the NES game's hardware features map onto the MSX turbo R.

## Target hardware

| | NES (Castlevania, 1986) | MSX turbo R (FS-A1ST / FS-A1GT) |
|---|---|---|
| CPU | Ricoh 2A03 (6502), 1.79 MHz | R800 at 7.16 MHz (Z80 compatible) |
| Work RAM | 2 KB | 256 KB / 512 KB |
| Video | PPU, 2 KB nametable RAM, 8 KB CHR-RAM | V9958, 128 KB VRAM |
| Background | 8x8 tiles, 4 colours per 16x16 area | 8x8 tiles, 2 colours per 8-pixel row (Screen 4) |
| Sprites | 64, 8x8/8x16, 3 colours + transparent, 8 per line | 32, 16x16, 1 colour per line (3 with OR-ing), 8 per line |
| Scrolling | hardware, both axes | V9958 hardware horizontal + vertical |
| Sound | 2 pulse, triangle, noise, DPCM | PSG (3 ch) + MSX-MUSIC FM (9 ch) + 8-bit PCM |
| Cartridge | UNROM: 128 KB PRG, CHR-RAM | ASCII16 MegaROM, 128 KB |

The engine requires a **V9958** (MSX2+ or turbo R) for the horizontal
scroll registers. It runs on an MSX2+ with a 3.58 MHz Z80 too, which is
useful for testing with the free C-BIOS, and it switches to the R800 when
it finds a turbo R.

## Screen layout

Screen 4 (Graphic 3): 256x192 pixels, 32x24 tiles, 16 colours from a palette of 512.

```
line   0-15   HUD       2 tile rows, never scrolls
line  16-191  playfield 22 tile rows = 11 metatile rows = the full NES playfield (176 px)
```

The NES HUD uses three text lines. It's compacted into two here so that
the NES playfield fits **without cropping**, which matters for gameplay
(stairs, ceilings, enemy spawn heights).

### HUD / playfield split

The V9958 scroll registers (R#26 coarse, R#27 fine) affect the whole screen. To keep the
HUD fixed:

1. **VBLANK interrupt** (`H.TIMI`): set the scroll to 0, so the HUD is drawn unscrolled.
2. **Line interrupt** at `SPLIT_LINE` (`H.KEYI`, R#19): load the camera scroll.

The split fires a few lines before the playfield, inside the blank bottom
rows of the HUD font, so interrupt-latency jitter is invisible. R#25.MSK hides the
leftmost 8 pixels, which would otherwise show the column being redrawn.

### Column streaming

The 32-column name table is a ring. With camera at `X` the visible world
tile columns are `X/8+1 … X/8+32` (column `X/8` is always under the mask),
and those map to 32 distinct ring slots. When `X/8` changes, exactly one
column (22 name-table bytes) is rebuilt from the metatile map and
written during VBLANK. The camera moves at most 8 px per frame.

## VRAM map

| Address | Contents |
|---|---|
| 0x0000-0x17FF | pattern generator, 3 bands of 256 tiles |
| 0x1800-0x1AFF | name table |
| 0x1C00-0x1DFF | sprite colour table |
| 0x1E00-0x1E7F | sprite attribute table |
| 0x2000-0x37FF | colour table, 3 bands |
| 0x3800-0x3FFF | sprite patterns (64 x 16x16) |

Tile numbers: `0x00` blank, `0x01-0x1F` HUD symbols, `0x20-0x5F` font
(copied from the BIOS), `0x60-0xFF` background tiles. Each band has its
own background tile set (160 tiles per band), holding only the tiles used in
those rows.

## Area format

The placeholder generator and the NES converter both produce the same
"area" (see `tools/msx_area.py`):

| File | Contents |
|---|---|
| `palette.bin` | 16 colours |
| `bg_pgt_b0..2.bin`, `bg_ct_b0..2.bin` | patterns and colours per band |
| `level_tiles.bin` | name-table bytes, 22 per 8-pixel column |
| `level_coll.bin` | solidity, 11 per 16-pixel column |

Palette slots 0/1 (black), 2/4/6 (player OR-colours) and 15 (white) have
the same meaning in every area. In the converted build, slots 2/4/6 hold Simon's
colours (brown = layer A, peach = layer B, orange = both), so his 3 NES
colours are reproduced exactly. The HUD only uses 1, 6 and 15. The
converter assigns the stage's other NES colours to the remaining 10 slots.

## Colour restrictions

### Backgrounds

NES: each 16x16 area picks one of 4 palettes of 3 colours plus a shared backdrop.
MSX Screen 4: each 8-pixel row of a tile has a foreground and a background colour.

The converter will:
1. Expand every (NES tile, palette) pair actually used by a stage into an MSX tile.
2. Reduce rows that have 3-4 colours to 2. It will flag these for hand
   retouching; an automatic best fit is used until a hand-drawn
   replacement exists.
3. Deduplicate. Each band holds 128 background tiles at `0x80-0xFF`, or more if
   the HUD font moves.

This is implemented in `tools/msx_area.py`. For the Stage 1 courtyard
about 22% of tile rows lose a colour, and the result still looks very close to
the NES version. The tiles that look worst can later be redrawn by hand.

### Sprites

MSX sprites have one colour per line. Two sprites at the same position,
the second with the **CC** bit set in its colour table, are OR-ed:

```
layer A = palette 2 (brown)    layer B = palette 4 (skin)    A|B = palette 6 (red)
```

So a 16x16 NES-style figure with 3 colours costs **2 hardware sprites**,
and the 16x32 player costs 4. Palette entries 2, 4 and 6 are chosen together for this.

### Metasprites

Each pose of the player is a list of hardware sprites (`tools/msx_sprites.py`):
`count`, then `dy, dx, pattern, colour column` for each sprite. The body
uses the OR layers above. Single-colour parts such as the whip use one
sprite per 16x16 cell; MSX sprites can change colour on every line, so the
whip's light line and black outline fit in one sprite. A second sprite is added only
for lines with two colours. The converter refuses frames with more than
12 sprites, or more than 8 on one scanline (the hardware limit). The
whip strike needs 10 sprites, at most 8 on a line.

The MSX has no sprite flipping, so left-facing frames are stored
pre-mirrored: 12 poses x 2 directions.

### Double-buffered sprite pages

Patterns are streamed: only the current frame's patterns are in VRAM, in
the player's 12 pattern slots, leaving the rest of the sprite patterns for enemies.
Copying a new frame (up to 480 bytes) during VBLANK took too long on a 3.58 MHz
Z80 (7.5 ms worst case; the vertical blank is 4.4 ms). So there are two
complete sprite pages in VRAM: patterns, attributes and colours, with page 1 at
page 0 + 0x4000 (the V9958 has 128 KB). The game writes the next frame
into the hidden page during the frame. In VBLANK, R#5 and R#6 are switched
to it. Worst-case VBLANK work is now about 2.7 ms, and the smoke test checks it.

### Objects

Braziers, their bursts and the items they drop live in 8 object slots
(`src/objects.asm`). Their sprite patterns stay in VRAM permanently, in pattern
slots 12 and up of both sprite pages, after Simon's 12 streamed slots. Their sprites are
appended after Simon's in the attribute table each frame. Their hardware sprite
numbers change with Simon's sprite count, so their colour columns are rewritten
into the hidden page every frame (16 bytes per sprite).

That leaves 64 - 12 = 52 pattern slots for objects. The converter only includes
the frames an area can show (the courtyard has no enemies, the hall no braziers),
and stops the build if an area still needs more than 52 patterns. If one does, it first
folds the least visible frames into others (the hall's panthers use their first
running frame in place of the third). Object colours use the stage
palette: the exact colour where it exists, otherwise the nearest one.

The hardware shows at most 8 sprites per scanline. Simon uses up to 6 on a line
(whip strike) and a brazier 2, so two braziers on Simon's lines can exceed the
limit. Sprite rotation (flicker, as on the NES) is still to do.

### Collision

As on the NES, collision is decided per 8x8 tile: the converter marks the
tiles the NES treats as solid (`$60-$6B`). The area stores one byte per
tile in `level_coll` (22 bytes per 8-px column).

### Stairs

Each area's header points to its staircases (foot x/y, top x/y, direction),
converted from the NES stair table with Simon's measured alignment and an exact
45° slope. UP within 8 px of a foot (or DOWN near a top) makes Simon walk
to the exact spot and get on. On the stairs, gravity and collision are off.
He moves one pixel across and one up or down on alternating frames while the stick
points along the stairs, and gets off at either end.

### Enemies and getting hit

Enemies are objects too. Each area lists its zombie spawners (from the
NES enemy groups). While one is within the camera window, zombies come in
waves, like on the NES: three, 32 frames apart, at alternating screen edges. The
next wave starts only when the whole wave is gone (killed or walked off the
screen), after a pause of 96 + 32 frames. Simon has 64 HP,
shown as 8 HUD tiles. A hit freezes him, then the knock-back uses the same arc
code as the jump, with the NES knock-back table instead of the jump table. He
lands crouched, then blinks for 140 frames. Running out of health restarts the area.

Black panthers are placed enemies: the converter adds them to the area's
candle list as a third kind, so they spawn near the screen and stay dead
once killed, exactly like candles. A panther that wakes up is marked dead at
once, so it doesn't come back after running off the screen. Each runs a small
state machine (wait, run, leap with gravity, run). Whenever there is no floor
under a running panther it leaps again, so it never runs through the air.

Bats are spawned like zombies, from the area's spawner list (type 2): one at a time,
192 frames after the last one is gone (slower than the NES's quickest, so the way to
stage 2's door is fair), at the screen edge Simon faces. A bat flies
straight at him with a 96-frame vertical wave read from a table, and dies when it
hits him.

Fishmen come from the waterway's spawners (type 3, one per 64-px chunk): at most
two at a time, each jumping out of the water at a spawner on the screen but not
right under Simon. They use a small state machine like the panther's (in the air,
walking, shooting) and fire fireballs, which are objects of their own. A fireball
flies at standing height: crouching Simon ducks under it.

The stage 3 boss is placed like a panther (record type `$59` becomes a candle-list
entry of kind 5). It is a 48x32 object with its own state machine (asleep, flying to
a spot, hovering, swooping at Simon, burning). Its health is shown in the HUD's
enemy bar. Its swoops aim at where Simon is on both axes, so it reaches him on the
floor too. While hovering far from Simon (`BOSS_FIRE_FAR`, 128 px) it spits a slow
fireball at him, as in a video of the NES fight (the FCEUX recordings never had
Simon that far away). When it wakes, the camera locks: it can still move right but never back
left, so the fight stays on one screen as on the NES. When it dies it leaves an orb, and taking the orb clears the stage: for
now the game then starts again from the courtyard, because the next block isn't
converted yet.

With more than 8 sprites on a line, the VDP drops the extras. The order of
objects in the sprite list rotates every frame (Simon always comes first), so
crowded lines flicker instead of losing sprites, as on the NES.

### Performance

On the 3.58 MHz Z80 test machine, a normal frame needs about 6 ms of logic
plus 2.7 ms of VBLANK work. Most of the logic is building the sprite list (2.5 ms) and
writing it to the hidden page (2.4 ms). Busy scenes (5 candles, 3 zombies, or two fishmen and a fireball, with
Simon changing pose) occasionally need more than a frame: the smoke test reports
how often (about 3%). The turbo R's R800 runs the logic several times faster.

## Areas and ROM banks

Each area (courtyard, entrance hall, …) is one 16 KB ROM bank (area n =
bank n+1) that starts with a header: palette, background tiles per band,
map, collision, candle list, object sprites, start position, and an exit
(x position, the highest y at which it counts, plus next area). The current area's bank stays mapped at
0x8000 because column streaming and collision read it directly. The header
is copied to RAM. Code and data shared by all areas (Simon's sprites, HUD)
live in bank 0, at 0x4000.

A stage's sections (for example stage 2's corridor and the waterway under it) are
separate areas. Their header names the area below and the area above. A staircase
whose other end is in the next section is converted with a made-up end beyond the
playfield edge. When Simon walks down past the bottom of the playfield, or up past
its top, the next area is loaded around him. His x stays the same and his y moves
by 158 px, as measured on the NES, and he carries on along the same staircase
there. Each area also names the area to restart in after a fall.

`load_area` turns the display off, loads the palette, tiles and object
patterns, resets objects and the player, redraws the screen and turns
the display back on. Walking past the area's exit x loads the next area.
Falling into a pit reloads the current one.

Candles spawn like on the NES: only candles within the screen
(plus a margin) get one of the 8 object slots, objects far outside the
screen are freed, and a destroyed candle stays destroyed (one bit per candle)
until the area is loaded again.

## Memory