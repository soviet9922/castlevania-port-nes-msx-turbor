"""Convert candles/braziers and item sprites from the user's ROM.

Candle placement (fixed bank, see docs/NES_NOTES.md):
  word at $D29B + 2*stage        -> per-stage table
  word at that table + 2*section -> per-section table, 2 bytes per 64-px chunk:
                                    (enemy group, candle group)
  candle group g: word at $D6D1 + 2*g ($D7D1 when bit 7 is set) -> record
  record: [$FF item] [$FE] x y    (0 = no candle; $FE = brazier, object $28)

Observed in the game: the object stands at world x = (chunk-1)*64 + x,
with y the NES foot line. Drop codes: 0 whip upgrade, 4 big heart, 8 dagger.

Sprites (8x16, tile bit 0 selects the pattern table, as on the NES):
  brazier  flame $97/$99 (palette 3) over bowl $9B (palette 2), mirrored pairs
  burst    $91+$70, $93+$70, $93, $95 (palette 3)
  items    big heart $BF pair (pal 3), whip upgrade $C1 $C3 (pal 3),
           dagger $BD $BB (pal 2, flipped)
"""

from cv_rom import tile_pixels
from msx_sprites import SpriteBank

STAGE_TABLE = 0xD29B
CANDLE_GROUPS = (0xD6D1, 0xD7D1)
SPRITE_PALETTES = 0xCDEB         # 4 x 4 colours after the $3F $10 header

# engine object frame numbers (src/objects.asm)
OBJ_FRAMES = ["brazier1", "brazier2", "burst1", "burst2", "burst3", "burst4",
              "heart", "whipup", "dagger"]

# frame: list of (tile, dx, dy, palette, hflip) relative to the object's
# 16x32 box top-left (box = brazier: flame on top, bowl below)
FRAME_SPRITES = {
    "brazier1": [(0x97, 0, 0, 3, 0), (0x97, 8, 0, 3, 1), (0x9B, 0, 16, 2, 0), (0x9B, 8, 16, 2, 1)],
    "brazier2": [(0x99, 0, 0, 3, 0), (0x99, 8, 0, 3, 1), (0x9B, 0, 16, 2, 0), (0x9B, 8, 16, 2, 1)],
    "burst1": [(0x91, 4, 8, 3, 0), (0x70, 8, 8, 3, 0)],
    "burst2": [(0x93, 4, 8, 3, 0), (0x70, 8, 8, 3, 0)],
    "burst3": [(0x93, 4, 8, 3, 0)],
    "burst4": [(0x95, 4, 8, 3, 0)],
    "heart": [(0xBF, 0, 8, 3, 0), (0xBF, 8, 8, 3, 1)],
    "whipup": [(0xC1, 0, 8, 3, 0), (0xC3, 8, 8, 3, 0)],
    "dagger": [(0xBD, 0, 8, 2, 1), (0xBB, 8, 8, 2, 1)],
}


def candles(rom, stage, section, level_px):
    """-> list of (world_x_left, msx_y_top, item code) for braziers in the area."""
    def w7(a):
        return rom.fixed(a) | rom.fixed(a + 1) << 8
    table = w7(w7(STAGE_TABLE + 2 * stage) + 2 * section)
    out = []
    for chunk in range(level_px // 64 + 1):
        group = rom.fixed(table + 2 * chunk + 1)
        p = w7(CANDLE_GROUPS[group >> 7] + ((group << 1) & 0xFF))
        b = rom.fixed(p)
        if b == 0:
            continue
        item, k = 0, 0
        if b == 0xFF:
            item, k = rom.fixed(p + 1), 2
        brazier = rom.fixed(p + k) == 0xFE
        if brazier:
            k += 1
        x, y = rom.fixed(p + k), rom.fixed(p + k + 1)
        if not brazier:
            continue                    # wall candles: not converted yet
        wx = (chunk - 1) * 64 + x
        if 8 <= wx < level_px - 8:
            out.append((wx - 8, y - 64, item))
    return out


def sprite_frames(rom, slot_for_nes):
    """-> (SpriteBank, names) for the object frames, colours mapped to MSX slots."""
    chr_ram = rom.chr_ram()
    pals = [[rom.fixed(SPRITE_PALETTES + p * 4 + v) for v in range(4)] for p in range(4)]
    bank = SpriteBank()
    for name in OBJ_FRAMES:
        pixels = {}
        for tile, dx, dy, pal, flip in FRAME_SPRITES[name]:
            table, top = (tile & 1) * 0x1000, tile & 0xFE
            for half in (0, 1):
                px = tile_pixels(chr_ram, table, top + half)
                for y in range(8):
                    for x in range(8):
                        v = px[y][7 - x if flip else x]
                        if v:
                            pixels[(dx + x, dy + half * 8 + y)] = slot_for_nes(pals[pal][v])
        bank.add_frame(pixels, name)
    return bank, list(OBJ_FRAMES)


def write_candles(path, items):
    data = bytearray([len(items)])
    for x, y, item in items:
        data += bytes([x & 0xFF, x >> 8, y & 0xFF, item])
    with open(path, "wb") as f:
        f.write(data)
