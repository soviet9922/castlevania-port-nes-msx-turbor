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
  player_*.bin/.inc  player metasprites (see tools/msx_sprites.py)
  assets.inc        sjasmplus equates for HUD and sprites
  *_preview.png     previews for humans
"""

import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import msx_area  # noqa: E402
import msx_sprites  # noqa: E402
import areas_asm  # noqa: E402

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
    (6, 5, 3),  # e whip (converted builds: the whip's NES colour)
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

# Sub-weapon icons for the HUD (16x16 = 4 tiles each: top left, top right,
# bottom left, bottom right; white on black). Original placeholder art; the
# converted build replaces them with the ROM's icons (tools/convert_stage.py).
HUD_ICON_NAMES = ["DAGGER", "AXE", "HOLY", "WATCH"]
_ICON_ART = {
    "DAGGER": ["................"] * 6 + ["..x.............", "..xx.xxxxxxxxx..",
               "xxxxxxxxxxxxxxx.", "..xx.xxxxxxxxx..", "..x............."] + ["................"] * 5,
    "AXE": ["................", "..xx........xx..", ".xxxx......xxxx.", ".xxxxx....xxxxx.",
            ".xxxxxxxxxxxxxx.", ".xxxxxxxxxxxxxx.", ".xxxxx.xx.xxxxx.", ".xxxx..xx..xxxx.",
            "..xx...xx...xx..", ".......xx.......", ".......xx.......", ".......xx.......",
            ".......xx.......", ".......xx.......", "......xxxx......", "................"],
    "HOLY": ["................", "......xxxx......", ".......xx.......", ".......xx.......",
             "......xxxx......", ".....xxxxxx.....", "....xxxxxxxx....", "...xxxxxxxxxx...",
             "...xxxxxxxxxx...", "...xxxxxxxxxx...", "....xxxxxxxx....", ".....xxxxxx.....",
             "................", "................", "................", "................"],
    "WATCH": ["................", "......xxxx......", ".......xx.......", ".....xxxxxx.....",
              "...xxx....xxx...", "..xx..........xx", "..x.....x.....x.", ".x......x......x",
              ".x......xxxx...x", ".x.............x", "..x...........x.", "..xx........xx..",
              "...xxx....xxx...", ".....xxxxxx.....", "................", "................"],
}


def icon_tiles(art):
    """16x16 art (x = lit) -> 4 HUD tiles (rows of 8: 'f' lit, '1' black)."""
    rows = [r.ljust(16, ".")[:16] for r in art]
    out = []
    for ty in (0, 8):
        for tx in (0, 8):
            out.append(["".join("f" if rows[ty + y][tx + x] != "." else "1" for x in range(8))
                         for y in range(8)])
    return out


for _name in HUD_ICON_NAMES:
    for _q, _rows in zip(("TL", "TR", "BL", "BR"), icon_tiles(_ICON_ART[_name])):
        HUD_TILES.append((f"I_{_name}_{_q}", _rows))

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

WHIP_SLOT = 14
POSE_NAMES = ["stand", "walk1", "walk2", "tuck", "whip1", "whip2", "whip3", "whip4",
              "whip1c", "whip2c", "whip3c", "whip4c", "stair", "hurt", "dead1", "dead2"]
POSE_NAMES += [p + w for p in ("chain_", "star_")
               for w in ("whip1", "whip2", "whip3", "whip4", "whip1c", "whip2c", "whip3c", "whip4c")]
POSE_NAMES += ["throw1", "throw2", "throw3", "throw1c", "throw2c", "throw3c"]
# Placeholder knock-back arc (dy per frame while rising; the fall mirrors it)
PLACEHOLDER_KNOCKBACK = [-4, -3, -2, -2, -1, -1, -1, 0, -1, 0, 0, 0, 0, 0, 0, 0]

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






# ---------------------------------------------------------------------------
# Placeholder objects (original art), hex digit = palette slot, "." = clear.
# Same frame order and 16x32 box as tools/convert_objects.py.
# ---------------------------------------------------------------------------
_FLAME_A = [
    "................", "......b.........", ".....bb....b....", ".....bcb..bb....",
    "....bccb.bcb....", "....bcccbccb....", "...bccccccccb...", "...bcccffcccb...",
    "...bccfffcccb...", "....bccffccb....", "....bbccccbb....", ".....bbbbbb.....",
    "................", "................", "................", "................",
]
_FLAME_B = [
    "................", ".........b......", "....b....bb.....", "....bb..bcb.....",
    "....bcb.bccb....", "....bccbcccb....", "...bccccccccb...", "...bcccffcccb...",
    "...bcccfffccb...", "....bccffccb....", "....bbccccbb....", ".....bbbbbb.....",
    "................", "................", "................", "................",
]
_BOWL = [
    "7777777777777777", "5777777777777775", ".55777777777755.", "..555555555555..",
    "......5775......", "......5775......", "......5775......", "......5775......",
    "......5775......", "......5775......", ".....557755.....", "....55577555....",
    "...5555555555...", "..555555555555..", "................", "................",
]
_EMPTY16 = ["................"] * 8
_BURSTS = [
    _EMPTY16 + ["................", ".......f........", "...f...c...f....", "....c.fcf.c.....",
                ".....fcccf......", "...ffcccccff....", ".....fcccf......", "....c.fcf.c.....",
                "...f...c...f....", ".......f........", "................", "................",
                "................", "................", "................", "................"],
    _EMPTY16 + ["................", "................", ".......c........", "......cfc.......",
                ".....cfffc......", "......cfc.......", ".......c........", "................"]
    + ["................"] * 8,
    _EMPTY16 + ["................"] * 3 + [".......c........", "......cbc.......", ".......c........"]
    + ["................"] * 10,
    _EMPTY16 + ["................"] * 4 + [".......b........"] + ["................"] * 11,
]
_HEART = _EMPTY16 + [
    "................", "...666....666...", "..66666..66666..", ".6666f6666666666",
    ".666ff666666666.", ".66666666666666.", "..666666666666..", "...6666666666...",
    "....66666666....", ".....666666.....", "......6666......", ".......66.......",
    "................", "................", "................", "................",
]
_WHIPUP = _EMPTY16 + [
    "................", ".....222222.....", "...22......22...", "..2..222222..2..",
    "..2.2......2.2..", "..2.2.2222.2.2..", "..2.2.2..2.2.2..", "..2.2..22..2.2..",
    "..2..2....2..2..", "...2..2222..2...", "....22....22....", "......2222......",
    "................", "................", "................", "................",
]
_DAGGER = _EMPTY16 + [
    "................"] * 5 + [
    "..22.....7......", "..2277777777....", "22227777777777f.", "..2277777777....",
    "..22.....7......"] + ["................"] * 6
_ZOMBIE_TOP = [
    "................", "......eeee......", ".....eeeeee.....", ".....e1ee1e.....",
    ".....eeeeee.....", "......e11e......", ".......ee.......", "....33333333....",
    "...3333333333...", "..ee33333333....", "..ee.333333.....", "......3333......",
    "......3333......", "......3333......", ".....333333.....", ".....33..33.....",
]
_ZOMBIE_LEGS_1 = [".....33..33....."] * 4 + [".....ee..ee....."] * 10 + ["....eee..eee...."] * 2
_ZOMBIE_LEGS_2 = [".....33..33....."] * 4 + ["....ee....ee...."] * 10 + ["...eee....eee..."] * 2
_CANDLE_A = _EMPTY16 + [
    "................", ".......b........", "......bcb.......", ".......c........",
    "......ffff......", "......ffff......", "......ffff......", "......ffff......",
    "......ffff......", "......ffff......", ".....777777.....", "......7777......",
]
_CANDLE_B = _EMPTY16 + [
    "........b.......", "......bcb.......", ".......cb.......", ".......c........",
    "......ffff......", "......ffff......", "......ffff......", "......ffff......",
    "......ffff......", "......ffff......", ".....777777.....", "......7777......",
]
_SMALL_HEART = _EMPTY16 + [
    "................", "................", "................", "....66..66......",
    "...66666666.....", "...66666666.....", "....666666......", ".....6666.......",
    "......66........",
]
# placeholder black panther, 32x16, facing left (kind 2)
_PANTHER_SIT = [
    "................................", "................................",
    "................................", "................................",
    "................................", "........11......................",
    ".......1611.....................", "......111111111111111...........",
    ".....1111111111111111111........", "....11111111111111111111111.....",
    "....111111111111111111111111....", "....11.11...........11.11.......",
    "....11.11...........11.11.......", "...111.111.........111.111......",
    "................................", "................................",
]
_PANTHER_RUN = [
    "................................", "................................",
    "................................", "................................",
    "................................", "..11............................",
    ".1611...........................", "111111111111111111111111........",
    "11111111111111111111111111111...", ".1111111111111111111111111111111",
    "..11111111111111111111111111....", "...11.11............11.11.......",
    "..11...11..........11...11......", ".11.....11........11.....11.....",
    "................................", "................................",
]
PLACEHOLDER_OBJECTS = {
    "panther_sit_l": _PANTHER_SIT, "panther_run1_l": _PANTHER_RUN,
    "panther_run2_l": _PANTHER_RUN, "panther_run3_l": _PANTHER_SIT,
    "panther_sit_r": [r[::-1] for r in _PANTHER_SIT], "panther_run1_r": [r[::-1] for r in _PANTHER_RUN],
    "panther_run2_r": [r[::-1] for r in _PANTHER_RUN], "panther_run3_r": [r[::-1] for r in _PANTHER_SIT],
    "candle1": _CANDLE_A, "candle2": _CANDLE_B, "smallheart": _SMALL_HEART,
    "zombie_l1": _ZOMBIE_TOP + _ZOMBIE_LEGS_1, "zombie_l2": _ZOMBIE_TOP + _ZOMBIE_LEGS_2,
    "zombie_r1": [r[::-1] for r in _ZOMBIE_TOP + _ZOMBIE_LEGS_1],
    "zombie_r2": [r[::-1] for r in _ZOMBIE_TOP + _ZOMBIE_LEGS_2],
    "brazier1": _FLAME_A + _BOWL, "brazier2": _FLAME_B + _BOWL,
    "burst1": _BURSTS[0], "burst2": _BURSTS[1], "burst3": _BURSTS[2], "burst4": _BURSTS[3],
    "heart": _HEART, "whipup": _WHIPUP, "dagger": _DAGGER,
}
OBJ_FRAMES = ["brazier1", "brazier2", "burst1", "burst2", "burst3", "burst4",
              "heart", "whipup", "dagger", "candle1", "candle2", "smallheart",
              "zombie_l1", "zombie_l2", "zombie_r1", "zombie_r2",
              "panther_sit_l", "panther_run1_l", "panther_run2_l", "panther_run3_l",
              "panther_sit_r", "panther_run1_r", "panther_run2_r", "panther_run3_r"]
# frames the placeholder level doesn't use (bats, fishmen, boss: OBJF 24-39)
# stay empty so that the engine's frame numbers match; then the flying dagger
OBJ_FRAMES += [f"unused{i}" for i in range(24, 40)] + ["dagger_fly_r", "dagger_fly_l"]
OBJ_FRAMES += ["axe1", "axe2", "axe3", "axe4", "bottle", "flame1", "flame2", "flame3",
               "holy_item", "watch_item", "flame4", "flame5", "axe_item"]
# original placeholder art: a double-bladed throwing hatchet, turning
_HATCHET = [
    "................", "..77........77..", ".7777......7777.", ".77777....77777.",
    ".777777ff777777.", ".777777ff777777.", ".77777.ff.77777.", ".7777..ff..7777.",
    "..77...ff...77..", ".......ff.......", ".......ff.......", ".......ff.......",
    ".......ff.......", ".......ff.......", "......ffff......", "................",
]
_FLASK = [
    "................", "......ffff......", ".......55.......", ".......55.......",
    "......5555......", ".....555555.....", "....55555555....", "....55555555....",
    "....55555555....", ".....555555.....", "......5555......", "................",
    "................", "................", "................", "................",
]
def _turn(art):  # a quarter turn clockwise
    return ["".join(art[15 - x][y] for x in range(16)) for y in range(16)]
PLACEHOLDER_OBJECTS["axe1"] = _HATCHET
PLACEHOLDER_OBJECTS["axe2"] = _turn(_HATCHET)
# (two turns only: the placeholder level has no room for four in 52 patterns)
PLACEHOLDER_OBJECTS["axe3"] = _HATCHET
PLACEHOLDER_OBJECTS["axe4"] = _turn(_HATCHET)
PLACEHOLDER_OBJECTS["bottle"] = _FLASK
PLACEHOLDER_OBJECTS["axe_item"] = _HATCHET
PLACEHOLDER_OBJECTS["holy_item"] = _FLASK
PLACEHOLDER_OBJECTS["watch_item"] = [r.replace("x", "f") for r in [
    "................", "......xxxx......", ".......xx.......", ".....xxxxxx.....",
    "...xxx....xxx...", "..xx........xx..", "..x.....x.....x.", ".x......x......x",
    ".x......xxxx...x", ".x.............x", "..x...........x.", "..xx........xx..",
    "...xxx....xxx...", ".....xxxxxx.....", "................", "................"]]
for _n, _b in (("flame1", 0), ("flame2", 1), ("flame3", 2), ("flame4", 3), ("flame5", 2)):
    PLACEHOLDER_OBJECTS[_n] = _BURSTS[_b][8:24]
for _i in range(24, 40):
    PLACEHOLDER_OBJECTS[f"unused{_i}"] = ["." * 16]
PLACEHOLDER_OBJECTS["dagger_fly_r"] = _DAGGER
PLACEHOLDER_OBJECTS["dagger_fly_l"] = [r[::-1] for r in _DAGGER]
PLACEHOLDER_SPAWNERS = [(900, 128)]     # one zombie spawner near the end
# placeholder candles: (box x, box y, item id, kind) - see tools/convert_objects.py
# item ids: 0 whip upgrade, 1 big heart, 2 dagger, 3 small heart; kind 0 brazier, 1 candle
PLACEHOLDER_CANDLES = [(88, 128, 1, 0), (216, 128, 0, 0),     # braziers on the floor (y 160)
                       (344, 96, 3, 1), (472, 96, 3, 1),       # wall candles
                       (376, 112, 0xFF, 2)]                    # panther on the platform


def placeholder_objects():
    bank = msx_sprites.SpriteBank()
    for name in OBJ_FRAMES:
        art = PLACEHOLDER_OBJECTS[name]
        art = art + ["." * len(art[0])] * (32 - len(art))  # pad to 32 rows
        assert len(art) == 32 and all(len(r) in (16, 32) for r in art), name
        bank.add_frame({(x, y): int(ch, 16) for y, row in enumerate(art)
                        for x, ch in enumerate(row) if ch != "."}, name)
    return bank


def _ascii_pixels(frame):
    return {(x, y): ch for y, row in enumerate(frame) for x, ch in enumerate(row) if ch in "ABC"}


def _line(pixels, x0, y0, x1, y1, slot):
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i // n
        y = y0 + (y1 - y0) * i // n
        pixels[(x, y)] = slot


def placeholder_whip(pose):
    """Original placeholder whip pixels for pose 1..4 (facing right)."""
    w = {}
    if pose == 1:                       # held behind the back
        _line(w, -10, 6, -1, 10, WHIP_SLOT)
        _line(w, -10, 7, -1, 11, WHIP_SLOT)
    elif pose == 2:                     # raised
        _line(w, -12, -6, -1, 8, WHIP_SLOT)
        _line(w, -11, -6, 0, 8, WHIP_SLOT)
    elif pose == 3:                     # extended
        for y, slot in ((11, 1), (12, WHIP_SLOT), (13, WHIP_SLOT), (14, 1)):
            _line(w, 16, y, 43, y, slot)
    return w


def placeholder_chain(pose, extra=0):
    """Original placeholder for the upgraded whips: a dotted chain (pose 3 is
    extended; extra = more length for the long whip, which ends in a ball)."""
    w = placeholder_whip(pose)
    if pose == 3:
        w = {}
        for x in range(16, 44 + extra):
            if x % 3 != 2:
                w[(x, 12)] = WHIP_SLOT
                w[(x, 13)] = WHIP_SLOT
        if extra:
            for dx in range(3):
                for dy in range(3):
                    w[(43 + extra - dx, 11 + dy)] = WHIP_SLOT
    return w


def player_sprites():
    """-> (SpriteBank, frame names) in the engine's pose order."""
    stand, walk1, walk2, tuck = (_ascii_pixels(f) for f in PLAYER_FRAMES)
    poses = [stand, walk1, walk2, tuck]
    for base in (stand, tuck):
        for n in (1, 2, 3, 4):
            px = dict(placeholder_whip(n))
            px.update(base)
            poses.append(px)
    poses.append(walk2)                 # placeholder stair pose
    poses.append(tuck)                  # placeholder hurt pose
    poses.append({(x, y + 8): v for (x, y), v in tuck.items() if y + 8 < 32})  # falling
    # lying: the standing figure turned on its side, head first (32x16)
    poses.append({(31 - y, 16 + x): v for (x, y), v in stand.items() if x < 16})
    for extra in (0, 16):               # chain whip, long whip
        for base in (stand, tuck):
            for n in (1, 2, 3, 4):
                px = dict(placeholder_chain(n, extra))
                px.update(base)
                poses.append(px)
    for base in (stand, tuck):          # throwing: arm poses without a whip
        for n in (1, 2, 3):
            poses.append(dict(base))
    bank = msx_sprites.SpriteBank()
    names = []
    for facing in ("right", "left"):
        for i, px in enumerate(poses):
            if facing == "left":
                px = msx_sprites.mirror(px)
            bank.add_frame(px, f"{POSE_NAMES[i]}-{facing}")
            names.append(f"{POSE_NAMES[i]} {facing}")
    return bank, names


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
    # collision per 8x8 tile (each solid metatile = 2x2 solid tiles)
    solid = [[1 if solids[level[r // 2][c // 2]] else 0 for c in range(LEVEL_W * 2)]
             for r in range(MT_ROWS * 2)]
    area_dir = os.path.join(out_dir, "area_0")
    stats = msx_area.write_area(area_dir, pixels, PALETTE, solid, START_X, START_Y,
                                "placeholder")
    if stats["lossy_rows"]:
        raise SystemExit("placeholder art breaks the 2-colours-per-row rule")

    # --- HUD tiles ---
    hud_pgt, hud_ct = bytearray(), bytearray()
    for name, rows in HUD_TILES:
        p, c = tile_from_rows(rows, f"hud tile {name}")
        hud_pgt += p
        hud_ct += c

    bank, frame_names = player_sprites()
    n_patterns, n_frames = msx_sprites.write_bank(out_dir, bank, frame_names)
    n_obj, _ = msx_sprites.write_bank(area_dir, placeholder_objects(), OBJ_FRAMES,
                                      prefix="a0_obj")
    cdata = bytearray([len(PLACEHOLDER_CANDLES)])
    for x, y, item, kind in PLACEHOLDER_CANDLES:
        cdata += bytes([x & 0xFF, x >> 8, y, item, kind])
    with open(os.path.join(area_dir, "candles.bin"), "wb") as f:
        f.write(cdata)
    with open(os.path.join(area_dir, "stairs.bin"), "wb") as f:
        f.write(bytes([0]))             # the placeholder level has no stairs
    edata = bytearray([len(PLACEHOLDER_SPAWNERS)])
    for x, y in PLACEHOLDER_SPAWNERS:
        edata += bytes([x & 0xFF, x >> 8, y, 1])
    with open(os.path.join(area_dir, "enemies.bin"), "wb") as f:
        f.write(edata)
    stats.update(dir="area_0", obj_patterns=n_obj, exit_x=None)
    areas_asm.write(out_dir, [stats])

    files = {
        "player_jump.bin": bytes(v & 0xFF for v in PLACEHOLDER_JUMP),
        "player_kb.bin": bytes(v & 0xFF for v in PLACEHOLDER_KNOCKBACK),
        "hud_pgt.bin": bytes(hud_pgt),
        "hud_ct.bin": bytes(hud_ct),
    }
    for fn, data in files.items():
        with open(os.path.join(out_dir, fn), "wb") as f:
            f.write(data)

    inc = [
        "; generated by tools/gen_placeholder_assets.py - do not edit",
        f"MT_ROWS          equ {MT_ROWS}",
        f"HUD_TILE_COUNT   equ {len(HUD_TILES)}",
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
          f"level {LEVEL_W}x{MT_ROWS}, {n_frames} sprite frames / {n_patterns} patterns")


if __name__ == "__main__":
    main()
