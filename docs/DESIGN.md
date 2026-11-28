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
| Cartridge | UNROM: 128 KB PRG, CHR-RAM | ASCII16 MegaROM, 256 KB (512 KB with block 2, 1 MB with stages 13-18) |

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
| 0x4000-0x7FFF | sprite page 1 (its tables at the same offsets) |
| 0x8000-...   | all of Simon's frames, copied by the VDP (see below) |

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

Patterns are streamed: only the current frame's patterns are in a sprite page,
in the player's 12 pattern slots, leaving the rest of the sprite patterns for
enemies. There are two complete sprite pages in VRAM: patterns, attributes and
colours, with page 1 at page 0 + 0x4000 (the V9958 has 128 KB). During the
frame the game notes what the hidden page needs (`write_player_sprites`); in
VBLANK `sprite_vram` writes it and switches R#5 and R#6 to it.

### VDP write speed (real hardware)

In screen 4 the V99x8 gives the CPU few VRAM access slots in the border and
the vertical blank. A Z80 writing faster than about one byte per 90 T-states
there loses bytes (openMSX shows it with `too_fast_vram_access real`; the
first real-hardware tests showed garbled sprites). On a turbo R the S1990
spaces the R800's VDP writes itself. So:

- every CPU copy loop to the VDP waits about 100 T-states per byte
  (`vram_out_vb`, `vpace` in `src/vdp.asm`);
- a new pose of Simon (up to 11 sprites: 528 bytes) is not written by the
  CPU. All 140 of his frames are copied once at start-up into the VRAM above
  0x8000, each as its patterns in sprite order followed by its colours
  (`player_vram` in `tools/areas_asm.py` lays them out in 256-byte lines).
  A pose change is then 2 or 3 HMMM commands into the hidden page
  (`src/player_bank.asm`). The V9958 runs VDP commands in screen 4 when
  R#25.CMD is set, addressing the VRAM as in screen 8.
- the pose is copied at the end of the frame's logic, not in VBLANK: on a
  turbo R every VDP access of the R800 waits for the VDP, and in VBLANK the
  copy pushed the VBLANK work past the HUD's scroll split (line 13), which
  tore the top of the playfield.
- the VBLANK work itself runs with interrupts on, so the line interrupt
  that splits the HUD's scroll from the playfield's comes on time however
  long that work takes (on a Goa'uld MSX2+ it ran past the split). An
  interrupt between two VRAM data writes is harmless (the handler moves no
  VRAM address); only the two bytes of an address or register write are
  protected (`vram_set_write`, `vdp_wreg`, ...), and every page-2 bank
  switch sets `page2_bank`, which the sound interrupt maps back.

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
left, so the fight stays on one screen as on the NES. When it dies it leaves an orb, and taking the orb clears the stage
(`clear_tick`, as measured on the NES): the jingle, the timer runs down into the
score (10 points a step), then the hearts (100 points each), and the area named by
the boss area's `AH_NEXT` loads with 5 hearts and its stage's timer. The castle
map the NES shows between blocks is left out.

With more than 8 sprites on a line, the VDP drops the extras. The order of
objects in the sprite list rotates every frame (Simon always comes first), so
crowded lines flicker instead of losing sprites, as on the NES.

### Performance

On the 3.58 MHz Z80 test machine, a normal frame needs about 6 ms of logic
plus 2.7 ms of VBLANK work. Most of the logic is building the sprite list (2.5 ms) and
writing it to the hidden page (2.4 ms). Busy scenes (5 candles, 3 zombies, or two fishmen and a fireball, with
Simon changing pose) occasionally need more than a frame: the smoke test reports
how often (about 3%). The turbo R's R800 runs the logic several times faster.

### Game rules

A HUD redraw is spread over three frames (the bars; score, timer and stage; lives,
icon and hearts), so it never takes too much of one vertical blank. The HUD shows the score, the timer, the stage number (from the area header), the
health bars, hearts and lives. The timer counts down in BCD, one step every 64
frames as on the NES. Kills add points (zombie 100 and panther 200 as measured on
the NES; bat, fishman and boss values are estimates). When health or time runs out,
Simon plays the 97-frame death animation and loses a life: he restarts at the start
of the section with full health, 5 hearts and the timer of his stage (the NES's
table: 300, 200, 100 for stages 1-3, 400, 300, 200 for 4-6). A fall into a pit costs
the life without the animation. With no lives left it's game over: the HUD says so
for 3 seconds and a new game starts.

### Whips and the dagger

Simon's whip poses come in three sets, one per whip level (leather, chain,
morning star), each standing and crouched; the whip level picks the set. The
morning star's hit box is 16 px longer. The NES flashes the morning star by cycling
its palette; the port shows it in the whip colour for now.

UP + whip with the dagger and at least one heart throws it instead: one heart, the
whip's arm poses without a whip, and a dagger object that flies 4 px per frame. The
whip and the dagger share one hit test (`weapon_hits`), so everything the whip can
destroy, the dagger can too; a dagger is spent on its first hit. One dagger can fly at
a time.

The axe and holy water work the same way (one sub-weapon in the air at a time, one
heart each) with their own movement: the axe flies up and forward under gravity,
goes through what it hits and leaves the screen; holy water is lobbed low and burns
on the floor for 77 frames through the NES's five flame pictures, hitting what
touches the fire. A multi-hit enemy (so far only the boss) is held in the fire: it
cannot move and is hurt again whenever its hit flash ends.

Only the held sub-weapon's flying sprites are in VRAM: each area keeps a window of
sprite patterns (`AH_SUB_SLOT`) and `load_sub_patterns` copies the held weapon's
patterns into it when an area loads and when Simon picks one up. Patterns the window
shares with the area's other frames are stored once. Where an area still needs more
than the 52 free sprite patterns, the converter folds animation frames together
(listed in `FOLDS`, least visible first; the hall shows the second wide flame as the
first, stage 3 uses one walking frame for a zombie). A death resets the whip and the
sub-weapon, as on the NES, so the window always matches what Simon can hold.

Frames that are never on screen together share a second window (`AH_SWAP_*`):
in stage 3 the zombies' patterns are there until the boss wakes. Then the screen
locks, the zombies vanish, zombie spawning stops, and the boss's patterns
(`load_swap_patterns`) take their place until the area is loaded again. This is
what lets stage 3 keep every frame unfolded.

The stopwatch (5 hearts) freezes enemies, their fireballs, the spawners and the
timer for 178 frames, as on the NES. Frozen enemies can still be whipped. A candle
drops a small heart instead of the sub-weapon Simon already holds, the NES rule. The
HUD shows the sub-weapon as a 2x2-tile icon at its top right (white on black: the
HUD has two colours per tile row), converted from the NES HUD's icons.

## Areas and ROM banks

Bank 0 holds the code, bank 7 Simon's sprites and the RAM code, banks 8 and up the
sound streams (as many as they fill). Every area (courtyard, entrance hall, …) has
two pieces, packed into the other banks first fit, largest first
(`tools/areas_asm.py`): its run-time piece (header, map, collision, object tables)
and its graphics (palette, background tiles, sprite patterns, the windows'
pictures), which are mapped only while they are copied (`AH_SWAP_BANK`). A bank
with run-time pieces starts with their header addresses; `area_bank_tab` gives
per area its bank and slot (`area_bank`, `area_entry`). The whole game fits in
512 KB. The collision map is a bit per tile (3 bytes a column). The header holds:
palette, background tiles per band,
map, collision, candle list, object sprites, start position, and an exit
(x position, the highest y at which it counts, plus next area). The current area's bank stays mapped at
0x8000 because column streaming and collision read it directly. The header
is copied to RAM. Code and data shared by all areas live in bank 0, at 0x4000. Simon's sprite
patterns and colours are in the last bank: the code that copies his current frame
into video memory maps it at 0x8000 for the copy, then maps the area's bank back.

A stage's sections (for example stage 2's corridor and the waterway under it) are
separate areas. Their header names the area below and the area above. A staircase
whose other end is in the next section is converted with a made-up end beyond the
playfield edge. When Simon walks down past the bottom of the playfield, or up past
its top, the next area is loaded around him. His x stays the same and his y moves
by 158 px, as measured on the NES, and he carries on along the same staircase
there. Each area also names the area to restart in after a fall.

Exits can play a sequence first, as on the NES (`AH_EXIT_KIND`). At the castle gate
Simon walks in by himself and goes behind the gate's right pillar a column of pixels at
a time, as on the NES. The MSX can't draw sprites behind the background, so while he
walks in, the columns of his sprite patterns past the pillar's edge (`AH_DOOR_COL`) are
cleared as the patterns are copied to video memory (`clip_pattern`), every frame. At a door the screen
scrolls on to `AH_DOOR_CAM`; the door half opens, opens, half opens again and shuts.
The NES draws the opened door with sprites; the port has no sprite patterns to spare
in these areas, so the converter draws the half-open and open door over the wall into
6 extra tile columns at the end of the area's map (`AH_DOOR_VCOL`, never on screen),
and the sequence copies 3 columns of them into the name table at each step. After the
door shuts, Simon walks on to `AH_WALK_END` and the screen scrolls on to `AH_CAM_END`:
the next stage's start x on the first of its columns, and the x where its map begins.
So when the next stage loads (camera 0, Simon at its start), nothing on the screen
jumps, and Simon is still on its ledge. The hall
and stage 2's corridor include the next stage's first 8 map columns for this; their
normal camera limit (`AH_MAXCAM`) stays where it was, so those columns only show
during the sequence. The game logic, the timer and the enemies wait meanwhile. An exit only starts while
Simon stands on the ground (not in a jump, on stairs or knocked back), so a jump into
the gate or a door starts the sequence when he lands.

Block 2 (stages 4-6) runs right to left on the NES: its doors are at the left end of
a section. Its areas start with 8 extra map columns, the last 8 columns of the next
stage's first section (they come straight before the section's map in the ROM), so
every x there is the NES x + 256. `AH_MINCAM` keeps them off the screen in normal
play (stage 4's first section is one screen: its least and greatest camera x are the
same). At a door with `AH_EXIT_LEFT` set, the sequence runs mirrored: the screen
scrolls left to `AH_DOOR_CAM`, the door opens to the left (the converter mirrors the
NES door picture), Simon walks left into the next stage's columns, and the next stage
loads at its right end with Simon facing left (`AH_FACE`), as on the NES. The door's
height varies (`AH_DOOR_ROW`), and each area names its music (`AH_MUSIC`: block 2
has its own).

Block 2's enemies: Medusa heads come from their spawners like the stage 2 bats (every
64 frames, up to three, at the screen edge Simon faces) and fly in a cosine wave
(`mhead_wave`). Spear knights and hanging bats are placed enemies in the candle list,
like the panthers: the knight uses the zombie's frames (block 2's graphics have the
knight in those tiles), paces its floor, turns to face Simon now and then and at the
end of its floor, and takes two whip hits; the hanging bat flies at Simon when he comes
near and level with it, along the recorded drop.

Stage 6's ceiling crushers are background tiles, as on the NES. The converter draws
the spikes at each of their heights into hidden map columns (`AH_CRUSH_VCOL`, 4 per
height) and lists each crusher's x and cycle (`AH_CRUSHERS`). Each frame every crusher
steps through its cycle, and spikes that reach Simon kill him. In the vertical blank
one crusher whose height changed is copied into the name table (only when the HUD has
nothing to redraw and no map column is uploaded, so the vertical blank stays short);
a new map column shows them at rest, so it marks them all to be drawn again.

Medusa is placed like the stage 3 boss (candle list kind 8) and shares its health bar,
hit, burn and orb code (`boss_update.hits`, `.burning`). Asleep she is the statue in the
map and draws no sprites. She wakes when Simon is near and the screen has reached her
room at the area's left end: the boss music starts, the camera locks (its least and
greatest x both set to where it is), and `medusa_vram` blanks the statue's 4x3 tiles
in the next vertical blank. She flies with the bat's wave, stops now and then and drops
a snake, which falls to the floor and slides at Simon. Taking her orb clears the
stage, and block 3 starts.

Block 3 (stages 7-9) uses the same machinery: stage 7 starts at its right end facing
left, and its doors are on the right, followed in the ROM by the next stage's first
columns as in block 1, so its areas need no x offset. Its enemies (fleamen, ghosts,
skeletons and their bones, bone pillars and their fireballs, ravens) are placed in the
candle list; the skeleton uses the zombie's frames, the pillar's fireball the fishman's
(at 2 px a frame). The ghost and the pillar take several hits: `obj_hits` keeps hits
taken and a short flash per object slot.

The mummies (stage 9's boss) are two placed enemies with 32 health each; the HUD's bar
shows both. They wake when the screen reaches their room (the area's last screen): the
screen locks, the bridge's enemies go, and the swap window, generalised to pairs of
frame sets (`SWAP_PAIRS`), gives their sprite patterns to the mummies. They walk at
Simon and throw bandages along the bat's wave; the last one to fall burns into the orb,
and the stage clear ends block 3 (block 4 is not converted: the game goes back to the
courtyard).

### Code in RAM

Bank 0, the code page, is full. The enemies of blocks 2-7 run from RAM
(`src/ramcode.asm`, sjasmplus `DISP`). The resident part (`src/enemies2.asm`: the
shared helpers and the enemies several blocks use) is stored in Simon's bank and
copied at start-up to `RAMCODE` (0xC600). After it, at `OVL_BASE`, one overlay at a
time (`src/overlays.asm`): overlay A (`src/ovl_a.asm`, blocks 2-4's own enemies and
bosses) or overlay B (`src/ovl_b.asm`, blocks 5-7's), stored in a bank of their own
(`OVL_BANK`) and copied by `load_area` when the stage needs the other one. Resident
code calls an overlay's routines only for objects of the blocks that load it. All of
it calls the engine in bank 0 and reads the current area's bank at 0x8000 like the
rest of the object code.

### Swap sets

An area's object patterns are the main set (always in video memory), the window of
the sub-weapon Simon holds, and a swap window: sets that are never on the screen
together (stage 3's zombies, then the bat boss; the corridor's enemies, then
Frankenstein or Death; each of Dracula's pictures). `load_swap_patterns` copies a set
into the window; the area header points to a table of the sets (`AH_SWAP_TAB`), and
an area whose sets are big keeps them in a bank of their own (`AH_SWAP_BANK`, mapped
while they are copied). Dracula loads the set of the picture he shows whenever it
changes. A frame may use up to 16 hardware sprites; one that would need more gets a
single sprite for the cells whose second colour has the fewest pixels.

### Late frames

`wait_frame` returns right after a VBLANK interrupt. A frame whose logic ran past the
next VBLANK goes on at once only while the VDP is still in the vertical retrace (S#2
bit 6); otherwise it waits for the next one, rather than writing to video memory while
the screen is drawn and staying out of step with the interrupts from then on.

`load_area` turns the display off, loads the palette, tiles and object
patterns, resets objects and the player, redraws the screen and turns
the display back on. Walking past the area's exit x loads the next area.
Falling into a pit reloads the current one.

Candles spawn like on the NES: only candles within the screen
(plus a margin) get one of the 8 object slots, objects far outside the
screen are freed, and a destroyed candle stays destroyed (one bit per candle)
until the area is loaded again.

## Memory

## Editing sprite frames

`tools/sprite_edit.py export <rom> <frame names | --all>` writes object frames
from your own ROM as 1:1 24-bit BMPs into `art_overrides/` (magenta is
transparent). Edit them and rebuild: the converter uses an edited frame
instead of the ROM's pixels, mapping each colour to the nearest NES colour.
Delete a file to return to the ROM's pixels. `art_overrides/` is git-ignored:
the files come from the ROM and must never be committed.


## Sound

`src/sound.asm` plays one music stream and one sound-effect stream on the PSG.
The main loop calls `sound_tick` right after its VBLANK work (the PSG needs no
VRAM, so it stays out of the vertical blank). A stream is a list of PSG
register changes per frame (`tools/sound_out.py` describes the bytes). Streams
live in ROM banks 8-15, after Simon's sprite bank, and may run on into the
next bank. The player switches the 0x8000 page to the stream's bank and puts
back `page2_bank`, which every bank switch in the engine keeps up to date. An
effect takes over only the PSG channels in its table mask; the music carries
on underneath and is heard again when the effect ends.

The engine asks for sounds by name (`SND_STAGE`, `SND_WHIP`, ... in the
generated `sound.inc`). Two sets provide them:

- `tools/gen_sound.py`: original placeholder effects and short tunes, used
  by default in both builds.
- `tools/convert_sound.py` (`make nes SOUND=rom`): the music and effects of
  your own NES ROM, made on your machine. It runs the game's own sound
  driver in a small 6502 interpreter (`tools/cpu6502.py`,
  `tools/nes_sound.py`), models the NES sound chip's per-frame state and
  maps pulse 1 / pulse 2 / triangle to PSG A / B / C and the noise channel to
  C's noise. DPCM samples are not converted. Like everything made from the
  ROM, the result stays in `build/` and is never committed.
