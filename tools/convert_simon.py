"""Convert Simon (sprites incl. whip, palette, jump arc) from the user's ROM.

Simon is built from NES 8x16 sprites. The poses below were recorded from
the running game (tools/nes_probe/record_simon.lua): tile number and
position relative to the top-left of his 16x32 box, facing right (the
NES draws them horizontally flipped; the art faces left).

Colours:
  Simon (sprite palette 0)   NES value 3 -> layer A (slot 2)
                             NES value 2 -> layer B (slot 4)
                             NES value 1 -> both    (slot 6 = 2|4)
  whip  (sprite palette 1)   values 1, 2 -> slot WHIP_SLOT, value 3 -> slot 1 (black)
"""

from cv_rom import tile_pixels
from msx_sprites import SpriteBank, mirror

WHIP_SLOT = 14

LEGS_STAND = [(0x08, 0, 16), (0x06, 8, 16)]
LEGS_TUCK = [(0x34, 0, 16), (0x32, 8, 16)]

# (body sprites, whip sprites); positions (tile, dx, dy) relative to the box
POSES = {
    "stand": ([(0x04, 0, 0), (0x02, 8, 0)] + LEGS_STAND, []),
    "walk1": ([(0x0C, 0, 0), (0x0A, 8, 0), (0x10, 0, 16), (0x0E, 8, 16)], []),
    "walk2": ([(0x14, 0, 0), (0x12, 8, 0), (0x18, 0, 16), (0x16, 8, 16)], []),
    "tuck": ([(0x04, 0, 0), (0x02, 8, 0)] + LEGS_TUCK, []),
    # climbing: alternates with walk1 every 8 frames (recorded on the hall stairs)
    "stair": ([(0x14, 0, 0), (0x12, 8, 0), (0x38, 0, 16), (0x36, 8, 16)], []),
}
WHIP_TOPS = {
    "whip1": ([(0x1C, -8, 0), (0x1A, 0, 0)], [(0x1E, -16, 0), (0x20, -16, 16)]),
    "whip2": ([(0x22, 0, 0)], [(0x26, -16, 8), (0x24, -8, 0)]),
    "whip3": ([(0x2A, 0, 0), (0x28, 8, 0), (0x2C, 16, 0)],
              [(0x2E, 20, -1), (0x2E, 28, -1), (0x30, 36, -1)]),
    "whip4": ([(0x2A, 0, 0), (0x28, 8, 0)], []),        # recovery, whip gone
}
for name, (top, whip) in WHIP_TOPS.items():
    POSES[name] = (top + LEGS_STAND, whip)
for name, (top, whip) in WHIP_TOPS.items():
    POSES[name + "c"] = (top + LEGS_TUCK, whip)          # crouching / in the air

# engine pose numbers (src/player.asm)
POSE_ORDER = ["stand", "walk1", "walk2", "tuck",
              "whip1", "whip2", "whip3", "whip4",
              "whip1c", "whip2c", "whip3c", "whip4c", "stair"]

SIMON_PALETTE = 0xCDE9          # fixed bank: $3F $10, then the sprite palettes
JUMP_TABLE = (6, 0x9B90)        # 20 signed bytes: dy per frame while rising
JUMP_LEN = 20

BODY_KIND = {1: "C", 2: "B", 3: "A"}
SIMON_SLOT_FOR_VALUE = {1: 6, 2: 4, 3: 2}


def _place(pixels, chr_ram, tile, dx, dy, kind_of):
    """Draw an H-flipped 8x16 sprite (tile, tile+1) into the pixel dict."""
    for half in (0, 1):
        px = tile_pixels(chr_ram, 0x0000, tile + half)
        for y in range(8):
            for x in range(8):
                v = px[y][7 - x]
                if v:
                    pixels[(dx + x, dy + half * 8 + y)] = kind_of(v)


def frame_pixels(chr_ram, pose):
    body, whip = POSES[pose]
    pixels = {}
    for t, dx, dy in whip:
        _place(pixels, chr_ram, t, dx, dy, lambda v: 1 if v == 3 else WHIP_SLOT)
    for t, dx, dy in body:
        _place(pixels, chr_ram, t, dx, dy, lambda v: BODY_KIND[v])
    return pixels


def convert(rom, nes_rgb, to_msx_rgb):
    """-> (SpriteBank, frame names, {slot: msx rgb}, jump table bytes)"""
    chr_ram = rom.chr_ram()
    bank = SpriteBank()
    names = []
    for facing in ("right", "left"):
        for pose in POSE_ORDER:
            px = frame_pixels(chr_ram, pose)
            if facing == "left":
                px = mirror(px)
            bank.add_frame(px, f"{pose}-{facing}")
            names.append(f"{pose} {facing}")

    a = SIMON_PALETTE
    assert rom.fixed(a) == 0x3F and rom.fixed(a + 1) == 0x10, "Simon palette not found"
    pal0 = [rom.fixed(a + 2 + i) for i in range(4)]
    pal1 = [rom.fixed(a + 6 + i) for i in range(4)]
    slots = {SIMON_SLOT_FOR_VALUE[v]: to_msx_rgb(nes_rgb[pal0[v]]) for v in (1, 2, 3)}
    slots[WHIP_SLOT] = to_msx_rgb(nes_rgb[pal1[2]])

    b, addr = JUMP_TABLE
    jump = bytes(rom.rd(b, addr + i) for i in range(JUMP_LEN))
    if sum(v - 256 if v >= 128 else v for v in jump) >= 0:
        raise SystemExit("jump table not found where expected")
    return bank, names, slots, jump
