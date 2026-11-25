"""Write a set of PSG sound streams for the engine (src/sound.asm):

    sound.inc         SOUND_COUNT, SND_<NAME> numbers and snd_table (8 bytes
                      a sound: bank, pointer, loop bank, loop pointer,
                      channel mask, unused); included in the code bank
    sound_banks.asm   the streams, packed into the ROM banks after Simon's
                      sprite bank (a stream may run on into the next bank)
    snd_bank<n>.bin   one file per sound bank

Used by tools/gen_sound.py (the original placeholder sounds) and
tools/convert_sound.py (sounds converted from your own ROM).
"""

import os


def encode(regs_frames, loop):
    """PSG frames -> bytes. A frame that changes registers: a mask byte
    (0x01-0x7F: bits 0-5 = registers 0-5 follow, bit 6 = a second mask byte
    follows with bits 0-4 = registers 6-10), then the new values in register
    order. Control bytes: 0x80-0xFC = wait 1-125 frames (no change);
    0xFD = loop (to the sound's loop point); 0xFE = end. The first frame, and
    the loop's first frame, write every register."""
    out = bytearray()
    loop_off = None
    prev = None
    wait = 0

    def flush():
        nonlocal wait
        while wait:
            n = min(wait, 125)
            out.append(0x7F + n)
            wait -= n

    for i, regs in enumerate(regs_frames):
        if i == loop:
            flush()
            loop_off = len(out)
            prev = None
        changed = [r for r in range(11) if prev is None or regs[r] != prev[r]]
        prev = regs
        if not changed:
            wait += 1
            continue
        flush()
        m1 = sum(1 << r for r in changed if r < 6)
        m2 = sum(1 << (r - 6) for r in changed if r >= 6)
        if m2:
            out += bytes([m1 | 0x40, m2])
        else:
            out.append(m1)
        out += bytes(regs[r] for r in changed)
    flush()
    out.append(0xFD if loop is not None else 0xFE)
    return bytes(out), (loop_off if loop_off is not None else 0)

FIRST_BANK = 8                  # after the code, area and sprite banks
BANK_SIZE = 0x4000
MAX_BANKS = 8                   # ROM: 16 banks in all (256 KB)

# names the engine uses (src/sound.asm callers); a set may leave some out
NAMES = ["STAGE", "BOSS", "CLEAR", "DEATH", "GAME_OVER",
         "WHIP", "HIT", "HEART", "ITEM", "HURT", "THROW", "HOLY", "STOPWATCH",
         "SPLASH", "DOOR", "KILL", "TICK"]


def write(out_dir, sounds):
    """sounds: list of (name, data bytes, loop offset or None, channel mask)."""
    blob = bytearray()
    table = []
    for name, data, loop, mask in sounds:
        start = len(blob)
        blob += data
        lp = start + (loop if loop is not None else 0)
        table.append((name, start, lp, mask))
    banks = (len(blob) + BANK_SIZE - 1) // BANK_SIZE
    if banks > MAX_BANKS:
        raise SystemExit(f"sound data needs {banks} banks, only {MAX_BANKS}")

    def where(off):
        return FIRST_BANK + off // BANK_SIZE, 0x8000 + off % BANK_SIZE

    inc = ["; generated sound table - do not edit",
           f"SOUND_COUNT equ {len(table)}"]
    numbers = {name: i for i, (name, *_rest) in enumerate(table)}
    for n in NAMES:
        inc.append(f"SND_{n:<10} equ {numbers.get(n, 0xFF)}")
    inc.append("snd_table:")
    for name, start, lp, mask in table:
        b, a = where(start)
        lb, la = where(lp)
        inc.append(f"        db {b}, {a & 0xFF}, {a >> 8}, {lb}, {la & 0xFF}, {la >> 8}, {mask}, 0"
                   f"  ; {name}")
    if not table:
        inc.append("        db 0")
    with open(os.path.join(out_dir, "sound.inc"), "w") as f:
        f.write("\n".join(inc) + "\n")

    asm = ["; generated: sound banks - do not edit"]
    for k in range(MAX_BANKS):
        chunk = bytes(blob[k * BANK_SIZE:(k + 1) * BANK_SIZE])
        asm += ["", f"; ---- bank {FIRST_BANK + k}: sound ----", "        ORG 0x8000"]
        if chunk:
            path = f"snd_bank{FIRST_BANK + k}.bin"
            with open(os.path.join(out_dir, path), "wb") as f:
                f.write(chunk)
            asm.append(f'        INCBIN "{path}"')
        asm.append("        ds 0xC000-$, 0xFF")
    with open(os.path.join(out_dir, "sound_banks.asm"), "w") as f:
        f.write("\n".join(asm) + "\n")
    return len(blob), banks
