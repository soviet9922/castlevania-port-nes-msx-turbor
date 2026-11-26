#!/usr/bin/env python3
"""Convert Castlevania (NES) areas from YOUR ROM into the engine format.

  convert_stage.py ROM OUT_DIR [--nes-palette FILE.pal]

Writes the common data (Simon) to OUT_DIR, each area to OUT_DIR/area_<n>/,
and OUT_DIR/areas.asm with one ROM bank per area. OUT_DIR is normally
build/gen/converted, which is git-ignored: nothing converted is committed.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cv_rom import (BG_PATTERN_TABLE, CastlevaniaROM, load_nes_palette,  # noqa: E402
                    tile_pixels)
import areas_asm  # noqa: E402
import convert_objects  # noqa: E402
import convert_simon  # noqa: E402
import msx_area  # noqa: E402
import msx_sprites  # noqa: E402
from gen_placeholder_assets import PALETTE as PLACEHOLDER_PALETTE  # noqa: E402
from gen_placeholder_assets import write_png  # noqa: E402

# Palette slots that keep a fixed meaning in every area:
#   0 transparent/backdrop, 1 black, 2/4/6 player sprite (OR trick), 14 whip,
#   15 white
FIXED_SLOTS = {0: None, 1: 0x0F, 2: None, 4: None, 6: None, 15: 0x30}
FREE_SLOTS = [3, 5, 7, 8, 9, 10, 11, 12, 13]     # 14 = whip (convert_simon.py)

# The NES decides collision per tile: tiles $60-$6B are solid ($F9DB).
SOLID_TILES = range(0x60, 0x6C)

# Stage maps in bank 4: world column 0 is the stage's header word + 24 bytes
# (6 bytes per 32-px column; the 4 columns before it are pre-drawn off-screen).
# Each block has its own 4x4 tile-block table (word per stage at $FA01) and
# graphics (cv_rom.BLOCK_CHR_SETS) and background palette.
MAP_BANK, BLOCKS = 4, 0x830A
BLOCK_TABLES = {1: 0x830A, 2: 0x8B25, 3: 0x9156, 4: 0x975B, 5: 0x9ED1, 6: 0xA537, 7: 0xA9F4}
BLOCK_PALETTES = {1: "1-courtyard", 2: "2-castle", 3: "3-castle", 4: "4-castle",
                  5: "5-castle", 6: "6-castle", 7: "7-dracula"}
# NES $2A, $2D, $30 (table at $FB56 by stage); stage 10 has its own ($39),
# 11-12 play block 2's ($2D): an area's "music" overrides
BLOCK_MUSIC = {1: "STAGE", 2: "STAGE2", 3: "STAGE3", 4: "STAGE2"}

# Block 2 runs right to left: its doors are at the left end of a section, and
# the 8 map columns before a section's world column 0 are the last 8 columns of
# the next stage's first section (the stage that the door leads to). Its areas
# include those columns, so every x in them is the NES x + BLOCK2_X_OFF.
BLOCK2_X_OFF = 256

# Areas in ROM bank order. Map ranges are [start, end) addresses in bank 4.
AREAS = [
    {
        "name": "1-courtyard",
        "map": (0x800A, 0x809A),        # courtyard + castle gate (768 px)
        "palette": "1-courtyard",
        "stage": 0, "section": 0,       # candle placement ($28, $46)
        "start_x": 40,                  # NES: Simon at world x 48 (centre)
        "exit_x": 688,                  # walking into the gate ...
        "next_area": 1,                 # ... enters the hall
        "exit_kind": 1,                 # (Simon walks into the gate first,
        "door_col": 88,                 # and goes behind its right pillar here)
    },
    {
        "name": "1-hall",
        "map": (0x809A, 0x81EA),        # entrance hall (1536 px), plus 8 columns
        "play_px": 1536,                # of stage 2 seen through its door
        "palette": "1-courtyard",       # the hall uses the same palette
        "stage": 1, "section": 0,
        "start_x": 40,
        "exit_x": 1500,                 # NES: the door opens at world x 1516
        "exit_y": 40,                   # (centre), on the upper floor only
        "next_area": 2,
        "max_cam": 1280,                # (the extra columns only show in the
        "exit_kind": 2,                 # door sequence: camera to 1408)
        "door_col": 191, "door_cam": 1408,
    },
    {
        "name": "2-upper",
        "map": (0x81BA, 0x824A),        # stage 2, section 1 (512 px): behind
        "play_px": 512,                 # (+ 8 columns of stage 3 for its door)
        "palette": "1-courtyard",       # the hall's door; same palette
        "stage": 2, "section": 1,
        "start_x": 40,                  # NES: world x 48 (centre), upper floor
        "exit_x": 484,                  # NES: the door at the top right opens at
        "exit_y": 40,                   # world x 492 (centre), on the ledge
        "next_area": 4,
        "max_cam": 256, "exit_kind": 2,
        "door_col": 63, "door_cam": 384,
        "below": 3,                     # two staircases lead down to section 0
    },
    {
        "name": "2-lower",
        "map": (0x82AA, 0x830A),        # stage 2, section 0 (512 px): the
        "palette": "1-courtyard",       # waterway under section 1
        "stage": 2, "section": 0,
        "start_x": 40,                  # (not used: entered by the stairs)
        "exit_x": None,
        "above": 2,
        "respawn": 2,                   # the NES restarts in section 1
    },
    {
        "name": "3-gallery",
        "map": (0x821A, 0x82AA),        # stage 3, section 0 (768 px), behind
        "palette": "1-courtyard",       # stage 2's door
        "stage": 3, "section": 0,
        "start_x": 40,                  # NES: world x 48 (centre), upper floor
        "exit_x": None,
        "next_area": 5,                 # after the boss and the stage clear
    },
    # ---- block 2 (all x: NES x + BLOCK2_X_OFF) ----
    {
        "name": "4-lower",
        "block": 2,
        "map": (0x8825 - 48, 0x8885),   # stage 4, section 0 (512 px; the NES
        "stage": 4, "section": 0,       # camera stays at 256: one screen)
        "x_off": BLOCK2_X_OFF,
        "start_x": 312 + BLOCK2_X_OFF,  # NES $CA0C: world x 320 (centre),
        "start_y": 192 - 64,            # on the floor (y 192)
        "min_cam": 256 + BLOCK2_X_OFF,
        "exit_x": None,
        "above": 6,                     # a staircase leads up to section 1
    },
    {
        "name": "4-upper",
        "block": 2,
        "map": (0x8915 - 48, 0x8975),   # stage 4, section 1 (512 px) after the
        "stage": 4, "section": 1,       # last 8 columns of stage 5's section 0
        "x_off": BLOCK2_X_OFF,
        "start_x": 440 + BLOCK2_X_OFF,  # (not used: entered by the stairs)
        "below": 5,
        "respawn": 5,
        "exit_x": 284, "exit_y": 40,    # the door at the left end, upper floor
        "exit_left": True, "exit_kind": 2,
        "door_col": 33, "door_row": 2, "door_cam": 128,
        "next_area": 7,
    },
    {
        "name": "5-lower",
        "block": 2,
        "map": (0x8885 - 48, 0x8915),   # stage 5, section 0 (768 px)
        "stage": 5, "section": 0,
        "x_off": BLOCK2_X_OFF,
        "start_x": 712 + BLOCK2_X_OFF,  # NES $CA0C: world x 720 (centre), y 96,
        "start_y": 96 - 64,             # facing left
        "start_face": 1,
        "exit_x": None,
        "above": 8,
    },
    {
        "name": "5-upper",
        "block": 2,
        "map": (0x8A95 - 48, 0x8B25),   # stage 5, section 1 (768 px) after the
        "stage": 5, "section": 1,       # last 8 columns of stage 6's section 0
        "x_off": BLOCK2_X_OFF,
        "start_x": 300 + BLOCK2_X_OFF,  # (not used: entered by the stairs)
        "below": 7,
        "respawn": 7,
        "exit_x": 284, "exit_y": 72,    # the door at the left end
        "exit_left": True, "exit_kind": 2,
        "door_col": 33, "door_row": 6, "door_cam": 128,
        "next_area": 9,
    },
    {
        "name": "6-lower",
        "block": 2,
        "map": (0x8A05 - 48, 0x8A95),   # stage 6, section 0 (768 px)
        "stage": 6, "section": 0,
        # three ceiling crushers (recorded): NES x, the lowest row their spikes
        # reach (nametable row), frames into their cycle at the start
        "crushers": [(352, 18, 40), (416, 18, 0), (480, 21, 20)],
        "x_off": BLOCK2_X_OFF,
        "start_x": 712 + BLOCK2_X_OFF,  # NES $CA0C: world x 720 (centre), y 128,
        "start_y": 128 - 64,            # facing left
        "start_face": 1,
        "exit_x": None,
        "above": 10,
    },
    {
        "name": "6-upper",
        "block": 2,
        "map": (0x8975 - 48, 0x8A05),   # stage 6, section 1 (768 px): Medusa's
        "stage": 6, "section": 1,       # room at its left end
        "x_off": BLOCK2_X_OFF,
        "start_x": 600 + BLOCK2_X_OFF,  # (not used: entered by the stairs)
        "below": 9,
        "respawn": 9,
        "exit_x": None,
        "next_area": 11,                # after Medusa and the stage clear
    },
    # ---- block 3 (stages 7-9): NES x as they are ----
    {
        "name": "7-lower",
        "block": 3,
        "map": (0x8DC6, 0x8E56),        # stage 7, section 0 (768 px)
        "stage": 7, "section": 0,
        "start_x": 712,                 # NES $CA0C: x 720 (centre), y 176,
        "start_y": 176 - 64,            # facing left
        "start_face": 1,
        "exit_x": None,
        "above": 12,                    # its staircase at x 159 leads up
    },
    {
        "name": "7-upper",
        "block": 3,
        "map": (0x8E56, 0x8EE6 + 48),   # stage 7, section 1 (768 px), plus 8
        "play_px": 768,                 # columns of stage 8 seen through its door
        "stage": 7, "section": 1,
        "start_x": 80,                  # (not used: entered by the stairs)
        "below": 11,
        "respawn": 11,
        "exit_x": 724, "exit_y": 88,    # the door at the right end
        "exit_kind": 2, "door_col": 94, "door_row": 8,
        "max_cam": 512, "door_cam": 640,
        "next_area": 13,
    },
    {
        "name": "8-lower",
        "block": 3,
        "map": (0x8EE6, 0x8F46 + 48),   # stage 8, section 0: 512 px, then on
        "stage": 8, "section": 0,       # into the next map's first 256 px
        "start_x": 40,                  # NES $CA0C: x 48 (centre), y 144
        "start_y": 144 - 64,
        "exit_x": None,
        "above": 14,
    },
    {
        "name": "8-upper",
        "block": 3,
        "map": (0x8F46, 0x9036 + 48),   # stage 8, section 1 (1280 px; its first
        "play_px": 1280,                # 480 are section 0's), plus 8 columns
        "stage": 8, "section": 1,       # of stage 9 seen through its door
        "start_x": 600,                 # (not used: entered by the stairs)
        "min_cam": 480,
        "below": 13,
        "respawn": 13,
        "exit_x": 1236, "exit_y": 56,   # the door at the right end
        "exit_kind": 2, "door_col": 158, "door_row": 4,
        "max_cam": 1024, "door_cam": 1152,
        "next_area": 15,
    },
    {
        "name": "9-bridge",
        "block": 3,
        "map": (0x9036, 0x9156),        # stage 9 (1536 px): the bridge and the
        "stage": 9, "section": 0,       # tower room of the boss
        "start_x": 40,                  # NES $CA0C: x 48 (centre), y 112
        "start_y": 112 - 64,
        "exit_x": None,
        "next_area": 16,                # after the mummies and the stage clear
    },
    # block 4 (stages 10-12; bank 4 maps, tile blocks $975B, palette $CE61,
    # graphics sets 3 and 6): left to right
    {
        "name": "10-cave",
        "block": 4,
        "map": (0x945B, 0x957B),        # stage 10 (1536 px): the cave and its
        "stage": 10, "section": 0,      # waterway
        "start_x": 80 - 8,              # NES $CA0C: x 80, y 144
        "start_y": 144 - 64,
        "music": "STAGE4",              # (NES $39)
        # the NES's exit point ($FC19): screen x $D0, y $40 at the end of the
        # camera, halfway up the last staircase: stage 11 starts
        "exit_x": 1280 + 0xD0 - 8, "exit_y": 0x40 - 64, "exit_kind": 3,
        "next_area": 17,
    },
    {
        "name": "11-ruins",
        "block": 4,
        "map": (0x957B, 0x969B),        # stage 11 (1536 px): outside
        "stage": 11, "section": 0,
        "start_x": 48 - 8,              # NES: x 48, y 176
        "start_y": 176 - 64,
        "exit_x": 1280 + 0xF2 - 8,      # NES $FC19: the right edge, y $B0
        "exit_y": 0xB0 - 64,
        "next_area": 18,
    },
    {
        "name": "12-corridor",
        "block": 4,
        "map": (0x969B, 0x975B),        # stage 12 (1024 px): the corridor, and
        "stage": 12, "section": 0,      # Frankenstein's room at its end
        "start_x": 48 - 8,              # NES: x 48, y 176
        "start_y": 176 - 64,
        "exit_x": None,
    },
]

# Sections of a stage are joined by staircases: an end without a partner in
# its own section continues in the next one. On the NES, Simon keeps his x
# and his y moves by SECTION_DY (measured: y 207 in section 1 = y 49 in
# section 0). Must match SECTION_DY in src/config.inc.
SECTION_DY = 158
LINK_LEN = 64                   # least length of the off-screen part of such a staircase
SECTION_DOWN_Y, SECTION_UP_Y = 144, -15     # must match src/config.inc


# Stairs (bank 6, $9CBD): word at $FBF3 + 2*stage -> list of 2-byte endpoints,
# 0-terminated. Byte 0: y (high nibble), section (bit 2), type (bits 0-1:
# bit 1 = top end, bit 0 = staircase rises to the left). Byte 1: x / 8 in
# bits 7-3, screen page in bits 0-2. The pointers point into bank 6.
STAIR_TABLE = 0xFBF3
STAIR_X_ADJUST = 0x9D47         # bank 6: per-type x adjustment (signed)


def stairs(rom, stage, section):
    """-> list of (foot x, foot y, top x, top y, dir) in engine coordinates
    (Simon's box left/top); dir +1 = rises to the right, -1 = to the left."""
    p = rom.fixed(STAIR_TABLE + 2 * stage) | rom.fixed(STAIR_TABLE + 2 * stage + 1) << 8
    adj = [rom.rd(6, STAIR_X_ADJUST + i) for i in range(4)]
    ends = []
    while rom.rd(6, p) != 0:
        b0, b1 = rom.rd(6, p), rom.rd(6, p + 1)
        p += 2
        if (b0 >> 2) & 1 != section:
            continue
        t = b0 & 3
        a = adj[t] - 256 if adj[t] >= 128 else adj[t]
        ends.append((t, (b1 & 0xF8) + ((b1 & 7) << 8) + a, b0 & 0xF0))
    # Ends come in (foot, top) pairs. An end without a partner in this section
    # leads to another section (a staircase down to the section below, say);
    # those are left out until sections are joined.
    out = []
    i = 0
    while i < len(ends):
        pair = _staircase(ends[i], ends[i + 1]) if i + 1 < len(ends) else None
        if pair is None:
            out.append(_link_staircase(ends[i]))
            i += 1
            continue
        out.append(pair)
        i += 2
    return out


def _link_staircase(end):
    """An end whose partner is in another section: a staircase that runs
    LINK_LEN px past the playfield edge (the engine switches sections when
    Simon gets there, before the made-up end)."""
    t, x, y = end
    d = -1 if t & 1 else 1
    ex, ey = x + 2 - 8, y - 64
    if t & 2:                                   # a top: continues down past the
        n = max(LINK_LEN, SECTION_DOWN_Y + 16 - ey)     # section switch line
        return (ex - d * n, ey + n, ex, ey, d)
    n = max(LINK_LEN, ey - SECTION_UP_Y + 16)   # a foot: continues up past it
    return (ex, ey, ex + d * n, ey - n, d)


def _staircase(a, b):
    """Two stair ends -> (foot x, foot y, top x, top y, dir), or None if they
    aren't the foot and top of one 45 degree staircase."""
    (ta, xa, ya), (tb, xb, yb) = a, b
    if (ta & 2) == (tb & 2) or (ta & 1) != (tb & 1):
        return None
    foot, top = ((xa, ya, ta), (xb, yb, tb)) if not ta & 2 else ((xb, yb, tb), (xa, ya, ta))
    d = -1 if foot[2] & 1 else 1
    # Simon lines up 2 px right of the endpoint (measured); exact 45 degrees
    fx, fy, ty = foot[0] + 2 - 8, foot[1] - 64, top[1] - 64
    tx = fx + d * (fy - ty)
    if fy <= ty or abs(tx - (top[0] + 2 - 8)) > 6:
        return None
    return (fx, fy, tx, ty, d)


def nes_to_msx_rgb(c):
    return tuple(min(7, (v * 7 + 127) // 255) for v in c)


def nes_width(area):
    """The area's own width in px on the NES (without columns added for doors)."""
    return area.get("play_px", (area["map"][1] - area["map"][0]) // 6 * 32 - area.get("x_off", 0))


def convert_area(rom, area, index, out_root, nes_rgb, simon_slots, carried=(), preview=True):
    import cv_rom
    out_dir = os.path.join(out_root, f"area_{index}")
    os.makedirs(out_dir, exist_ok=True)
    block = area.get("block", 1)
    rom.chr_sets = cv_rom.BLOCK_CHR_SETS[block]
    chr_ram = rom.chr_ram()
    pal = rom.palette(area.get("palette", BLOCK_PALETTES[block]))
    x_off = area.get("x_off", 0)

    key = f"area{index}"
    cv_rom.STAGE_LAYOUTS[key] = (MAP_BANK, area["map"][0], area["map"][1], BLOCK_TABLES[block])
    tiles, pals = rom.stage_nametable(key)
    width = len(tiles[0]) * 8

    # --- NES colours -> MSX palette slots ---
    used = set()
    for r in range(2, 24):
        for c in range(len(tiles[r])):
            used.update(pal[pals[r][c] * 4 + i] for i in range(1, 4))
    used.add(pal[0])
    msx_pal = list(PLACEHOLDER_PALETTE)
    nes_to_slot = {}
    for slot, nes in FIXED_SLOTS.items():
        if nes is not None:
            nes_to_slot[nes] = slot
            msx_pal[slot] = nes_to_msx_rgb(nes_rgb[nes])
    for slot, rgb in simon_slots.items():
        msx_pal[slot] = rgb
    free = list(FREE_SLOTS)
    for nes in sorted(used):
        if nes in nes_to_slot:
            continue
        rgb = nes_to_msx_rgb(nes_rgb[nes])
        same = [s for s, v in enumerate(msx_pal) if v == rgb and s not in (0, 2, 4, 6, 14)]
        if same:
            nes_to_slot[nes] = same[0]
            continue
        if not free:
            raise SystemExit(f"{area['name']}: more than 9 background colours")
        s = free.pop(0)
        msx_pal[s] = rgb
        nes_to_slot[nes] = s
    msx_pal[0] = msx_pal[1]

    # --- indexed image of the playfield (NES nametable rows 6..27) ---
    pixels = []
    for r in range(2, 24):
        rows = [[] for _ in range(8)]
        for c in range(len(tiles[r])):
            px = tile_pixels(chr_ram, BG_PATTERN_TABLE, tiles[r][c])
            p = pals[r][c]
            for y in range(8):
                rows[y] += [nes_to_slot[pal[0] if v == 0 else pal[p * 4 + v]] for v in px[y]]
        pixels += rows

    # --- collision per tile, as on the NES ---
    solid = [[1 if tiles[r][c] in SOLID_TILES else 0 for c in range(len(tiles[r]))]
             for r in range(2, 24)]

    # start: standing on the first solid tile below the top, at start_x
    sx = area["start_x"]
    col = (sx + 8) // 8
    if "start_y" in area:
        sy = area["start_y"]
    else:
        row = next((r for r in range(4, msx_area.PF_ROWS) if solid[r][col]), 4)
        sy = row * 8 - 32

    # --- candles and object sprites (colours: exact slot, else nearest) ---
    def slot_for_nes(nes):
        if nes == 0x0F:
            return 1
        rgb = nes_to_msx_rgb(nes_rgb[nes])
        return min(range(1, 16), key=lambda s: (sum((a - b) ** 2 for a, b in
                                                    zip(msx_pal[s], rgb)), s))
    door_vcol = 0
    exit_left = area.get("exit_left", False)
    if area.get("exit_kind") == 2:
        door_vcol = len(pixels[0]) // 8
        add_door_columns(rom, pixels, solid, area["door_col"], slot_for_nes, nes_to_slot[pal[0]],
                         left=exit_left, door_row=area.get("door_row", DOOR_ROW))
    crush_vcol, crushers = 0, []
    if area.get("crushers"):
        crush_vcol = len(pixels[0]) // 8
        crushers = add_crusher_columns(pixels, solid, area["crushers"][0][0] + x_off)
        crushers = [(nx + x_off, bottom, phase) for nx, bottom, phase in area["crushers"]]
    play_px = nes_width(area)               # objects only from the area itself
    cl = [(x + x_off, y, it, k) for x, y, it, k in
          convert_objects.candles(rom, area["stage"], area["section"], play_px)]
    en = [(x + x_off, y, t) for x, y, t in
          convert_objects.enemy_spawners(rom, area["stage"], area["section"], play_px)]
    objs = convert_objects.object_sprites(
        rom, slot_for_nes, convert_objects.needed_frames(cl, en, carried), carried)
    write_object_sprites(out_dir, index, objs)
    n_obj_patterns = objs.n_main
    convert_objects.write_candles(os.path.join(out_dir, "candles.bin"), cl)
    convert_objects.write_enemies(os.path.join(out_dir, "enemies.bin"), en)

    st = [(fx + x_off, fy, tx + x_off, ty, d)
          for fx, fy, tx, ty, d in stairs(rom, area["stage"], area["section"])]
    data = bytearray([len(st)])
    for fx, fy, tx, ty, d in st:
        data += bytes([fx & 0xFF, fx >> 8, fy & 0xFF, tx & 0xFF, tx >> 8, ty & 0xFF, d & 0xFF])
    with open(os.path.join(out_dir, "stairs.bin"), "wb") as f:
        f.write(data)

    write_crushers(out_dir, crushers)
    params = msx_area.write_area(out_dir, pixels, msx_pal, solid, sx, sy, area["name"])
    nxt = AREAS[area.get("next_area", 0)]
    if area.get("exit_kind") == 2 and exit_left:
        # the next stage's last 8 columns are this area's first 8: its x is
        # this area's x + (its width - 256); it starts at its camera maximum
        nxt_w = (nxt["map"][1] - nxt["map"][0]) // 6 * 32
        walk_end, cam_end = nxt["start_x"] - (nxt_w - 256), 0
    elif area.get("exit_kind") == 2:
        walk_end, cam_end = area.get("play_px", width) + nxt["start_x"], area.get("play_px", width)
    else:
        walk_end, cam_end = 0, area.get("play_px", width)
    params.update(dir=f"area_{index}", obj_patterns=n_obj_patterns, subs=sorted(objs.subs),
                  sub_slot=objs.sub_slot, swaps=len(objs.swaps), swap_slot=objs.n_main,
                  exit_x=area.get("exit_x"), exit_y=area.get("exit_y", 0xFF),
                  below=area.get("below", 0xFF), above=area.get("above", 0xFF),
                  respawn=area.get("respawn", index),
                  stage_no=area["stage"] if area["stage"] >= 1 else 1,
                  exit_kind=area.get("exit_kind", 0), door_col=area.get("door_col", 0),
                  door_cam=area.get("door_cam", 0), door_vcol=door_vcol,
                  walk_end=walk_end, cam_end=cam_end,
                  min_cam=area.get("min_cam", x_off), music=area.get("music", BLOCK_MUSIC[block]),
                  start_face=area.get("start_face", 0), exit_left=int(exit_left),
                  door_row=area.get("door_row", DOOR_ROW), crush_vcol=crush_vcol,
                  max_cam=area.get("max_cam", width - 256),     # (not the door's columns)
                  next_area=area.get("next_area", 0))

    if preview:
        pgt = [open(os.path.join(out_dir, f"bg_pgt_b{b}.bin"), "rb").read() for b in range(3)]
        ct = [open(os.path.join(out_dir, f"bg_ct_b{b}.bin"), "rb").read() for b in range(3)]
        tmap = open(os.path.join(out_dir, "level_tiles.bin"), "rb").read()
        rgb8 = [tuple(v * 255 // 7 for v in c) for c in msx_pal]
        img = [[(0, 0, 0)] * width for _ in range(len(pixels))]
        for tc in range(width // 8):
            for tr in range(msx_area.PF_ROWS):
                b = msx_area.band_of(tr)
                t = tmap[tc * msx_area.PF_ROWS + tr] - msx_area.BG_TILE_BASE
                for y in range(8):
                    bits, colr = pgt[b][t * 8 + y], ct[b][t * 8 + y]
                    for x in range(8):
                        c = colr >> 4 if bits & (0x80 >> x) else colr & 15
                        img[tr * 8 + y][tc * 8 + x] = rgb8[c]
                    if solid[tr][tc]:
                        img[tr * 8][tc * 8] = (255, 255, 0)
        write_png(os.path.join(out_dir, "level_msx_preview.png"), width, len(img), img)

    kinds = ["brazier", "candle", "panther", "?", "?", "boss", "knight", "hbat", "medusa",
             "flea", "skeleton", "pillar", "raven", "ghost", "mummy"]
    print(f"area {index} {area['name']}: {width} px, tiles per band {params['tiles']}, "
          f"{params['lossy_rows']}/{params['total_rows']} tile rows reduced, "
          f"start ({sx},{sy}), {len(st)} stairs, {len(en)} enemy spawners {en}, {len(cl)} candles "
          f"({', '.join(f'{kinds[k]}@{x + 8}' for x, _, _, k in cl[:6])}{', ...' if len(cl) > 6 else ''})")
    return params


# HUD sub-weapon icons (recorded: the NES HUD's sub-weapon box), in the order of
# HUD_ICON_NAMES in gen_placeholder_assets.py: (tile, dx, palette, flip)
HUD_ICONS = [
    [(0xBD, 0, 2, 3), (0xBB, 8, 2, 3)],         # dagger
    [(0xB7, 0, 1, 0), (0xB9, 8, 1, 0)],         # axe
    [(0xA1, 0, 2, 0), (0xA3, 8, 2, 0)],         # holy water
    [(0x89, 0, 2, 0), (0x8B, 8, 2, 0)],         # stopwatch
]
HUD_ICON_FIRST = 4                  # HUD tile index of the first icon tile


# The opened door (recorded: sprites over the door's wall on the NES), relative
# to the door's tile column and DOOR_ROW: (tile, dx, dy), palette 3, mirrored.
# Half open: the door column goes dark and the door shows on the 2 columns to its
# right; open: 3 columns wide over the doorway.
DOOR_HALF = [(0x77, 8, 0), (0x7B, 8, 16), (0x7B, 8, 32),
             (0x75, 16, 0), (0x79, 16, 16), (0x79, 16, 32)]
DOOR_OPEN = [(0x87, 0, 0), (0x7B, 0, 16), (0x7B, 0, 32),
             (0x87, 8, 0), (0x7B, 8, 16), (0x7B, 8, 32),
             (0x85, 16, 0), (0x7B, 16, 16), (0x7B, 16, 32)]
DOOR_ROW = 2                        # playfield row (NES nametable row 8); must match src/config.inc
# After the door shuts Simon walks on into the next stage's first columns (shown
# at the end of the area's map) to the next stage's start x, and the screen
# scrolls on to where the next stage's map begins: then the next stage loads
# with no jump (and Simon is still on its ledge)
DOOR_ROWS = 6


def add_door_columns(rom, pixels, solid, door_col, slot_for_nes, backdrop, left=False,
                     door_row=None):
    """Append 6 tile columns to the level image (never on screen): the door's 3
    columns half open, then open, drawn over the wall. The door sequence copies
    them into the name table (src/area.asm, door_vram). A door at the left end
    of an area opens to the left: the picture is mirrored, and its 3 columns are
    the door's column and the 2 to its left."""
    from cv_rom import tile_pixels
    DOOR_ROW = door_row if door_row is not None else globals()["DOOR_ROW"]
    chr_ram = rom.chr_ram()
    pal = [rom.fixed(convert_objects.SPRITE_PALETTES + 3 * 4 + v) for v in range(4)]
    x0 = (door_col - 2) * 8 if left else door_col * 8
    for sprites, dark_first in ((DOOR_HALF, True), (DOOR_OPEN, True)):
        block = [row[x0:x0 + 24] for row in pixels]
        if left:
            sprites = [(tile, 16 - dx, dy, True) for tile, dx, dy in sprites]
        else:
            sprites = [(tile, dx, dy, False) for tile, dx, dy in sprites]
        if dark_first:
            dark = slice(16, 24) if left else slice(0, 8)
            for y in range(DOOR_ROW * 8, (DOOR_ROW + DOOR_ROWS) * 8):
                block[y][dark] = [backdrop] * 8
        for tile, dx, dy, unmirror in sprites:
            table, top = (tile & 1) * 0x1000, tile & 0xFE
            for half in (0, 1):
                px = tile_pixels(chr_ram, table, top + half)
                for y in range(8):
                    for x in range(8):
                        v = px[y][x if unmirror else 7 - x]     # mirrored (NES attribute $43)
                        if v:
                            block[DOOR_ROW * 8 + dy + half * 8 + y][dx + x] = slot_for_nes(pal[v])
        for y, row in enumerate(pixels):
            row += block[y]
    for row in solid:
        row += [0] * 6


# Stage 6's ceiling crushers (recorded: background tiles the NES rewrites). In
# the map one rests with its chain at nametable row 14 and its spikes at row 15.
# Each cycle: the spikes drop a row every 4 frames to their lowest row, stay 4
# frames, and go back up a row every 16 frames to row 14.
CRUSH_TOP = 14                      # highest row of the spikes (nametable row)
CRUSH_LOW = 21                      # lowest row any of them reaches
CRUSH_FIRST_ROW = CRUSH_TOP - 6     # first playfield row the engine rewrites
CRUSH_ROWS = CRUSH_LOW - CRUSH_TOP + 1


def add_crusher_columns(pixels, solid, x):
    """Append 4 tile columns for each height of the spikes (rows CRUSH_TOP to
    CRUSH_LOW): chain above the spikes, nothing below, cut from the crusher at
    world x as the map draws it. The engine copies them into the name table."""
    def row(nt_row, dx):
        y0 = (nt_row - 6) * 8
        return [r[x + dx:x + dx + 8] for r in pixels[y0:y0 + 8]]
    for spikes in range(CRUSH_TOP, CRUSH_LOW + 1):
        for dx in range(0, 32, 8):
            col = [r[x + dx:x + dx + 8] for r in pixels]        # the map's own column
            for nt_row in range(CRUSH_TOP, CRUSH_LOW + 1):
                src = 14 if nt_row < spikes else 15 if nt_row == spikes else 16
                y0 = (nt_row - 6) * 8
                col[y0:y0 + 8] = row(src, dx)
            for y, r in enumerate(pixels):
                r += col[y]
            for r in solid:
                r.append(0)


def crusher_segments(bottom):
    """(row, frames) steps of one cycle, starting at the top"""
    segs = [(r, 4) for r in range(CRUSH_TOP + 1, bottom + 1)]
    segs[-1] = (bottom, 8)              # (reached, then 4 frames still)
    segs += [(r, 16) for r in range(bottom - 1, CRUSH_TOP - 1, -1)]
    return segs


def write_crushers(out_dir, crushers):
    """crushers.bin: count, then per crusher x (2 bytes), a phase (frames) and its
    cycle: steps, then (spike row - CRUSH_TOP, frames) per step"""
    data = bytearray([len(crushers)])
    for x, bottom, phase in crushers:
        segs = crusher_segments(bottom)
        data += bytes([x & 0xFF, x >> 8, phase, len(segs)])
        for r, n in segs:
            data += bytes([r - CRUSH_TOP, n])
    with open(os.path.join(out_dir, "crushers.bin"), "wb") as f:
        f.write(data)


def write_object_sprites(out_dir, index, objs):
    """a<n>_obj_spt/sct/frames.bin, the frame table include, and a<n>_sub<k>_spt.bin
    for each sub-weapon's window patterns (see convert_objects.ObjectSprites)"""
    p = f"a{index}_obj"
    for suffix, data in (("spt", objs.main_spt), ("sct", objs.sct), ("frames", objs.frames)):
        with open(os.path.join(out_dir, f"{p}_{suffix}.bin"), "wb") as f:
            f.write(data)
    for n, data in objs.subs.items():
        with open(os.path.join(out_dir, f"a{index}_sub{n}_spt.bin"), "wb") as f:
            f.write(data)
    for n, data in enumerate(objs.swaps):
        with open(os.path.join(out_dir, f"a{index}_swap{n}_spt.bin"), "wb") as f:
            f.write(data)
    lines = ["; generated sprite frames - do not edit",
             f"{p.upper()}_FRAME_COUNT equ {len(objs.offsets)}",
             f"{p.upper()}_PATTERNS    equ {objs.n_main}",
             f"{p}_frame_table:"]
    for name, off in zip(convert_objects.OBJ_FRAMES, objs.offsets):
        lines.append(f"        dw {p}_frames+{off:<5}  ; {name}")
    with open(os.path.join(out_dir, f"{p}_frames.inc"), "w") as f:
        f.write("\n".join(lines) + "\n")


def write_hud_icons(rom, out_dir):
    """Replace the placeholder icon tiles in hud_pgt.bin / hud_ct.bin with the
    ROM's sub-weapon icons, white on black (the HUD has 2 colours per row)."""
    chr_ram = rom.chr_ram()
    pgt = bytearray(open(os.path.join(out_dir, "hud_pgt.bin"), "rb").read())
    ct = bytearray(open(os.path.join(out_dir, "hud_ct.bin"), "rb").read())
    for i, sprites in enumerate(HUD_ICONS):
        lit = set()
        for tile, dx, _pal, flip in sprites:
            table, top = (tile & 1) * 0x1000, tile & 0xFE
            for half in (0, 1):
                px = cv_rom_tile_pixels(chr_ram, table, top + half)
                for y in range(8):
                    for x in range(8):
                        if px[y][7 - x if flip & 1 else x]:
                            yy = 15 - (half * 8 + y) if flip & 2 else half * 8 + y
                            lit.add((dx + x, yy))
        for q, (tx, ty) in enumerate(((0, 0), (8, 0), (0, 8), (8, 8))):
            t = HUD_ICON_FIRST + i * 4 + q
            for y in range(8):
                pgt[t * 8 + y] = sum(0x80 >> x for x in range(8) if (tx + x, ty + y) in lit)
                ct[t * 8 + y] = 0xF1
    with open(os.path.join(out_dir, "hud_pgt.bin"), "wb") as f:
        f.write(pgt)
    with open(os.path.join(out_dir, "hud_ct.bin"), "wb") as f:
        f.write(ct)


def cv_rom_tile_pixels(chr_ram, table, n):
    from cv_rom import tile_pixels
    return tile_pixels(chr_ram, table, n)


def convert(rom_path, out_dir, nes_pal_path=None):
    import cv_rom
    rom = CastlevaniaROM(rom_path)
    nes_rgb = load_nes_palette(nes_pal_path)
    os.makedirs(out_dir, exist_ok=True)

    # Simon (common to all areas): sprites, colours for slots 2/4/6/14, jump arc
    bank, frame_names, simon_slots, jump, kb = convert_simon.convert(rom, nes_rgb, nes_to_msx_rgb)
    msx_sprites.write_bank(out_dir, bank, frame_names, extra_dy=1)   # NES: 1 line lower
    with open(os.path.join(out_dir, "player_jump.bin"), "wb") as f:
        f.write(jump)
    with open(os.path.join(out_dir, "player_kb.bin"), "wb") as f:
        f.write(kb)

    # sub-weapons Simon can carry into each area: those found in it or before
    # it (areas are in play order)
    areas, carried = [], set()
    for i, a in enumerate(AREAS):
        width = nes_width(a)
        rom.chr_sets = cv_rom.BLOCK_CHR_SETS[a.get("block", 1)]
        items = {it for _, _, it, _ in convert_objects.candles(rom, a["stage"], a["section"], width)}
        carried |= items & set(convert_objects.SUB_FRAMES)
        areas.append(convert_area(rom, a, i, out_dir, nes_rgb, simon_slots, carried))
    rom.chr_sets = cv_rom.BLOCK_CHR_SETS[1]
    write_hud_icons(rom, out_dir)
    areas_asm.write(out_dir, areas)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rom")
    ap.add_argument("out_dir")
    ap.add_argument("--nes-palette")
    args = ap.parse_args()
    convert(args.rom, args.out_dir, args.nes_palette)


if __name__ == "__main__":
    main()
