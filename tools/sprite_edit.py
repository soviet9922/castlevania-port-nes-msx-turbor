#!/usr/bin/env python3
"""Export object sprite frames from your own NES ROM as BMP files to edit, and
read edited ones back (the converter uses them instead of the ROM's pixels).

    python3 tools/sprite_edit.py export castlevania.nes zombie_l1 zombie_l2 ...
    python3 tools/sprite_edit.py export castlevania.nes --all

Files go to art_overrides/ (git-ignored: they are made from the ROM, so they
must never be committed). Each frame is a 24-bit BMP at 1:1 size; magenta
(255, 0, 255) is transparent. Edit them with any paint program, keeping the
size and using the frame's NES colours (any other colour is taken as the
nearest NES colour). Delete a file to go back to the ROM's pixels.

Standard library only.
"""

import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVERRIDE_DIR = os.path.join(ROOT, "art_overrides")
TRANSPARENT = (255, 0, 255)

# a common NES (2C02) palette, used for both export and import so colours
# round-trip exactly
NES_RGB = [
    (84, 84, 84), (0, 30, 116), (8, 16, 144), (48, 0, 136), (68, 0, 100), (92, 0, 48),
    (84, 4, 0), (60, 24, 0), (32, 42, 0), (8, 58, 0), (0, 64, 0), (0, 60, 0), (0, 50, 60),
    (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (152, 150, 152), (8, 76, 196), (48, 50, 236), (92, 30, 228), (136, 20, 176),
    (160, 20, 100), (152, 34, 32), (120, 60, 0), (84, 90, 0), (40, 114, 0), (8, 124, 0),
    (0, 118, 40), (0, 102, 120), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (236, 238, 236), (76, 154, 236), (120, 124, 236), (176, 98, 236), (228, 84, 236),
    (236, 88, 180), (236, 106, 100), (212, 136, 32), (160, 170, 0), (116, 196, 0),
    (76, 208, 32), (56, 204, 108), (56, 180, 204), (60, 60, 60), (0, 0, 0), (0, 0, 0),
    (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236),
    (236, 174, 212), (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120),
    (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (0, 0, 0), (0, 0, 0),
]


def override_path(name):
    return os.path.join(OVERRIDE_DIR, f"{name}.bmp")


def write_bmp(path, width, height, pixels):
    """pixels: {(x, y): (r, g, b)}; others transparent (magenta)."""
    row = (width * 3 + 3) & ~3
    data = bytearray()
    for y in range(height - 1, -1, -1):
        line = bytearray()
        for x in range(width):
            r, g, b = pixels.get((x, y), TRANSPARENT)
            line += bytes([b, g, r])
        data += line + bytes(row - len(line))
    head = struct.pack("<2sIHHI", b"BM", 54 + len(data), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(data), 2835, 2835, 0, 0)
    with open(path, "wb") as f:
        f.write(head + info + data)


def read_bmp(path):
    """-> (width, height, {(x, y): (r, g, b)}) without the transparent pixels.
    Reads uncompressed 24/32-bit and 8-bit (palette) BMPs."""
    d = open(path, "rb").read()
    if d[:2] != b"BM":
        raise SystemExit(f"{path}: not a BMP file")
    off = struct.unpack_from("<I", d, 10)[0]
    hsize, w, h, _, bpp, comp = struct.unpack_from("<IiiHHI", d, 14)
    if comp not in (0, 3):
        raise SystemExit(f"{path}: compressed BMPs are not supported, save it uncompressed")
    flip = h > 0
    h = abs(h)
    pal = []
    if bpp == 8:
        n = struct.unpack_from("<I", d, 46)[0] or 256
        p = 14 + hsize
        pal = [(d[p + 4 * i + 2], d[p + 4 * i + 1], d[p + 4 * i]) for i in range(n)]
    elif bpp not in (24, 32):
        raise SystemExit(f"{path}: {bpp}-bit BMPs are not supported (use 8, 24 or 32)")
    row = ((w * bpp + 31) // 32) * 4
    out = {}
    for y in range(h):
        base = off + (h - 1 - y if flip else y) * row
        for x in range(w):
            if bpp == 8:
                rgb = pal[d[base + x]]
            else:
                q = base + x * (bpp // 8)
                rgb = (d[q + 2], d[q + 1], d[q])
            if rgb != TRANSPARENT:
                out[(x, y)] = rgb
    return w, h, out


def nearest_nes(rgb):
    return min(range(64), key=lambda i: (sum((a - b) ** 2 for a, b in zip(NES_RGB[i], rgb)), i))


def load_override(name, slot_for_nes):
    """The edited frame as {(x, y): slot}, or None if there is none."""
    path = override_path(name)
    if not os.path.exists(path):
        return None
    _, _, px = read_bmp(path)
    return {k: slot_for_nes(nearest_nes(v)) for k, v in px.items()}


def export(rom_path, names):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import convert_objects as co
    from cv_rom import CastlevaniaROM
    rom = CastlevaniaROM(rom_path)
    chr_ram = rom.chr_ram()
    pals = [[rom.fixed(co.SPRITE_PALETTES + p * 4 + v) for v in range(4)] for p in range(4)]
    os.makedirs(OVERRIDE_DIR, exist_ok=True)
    for name in names:
        px = co._pixels(chr_ram, pals, name, lambda nes: nes, use_overrides=False)
        if not px:
            continue
        w = max(x for x, _ in px) + 1
        h = max(y for _, y in px) + 1
        w, h = max(w, 16), max(h, 16)
        path = override_path(name)
        if os.path.exists(path):
            print(f"{path}: exists, not overwritten (delete it to export again)")
            continue
        write_bmp(path, w, h, {k: NES_RGB[v] for k, v in px.items()})
        print(f"wrote {path} ({w}x{h})")


def main():
    args = sys.argv[1:]
    if len(args) < 3 or args[0] != "export":
        raise SystemExit(__doc__)
    rom, names = args[1], args[2:]
    if names == ["--all"]:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import convert_objects as co
        names = list(co.OBJ_FRAMES)
    export(rom, names)


if __name__ == "__main__":
    main()
