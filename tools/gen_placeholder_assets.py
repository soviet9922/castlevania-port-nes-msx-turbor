#!/usr/bin/env python3
"""Generate the ORIGINAL placeholder graphics and test level for the engine.

Nothing in here comes from the NES game. These assets exist only so the
engine can be built, run and tested before the real game data is converted
from a ROM that the user owns (see tools/nes_rom_tool.py and docs/DESIGN.md).

Outputs (written to the directory given on the command line):
  palette.bin, bg_*_b?.bin, level_*.bin, level.inc
                    the level ("area"), see tools/msx_area.py
  hud_pgt.bin       HUD tile patterns
  hud_ct.bin        HUD tile colours
  player_spt.bin    player sprite patterns (16x16, MSX order)
  assets.inc        sjasmplus equates for HUD and sprites
  *_preview.png     previews for humans
"""

import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import msx_area  # noqa: E402

# ---------------------------------------------------------------------------
# Palette: 16 entries, RGB components 0..7 (MSX2 9-bit palette)
# Index 2, 4 and 6 are tied together by the sprite OR-colour trick:
#   layer A = 2, layer B = 4, overlap = 2|4 = 6
# ---------------------------------------------------------------------------
PALETTE = [
    (0, 0, 0),  # 0 transparent / backdrop (black)
    (0, 0, 0),  # 1 black
    (4, 2, 1),  # 2 brown       (player layer A)
    (2, 2, 2),  # 3 dark grey
    (7, 5, 3),  # 4 skin        (player layer B)
    (4, 4, 4),  # 5 grey
    (5, 1, 1),  # 6 red         (player A|B overlap)
    (6, 6, 6),  # 7 light grey
    (1, 1, 2),  # 8 very dark blue
    (2, 3, 6),  # 9 blue
    (3, 1, 0),  # a dark brick
    (7, 4, 0),  # b orange
    (7, 7, 2),  # c yellow
    (3, 1, 3),  # d purple
    (1, 4, 1),  # e green
    (7, 7, 7),  # f white
]

HUD_TILE_BASE = 0x01    # HUD tiles live at 0x01..; font uses 0x20..0x5F
MT_ROWS = 11            # metatile rows in the playfield (11 * 16 = 176 px)

# ---------------------------------------------------------------------------
# Metatiles: 16x16 pixel art, one hex digit (palette index) per pixel.
# Every 8-pixel half row may use at most 2 colours (Screen 4 restriction).
# ---------------------------------------------------------------------------
BRICK = [
    "1111111111111111",
    "2222222122222221",
    "aaaaaaa1aaaaaaa1",
    "aaaaaaa1aaaaaaa1",
    "1111111111111111",
    "2221222222212222",
    "aaa1aaaaaaa1aaaa",
    "aaa1aaaaaaa1aaaa",
] * 2

STONE = (
    ["7777777777777773"]
    + ["7555555555555553"] * 2
    + ["7557555555555553", "7555555555553553"]
    + ["7555555555555553"] * 10
    + ["3333333333333333"]
)

WINDOW_TOP = [
    "1111111111111111",
    "1111119999111111",
    "1111999999991111",
    "1119999999999111",
    "1199999119999911",
    "1199999119999911",
    "1199999119999911",
    "1111111111111111",
] + ["1199999119999911"] * 8

WINDOW_BOT = (
    ["1199999119999911"] * 7
    + ["1111111111111111"]
    + ["1199999119999911"] * 6
    + ["1111111111111111", "2222222222222222"]
)

PILLAR_BODY_ROW = "7777555555553333"
PILLAR_TOP = (
    ["7777777777777777"] * 2
    + ["5555555555555555", "3333333333333333"]
    + [PILLAR_BODY_ROW] * 12
)
PILLAR = [PILLAR_BODY_ROW] * 16

CANDLE = (
    ["aaaaaaaaaaaaaaaa"] * 4
    + [
        "aaaaaaabbaaaaaaa",
        "aaaaaabbbbaaaaaa",
        "aaaaaaccccaaaaaa",
        "aaaaaaabbaaaaaaa",
    ]
    + ["aaaaaaffffaaaaaa"] * 5
    + ["aaaa77777777aaaa", "aaaaa777777aaaaa", "aaaaaa7777aaaaaa"]
)

CURTAIN_ROW = "d1dd1dd1dd1dd1dd"
CURTAIN_TOP = ["cccccccccccccccc"] * 2 + ["dddddddddddddddd"] + [CURTAIN_ROW] * 13
CURTAIN = [CURTAIN_ROW] * 16

VOID = ["1111111111111111"] * 16

# (name, art, solid)   -- order defines the metatile id
METATILES = [
    ("VOID", VOID, False),
    ("BRICK", BRICK, False),
    ("STONE", STONE, True),
    ("WINDOW_TOP", WINDOW_TOP, False),
    ("WINDOW_BOT", WINDOW_BOT, False),
    ("PILLAR_TOP", PILLAR_TOP, False),
    ("PILLAR", PILLAR, False),
    ("CANDLE", CANDLE, False),
    ("CURTAIN_TOP", CURTAIN_TOP, False),
    ("CURTAIN", CURTAIN, False),
]
MT = {name: i for i, (name, _, _) in enumerate(METATILES)}

# ---------------------------------------------------------------------------
# HUD tiles (8x8). Only palette slots 1, 6 and 15 may be used here: they keep
# the same meaning in converted areas (black, red, white).
# ---------------------------------------------------------------------------
HUD_TILES = [
    ("HEART", [
        "11111111",
        "16611661",
        "66666666",
        "66666666",
        "16666661",
        "11666611",
        "11166111",
        "11111111",
    ]),
    ("BAR_PLAYER", ["11111111"] * 2 + ["6666666" + "1"] * 4 + ["11111111"] * 2),
    ("BAR_EMPTY", ["11111111"] * 2 + ["ffffff11", "f1111f11", "f1111f11", "ffffff11"]
     + ["11111111"] * 2),
    ("BAR_ENEMY", ["11111111"] * 2 + ["fffffff1"] * 4 + ["11111111"] * 2),
]

# ---------------------------------------------------------------------------
# Player sprite: an original placeholder "hunter", 16x32, facing right.
#   .  transparent
#   A  layer A only  -> palette 2 (brown: hair, tunic, boots)
#   B  layer B only  -> palette 4 (skin)
#   C  both layers   -> palette 6 (red: headband, belt, garters)
# ---------------------------------------------------------------------------
UPPER = [
    "................",
    "......AAAA......",
    ".....AAAAAA.....",
    "....AAAAAAAA....",
    "....ACCCCCCC....",
    "....AABBBBB.....",
    "....AABBCBC.....",
    ".....ABBBBB.....",
    "......BBBB......",
    ".......BB.......",
    ".....CAAAAC.....",
    "....AAAAAAAA....",
    "...AAAAAAAAAA...",
    "...AA.AAAA.AA...",
    "...AA.AAAA.AA...",
    "...AA.AAAA.AA...",
    "...AA.AAAA.AA...",
    "...BB.CCCC.BB...",
    "...BB.AAAA.BB...",
]

STAND_LEGS = [
    "......AAAA......",
    ".....AAAAAA.....",
    ".....AAAAAA.....",
    ".....AA..AA.....",
    ".....AA..AA.....",
    ".....BB..BB.....",
    ".....BB..BB.....",
    ".....BB..BB.....",
    ".....CC..CC.....",
    ".....AA..AA.....",
    ".....AA..AA.....",
    ".....AAA.AAA....",
    ".....AAA.AAAA...",
]

WALK1_LEGS = [
    "......AAAA......",
    ".....AAAAAA.....",
    "....AAA..AAA....",
    "....AA....AA....",
    "...AA......AA...",
    "...BB......BB...",
    "...BB......BB...",
    "..BB........BB..",
    "..CC........CC..",
    "..AA........AA..",
    "..AA........AA..",
    ".AAA........AAA.",
    ".AAA........AAAA",
]

WALK2_LEGS = [
    "......AAAA......",
    ".....AAAAAA.....",
    ".....AAAAAA.....",
    ".....AA.AA......",
    ".....AA.AA......",
    "....BB...BB.....",
    "....BB...BB.....",
    "....BB...BB.....",
    "....CC...CC.....",
    "....AA...AA.....",
    "...AA....AA.....",
    "...AAA...AAA....",
    "...AAA...AAAA...",
]

JUMP_LEGS = [
    "......AAAA......",
    ".....AAAAAA.....",
    "....AAAAAAAA....",
    "...AAA....BBB...",
    "...BB.....BBB...",
    "...BB......CC...",
    "...CC......AA...",
    "...AAA.....AAA..",
    "...AAA..........",
    "................",
    "................",
    "................",
    "................",
]

# frame order matters: 0 stand, 1 walk1, 2 walk2, 3 jump (see src/player.asm)
PLAYER_FRAMES = [
    UPPER + STAND_LEGS,
    UPPER + WALK1_LEGS,
    UPPER + WALK2_LEGS,
    UPPER + JUMP_LEGS,
]
# Placeholder jump arc: dy per frame while rising (the fall mirrors it).
# 20 entries, peak 36 px. A converted build uses the game's own table.
PLACEHOLDER_JUMP = [-5, -4, -4, -3, -3, -3, -2, -2, -2, -2,
                    -1, -1, -1, -1, -1, 0, -1, 0, 0, 0]
assert len(PLACEHOLDER_JUMP) == 20

PLAYER_COLOR_A = 2
PLAYER_COLOR_B = 4


# ---------------------------------------------------------------------------
# Level: 64 metatile columns x 11 rows, row 10 = bottom
# ---------------------------------------------------------------------------
LEVEL_W = 64
START_X = 32
START_Y = 10 * 16 - 32  # standing on the floor row


def build_level():
    g = [[MT["BRICK"]] * LEVEL_W for _ in range(MT_ROWS)]
    # curtains
    for c in range(16, 23):
        g[0][c] = MT["CURTAIN_TOP"]
        for r in range(1, 4):
            g[r][c] = MT["CURTAIN"]
    # windows
    for c in range(3, LEVEL_W - 4, 8):
        if g[2][c] == MT["BRICK"]:
            g[2][c] = MT["WINDOW_TOP"]
            g[3][c] = MT["WINDOW_BOT"]
    # pillars
    for c in range(7, LEVEL_W - 2, 8):
        g[1][c] = MT["PILLAR_TOP"]
        for r in range(2, 10):
            g[r][c] = MT["PILLAR"]
    # candles
    for c in range(1, LEVEL_W - 1, 4):
        if g[6][c] == MT["BRICK"]:
            g[6][c] = MT["CANDLE"]
    # floor
    for c in range(LEVEL_W):
        g[10][c] = MT["STONE"]
    # pits
    for c in (30, 31, 47, 48):
        g[10][c] = MT["VOID"]
    # platforms and steps (each step rises 32 px; jump peak is ~42 px)
    for c in range(22, 26):
        g[8][c] = MT["STONE"]
    for c in (36, 37):
        g[8][c] = MT["STONE"]
    for c in (39, 40):
        g[6][c] = MT["STONE"]
    for c in (42, 43, 44):
        g[4][c] = MT["STONE"]
    for c in range(46, 50):
        g[7][c] = MT["STONE"]
    # low obstacle to jump over
    g[9][55] = MT["STONE"]
    # end wall
    for r in range(MT_ROWS):
        g[r][LEVEL_W - 1] = MT["STONE"]
    return g


# ---------------------------------------------------------------------------
# Conversion helpers
# ---------------------------------------------------------------------------
def tile_from_rows(rows, where):
    """8 rows of 8 hex chars -> (pattern bytes, colour bytes)."""
    pat, col = [], []
    for y, row in enumerate(rows):
        assert len(row) == 8, (where, row)
        px = [int(ch, 16) for ch in row]
        colours = sorted(set(px))
        if len(colours) > 2:
            raise SystemExit(f"{where}: row {y} '{row}' uses {len(colours)} colours (max 2)")
        if len(colours) == 1:
            fg = bg = colours[0]
        else:
            # fg = the colour that is NOT in the first pixel's background guess;
            # use the less frequent colour as foreground for nicer bit patterns
            a, b = colours
            fg, bg = (a, b) if px.count(a) <= px.count(b) else (b, a)
        bits = 0
        for x, p in enumerate(px):
            if p == fg and fg != bg:
                bits |= 0x80 >> x
        pat.append(bits)
        col.append((fg << 4) | bg)
    return bytes(pat), bytes(col)




def sprite16(rows16):
    """16 rows of 16 '0'/'1' -> 32 bytes in MSX 16x16 sprite order."""
    out = bytearray()
    for half in (0, 8):
        for r in rows16:
            b = 0
            for x in range(8):
                if r[half + x] == "1":
                    b |= 0x80 >> x
            out.append(b)
    return bytes(out)


def player_patterns():
    out = bytearray()
    for flip in (False, True):
        for frame in PLAYER_FRAMES:
            assert len(frame) == 32, len(frame)
            for r in frame:
                assert len(r) == 16 and set(r) <= set(".ABC"), r
            rows = [r[::-1] if flip else r for r in frame]
            layer_a = ["".join("1" if c in "AC" else "0" for c in r) for r in rows]
            layer_b = ["".join("1" if c in "BC" else "0" for c in r) for r in rows]
            # order per frame: topA, topB, botA, botB
            out += sprite16(layer_a[:16])
            out += sprite16(layer_b[:16])
            out += sprite16(layer_a[16:])
            out += sprite16(layer_b[16:])
    return bytes(out)




def rgb(i):
    r, g, b = PALETTE[i]
    return (r * 255 // 7, g * 255 // 7, b * 255 // 7)


def write_png(path, w, h, pixels):
    """pixels: list of rows, each a list of (r,g,b)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for p in row:
            raw += bytes(p)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "build/gen"
    os.makedirs(out_dir, exist_ok=True)

    # --- level: render the metatile grid to an indexed image ---
    level = build_level()
    arts = [art for _, art, _ in METATILES]
    solids = [solid for _, _, solid in METATILES]
    pixels = []
    for r in range(MT_ROWS):
        for y in range(16):
            pixels.append([int(arts[level[r][c]][y][x], 16)
                           for c in range(LEVEL_W) for x in range(16)])
    solid = [[1 if solids[level[r][c]] else 0 for c in range(LEVEL_W)]
             for r in range(MT_ROWS)]
    stats = msx_area.write_area(out_dir, pixels, PALETTE, solid, START_X, START_Y,
                                "placeholder")
    if stats["lossy_rows"]:
        raise SystemExit("placeholder art breaks the 2-colours-per-row rule")

    # --- HUD tiles ---
    hud_pgt, hud_ct = bytearray(), bytearray()
    for name, rows in HUD_TILES:
        p, c = tile_from_rows(rows, f"hud tile {name}")
        hud_pgt += p
        hud_ct += c

    spt = player_patterns()

    files = {
        "player_jump.bin": bytes(v & 0xFF for v in PLACEHOLDER_JUMP),
        "hud_pgt.bin": bytes(hud_pgt),
        "hud_ct.bin": bytes(hud_ct),
        "player_spt.bin": spt,
    }
    for fn, data in files.items():
        with open(os.path.join(out_dir, fn), "wb") as f:
            f.write(data)

    inc = [
        "; generated by tools/gen_placeholder_assets.py - do not edit",
        f"MT_ROWS          equ {MT_ROWS}",
        f"HUD_TILE_COUNT   equ {len(HUD_TILES)}",
        f"PLAYER_SPT_SIZE  equ {len(spt)}",
        f"PLAYER_COLOR_A   equ {PLAYER_COLOR_A}",
        f"PLAYER_COLOR_B   equ {PLAYER_COLOR_B}",
    ]
    for i, (name, _) in enumerate(HUD_TILES):
        inc.append(f"HUDT_{name:<12} equ 0x{HUD_TILE_BASE + i:02X}")
    with open(os.path.join(out_dir, "assets.inc"), "w") as f:
        f.write("\n".join(inc) + "\n")

    # --- previews ---
    lw, lh = LEVEL_W * 16, MT_ROWS * 16
    img = [[(0, 0, 0)] * lw for _ in range(lh)]
    arts = [art for _, art, _ in METATILES]
    for c in range(LEVEL_W):
        for r in range(MT_ROWS):
            art = arts[level[r][c]]
            for y in range(16):
                for x in range(16):
                    img[r * 16 + y][c * 16 + x] = rgb(int(art[y][x], 16))
    write_png(os.path.join(out_dir, "level1_preview.png"), lw, lh, img)

    sw = 16 * len(PLAYER_FRAMES) * 2 + 8
    sheet = [[(40, 40, 60)] * sw for _ in range(32)]
    cmap = {"A": rgb(PLAYER_COLOR_A), "B": rgb(PLAYER_COLOR_B),
            "C": rgb(PLAYER_COLOR_A | PLAYER_COLOR_B)}
    for i, frame in enumerate(PLAYER_FRAMES * 2):
        flip = i >= len(PLAYER_FRAMES)
        ox = i * 16 + (8 if flip else 0)
        for y, row in enumerate(frame):
            row = row[::-1] if flip else row
            for x, ch in enumerate(row):
                if ch in cmap:
                    sheet[y][ox + x] = cmap[ch]
    write_png(os.path.join(out_dir, "player_preview.png"), sw, 32, sheet)

    print(f"placeholder assets: tiles per band {stats['tiles']}, "
          f"level {LEVEL_W}x{MT_ROWS}, {len(spt)} bytes of sprite patterns")


if __name__ == "__main__":
    main()
