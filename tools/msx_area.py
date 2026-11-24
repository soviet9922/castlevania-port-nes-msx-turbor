"""Convert an indexed level image into the engine's Screen 4 area format.

Input
  pixels      list of rows (PF_ROWS*8 = 176 rows), each a list of MSX palette
              indices (0..15); width must be a multiple of 16
  palette     16 (r, g, b) tuples, components 0..7
  solid       list of rows (11) of 0/1 per 16x16 cell

Output files (in out_dir)
  palette.bin            V9938 palette, 32 bytes
  bg_pgt_b{0,1,2}.bin    pattern bytes for the tiles used in each band
  bg_ct_b{0,1,2}.bin     colour bytes (fg<<4 | bg per row)
  level_tiles.bin        column-major tile numbers, PF_ROWS bytes per 8-px column
  level_coll.bin         column-major solidity, MT_ROWS bytes per 16-px column
  level.inc              equates

Screen 4 allows 2 colours per 8-pixel tile row. Rows with more colours are
reduced to the best pair (least RGB error) and counted as lossy.
"""

import os

PF_ROWS = 22
MT_ROWS = 11
HUD_ROWS = 2
BG_TILE_BASE = 0x60     # 0x00 blank, 0x01-0x1F HUD, 0x20-0x5F font (band 0)
MAX_TILES = 256 - BG_TILE_BASE


def _dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def _reduce_row(row, palette):
    cols = sorted(set(row))
    if len(cols) <= 2:
        return row, False
    best = None
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            a, b = cols[i], cols[j]
            err = 0
            out = []
            for p in row:
                da, db = _dist(palette[p], palette[a]), _dist(palette[p], palette[b])
                out.append(a if da <= db else b)
                err += min(da, db)
            if best is None or err < best[0]:
                best = (err, out)
    return best[1], True


def _encode_row(row):
    cols = sorted(set(row))
    if len(cols) == 1:
        return 0, (cols[0] << 4) | cols[0]
    a, b = cols
    fg, bg = (a, b) if row.count(a) <= row.count(b) else (b, a)
    bits = 0
    for x, p in enumerate(row):
        if p == fg:
            bits |= 0x80 >> x
    return bits, (fg << 4) | bg


def band_of(pf_row):
    return (pf_row + HUD_ROWS) // 8


def write_area(out_dir, pixels, palette, solid, start_x, start_y, name="area"):
    h = len(pixels)
    w = len(pixels[0])
    assert h == PF_ROWS * 8, h
    assert w % 16 == 0, w
    assert len(solid) == MT_ROWS and all(len(r) == w // 16 for r in solid)
    tcols = w // 8

    bands = [dict() for _ in range(3)]          # (pat, col) -> index
    band_lists = [[] for _ in range(3)]
    tile_map = [[0] * PF_ROWS for _ in range(tcols)]
    lossy_rows = 0
    for tr in range(PF_ROWS):
        b = band_of(tr)
        for tc in range(tcols):
            pat, col = bytearray(), bytearray()
            for y in range(8):
                row = pixels[tr * 8 + y][tc * 8:tc * 8 + 8]
                row, lossy = _reduce_row(list(row), palette)
                lossy_rows += lossy
                p, c = _encode_row(row)
                pat.append(p)
                col.append(c)
            key = (bytes(pat), bytes(col))
            if key not in bands[b]:
                bands[b][key] = BG_TILE_BASE + len(band_lists[b])
                band_lists[b].append(key)
            tile_map[tc][tr] = bands[b][key]
    for b in range(3):
        if len(band_lists[b]) > MAX_TILES:
            raise SystemExit(f"{name}: band {b} needs {len(band_lists[b])} tiles (max {MAX_TILES})")

    os.makedirs(out_dir, exist_ok=True)

    def wr(fn, data):
        with open(os.path.join(out_dir, fn), "wb") as f:
            f.write(bytes(data))

    pal = bytearray()
    for r, g, b in palette:
        pal += bytes([(r << 4) | b, g])
    wr("palette.bin", pal)
    for b in range(3):
        wr(f"bg_pgt_b{b}.bin", b"".join(k[0] for k in band_lists[b]) or b"\0" * 8)
        wr(f"bg_ct_b{b}.bin", b"".join(k[1] for k in band_lists[b]) or b"\0" * 8)
    wr("level_tiles.bin", bytes(v for col in tile_map for v in col))
    wr("level_coll.bin", bytes(solid[r][c] for c in range(w // 16) for r in range(MT_ROWS)))

    blank = tile_map[0][0]
    inc = [
        f"; generated area '{name}' - do not edit",
        f"LEVEL_W          equ {w // 16}",
        f"BG_TILES_B0      equ {max(1, len(band_lists[0]))}",
        f"BG_TILES_B1      equ {max(1, len(band_lists[1]))}",
        f"BG_TILES_B2      equ {max(1, len(band_lists[2]))}",
        f"BLANK_TILE       equ 0x{blank:02X}",
        f"START_X          equ {start_x}",
        f"START_Y          equ {start_y}",
    ]
    with open(os.path.join(out_dir, "level.inc"), "w") as f:
        f.write("\n".join(inc) + "\n")
    return {
        "tiles": [len(x) for x in band_lists],
        "lossy_rows": lossy_rows,
        "total_rows": PF_ROWS * tcols * 8,
        "width": w,
    }
