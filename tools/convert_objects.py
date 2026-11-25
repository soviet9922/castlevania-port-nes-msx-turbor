"""Convert candles/braziers and item sprites from the user's ROM.

Candle placement (fixed bank, see docs/NES_NOTES.md):
  word at $D29B + 2*stage        -> per-stage table
  word at that table + 2*section -> per-section table, 2 bytes per 64-px chunk:
                                    (enemy group, candle group)
  candle group g: word at $D6D1 + 2*g ($D7D1 when bit 7 is set) -> record
  record: [$FF item] [$FE] x y    (0 = no candle; $FE = brazier, object $28)

Observed in the game: the object is centred at world x = (chunk-1)*64 + x;
y is the NES centre line of a wall candle / foot line of a brazier.
Drop codes seen: 0 (brazier: whip upgrade; wall candle: usually a small
heart - the NES has a drop rule not decoded yet), 4 big heart, 8 dagger.
Other codes ($0A, $0B, $11, $21) are not identified and drop a small heart.

Engine item ids: 0 whip upgrade, 1 big heart, 2 dagger, 3 small heart.
Engine object kinds: 0 brazier (16x32 box), 1 wall candle (16x16 box at y+8).

Sprites (8x16, tile bit 0 selects the pattern table, as on the NES):
  brazier  flame $97/$99 (palette 3) over bowl $9B (palette 2), mirrored pairs
  burst    $91+$70, $93+$70, $93, $95 (palette 3)
  items    big heart $BF pair (pal 3), whip upgrade $C1 $C3 (pal 3),
           dagger $BD $BB (pal 2, flipped), small heart $9F (pal 3)
  candle   $40 / $50 alternating every 9 frames (pal 3)
"""

from cv_rom import tile_pixels
from msx_sprites import SpriteBank

STAGE_TABLE = 0xD29B
CANDLE_GROUPS = (0xD6D1, 0xD7D1)
SPRITE_PALETTES = 0xCDEB         # 4 x 4 colours after the $3F $10 header

# engine object frame numbers (src/objects.asm)
OBJ_FRAMES = ["brazier1", "brazier2", "burst1", "burst2", "burst3", "burst4",
              "heart", "whipup", "dagger", "candle1", "candle2", "smallheart",
              "zombie_l1", "zombie_l2", "zombie_r1", "zombie_r2",
              "panther_sit_l", "panther_run1_l", "panther_run2_l", "panther_run3_l",
              "panther_sit_r", "panther_run1_r", "panther_run2_r", "panther_run3_r",
              "bat1_l", "bat2_l", "bat3_l", "bat1_r", "bat2_r", "bat3_r",
              "fish_walk1_l", "fish_walk2_l", "fish_shoot_l",
              "fish_walk1_r", "fish_walk2_r", "fish_shoot_r", "fireball"]

# Black panther: 32x16, palette 3, art faces left (recorded in the hall).
# Run cycle run1 -> run2 -> run3, 7 frames each; the leap shows run2.
PANTHER_LEFT = {
    "panther_sit_l": [(0xB0, 8, 0, 3, 0), (0xB2, 16, 0, 3, 0), (0xB4, 24, 0, 3, 0)],
    "panther_run1_l": [(0xC0, 0, 0, 3, 0), (0xC2, 8, 0, 3, 0), (0xC4, 16, 0, 3, 0), (0xC6, 24, 0, 3, 0)],
    "panther_run2_l": [(0xB8, 0, 0, 3, 0), (0xBA, 8, 0, 3, 0), (0xBC, 16, 0, 3, 0), (0xBE, 24, 0, 3, 0)],
    "panther_run3_l": [(0xC8, 0, 0, 3, 0), (0xCA, 8, 0, 3, 0), (0xCC, 16, 0, 3, 0), (0xCE, 24, 0, 3, 0)],
}

KIND_BRAZIER, KIND_CANDLE, KIND_PANTHER = 0, 1, 2
ITEM_NONE = 0xFF
ENEMY_PANTHER = 0x51            # enemy group record type: a waiting black panther
ITEM_WHIPUP, ITEM_HEART, ITEM_DAGGER, ITEM_SMALLHEART = 0, 1, 2, 3

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
    "candle1": [(0x40, 4, 8, 3, 0)],
    "candle2": [(0x50, 4, 8, 3, 0)],
    "smallheart": [(0x9F, 4, 8, 3, 0)],
    # zombie: 16x32 like Simon, palette 1; art faces left, flipped for right
    "zombie_l1": [(0x80, 0, 0, 1, 0), (0x82, 8, 0, 1, 0), (0x88, 0, 16, 1, 0), (0x8A, 8, 16, 1, 0)],
    "zombie_l2": [(0x80, 0, 0, 1, 0), (0x82, 8, 0, 1, 0), (0x84, 0, 16, 1, 0), (0x86, 8, 16, 1, 0)],
    "zombie_r1": [(0x82, 0, 0, 1, 1), (0x80, 8, 0, 1, 1), (0x8A, 0, 16, 1, 1), (0x88, 8, 16, 1, 1)],
    "zombie_r2": [(0x82, 0, 0, 1, 1), (0x80, 8, 0, 1, 1), (0x86, 0, 16, 1, 1), (0x84, 8, 16, 1, 1)],
}

# bat: 16x16, palette 3, art faces left (recorded in stage 2); wings 1 2 3 2
for _n, _t in (("bat1", 0x90), ("bat2", 0x94), ("bat3", 0x98)):
    FRAME_SPRITES[_n + "_l"] = [(_t, 0, 0, 3, 0), (_t + 2, 8, 0, 3, 0)]
    FRAME_SPRITES[_n + "_r"] = [(_t + 2, 0, 0, 3, 1), (_t, 8, 0, 3, 1)]

# fishman: 16x32, palette 3, art faces left (recorded in the stage 2
# waterway); legs (bottom tiles) alternate; shooting pose; fireball 8x16
for _n, (_top, _bot) in (("fish_walk1", (0xA0, 0xA4)), ("fish_walk2", (0xA0, 0xA8)),
                         ("fish_shoot", (0xAC, 0x8C))):
    FRAME_SPRITES[_n + "_l"] = [(_top, 0, 0, 3, 0), (_top + 2, 8, 0, 3, 0),
                                (_bot, 0, 16, 3, 0), (_bot + 2, 8, 16, 3, 0)]
    FRAME_SPRITES[_n + "_r"] = [(_top + 2, 0, 0, 3, 1), (_top, 8, 0, 3, 1),
                                (_bot + 2, 0, 16, 3, 1), (_bot, 8, 16, 3, 1)]
FRAME_SPRITES["fireball"] = [(0x68, 4, 0, 3, 0)]

ENEMY_ZOMBIE = 0x01             # spawner types in the enemy group records
ENEMY_BAT = 0x02
ENEMY_FISH = 0x03
SPAWNER_TYPES = (ENEMY_ZOMBIE, ENEMY_BAT, ENEMY_FISH)


def candles(rom, stage, section, level_px):
    """-> list of (box x, box y, item id, kind) for the area's candles.
    Box: x = centre - 8; y = NES y - 64 (brazier box top / candle box top - 8)."""
    def w7(a):
        return rom.fixed(a) | rom.fixed(a + 1) << 8
    table = w7(w7(STAGE_TABLE + 2 * stage) + 2 * section)
    out = []
    for chunk in range(level_px // 64 + 2):
        group = rom.fixed(table + 2 * chunk + 1)
        p = w7(CANDLE_GROUPS[group >> 7] + ((group << 1) & 0xFF))
        b = rom.fixed(p)
        if b == 0:
            continue
        code, k = 0, 0
        if b == 0xFF:
            code, k = rom.fixed(p + 1), 2
        kind = KIND_CANDLE
        if rom.fixed(p + k) == 0xFE:
            kind, k = KIND_BRAZIER, k + 1
        x, y = rom.fixed(p + k), rom.fixed(p + k + 1)
        wx = (chunk - 1) * 64 + x
        if not 8 <= wx < level_px - 8:
            continue
        if code == 4:
            item = ITEM_HEART
        elif code == 8:
            item = ITEM_DAGGER
        elif code == 0 and kind == KIND_BRAZIER:
            item = ITEM_WHIPUP
        else:
            item = ITEM_SMALLHEART
        out.append((wx - 8, y - 64, item, kind))

    # black panthers are single placed enemies: spawned like candles
    for chunk in range(level_px // 64 + 2):
        group = rom.fixed(table + 2 * chunk)
        if group == 0:
            continue
        p = w7(CANDLE_GROUPS[group >> 7] + ((group << 1) & 0xFF))
        if rom.fixed(p) != ENEMY_PANTHER:
            continue
        cx, cy = (chunk - 1) * 64 + rom.fixed(p + 1) - 1, rom.fixed(p + 2)
        if 16 <= cx < level_px - 16:
            # 32x16 box: left = centre - 16, top = NES centre - 8 - 48
            out.append((cx - 16, cy - 56, ITEM_NONE, KIND_PANTHER))
    return out


# Hardware limit: 64 sprite patterns, the first 12 streamed for Simon.
MAX_OBJ_PATTERNS = 64 - 12

ITEM_FRAMES = {ITEM_WHIPUP: "whipup", ITEM_HEART: "heart",
               ITEM_DAGGER: "dagger", ITEM_SMALLHEART: "smallheart"}

# Frames to fold into another one when an area is over the pattern budget,
# least visible loss first.
FOLDS = [("panther_run3_l", "panther_run1_l"), ("panther_run3_r", "panther_run1_r"),
         ("panther_sit_r", "panther_sit_l")]


def needed_frames(candle_list, spawners):
    """-> set of frame names an area can show (others are left empty)."""
    need = {"burst1", "burst2", "burst3", "burst4"}
    for _, _, item, kind in candle_list:
        if kind == KIND_BRAZIER:
            need |= {"brazier1", "brazier2"}
        elif kind == KIND_CANDLE:
            need |= {"candle1", "candle2"}
        else:
            need |= {n for n in OBJ_FRAMES if n.startswith("panther")}
        if item in ITEM_FRAMES:
            need.add(ITEM_FRAMES[item])
    kinds = {k for _, _, k in spawners}
    if ENEMY_ZOMBIE in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("zombie")}
    if ENEMY_BAT in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("bat")}
    if ENEMY_FISH in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("fish")} | {"fireball"}
    return need


def sprite_frames(rom, slot_for_nes, need=None):
    """-> (SpriteBank, names) for the object frames, colours mapped to MSX slots.
    Frames not in `need` are empty. If the patterns don't fit in the hardware's
    free pattern slots, frames from FOLDS reuse another frame's sprites."""
    need = set(OBJ_FRAMES) if need is None else set(need)
    alias = {}
    for drop, keep in [(None, None)] + FOLDS:
        if drop is not None and drop in need:
            alias[drop] = keep
        bank = _build_bank(rom, slot_for_nes, need, alias)
        if len(bank.patterns) <= MAX_OBJ_PATTERNS:
            return bank, list(OBJ_FRAMES)
    raise SystemExit(f"object sprites need {len(bank.patterns)} patterns, "
                     f"only {MAX_OBJ_PATTERNS} available")


def _build_bank(rom, slot_for_nes, need, alias):
    chr_ram = rom.chr_ram()
    pals = [[rom.fixed(SPRITE_PALETTES + p * 4 + v) for v in range(4)] for p in range(4)]
    from msx_sprites import mirror
    frames = dict(FRAME_SPRITES)
    frames.update(PANTHER_LEFT)
    bank = SpriteBank()
    for name in OBJ_FRAMES:
        if name not in need:
            bank.add_frame({}, name)
            continue
        name = alias.get(name, name)
        if name.startswith("panther") and name.endswith("_r"):
            src = name[:-2] + "_l"
            pixels = mirror(_frame_pixels(chr_ram, pals, frames[src], slot_for_nes), width=32)
            bank.add_frame(pixels, name)
            continue
        pixels = {}
        for tile, dx, dy, pal, flip in frames[name]:
            table, top = (tile & 1) * 0x1000, tile & 0xFE
            for half in (0, 1):
                px = tile_pixels(chr_ram, table, top + half)
                for y in range(8):
                    for x in range(8):
                        v = px[y][7 - x if flip else x]
                        if v:
                            pixels[(dx + x, dy + half * 8 + y)] = slot_for_nes(pals[pal][v])
        bank.add_frame(pixels, name)
    return bank


def _frame_pixels(chr_ram, pals, sprites, slot_for_nes):
    pixels = {}
    for tile, dx, dy, pal, flip in sprites:
        table, top = (tile & 1) * 0x1000, tile & 0xFE
        for half in (0, 1):
            px = tile_pixels(chr_ram, table, top + half)
            for y in range(8):
                for x in range(8):
                    v = px[y][7 - x if flip else x]
                    if v:
                        pixels[(dx + x, dy + half * 8 + y)] = slot_for_nes(pals[pal][v])
    return pixels


def enemy_spawners(rom, stage, section, level_px):
    """Zombie and bat spawners of the area -> list of (world x, box y, type). The enemy
    group (first byte of each chunk) indexes the same pointer tables as the
    candle groups; record: type, x, y."""
    def w7(a):
        return rom.fixed(a) | rom.fixed(a + 1) << 8
    table = w7(w7(STAGE_TABLE + 2 * stage) + 2 * section)
    out = []
    for chunk in range(level_px // 64 + 2):
        group = rom.fixed(table + 2 * chunk)
        if group == 0:
            continue
        p = w7(CANDLE_GROUPS[group >> 7] + ((group << 1) & 0xFF))
        kind = rom.fixed(p)
        if kind not in SPAWNER_TYPES:
            continue
        x = (chunk - 1) * 64 + rom.fixed(p + 1)
        if 0 <= x < level_px:
            out.append((x, rom.fixed(p + 2) - 64, kind))
    return out


def write_enemies(path, spawners):
    data = bytearray([len(spawners)])
    for x, y, kind in spawners:
        data += bytes([x & 0xFF, x >> 8, y & 0xFF, kind])
    with open(path, "wb") as f:
        f.write(data)


def write_candles(path, items):
    if len(items) > 64:
        raise SystemExit(f"{len(items)} candles in one area (engine keeps flags for 64)")
    data = bytearray([len(items)])
    for x, y, item, kind in items:
        data += bytes([x & 0xFF, x >> 8, y & 0xFF, item, kind])
    with open(path, "wb") as f:
        f.write(data)
