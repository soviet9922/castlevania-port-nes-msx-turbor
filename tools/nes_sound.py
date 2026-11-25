"""Run the NES game's own sound driver (from your ROM) in a 6502 interpreter
and record, frame by frame, the sound-chip state it produces for each sound
number. Used at build time by tools/convert_sound.py; nothing it produces is
committed.

Driver (found in the ROM, see docs/NES_NOTES.md "Sound"):
    PRG bank 0: $8187 starts sound A, $838A is the per-frame update (from NMI)
    six channel slots in zero page $80-$DF (16 bytes each, $02,X = active)
"""

from cpu6502 import CPU

SOUND_BANK = 0
START, UPDATE = 0x8187, 0x838A
SLOTS = range(0x80, 0xE0, 0x10)


class NesSound:
    def __init__(self, rom):
        size = len(rom.prg) // rom.nbanks
        self.prg = [rom.prg[b * size:(b + 1) * size] for b in range(rom.nbanks)]
        self.fixed = self.prg[-1]
        self.bank = SOUND_BANK
        self.ram = bytearray(0x800)
        self.apu = [0] * 0x18
        self.writes = []                # (reg, value) in this frame
        self.cpu = CPU(self._read, self._write)

    def _read(self, a):
        if a < 0x2000:
            return self.ram[a & 0x7FF]
        if a >= 0xC000:
            return self.fixed[a - 0xC000]
        if a >= 0x8000:
            return self.prg[self.bank][a - 0x8000]
        if a == 0x4015:
            return 0
        return 0

    def _write(self, a, v):
        if a < 0x2000:
            self.ram[a & 0x7FF] = v
        elif 0x4000 <= a <= 0x4017:
            self.apu[a - 0x4000] = v
            self.writes.append((a - 0x4000, v))
        elif a >= 0x8000:
            self.bank = v & (len(self.prg) - 1)

    def reset(self):
        self.ram = bytearray(0x800)
        self.apu = [0] * 0x18
        self.bank = SOUND_BANK

    def start(self, n):
        self.bank = SOUND_BANK
        self.cpu.call(START, a=n)

    def frame(self):
        """One frame of the driver -> list of (register, value) writes."""
        self.writes = []
        self.bank = SOUND_BANK
        self.cpu.call(UPDATE)
        return self.writes

    def active(self):
        return any(self.ram[s + 2] for s in SLOTS)

    def state(self):
        """The driver's state (for finding where music loops)."""
        return bytes(self.ram[0x80:0xF0])


def capture(rom, n, max_frames=60 * 240):
    """Sound n -> (frames, loop): frames = list of per-frame write lists;
    loop = index of the frame the music loops back to, or None if it ends."""
    s = NesSound(rom)
    s.start(n)
    frames, seen = [], {}
    for f in range(max_frames):
        st = s.state()
        if st in seen:
            return frames, seen[st]
        seen[st] = f
        frames.append(s.frame())
        if not s.active():
            frames.append(s.frame())     # (the silencing writes)
            return frames, None
    return frames, None
