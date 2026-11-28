"""Write areas.asm: one 16 KB ROM bank per area, each starting with a header.

The engine maps an area's bank at 0x8000 and copies its header to RAM
(src/area.asm). Header layout (must match AH_* in src/config.inc):

  +0  palette            +2..+12 bg patterns / colours for bands 0..2
  +14..+18 bg sizes (bytes) for bands 0..2
  +20 level_tiles        +22 level_coll         +24 tile columns
  +26 max camera x       +28 start x            +30 start y
  +32 candle list        +34 object patterns    +36 object pattern bytes
  +38 object colours     +40 object frame table
  +42 exit x (0xFFFF = none)   +44 next area   +45 blank tile
  +46 stairs (count, then 7 bytes each: foot x, foot y, top x, top y, dir)
  +48 enemy spawners (count, then 4 bytes each: x, y, type)
  +50 exit only when Simon's y <= this (0xFF = at any height)
  +51 area below, +52 area above (sections joined by stairs; 0xFF = none)
  +53 area to restart in after a fall or death
  +54 stage number for the HUD (BCD)
  +55 exit kind (0 at once, 1 castle gate, 2 door), +56 door tile column,
  +58 camera x while the door opens, +60 first of the door's 6 extra tile columns
  (half open, open; or for the castle gate, +56 is where Simon goes behind it),
  +62 the x Simon walks on to after the door shuts, +64 the camera x the
  screen scrolls on to (both: where the next area starts)
  +66 patterns of the flying dagger, axe, holy water (0 = none here), +72 their
  sizes, +78 the pattern slot of the sub-weapon window (after the main ones)
  +79 patterns of the swap window's two sets (zombies, then the boss; 0 = no
  swapping here), +83 their sizes, +87 the swap window's pattern slot
  +88 least camera x, +90 the music (SND_ number), +91 Simon's start facing
  (0 right, 1 left), +92 1 = the exit (door) is at the left end, +93 the
  door's top playfield row, +94 ceiling crushers (count, then x, phase and
  cycle each), +96 the first of their hidden tile columns

Banks: 0 code, 7 Simon's sprites (and the RAM code), 8 and up the sound
streams (as many as tools/sound_out.py filled); the others are packed: one
for the RAM overlays, and every area's two pieces, first fit from the
largest: its run-time piece (header, map, collision, object tables: mapped at
0x8000 while the area is played) and its graphics (palette, background tiles,
sprite patterns, the windows' pictures: mapped only while they are copied,
AH_SWAP_BANK). A bank with run-time pieces starts with their header
addresses; area_tab.inc (in the RAM code) has per area its bank | slot << 5.
The ROM is the smallest power of 2 of 16 KB banks that holds it all.
"""

import json

import os

PLAYER_BANK = 7
SOUND_FIRST = 8                 # tools/sound_out.py FIRST_BANK
SOUND_MAX = 8
BANK = 0x4000
MIN_BANKS = 16                  # 256 KB at least


def window_lines(i, a):
    """the pictures copied into an area's windows: sub-weapons, swap sets,
    power-up items"""
    p, d = f"a{i}_", a["dir"]
    return ([line for n in a.get("subs", [])
             for line in (f'{p}sub{n}_spt: INCBIN "{d}/{p}sub{n}_spt.bin"', f"{p}sub{n}_end:")]
            + [line for n in range(a.get("swaps", 0))
               for line in (f'{p}swap{n}_spt: INCBIN "{d}/{p}swap{n}_spt.bin"', f"{p}swap{n}_end:")]
            + [line for c in a.get("items", [])
               for line in (f'{p}item{c}_spt: INCBIN "{d}/{p}item{c}_spt.bin"', f"{p}item{c}_end:")])


def _size(gen_dir, a, name):
    path = os.path.join(gen_dir, a["dir"], name)
    return os.path.getsize(path) if os.path.exists(path) else 0


def _opt(gen_dir, a, label, name):
    """an INCBIN of the area's file, or one 0 byte (an empty list)"""
    if os.path.exists(os.path.join(gen_dir, a["dir"], name)):
        return f'{label}: INCBIN "{a["dir"]}/{name}"'
    return f"{label}: db 0"


def runtime_lines(gen_dir, i, a):
    p, d = f"a{i}_", a["dir"]
    exit_x = a.get("exit_x")
    return [
        f"{p}header:",
        f"        dw {p}palette",
        f"        dw {p}pgt0, {p}ct0, {p}pgt1, {p}ct1, {p}pgt2, {p}ct2",
        "        dw " + ", ".join(str(n * 8) for n in a["bg_tiles"]),
        f"        dw {p}tiles, {p}coll, {a['tcols']}, {a.get('max_cam', a['width'] - 256)}",
        f"        dw {a['start_x']}, {a['start_y'] & 0xFFFF}",
        f"        dw {p}candles, {p}obj_spt, {a['obj_patterns'] * 32}, {p}obj_sct, {p}obj_frame_table",
        f"        dw {exit_x if exit_x is not None else 0xFFFF}",
        f"        db {a.get('next_area', 0)}, 0x{a['blank']:02X}",
        f"        dw {p}stairs, {p}enemies",
        f"        db {a.get('exit_y', 0xFF)}, {a.get('below', 0xFF)}, {a.get('above', 0xFF)}, "
        f"{a.get('respawn', i)}, 0x{a.get('stage_no', 1):02d}, {a.get('exit_kind', 0)}",
        f"        dw {a.get('door_col', 0)}, {a.get('door_cam', 0)}, {a.get('door_vcol', 0)}, "
        f"{a.get('walk_end', 0)}, {a.get('cam_end', 0)}",
        "        dw " + ", ".join(f"{p}sub{n}_spt" if n in a.get("subs", []) else "0" for n in (1, 2, 3)),
        "        dw " + ", ".join(f"{p}sub{n}_end-{p}sub{n}_spt" if n in a.get("subs", []) else "0"
                                 for n in (1, 2, 3)),
        f"        db {a.get('sub_slot', 0)}",
        "        dw " + ", ".join(f"{p}swap{n}_spt" if n < a.get("swaps", 0) else "0" for n in (0, 1)),
        "        dw " + ", ".join(f"{p}swap{n}_end-{p}swap{n}_spt" if n < a.get("swaps", 0) else "0"
                                 for n in (0, 1)),
        f"        db {a.get('swap_slot', 0)}",
        f"        dw {a.get('min_cam', 0)}",
        f"        db SND_{a.get('music', 'STAGE')}, {a.get('start_face', 0)}, {a.get('exit_left', 0)}, "
        f"{a.get('door_row', 2)}",
        f"        dw {p}crushers, {a.get('crush_vcol', 0)}",
        f"        dw {p}swap_tab",
        f"        db GFX_BANK_{i}",
        f"        dw {p}item_tab",
        f"        db {a.get('item_slot', 0)}",
        f"        dw {p}sub5_spt, {p}sub5_end-{p}sub5_spt" if 5 in a.get("subs", []) else "        dw 0, 0",
        f"        dw {p}walls",
        f"        dw {p}treasures",
        f"        dw {p}platforms",
        f"        dw {p}ctiles",
        f"{p}header_end:",
        f"        ASSERT {p}header_end - {p}header == AH_SIZE",
        f'{p}tiles:   INCBIN "{d}/level_tiles.bin"',
        f'{p}coll:    INCBIN "{d}/level_coll.bin"',
        f'{p}candles: INCBIN "{d}/candles.bin"',
        f'{p}stairs:  INCBIN "{d}/stairs.bin"',
        f'{p}enemies: INCBIN "{d}/enemies.bin"',
        f'{p}crushers: INCBIN "{d}/crushers.bin"' if a.get('crush_vcol') else f"{p}crushers: db 0",
        _opt(gen_dir, a, f"{p}walls", "walls.bin"),
        _opt(gen_dir, a, f"{p}treasures", "treasures.bin"),
        _opt(gen_dir, a, f"{p}platforms", "platforms.bin"),
        _opt(gen_dir, a, f"{p}ctiles", "ctiles.bin"),
        f"{p}item_tab:                   ; (code, ptr, size) per power-up picture, 0xFF ends",
        *[f"        db {c}\n        dw {p}item{c}_spt, {p}item{c}_end-{p}item{c}_spt"
          for c in a.get("items", [])],
        "        db 0xFF",
        f"{p}swap_tab:",
        *[f"        dw {p}swap{n}_spt, {p}swap{n}_end-{p}swap{n}_spt" for n in range(a.get("swaps", 0))],
        "        dw 0, 0",
        f'{p}obj_sct: INCBIN "{d}/{p}obj_sct.bin"',
        f'{p}obj_frames: INCBIN "{d}/{p}obj_frames.bin"',
        f'        INCLUDE "{d}/{p}obj_frames.inc"',
    ]


def runtime_size(gen_dir, i, a):
    inc = os.path.join(gen_dir, a["dir"], f"a{i}_obj_frames.inc")
    n_frames = open(inc).read().count("dw ") if os.path.exists(inc) else 0
    files = ["level_tiles.bin", "level_coll.bin", "candles.bin", "stairs.bin", "enemies.bin",
             f"a{i}_obj_sct.bin", f"a{i}_obj_frames.bin"]
    opt = ["crushers.bin", "walls.bin", "treasures.bin", "platforms.bin", "ctiles.bin"]
    return (128 + sum(_size(gen_dir, a, n) for n in files)
            + sum(max(1, _size(gen_dir, a, n)) for n in opt)
            + 2 * n_frames + 5 * len(a.get("items", [])) + 1 + 4 * a.get("swaps", 0) + 4 + 16)


def gfx_lines(gen_dir, i, a):
    p, d = f"a{i}_", a["dir"]
    out = [f'{p}palette: INCBIN "{d}/palette.bin"']
    for b in range(3):
        out += [f'{p}pgt{b}:    INCBIN "{d}/bg_pgt_b{b}.bin"',
                f'{p}ct{b}:     INCBIN "{d}/bg_ct_b{b}.bin"']
    out += [f'{p}obj_spt: INCBIN "{d}/{p}obj_spt.bin"']
    return out + window_lines(i, a)


def gfx_size(gen_dir, i, a):
    files = ["palette.bin", f"a{i}_obj_spt.bin"]
    files += [f"bg_{t}_b{b}.bin" for t in ("pgt", "ct") for b in range(3)]
    files += [f"a{i}_sub{n}_spt.bin" for n in a.get("subs", [])]
    files += [f"a{i}_swap{n}_spt.bin" for n in range(a.get("swaps", 0))]
    files += [f"a{i}_item{c}_spt.bin" for c in a.get("items", [])]
    return sum(_size(gen_dir, a, n) for n in files) + 16


def write(gen_dir, areas):
    """areas: list of dicts with keys dir, tcols, bg_tiles, blank, start_x,
    start_y, width, obj_patterns, exit_x, next_area, name. Saved to
    areas.json, so that the layout can be made again once the sound banks
    are known (python3 tools/areas_asm.py GEN_DIR)."""
    keep = [{k: v for k, v in a.items() if k not in ("tile_map", "extra_tiles")} for a in areas]
    with open(os.path.join(gen_dir, "areas.json"), "w") as f:
        json.dump(keep, f)
    layout(gen_dir, keep)


def layout(gen_dir, areas):
    sound = [b for b in range(SOUND_FIRST, SOUND_FIRST + SOUND_MAX)
             if os.path.exists(os.path.join(gen_dir, f"snd_bank{b}.bin"))]
    fixed = {0, PLAYER_BANK, *sound}
    # pieces: (size, kind, area)
    pieces = [(runtime_size(gen_dir, i, a), "run", i) for i, a in enumerate(areas)]
    pieces += [(gfx_size(gen_dir, i, a), "gfx", i) for i, a in enumerate(areas)]
    for size, kind, i in pieces:
        if size > BANK - 2:
            raise SystemExit(f"area {i}'s {kind} piece is {size} bytes: more than a bank")
    banks = {}                          # bank -> {"used": n, "run": [areas], "gfx": [areas]}
    ovl_bank = next(b for b in range(1, 256) if b not in fixed)
    fixed.add(ovl_bank)

    def free_banks():
        b = 1
        while True:
            if b not in fixed:
                yield b
            b += 1
    for size, kind, i in sorted(pieces, key=lambda t: (-t[0], t[1], t[2])):
        need = size + (2 if kind == "run" else 0)
        for b in free_banks():
            slot = banks.setdefault(b, {"used": 0, "run": [], "gfx": []})
            if slot["used"] + need <= BANK and (kind != "run" or len(slot["run"]) < 8):
                slot["used"] += need
                slot[kind].append(i)
                break
    last = max([PLAYER_BANK, ovl_bank, *sound, *banks])
    total = MIN_BANKS
    while total <= last:
        total *= 2
    if max(banks) > 31:
        raise SystemExit("the areas need banks past 31 (area_bank_tab keeps 5 bits)")
    where = {}
    for b, slot in banks.items():
        for k, i in enumerate(slot["run"]):
            where[i] = (b, k)
    gfx_bank = {i: b for b, slot in banks.items() for i in slot["gfx"]}

    out = ["; generated by tools/areas_asm.py - do not edit",
           f"AREA_COUNT equ {len(areas)}",
           f"ROM_BANKS equ {total}",
           f"OVL_BANK equ {ovl_bank}",
           f"PLAYER_BANK equ {PLAYER_BANK}"]
    out += [f"GFX_BANK_{i} equ {b}" for i, b in sorted(gfx_bank.items())]
    for b in range(1, total):
        out += ["", f"; ---- bank {b} ----", "        ORG 0x8000"]
        if b == PLAYER_BANK:
            out += ["; Simon's sprite patterns and colours, and the RAM code",
                    'player_spt:     INCBIN "player_spt.bin"         ; 32 bytes per 16x16 pattern',
                    'player_sct:     INCBIN "player_sct.bin"         ; 16 colour bytes per sprite',
                    'player_frames:  INCBIN "player_frames.bin"      ; count, then (dy, dx, pattern, colour)',
                    '        INCLUDE "player_frames.inc"             ; player_frame_table (build_sat maps this bank)',
                    '        INCLUDE "ramcode.asm"           ; code run from RAM (copied at start-up)']
        elif b in sound:
            out += [f'        INCBIN "snd_bank{b}.bin"         ; sound (tools/sound_out.py)']
        elif b == ovl_bank:
            out += ['        INCLUDE "overlays.asm"     ; RAM overlays (copied by load_area)']
        elif b in banks:
            slot = banks[b]
            out += ["; the run-time pieces' headers"]
            out += [f"        dw a{i}_header" for i in slot["run"]]
            for i in slot["run"]:
                out += [f"; area {i} ({areas[i]['name']}): run-time"] + runtime_lines(gen_dir, i, areas[i])
            for i in slot["gfx"]:
                out += [f"; area {i} ({areas[i]['name']}): graphics"] + gfx_lines(gen_dir, i, areas[i])
        out += [f"bank{b}_end:", f"        ASSERT bank{b}_end <= 0xC000", "        ds 0xC000-$, 0xFF"]
    with open(os.path.join(gen_dir, "areas.asm"), "w") as f:
        f.write("\n".join(out) + "\n")
    tab = ["; generated by tools/areas_asm.py - do not edit",
           "; per area: its run-time piece's bank | its slot in the bank's header list << 5",
           "area_bank_tab:"]
    tab += [f"        db {where[i][0] | where[i][1] << 5}   ; {a['name']}" for i, a in enumerate(areas)]
    with open(os.path.join(gen_dir, "area_tab.inc"), "w") as f:
        f.write("\n".join(tab) + "\n")
    used = sum(s["used"] for s in banks.values())
    print(f"layout: {total} banks ({total * 16} KB): areas in {len(banks)} banks "
          f"({used // 1024} KB), sound banks {sound}, overlays bank {ovl_bank}")


if __name__ == "__main__":
    import sys
    d = sys.argv[1]
    with open(os.path.join(d, "areas.json")) as f:
        layout(d, json.load(f))
