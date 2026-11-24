#!/usr/bin/env python3
"""Convert a Castlevania (NES) stage area from YOUR ROM into the engine format.

  convert_stage.py ROM OUT_DIR [--area 1-courtyard] [--nes-palette FILE.pal]

Output goes to OUT_DIR (normally build/gen, which is git-ignored) and
replaces the placeholder level. Nothing converted is ever committed.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cv_rom import (BG_PATTERN_TABLE, CastlevaniaROM, load_nes_palette,  # noqa: E402
                    tile_pixels)
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

AREAS = {
    # name: layout sections [(layout key, first column, last column+1)],
    #       palette key, NES tiles that are solid ground, start position
    "1-courtyard": {
        "sections": [("1-courtyard", 0, None), ("1-hall", 0, 2)],  # + castle gate
        "palette": "1-courtyard",
        "solid_tiles": {0x60, 0x68},
        "stage": 0, "section": 0,       # candle placement ($28, $46)
        "start": (32, 9 * 16 - 32),
    },
}

# Layout sections in bank 4 (see docs/NES_NOTES.md)
SECTIONS = {
    "1-courtyard": (4, 0x800A, 0x8082, 0x830A),
    "1-hall": (4, 0x8082, 0x81A2, 0x830A),
}


def nes_to_msx_rgb(c):
    return tuple(min(7, (v * 7 + 127) // 255) for v in c)


def convert(rom_path, out_dir, area_name, nes_pal_path=None, preview=True):
    import cv_rom
    rom = CastlevaniaROM(rom_path)
    area = AREAS[area_name]
    nes_rgb = load_nes_palette(nes_pal_path)
    chr_ram = rom.chr_ram()
    pal = rom.palette(area["palette"])

    # --- assemble NES tiles + palette indices for the whole area ---
    tiles = [[] for _ in range(24)]
    pals = [[] for _ in range(24)]
    for key, c0, c1 in area["sections"]:
        cv_rom.STAGE_LAYOUTS[key] = SECTIONS[key]
        t, p = rom.stage_nametable(key)
        a, b = c0 * 4, (c1 * 4 if c1 is not None else len(t[0]))
        for r in range(24):
            tiles[r] += t[r][a:b]
            pals[r] += p[r][a:b]
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
            raise SystemExit(f"{area_name}: more than 11 background colours")
        s = free.pop(0)
        msx_pal[s] = rgb
        nes_to_slot[nes] = s
    msx_pal[0] = msx_pal[1]

    # --- Simon: sprite patterns, his colours in slots 2/4/6, jump arc ---
    bank, frame_names, simon_slots, jump = convert_simon.convert(rom, nes_rgb, nes_to_msx_rgb)
    for slot, rgb in simon_slots.items():
        msx_pal[slot] = rgb
    msx_sprites.write_bank(out_dir, bank, frame_names)
    with open(os.path.join(out_dir, "player_jump.bin"), "wb") as f:
        f.write(jump)

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

    # --- collision: 16x16 cells containing solid ground tiles ---
    solid = []
    for mr in range(msx_area.MT_ROWS):
        row = []
        for mc in range(width // 16):
            cell = {tiles[2 + mr * 2 + y][mc * 2 + x] for y in (0, 1) for x in (0, 1)}
            row.append(1 if cell & area["solid_tiles"] else 0)
        solid.append(row)

    # --- candles and object sprites (colours: exact slot, else nearest) ---
    def slot_for_nes(nes):
        if nes == 0x0F:
            return 1
        rgb = nes_to_msx_rgb(nes_rgb[nes])
        return min(range(1, 16), key=lambda s: (sum((a - b) ** 2 for a, b in
                                                    zip(msx_pal[s], rgb)), s))
    obj_bank, obj_names = convert_objects.sprite_frames(rom, slot_for_nes)
    msx_sprites.write_bank(out_dir, obj_bank, obj_names, prefix="obj")
    cl = convert_objects.candles(rom, area["stage"], area["section"], width)
    convert_objects.write_candles(os.path.join(out_dir, "candles.bin"), cl)

    sx, sy = area["start"]
    stats = msx_area.write_area(out_dir, pixels, msx_pal, solid, sx, sy, area_name)

    if preview:
        img = []
        for y in range(len(pixels)):
            img.append([])
        # preview of the MSX result (after 2-colour reduction): rebuild from files
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
                    bits, col = pgt[b][t * 8 + y], ct[b][t * 8 + y]
                    for x in range(8):
                        c = col >> 4 if bits & (0x80 >> x) else col & 15
                        img[tr * 8 + y][tc * 8 + x] = rgb8[c]
        write_png(os.path.join(out_dir, "level_msx_preview.png"), width, len(img), img)

    print(f"{area_name}: {len(cl)} braziers at x {[c[0] + 8 for c in cl]}, items {[c[2] for c in cl]}")
    print(f"{area_name}: {width} px wide, tiles per band {stats['tiles']}, "
          f"{stats['lossy_rows']} of {stats['total_rows']} tile rows reduced to 2 colours, "
          f"{len(used)} NES colours")
    return stats


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rom")
    ap.add_argument("out_dir")
    ap.add_argument("--area", default="1-courtyard", choices=sorted(AREAS))
    ap.add_argument("--nes-palette")
    args = ap.parse_args()
    convert(args.rom, args.out_dir, args.area, args.nes_palette)


if __name__ == "__main__":
    main()
