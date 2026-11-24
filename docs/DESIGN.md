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

Sprite budget: 32 sprites total, 8 per scanline. The player takes 2 per line,
and the whip will add up to 2 more. Enemies have to be mostly 1–2 colours,
or flicker by rotating sprite priority each frame, like the NES game does.

The MSX has no sprite flipping, so left-facing patterns are stored
pre-mirrored. For the real game, patterns will be streamed to VRAM per
frame rather than all being resident.

## Memory

| Region | Use |
|---|---|
| 0x0000-0x3FFF | BIOS |
| 0x4000-0x7FFF | cartridge bank 0: engine code (fixed) |
| 0x8000-0xBFFF | cartridge bank 1-7: data (switched via 0x7000) |
| 0xC000-       | engine RAM (`src/ram.inc`) |

## Interrupt handling and the BIOS

The engine currently keeps the BIOS interrupt handler and uses its hooks.
That costs CPU time every frame (keyboard scan, etc.). A later step is to put RAM
in page 0 and own the interrupt vector at 0x0038. This is easy on a
turbo R, which always has a memory mapper.

On a turbo R, cartridge ROM is slower to read than internal RAM under the
R800. Hot code (the object update loop, column builder) should be copied
to RAM at boot.

## Porting the game logic

The plan is a faithful re-implementation, not emulation:

1. Disassemble the NES PRG banks (`tools/nes_rom_tool.py split`) and
   document the object system, stage format, and enemy/boss AI.
2. Re-implement each routine in Z80, keeping the NES data formats
   (stage layouts, enemy placement, physics tables) wherever possible, so
   converted data can be used directly.
3. Convert graphics and music at build time from the user's ROM.

No Konami code or data is committed to this repository.
