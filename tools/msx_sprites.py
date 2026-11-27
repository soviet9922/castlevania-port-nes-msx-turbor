"""Build MSX sprite-mode-2 metasprites from composite pixel images.

A frame is a dict {(x, y): pixel} relative to the player's box top-left,
where pixel is one of
    "A", "B", "C"   player body: layer A only, layer B only, both (OR trick)
    int 1..15       a palette slot drawn with plain single-colour sprites

Body pixels are cut into 16x16 cells on a grid anchored at (0, 0), so the
same legs or head give the same patterns in every frame. Each cell becomes
a layer-A sprite (slot 2) and a layer-B sprite (slot 4, CC bit set so it
ORs with layer A into slot 6).

Single-colour pixels (the whip) are cut into cells anchored at their own
bounding box. MSX sprites can change colour on every line, so one sprite
per cell carries the majority colour of each line; a second sprite is
added only for lines that use two colours. A line with three colours gets a
black silhouette behind the most used other colour, so the third colour
shows as black rather than as a hole.

Outputs (bytes):
    patterns   32 bytes per unique 16x16 pattern
    colors     16 bytes per unique colour column (one byte per line)
    frames     per frame: count, then count x (dy, dx, pattern, colour) (signed dy/dx)
"""

SLOT_A, SLOT_B = 2, 4
BLACK = 1               # palette slot of black (NES $0F)
CC = 0x40
MAX_SPRITES = 16        # hardware sprites per frame (Death 40x48: 14; the engine
                        # draws objects until its 32 slots are used)


def _pattern(cell):
    """cell: set of (x, y) inside 0..15 -> 32 bytes in MSX 16x16 order."""
    out = bytearray(32)
    for x, y in cell:
        out[(x // 8) * 16 + y] |= 0x80 >> (x % 8)
    return bytes(out)


class SpriteBank:
    def __init__(self):
        self.patterns, self.pat_index = [], {}
        self.colors, self.col_index = [], {}
        self.frames = []

    def _pat(self, cell):
        p = _pattern(cell)
        if p not in self.pat_index:
            self.pat_index[p] = len(self.patterns)
            self.patterns.append(p)
        return self.pat_index[p]

    def _col(self, rows):
        c = bytes(rows)
        if c not in self.col_index:
            self.col_index[c] = len(self.colors)
            self.colors.append(c)
        return self.col_index[c]

    def add_frame(self, pixels, name="", max_sprites=None):
        """max_sprites: fewer than MAX_SPRITES: cells get one sprite (their
        second colour merged into the first) until the frame fits"""
        limit = MAX_SPRITES if max_sprites is None else max_sprites
        sprites = []    # (dy, dx, pattern, colour)
        body = {k: v for k, v in pixels.items() if isinstance(v, str)}
        plain = {k: v for k, v in pixels.items() if not isinstance(v, str)}

        cells = sorted({(x // 16, y // 16) for x, y in body}, key=lambda c: (c[1], c[0]))
        for cx, cy in cells:
            ox, oy = cx * 16, cy * 16
            a = {(x - ox, y - oy) for (x, y), v in body.items()
                 if v in "AC" and x // 16 == cx and y // 16 == cy}
            b = {(x - ox, y - oy) for (x, y), v in body.items()
                 if v in "BC" and x // 16 == cx and y // 16 == cy}
            if a:
                sprites.append((oy, ox, self._pat(a), self._col([SLOT_A] * 16)))
            if b:
                cb = (SLOT_B | CC) if a else SLOT_B
                sprites.append((oy, ox, self._pat(b), self._col([cb] * 16)))

        plain_cells = []
        if plain:
            bx = min(x for x, _ in plain)
            by = min(y for _, y in plain)
            cells = sorted({((x - bx) // 16, (y - by) // 16) for x, y in plain},
                           key=lambda c: (c[1], c[0]))
            for cx, cy in cells:
                ox, oy = bx + cx * 16, by + cy * 16
                inside = {(x - ox, y - oy): v for (x, y), v in plain.items()
                          if 0 <= x - ox < 16 and 0 <= y - oy < 16}
                first, second = set(), set()
                c1, c2 = [0] * 16, [0] * 16
                for ly in range(16):
                    line = [(x, v) for (x, y), v in inside.items() if y == ly]
                    if not line:
                        continue
                    counts = {}
                    for _, v in line:
                        counts[v] = counts.get(v, 0) + 1
                    order = sorted(counts, key=lambda v: -counts[v])
                    if len(order) > 2:
                        # three colours, two sprites: the back one is the whole
                        # line in black (or the least used colour), the front
                        # one the most used other colour; the third colour's
                        # pixels show as the back colour instead of holes
                        back = BLACK if BLACK in order else order[-1]
                        front = next(v for v in order if v != back)
                        c1[ly], c2[ly] = front, back
                        first |= {(x, ly) for x, v in line if v == front}
                        second |= {(x, ly) for x, _ in line}
                        continue
                    c1[ly] = order[0]
                    first |= {(x, ly) for x, v in line if v == order[0]}
                    if len(order) > 1:
                        c2[ly] = order[1]
                        second |= {(x, ly) for x, v in line if v == order[1]}
                plain_cells.append([oy, ox, first, c1, second, c2, inside])
        # over the limit: the cells whose second colour has the fewest pixels
        # get one sprite. A picture drawn in one colour (max_sprites given):
        # each line in its most used colour other than black,
        # its black pixels (outlines, shading) left out, so that the picture
        # keeps its details; lines that are only black stay black
        extra = len(sprites) + sum(2 if c[4] else 1 for c in plain_cells) - limit
        for cell in sorted((c for c in plain_cells if c[4]), key=lambda c: len(c[4])):
            if extra <= 0:
                break
            if max_sprites is None:     # (a big frame over the hardware limit:
                oy, ox, first, c1, second, c2, _inside = cell   # black may fill it)
                for ly in range(16):
                    if not c1[ly] and c2[ly]:
                        c1[ly] = c2[ly]
                cell[2], cell[4] = first | second, set()
                extra -= 1
                continue
            inside = cell[6]
            one, col = set(), [0] * 16
            for ly in range(16):
                line = [(x, v) for (x, y), v in inside.items() if y == ly]
                if not line:
                    continue
                lit = [v for _, v in line if v != BLACK]
                if lit:
                    col[ly] = max(set(lit), key=lambda v: (lit.count(v), -v))
                    one |= {(x, ly) for x, v in line if v != BLACK}
                else:
                    col[ly] = BLACK
                    one |= {(x, ly) for x, _ in line}
            cell[2], cell[3], cell[4] = one, col, set()
            extra -= 1
        for oy, ox, first, c1, second, c2, _inside in plain_cells:
            # first sprite in front (lower sprite numbers have priority)
            sprites.append((oy, ox, self._pat(first), self._col(c1)))
            if second:
                sprites.append((oy, ox, self._pat(second), self._col(c2)))

        if len(sprites) > MAX_SPRITES:
            raise SystemExit(f"frame {name}: {len(sprites)} sprites (max {MAX_SPRITES})")
        for line in range(-48, 64):
            n = sum(1 for dy, _, _, _ in sprites if dy <= line < dy + 16)
            if n > 8:
                raise SystemExit(f"frame {name}: {n} sprites on one line (max 8)")
        self.frames.append(sprites)
        return len(self.frames) - 1

    def output(self):
        frames = bytearray()
        offsets = []
        for spr in self.frames:
            offsets.append(len(frames))
            frames.append(len(spr))
            for dy, dx, p, c in spr:
                frames += bytes([dy & 0xFF, dx & 0xFF, p, c])
        if len(self.patterns) > 255 or len(self.colors) > 255:
            raise SystemExit("too many sprite patterns or colour columns")
        return (b"".join(self.patterns), b"".join(self.colors), bytes(frames), offsets)


def mirror(pixels, width=16):
    """Mirror a frame around the centre of the player's 16-px box."""
    return {(width - 1 - x, y): v for (x, y), v in pixels.items()}


def _draw_dy(bank):
    """How far the first frame (standing) ends above the bottom of its 32 px
    box: the engine draws it that much lower so its feet meet the floor."""
    if not bank.frames:
        return 0
    bottom = -1
    for dy, _, p, _ in bank.frames[0]:
        pat = bank.patterns[p]
        for row in range(16):
            if pat[row] or pat[16 + row]:
                bottom = max(bottom, dy + row)
    return max(0, 31 - bottom) if bottom >= 0 else 0


def write_bank(out_dir, bank, frame_names, prefix="player", extra_dy=0):
    """extra_dy: lines added to <PREFIX>_DRAW_DY (the NES shows sprites one
    line below their position). Write <prefix>_spt.bin, _sct.bin, _frames.bin and an include with offsets."""
    import os
    pats, cols, frames, offsets = bank.output()
    for suffix, data in (("spt", pats), ("sct", cols), ("frames", frames)):
        with open(os.path.join(out_dir, f"{prefix}_{suffix}.bin"), "wb") as f:
            f.write(data)
    up = prefix.upper()
    lines = ["; generated sprite frames - do not edit",
             f"{up}_FRAME_COUNT equ {len(offsets)}",
             f"{up}_PATTERNS    equ {len(pats) // 32}",
             f"{up}_DRAW_DY     equ {_draw_dy(bank) + extra_dy}",
             f"{prefix}_frame_table:"]
    for name, off in zip(frame_names, offsets):
        lines.append(f"        dw {prefix}_frames+{off:<5}  ; {name}")
    with open(os.path.join(out_dir, f"{prefix}_frames.inc"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return len(pats) // 32, len(offsets)
