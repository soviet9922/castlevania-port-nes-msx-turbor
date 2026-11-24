#!/usr/bin/env python3
"""Inspect a Castlevania (NES) ROM image that YOU own.

This repository never contains Konami data. All conversion tools read the
user's own ROM dump and write their output to build/ (which is git-ignored).

Commands:
  info  ROM                 header, mapper, sizes, checksums
  split ROM OUTDIR          write each 16 KB PRG bank to OUTDIR/prgNN.bin
  tiles ROM OUT.png [--bank N] [--offset X] [--count N]
                            render PRG bytes as NES 2bpp tiles, to locate
                            graphics (Castlevania uses CHR-RAM, so its tile
                            graphics are stored inside the PRG banks)
"""

import argparse
import hashlib
import os
import struct
import sys
import zlib

PRG_BANK = 16 * 1024
CHR_BANK = 8 * 1024

EXPECTED = {
    "mapper": 2,            # UxROM (UNROM)
    "prg_size": 128 * 1024,
    "chr_size": 0,          # CHR-RAM
}


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"NES\x1a":
        sys.exit(f"{path}: not an iNES file")
    prg_units, chr_units, f6, f7 = data[4], data[5], data[6], data[7]
    has_trainer = bool(f6 & 0x04)
    nes2 = (f7 & 0x0C) == 0x08
    mapper = (f6 >> 4) | (f7 & 0xF0)
    off = 16 + (512 if has_trainer else 0)
    prg = data[off:off + prg_units * PRG_BANK]
    chr_ = data[off + len(prg):off + len(prg) + chr_units * CHR_BANK]
    return {
        "data": data, "prg": prg, "chr": chr_, "mapper": mapper, "nes2": nes2,
        "mirroring": "vertical" if f6 & 1 else "horizontal",
        "battery": bool(f6 & 2), "trainer": has_trainer,
    }


def cmd_info(args):
    rom = load(args.rom)
    body = rom["prg"] + rom["chr"]
    print(f"file        {args.rom} ({len(rom['data'])} bytes)")
    print(f"format      {'NES 2.0' if rom['nes2'] else 'iNES'}")
    print(f"mapper      {rom['mapper']}")
    print(f"PRG         {len(rom['prg']) // 1024} KB ({len(rom['prg']) // PRG_BANK} banks)")
    print(f"CHR         {len(rom['chr']) // 1024} KB" + (" (CHR-RAM)" if not rom["chr"] else ""))
    print(f"mirroring   {rom['mirroring']}")
    print(f"crc32 (PRG+CHR)  {zlib.crc32(body) & 0xFFFFFFFF:08X}")
    print(f"sha1  (PRG+CHR)  {hashlib.sha1(body).hexdigest()}")
    ok = (rom["mapper"] == EXPECTED["mapper"]
          and len(rom["prg"]) == EXPECTED["prg_size"]
          and len(rom["chr"]) == EXPECTED["chr_size"])
    print("layout      " + ("matches Castlevania (UNROM, 128 KB PRG, CHR-RAM)" if ok
                            else "does NOT match the expected Castlevania layout"))
    return 0 if ok else 1


def cmd_split(args):
    rom = load(args.rom)
    os.makedirs(args.outdir, exist_ok=True)
    prg = rom["prg"]
    for i in range(len(prg) // PRG_BANK):
        p = os.path.join(args.outdir, f"prg{i:02d}.bin")
        with open(p, "wb") as f:
            f.write(prg[i * PRG_BANK:(i + 1) * PRG_BANK])
        print(p)
    return 0


def write_png_gray(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def cmd_tiles(args):
    rom = load(args.rom)
    prg = rom["prg"]
    start = args.bank * PRG_BANK + args.offset
    count = args.count or (PRG_BANK - args.offset) // 16
    data = prg[start:start + count * 16]
    count = len(data) // 16
    per_row, scale = 16, args.scale
    shades = [0, 85, 170, 255]
    tw = per_row * 8
    th = ((count + per_row - 1) // per_row) * 8
    img = [[40] * tw for _ in range(th)]
    for t in range(count):
        lo = data[t * 16:t * 16 + 8]
        hi = data[t * 16 + 8:t * 16 + 16]
        ox, oy = (t % per_row) * 8, (t // per_row) * 8
        for y in range(8):
            for x in range(8):
                v = ((lo[y] >> (7 - x)) & 1) | (((hi[y] >> (7 - x)) & 1) << 1)
                img[oy + y][ox + x] = shades[v]
    rows = []
    for r in img:
        sr = [p for p in r for _ in range(scale)]
        rows.extend([sr] * scale)
    write_png_gray(args.out, tw * scale, th * scale, rows)
    print(f"{args.out}: {count} tiles from PRG offset 0x{start:05X}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("info")
    p.add_argument("rom")
    p.set_defaults(fn=cmd_info)
    p = sub.add_parser("split")
    p.add_argument("rom")
    p.add_argument("outdir")
    p.set_defaults(fn=cmd_split)
    p = sub.add_parser("tiles")
    p.add_argument("rom")
    p.add_argument("out")
    p.add_argument("--bank", type=int, default=0)
    p.add_argument("--offset", type=lambda s: int(s, 0), default=0)
    p.add_argument("--count", type=int, default=0)
    p.add_argument("--scale", type=int, default=2)
    p.set_defaults(fn=cmd_tiles)
    args = ap.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
