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
MAP_BANK, BLOCKS = 4, 0x830A

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
    },
    {
        "name": "1-hall",
        "map": (0x809A, 0x81BA),        # entrance hall (1536 px)
        "palette": "1-courtyard",       # the hall uses the same palette
        "stage": 1, "section": 0,
        "start_x": 40,
        "exit_x": None,
    },
]


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
    out = []
    for (ta, xa, ya), (tb, xb, yb) in zip(ends[0::2], ends[1::2]):
        foot, top = ((xa, ya, ta), (xb, yb, tb)) if not ta & 2 else ((xb, yb, tb), (xa, ya, ta))
        d = -1 if foot[2] & 1 else 1
        # Simon lines up 2 px right of the endpoint (measured); exact 45 degrees
        fx, fy, ty = foot[0] + 2 - 8, foot[1] - 64, top[1] - 64
        tx = fx + d * (fy - ty)
        if abs(tx - (top[0] + 2 - 8)) > 6:
            raise SystemExit(f"stair endpoints do not form a 45 degree staircase: {foot} {top}")
        out.append((fx, fy, tx, ty, d))
    return out


def nes_to_msx_rgb(c):
    return tuple(min(7, (v * 7 + 127) // 255) for v in c)


def convert_area(rom, area, index, out_root, nes_rgb, simon_slots, preview=True):
    import cv_rom
    out_dir = os.path.join(out_root, f"area_{index}")
    os.makedirs(out_dir, exist_ok=True)
    chr_ram = rom.chr_ram()
    pal = rom.palette(area["palette"])

    key = f"area{index}"
    cv_rom.STAGE_LAYOUTS[key] = (MAP_BANK, area["map"][0], area["map"][1], BLOCKS)
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
    row = next(r for r in range(4, msx_area.PF_ROWS) if solid[r][col])
    sy = row * 8 - 32

    # --- candles and object sprites (colours: exact slot, else nearest) ---
    def slot_for_nes(nes):
        if nes == 0x0F:
            return 1
        rgb = nes_to_msx_rgb(nes_rgb[nes])
        return min(range(1, 16), key=lambda s: (sum((a - b) ** 2 for a, b in
                                                    zip(msx_pal[s], rgb)), s))
    obj_bank, obj_names = convert_objects.sprite_frames(rom, slot_for_nes)
    n_obj_patterns, _ = msx_sprites.write_bank(out_dir, obj_bank, obj_names,
                                               prefix=f"a{index}_obj")
    cl = convert_objects.candles(rom, area["stage"], area["section"], width)
    convert_objects.write_candles(os.path.join(out_dir, "candles.bin"), cl)
    en = convert_objects.enemy_spawners(rom, area["stage"], area["section"], width)
    convert_objects.write_enemies(os.path.join(out_dir, "enemies.bin"), en)

    st = stairs(rom, area["stage"], area["section"])
    data = bytearray([len(st)])
    for fx, fy, tx, ty, d in st:
        data += bytes([fx & 0xFF, fx >> 8, fy, tx & 0xFF, tx >> 8, ty, d & 0xFF])
    with open(os.path.join(out_dir, "stairs.bin"), "wb") as f:
        f.write(data)

    params = msx_area.write_area(out_dir, pixels, msx_pal, solid, sx, sy, area["name"])
    params.update(dir=f"area_{index}", obj_patterns=n_obj_patterns,
                  exit_x=area.get("exit_x"), next_area=area.get("next_area", 0))

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

    kinds = ["brazier", "candle", "panther"]
    print(f"area {index} {area['name']}: {width} px, tiles per band {params['tiles']}, "
          f"{params['lossy_rows']}/{params['total_rows']} tile rows reduced, "
          f"start ({sx},{sy}), {len(st)} stairs, {len(en)} zombie spawners {en}, {len(cl)} candles "
          f"({', '.join(f'{kinds[k]}@{x + 8}' for x, _, _, k in cl[:6])}{', ...' if len(cl) > 6 else ''})")
    return params


def convert(rom_path, out_dir, nes_pal_path=None):
    rom = CastlevaniaROM(rom_path)
    nes_rgb = load_nes_palette(nes_pal_path)
    os.makedirs(out_dir, exist_ok=True)

    # Simon (common to all areas): sprites, colours for slots 2/4/6/14, jump arc
    bank, frame_names, simon_slots, jump, kb = convert_simon.convert(rom, nes_rgb, nes_to_msx_rgb)
    msx_sprites.write_bank(out_dir, bank, frame_names)
    with open(os.path.join(out_dir, "player_jump.bin"), "wb") as f:
        f.write(jump)
    with open(os.path.join(out_dir, "player_kb.bin"), "wb") as f:
        f.write(kb)

    areas = [convert_area(rom, a, i, out_dir, nes_rgb, simon_slots) for i, a in enumerate(AREAS)]
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
