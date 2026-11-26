#!/usr/bin/env python3
"""The NES game's own sprite frames, by running its sprite builder (bank 0
$8052) in tools/cpu6502.py on a single object: frame number -> the sprites
it makes, as (tile, dx, dy, palette, flip) relative to the object's
position (its centre), like convert_objects.FRAME_SPRITES.

  nes_frames.py ROM FRAME [FACING]     print a frame's sprites (hex frame)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpu6502 import CPU            # noqa: E402

BUILD_SPRITES = 0x8052             # bank 0: builds OAM from the object arrays
OX, OY = 0x80, 0x80                # where the object is put on screen


def _prg(path):
    d = open(path, "rb").read()
    assert d[:4] == b"NES\x1a"
    return d[16:16 + d[4] * 16384]


def frame_sprites(prg, frame, facing=0, attr=0):
    ram = bytearray(0x800)
    bank0 = prg[0:0x4000]
    fixed = prg[7 * 0x4000:8 * 0x4000]

    def read(a):
        if a < 0x2000:
            return ram[a & 0x7FF]
        if a >= 0xC000:
            return fixed[a - 0xC000]
        if a >= 0x8000:
            return bank0[a - 0x8000]
        return 0

    def write(a, v):
        if a < 0x2000:
            ram[a & 0x7FF] = v

    for o in range(0, 256, 4):             # OAM empty
        ram[0x200 + o] = 0xF4
    for i in range(0x1C):                  # every slot off screen but ours
        ram[0x300 + i] = 1
    s = 3
    ram[0x300 + s] = 0
    ram[0x31C + s] = frame
    ram[0x338 + s] = attr
    ram[0x354 + s] = OY
    ram[0x38C + s] = OX
    ram[0x450 + s] = facing
    cpu = CPU(read, write)
    cpu.call(BUILD_SPRITES, max_steps=200000)
    out = []
    for o in range(0, 256, 4):
        y, t, at, x = ram[0x200 + o:0x204 + o]
        if y == 0xF4 or y >= 0xEF:
            continue
        out.append((t, x - OX, y + 1 - OY, at & 3, (at >> 6) & 3))
    return sorted(out, key=lambda e: (e[2], e[1]))


def main():
    prg = _prg(sys.argv[1])
    frame = int(sys.argv[2], 16)
    facing = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    for t, dx, dy, pal, flip in frame_sprites(prg, frame, facing):
        print(f"tile {t:02X}  dx {dx:4d}  dy {dy:4d}  pal {pal}  flip {flip}")


if __name__ == "__main__":
    main()
