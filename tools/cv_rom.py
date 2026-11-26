"""Readers for Castlevania (NES) ROM data structures.

Everything here was worked out from the user's own ROM (see docs/NES_NOTES.md).
No game data is stored in this file, only addresses and formats.
"""

PRG_BANK = 0x4000

# CHR-RAM loader: index -> pointer at CHR_SET_TABLE, list of 7-byte records
# (bank, src lo/hi, ppu dst lo/hi, length lo/hi), terminated by $FF.
CHR_SET_TABLE = 0xFDC2          # fixed bank

# Stage layout data (bank 4 = block 1: stages 1-3)
#   map:    6 block numbers per 32-pixel column, top to bottom
#   blocks: 17 bytes each = attribute byte + 4x4 tile numbers (row-major)
STAGE_LAYOUTS = {
    # name: (bank, map start, map end, block table base)
    "1-courtyard": (4, 0x800A, 0x8082, 0x830A),
}

# Palette strings in the fixed bank: $3F $00, 16 colours, $FE
STAGE_PALETTES = {
    "1-courtyard": 0xCE28,
    "2-castle": 0xCE3B,         # block 2 (stages 4-6), read from the PPU
}

GAMEPLAY_CHR_SET = 3            # loaded when a game starts
# Block 2 (stages 4-6) loads set 4 over set 3 when it starts: replaying both
# reproduces stage 4's pattern tables exactly (checked against the PPU)
BLOCK_CHR_SETS = {1: (3,), 2: (3, 4)}
BG_PATTERN_TABLE = 0x1000


class CastlevaniaROM:
    def __init__(self, path):
        data = open(path, "rb").read()
        if data[:4] != b"NES\x1a":
            raise ValueError("not an iNES file")
        n = data[4]
        self.prg = data[16:16 + n * PRG_BANK]
        self.nbanks = n
        self.chr_sets = (GAMEPLAY_CHR_SET,)     # chr_ram()'s default (per block)
        mapper = (data[6] >> 4) | (data[7] & 0xF0)
        if mapper != 2 or n != 8 or data[5] != 0:
            raise ValueError("this is not the expected Castlevania ROM layout")

    # CPU-address read in a given bank (bank 7 is fixed at $C000)
    def rd(self, bank, addr):
        base = 0xC000 if bank == self.nbanks - 1 else 0x8000
        return self.prg[bank * PRG_BANK + addr - base]

    def rd16(self, bank, addr):
        return self.rd(bank, addr) | self.rd(bank, addr + 1) << 8

    def fixed(self, addr):
        return self.rd(self.nbanks - 1, addr)

    def chr_ram(self, sets=None):
        """Replay the game's CHR-RAM loader for the given sets (default:
        self.chr_sets, the block being converted)."""
        if sets is None:
            sets = self.chr_sets
        ram = bytearray(0x2000)
        for n in sets:
            y = self.rd16(7, CHR_SET_TABLE + 2 * n)
            while self.fixed(y) != 0xFF:
                bank = self.fixed(y)
                src = self.rd16(7, y + 1)
                dst = self.rd16(7, y + 3)
                ln = self.rd16(7, y + 5)
                y += 7
                off = bank * PRG_BANK + src - 0x8000
                ram[dst:dst + ln] = self.prg[off:off + ln]
        return ram

    def palette(self, stage):
        a = STAGE_PALETTES[stage]
        assert self.fixed(a) == 0x3F and self.fixed(a + 1) == 0x00
        return [self.fixed(a + 2 + i) for i in range(16)]

    def stage_map(self, stage):
        """-> list of columns, each a list of 6 (attribute, 16 tiles) blocks."""
        bank, start, end, blocks = STAGE_LAYOUTS[stage]
        cols = []
        for a in range(start, end, 6):
            col = []
            for r in range(6):
                n = self.rd(bank, a + r)
                b = blocks + 17 * n
                attr = self.rd(bank, b)
                tiles = [self.rd(bank, b + 1 + i) for i in range(16)]
                col.append((attr, tiles))
            cols.append(col)
        return cols

    def stage_nametable(self, stage):
        """-> (tiles[row][col], palette_index[row][col]) for 24 tile rows."""
        cols = self.stage_map(stage)
        w = len(cols) * 4
        tiles = [[0] * w for _ in range(24)]
        pals = [[0] * w for _ in range(24)]
        for c, col in enumerate(cols):
            for r, (attr, t) in enumerate(col):
                for y in range(4):
                    for x in range(4):
                        tiles[r * 4 + y][c * 4 + x] = t[y * 4 + x]
                        quad = (y // 2) * 2 + (x // 2)
                        pals[r * 4 + y][c * 4 + x] = (attr >> (quad * 2)) & 3
        return tiles, pals


def tile_pixels(chr_ram, table, n):
    """8x8 list of 2-bit colour indices for tile n of a pattern table."""
    o = table + n * 16
    lo, hi = chr_ram[o:o + 8], chr_ram[o + 8:o + 16]
    return [[((lo[y] >> (7 - x)) & 1) | (((hi[y] >> (7 - x)) & 1) << 1)
             for x in range(8)] for y in range(8)]


def load_nes_palette(path=None):
    """64 RGB triples. Uses an installed FCEUX palette file if available."""
    candidates = [path] if path else [
        "/usr/share/fceux/palettes/nestopia_yuv.pal",
        "/usr/share/fceux/palettes/FCEU-15-nitsuja_new.pal",
    ]
    for p in candidates:
        try:
            raw = open(p, "rb").read()
        except (OSError, TypeError):
            continue
        return [tuple(raw[i * 3:i * 3 + 3]) for i in range(64)]
    raise SystemExit("no NES palette file found; pass --nes-palette FILE.pal")
