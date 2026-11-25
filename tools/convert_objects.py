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
              "fish_walk1_r", "fish_walk2_r", "fish_shoot_r", "fireball",
              "boss_open", "boss_up", "orb", "dagger_fly_r", "dagger_fly_l",
              "axe1", "axe2", "axe3", "axe4", "bottle", "flame1", "flame2", "flame3",
              "holy_item", "watch_item", "flame4", "flame5", "axe_item", "boss_sleep"]

# Black panther: 32x16, palette 3, art faces left (recorded in the hall).
# Run cycle run1 -> run2 -> run3, 7 frames each; the leap shows run2.
PANTHER_LEFT = {
    "panther_sit_l": [(0xB0, 8, 0, 3, 0), (0xB2, 16, 0, 3, 0), (0xB4, 24, 0, 3, 0)],
    "panther_run1_l": [(0xC0, 0, 0, 3, 0), (0xC2, 8, 0, 3, 0), (0xC4, 16, 0, 3, 0), (0xC6, 24, 0, 3, 0)],
    "panther_run2_l": [(0xB8, 0, 0, 3, 0), (0xBA, 8, 0, 3, 0), (0xBC, 16, 0, 3, 0), (0xBE, 24, 0, 3, 0)],
    "panther_run3_l": [(0xC8, 0, 0, 3, 0), (0xCA, 8, 0, 3, 0), (0xCC, 16, 0, 3, 0), (0xCE, 24, 0, 3, 0)],
}

KIND_BRAZIER, KIND_CANDLE, KIND_PANTHER = 0, 1, 2
KIND_BOSS = 5
ENEMY_BOSS = 0x59               # enemy group record type: the stage 3 boss
ITEM_NONE = 0xFF
ENEMY_PANTHER = 0x51            # enemy group record type: a waiting black panther
ITEM_WHIPUP, ITEM_HEART, ITEM_DAGGER, ITEM_SMALLHEART = 0, 1, 2, 3
ITEM_AXE, ITEM_HOLYWATER, ITEM_STOPWATCH = 4, 5, 6

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

# stage 3 boss (giant bat): 48x32 box, symmetric, palette 3 (recorded in
# stage 3); wings open (48 px wide) and up (32 px); the orb it leaves
_BOSS_OPEN = [0xD0, 0xD2, 0xD4]
FRAME_SPRITES["boss_open"] = (
    [(t, 8 * i, 0, 3, 0) for i, t in enumerate(_BOSS_OPEN)]
    + [(t, 40 - 8 * i, 0, 3, 1) for i, t in enumerate(_BOSS_OPEN)]
    + [(0xD6, 16, 16, 3, 0), (0xD6, 24, 16, 3, 1)])
FRAME_SPRITES["boss_up"] = [(0xD8, 8, 0, 3, 0), (0xDA, 16, 0, 3, 0),
                            (0xDA, 24, 0, 3, 1), (0xD8, 32, 0, 3, 1),
                            (0xDC, 16, 16, 3, 0), (0xDC, 24, 16, 3, 1)]
# asleep, it is a small bat hanging under the ceiling (recorded: tile DE and its
# mirror, 16x16, at the top middle of the box)
FRAME_SPRITES["boss_sleep"] = [(0xDE, 16, 0, 3, 0), (0xDE, 24, 0, 3, 1)]
FRAME_SPRITES["orb"] = [(0x5C, 0, 0, 3, 0), (0x5C, 8, 0, 3, 1)]

# the thrown dagger (recorded): 16x16, palette 2, flipped both ways flying
# right (flip: 1 = horizontal, 2 = vertical); flying left, horizontal flip only
FRAME_SPRITES["dagger_fly_r"] = [(0xBD, 0, 0, 2, 3), (0xBB, 8, 0, 2, 3)]
FRAME_SPRITES["dagger_fly_l"] = [(0xBB, 0, 0, 2, 2), (0xBD, 8, 0, 2, 2)]

# the axe (recorded): 16x16, palette 1, turning: the same two tiles flipped
# four ways, 4 frames each; also its pickup
FRAME_SPRITES["axe1"] = [(0xB7, 0, 0, 1, 0), (0xB9, 8, 0, 1, 0)]
FRAME_SPRITES["axe2"] = [(0xB9, 0, 0, 1, 1), (0xB7, 8, 0, 1, 1)]
FRAME_SPRITES["axe3"] = [(0xB9, 0, 0, 1, 3), (0xB7, 8, 0, 1, 3)]
FRAME_SPRITES["axe4"] = [(0xB7, 0, 0, 1, 2), (0xB9, 8, 0, 1, 2)]
FRAME_SPRITES["axe_item"] = FRAME_SPRITES["axe1"]
# holy water (recorded): the bottle (palette 2, also its pickup) and the fire
# it leaves on the floor (palette 3)
FRAME_SPRITES["bottle"] = [(0x76, 4, 0, 2, 0)]
# the fire (recorded on the hall's floor): 91, 93, 95, then wide 97, 99 (both
# halves, mirrored), 8 frames each, round again, 77 frames in all. Drawn 8 px
# down like the bursts, so that flames 2 and 3 share the bursts' patterns
FRAME_SPRITES["flame1"] = [(0x91, 4, 8, 3, 0)]
FRAME_SPRITES["flame2"] = [(0x93, 4, 8, 3, 0)]
FRAME_SPRITES["flame3"] = [(0x95, 4, 8, 3, 0)]
FRAME_SPRITES["flame4"] = [(0x97, 0, 8, 3, 0), (0x97, 8, 8, 3, 1)]
FRAME_SPRITES["flame5"] = [(0x99, 0, 8, 3, 0), (0x99, 8, 8, 3, 1)]
# pickups shown like the HUD's icons (recorded): holy water, the stopwatch
FRAME_SPRITES["holy_item"] = [(0xA1, 0, 0, 2, 0), (0xA3, 8, 0, 2, 0)]
FRAME_SPRITES["watch_item"] = [(0x89, 0, 0, 2, 0), (0x8B, 8, 0, 2, 0)]

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
        elif code == 0x0D:              # the axe (NES: item $18)
            item = ITEM_AXE
        elif code == 0x0B:              # holy water (NES: item $44)
            item = ITEM_HOLYWATER
        elif code in (0x0E, 0x0F):      # the stopwatch (NES: items $45, $46)
            item = ITEM_STOPWATCH
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
        kind = rom.fixed(p)
        if kind == ENEMY_BOSS:
            # 48x32 box: left = centre - 24, top = NES centre - 8 - 48
            cx, cy = (chunk - 1) * 64 + rom.fixed(p + 1) - 1, rom.fixed(p + 2)
            out.append((cx - 24, cy - 56, ITEM_NONE, KIND_BOSS))
            continue
        if kind != ENEMY_PANTHER:
            continue
        cx, cy = (chunk - 1) * 64 + rom.fixed(p + 1) - 1, rom.fixed(p + 2)
        if 16 <= cx < level_px - 16:
            # 32x16 box: left = centre - 16, top = NES centre - 8 - 48
            out.append((cx - 16, cy - 56, ITEM_NONE, KIND_PANTHER))
    return out


# Hardware limit: 64 sprite patterns, the first 12 streamed for Simon.
MAX_OBJ_PATTERNS = 64 - 12

ITEM_FRAMES = {ITEM_WHIPUP: "whipup", ITEM_HEART: "heart",
               ITEM_DAGGER: "dagger", ITEM_SMALLHEART: "smallheart",
               ITEM_AXE: "axe_item", ITEM_HOLYWATER: "holy_item", ITEM_STOPWATCH: "watch_item"}

# Frames to fold into another one when an area is over the pattern budget,
# least visible loss first.
FOLDS = [("panther_run3_l", "panther_run1_l"), ("panther_run3_r", "panther_run1_r"),
         ("panther_sit_r", "panther_sit_l"), ("axe3", "axe1"), ("axe4", "axe2"),
         ("candle2", "candle1"),
         ("flame5", "flame4"),          # (the fire's two wide flames look alike)
         ("burst4", "burst3"), ("burst2", "burst1"),
         ("fish_walk2_l", "fish_walk1_l"), ("fish_walk2_r", "fish_walk1_r"),
         ("zombie_l2", "zombie_l1"), ("zombie_r2", "zombie_r1"),
         ("flame3", "flame1"), ("flame2", "flame1"), ("flame4", "flame1"), ("axe2", "axe1")]


SUB_FRAMES = {ITEM_DAGGER: {"dagger_fly_r", "dagger_fly_l"},
              ITEM_AXE: {"axe1", "axe2", "axe3", "axe4"},
              ITEM_HOLYWATER: {"bottle", "flame1", "flame2", "flame3", "flame4", "flame5"}}


def needed_frames(candle_list, spawners, carried=()):
    """-> set of frame names an area can show (others are left empty).
    carried: the sub-weapon items Simon can have picked up by now."""
    need = {"burst1", "burst2", "burst3", "burst4"}
    for _, _, item, kind in candle_list:
        if kind == KIND_BRAZIER:
            need |= {"brazier1", "brazier2"}
        elif kind == KIND_CANDLE:
            need |= {"candle1", "candle2"}
        elif kind == KIND_BOSS:
            need |= {"boss_sleep", "boss_open", "boss_up", "orb", "fireball"}
        else:
            need |= {n for n in OBJ_FRAMES if n.startswith("panther")}
        if item in ITEM_FRAMES:
            need.add(ITEM_FRAMES[item])
    # (the flying sub-weapons' frames are not here: only the one Simon holds
    # needs patterns, and it gets a window of its own, see object_sprites)
    kinds = {k for _, _, k in spawners}
    if ENEMY_ZOMBIE in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("zombie")}
    if ENEMY_BAT in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("bat")}
    if ENEMY_FISH in kinds:
        need |= {n for n in OBJ_FRAMES if n.startswith("fish")} | {"fireball"}
    return need


# the engine's sub-weapon numbers (src/ram.inc: subweapon) for the items
SUB_OF_ITEM = {ITEM_DAGGER: 1, ITEM_AXE: 2, ITEM_HOLYWATER: 3}
SUB_SETS = {1: ["dagger_fly_r", "dagger_fly_l"],
            2: ["axe1", "axe2", "axe3", "axe4"],
            3: ["bottle", "flame1", "flame2", "flame3", "flame4", "flame5"]}


# frames that are never on screen together share one window of patterns: an
# area with both zombies and the boss keeps the zombies' patterns there until
# the boss wakes (the screen locks, the zombies go), then the boss's
SWAP_SETS = [["zombie_l1", "zombie_l2", "zombie_r1", "zombie_r2"],
             ["boss_open", "boss_up", "orb"]]


class ObjectSprites:
    """An area's object sprites. The main patterns are always in video memory;
    a window after them holds the patterns of the sub-weapon Simon holds (only
    one can be in the air), loaded when the area starts or the sub-weapon
    changes: subs[n] = that sub-weapon's patterns (numbered from n_main)."""
    def __init__(self, main_spt, sct, frames, offsets, subs, n_main, window,
                 swaps=None, swap_window=0):
        self.main_spt, self.sct, self.frames, self.offsets = main_spt, sct, frames, offsets
        self.subs, self.n_main, self.window = subs, n_main, window
        self.swaps, self.swap_window = swaps or [], swap_window   # SWAP_SETS' patterns

    @property
    def sub_slot(self):
        return self.n_main + self.swap_window


def object_sprites(rom, slot_for_nes, need, carried_items):
    """-> ObjectSprites: frames in `need` in the main patterns, the carried
    sub-weapons' frames in the window; FOLDS applied until it all fits."""
    subs = sorted({SUB_OF_ITEM[i] for i in carried_items if i in SUB_OF_ITEM})
    alias = {}
    for drop, keep in [(None, None)] + FOLDS:
        if drop is not None and (drop in need or any(drop in SUB_SETS[n] for n in subs)):
            alias[drop] = keep
        result = _object_sprites(rom, slot_for_nes, need, subs, alias)
        if result.sub_slot + result.window <= MAX_OBJ_PATTERNS:
            if alias:
                print("  object frames folded to fit:", ", ".join(f"{a}->{b}" for a, b in alias.items()))
            return result
    raise SystemExit(f"object sprites need {result.sub_slot} + {result.window} patterns, "
                     f"only {MAX_OBJ_PATTERNS} available")


def _object_sprites(rom, slot_for_nes, need, subs, alias):
    chr_ram = rom.chr_ram()
    pals = [[rom.fixed(SPRITE_PALETTES + p * 4 + v) for v in range(4)] for p in range(4)]
    main = SpriteBank()
    per_frame = {}                          # name -> (bank, frame index, pattern offset)
    swapping = all(need & set(group) for group in SWAP_SETS)
    swapped = {n for group in SWAP_SETS for n in group} if swapping else set()
    for name in OBJ_FRAMES:
        if name in need and name not in swapped:
            per_frame[name] = (main, main.add_frame(_pixels(chr_ram, pals, alias.get(name, name),
                                                            slot_for_nes), name))
    n_main = len(main.patterns)
    swap_banks = []
    if swapping:
        for group in SWAP_SETS:
            b = _WindowBank(main, n_main)
            b.colors, b.col_index = main.colors, main.col_index
            for name in group:
                if name in need:
                    per_frame[name] = (b, b.add_frame(_pixels(chr_ram, pals, alias.get(name, name),
                                                              slot_for_nes), name))
            swap_banks.append(b)
    swap_window = max([len(b.patterns) for b in swap_banks] + [0])
    sub_banks = {}
    for n in subs:
        b = _WindowBank(main, n_main + swap_window)
        b.colors, b.col_index = main.colors, main.col_index      # one colour table
        for name in SUB_SETS[n]:
            per_frame[name] = (b, b.add_frame(_pixels(chr_ram, pals, alias.get(name, name),
                                                      slot_for_nes), name))
        sub_banks[n] = b
    window = max([len(b.patterns) for b in sub_banks.values()] + [0])
    frames, offsets = bytearray(), []
    for name in OBJ_FRAMES:
        offsets.append(len(frames))
        if name not in per_frame:
            frames.append(0)
            continue
        bank, idx = per_frame[name]
        spr = bank.frames[idx]
        frames.append(len(spr))
        for dy, dx, pat, col in spr:
            frames += bytes([dy & 0xFF, dx & 0xFF, pat, col])
    if len(main.colors) > 255:
        raise SystemExit("too many sprite colour columns")
    return ObjectSprites(b"".join(main.patterns), b"".join(main.colors), bytes(frames), offsets,
                         {n: b"".join(b.patterns) for n, b in sub_banks.items()}, n_main, window,
                         [b"".join(b.patterns) for b in swap_banks], swap_window)


class _WindowBank(SpriteBank):
    """A sub-weapon's frames: patterns the main set already has are used from
    there; the others go into the window after the main patterns."""
    def __init__(self, main, base):
        super().__init__()
        self.main, self.n_main = main, base      # base: the window's first pattern

    def _pat(self, cell):
        from msx_sprites import _pattern
        p = _pattern(cell)
        if p in self.main.pat_index:
            return self.main.pat_index[p]
        return self.n_main + super()._pat(cell)


def _pixels(chr_ram, pals, name, slot_for_nes, use_overrides=True):
    from msx_sprites import mirror
    if use_overrides:                   # an edited frame (tools/sprite_edit.py)
        import sprite_edit
        edited = sprite_edit.load_override(name, slot_for_nes)
        if edited is not None:
            return edited
    frames = dict(FRAME_SPRITES)
    frames.update(PANTHER_LEFT)
    if name.startswith("panther") and name.endswith("_r"):
        return mirror(_frame_pixels(chr_ram, pals, frames[name[:-2] + "_l"], slot_for_nes), width=32)
    return _frame_pixels(chr_ram, pals, frames[name], slot_for_nes)


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
            if alias:
                print("  object frames folded to fit:", ", ".join(f"{a}->{b}" for a, b in alias.items()))
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
                        v = px[y][7 - x if flip & 1 else x]
                        if v:
                            yy = 15 - (half * 8 + y) if flip & 2 else half * 8 + y
                            pixels[(dx + x, dy + yy)] = slot_for_nes(pals[pal][v])
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
                    v = px[y][7 - x if flip & 1 else x]
                    if v:
                        yy = 15 - (half * 8 + y) if flip & 2 else half * 8 + y
                        pixels[(dx + x, dy + yy)] = slot_for_nes(pals[pal][v])
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
