"""Convert Simon (player sprite, palette, jump arc) from the user's ROM.

Simon is 16x32 pixels: four NES 8x16 sprites in a 2x2 grid. The NES art
faces left; the MSX has no sprite flipping, so both directions are stored.

Each MSX frame is 2 OR-ed layers x 2 halves of 16x16 sprites. The three
NES colours map onto the layers like this (see docs/DESIGN.md):

    NES colour 3 -> layer A only   (palette slot 2)
    NES colour 2 -> layer B only   (palette slot 4)
    NES colour 1 -> both layers    (palette slot 6 = 2|4)
"""

from cv_rom import CastlevaniaROM, tile_pixels  # noqa: F401  (rom type)

# Engine frame order: 0 stand, 1 walk1, 2 walk2, 3 tucked (jump / crouch).
# Tile numbers of the four 8x16 sprites, NES art facing left:
#   (top-left, top-right, bottom-left, bottom-right)
SIMON_FRAMES = [
    (0x02, 0x04, 0x06, 0x08),
    (0x0A, 0x0C, 0x0E, 0x10),
    (0x12, 0x14, 0x16, 0x18),
    (0x02, 0x04, 0x32, 0x34),
]

SIMON_PALETTE = 0xCDE9          # fixed bank: $3F $10, then sprite palettes
JUMP_TABLE = (6, 0x9B90)        # 20 signed bytes: dy per frame while rising
JUMP_LEN = 20

NES_TO_LAYERS = {0: (0, 0), 1: (1, 1), 2: (0, 1), 3: (1, 0)}   # value -> (A, B)
SLOT_FOR_VALUE = {1: 6, 2: 4, 3: 2}


def _sprite16(rows16):
    out = bytearray()
    for half in (0, 8):
        for r in rows16:
            b = 0
            for x in range(8):
                if r[half + x]:
                    b |= 0x80 >> x
            out.append(b)
    return bytes(out)


def _frame_pixels(chr_ram, tiles):
    """16x32 list of NES colour values for one frame (facing left)."""
    tl, tr, bl, br = tiles
    img = [[0] * 16 for _ in range(32)]
    for col, top in ((0, tl), (8, tr)):
        for t, oy in ((top, 0), (top + 1, 8)):
            px = tile_pixels(chr_ram, 0x0000, t)
            for y in range(8):
                for x in range(8):
                    img[oy + y][col + x] = px[y][x]
    for col, top in ((0, bl), (8, br)):
        for t, oy in ((top, 16), (top + 1, 24)):
            px = tile_pixels(chr_ram, 0x0000, t)
            for y in range(8):
                for x in range(8):
                    img[oy + y][col + x] = px[y][x]
    return img


def convert(rom, nes_rgb, to_msx_rgb):
    """-> (sprite pattern bytes, {slot: msx rgb}, jump table bytes)"""
    chr_ram = rom.chr_ram()
    patterns = bytearray()
    for facing_left in (False, True):           # engine order: right, then left
        for tiles in SIMON_FRAMES:
            img = _frame_pixels(chr_ram, tiles)
            if not facing_left:
                img = [row[::-1] for row in img]
            layer_a = [[NES_TO_LAYERS[v][0] for v in row] for row in img]
            layer_b = [[NES_TO_LAYERS[v][1] for v in row] for row in img]
            patterns += _sprite16(layer_a[:16])
            patterns += _sprite16(layer_b[:16])
            patterns += _sprite16(layer_a[16:])
            patterns += _sprite16(layer_b[16:])

    a = SIMON_PALETTE
    assert rom.fixed(a) == 0x3F and rom.fixed(a + 1) == 0x10, "Simon palette not found"
    nes_cols = [rom.fixed(a + 2 + i) for i in range(4)]
    slots = {SLOT_FOR_VALUE[v]: to_msx_rgb(nes_rgb[nes_cols[v]]) for v in (1, 2, 3)}

    bank, addr = JUMP_TABLE
    jump = bytes(rom.rd(bank, addr + i) for i in range(JUMP_LEN))
    if sum(b - 256 if b >= 128 else b for b in jump) >= 0:
        raise SystemExit("jump table not found where expected")
    return bytes(patterns), slots, jump
