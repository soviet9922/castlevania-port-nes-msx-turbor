#!/usr/bin/env python3
"""Convert the game's music and sound effects (from your own NES ROM) to MSX
PSG register streams, at build time. Nothing it produces is committed.

    python3 tools/convert_sound.py <rom.nes> <out_dir>

The NES game's sound driver is run in a 6502 interpreter (tools/nes_sound.py)
for each sound; its writes to the NES sound chip (APU) are replayed through a
model of the APU's per-frame state (envelopes, sweeps, length counters, the
triangle's linear counter) and mapped to the PSG every frame:

    pulse 1  -> PSG channel A        (tone period = NES timer + 1)
    pulse 2  -> PSG channel B
    triangle -> PSG channel C        (one octave lower: period = 2 * (timer + 1))
    noise    -> PSG noise, on channel C (C's tone is muted while it sounds)
    DPCM     -> (not converted)

Output, per sound: a stream of frames, each the PSG registers 0-10 that
changed (see encode()); writes sound.inc / sound.asm for the engine.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cv_rom import CastlevaniaROM      # noqa: E402
import nes_sound                        # noqa: E402
import sound_out                        # noqa: E402
from sound_out import encode           # noqa: E402

LENGTHS = [10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
           12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30]
NOISE_PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
TRI_VOLUME = 13                 # the triangle has no volume control
NOISE_BOOST = 0                 # PSG volume steps added to noise

# the engine's sound names -> the NES game's sound numbers (found by logging
# its sound requests while playing; the uncertain ones are marked ?)
NES_SOUNDS = {"STAGE": 0x2A, "STAGE2": 0x2D, "STAGE3": 0x30, "BOSS": 0x42, "CLEAR": 0x48, "DEATH": 0x4E,
              "GAME_OVER": 0x51, "WHIP": 0x0A, "HIT": 0x14, "HEART": 0x18,
              "ITEM": 0x17, "HURT": 0x16, "THROW": 0x08, "HOLY": 0x1E,
              "STOPWATCH": 0x1A, "SPLASH": 0x0F, "DOOR": 0x1D, "KILL": 0x10,
              "TICK": 0x03, "TALLY": 0x04}
# CLEAR (at the orb), DEATH, TICK (timer tally) and TALLY (hearts tally) were
# logged on the NES; uncertain: HURT, SPLASH, DOOR, KILL, HOLY



def psg_volume(v):
    """NES 4-bit (linear) volume -> PSG 4-bit (about 3 dB a step)."""
    if v <= 0:
        return 0
    return max(1, min(15, round(15 + 2 * math.log2(v / 15))))


class Envelope:
    def __init__(self):
        self.start = False
        self.divider = 0
        self.decay = 0

    def clock(self, reg0):
        if self.start:
            self.start = False
            self.decay = 15
            self.divider = reg0 & 15
        elif self.divider == 0:
            self.divider = reg0 & 15
            if self.decay:
                self.decay -= 1
            elif reg0 & 0x20:
                self.decay = 15
        else:
            self.divider -= 1

    def volume(self, reg0):
        return reg0 & 15 if reg0 & 0x10 else self.decay


class Apu:
    """Just enough of the NES APU to know, each frame, each channel's pitch
    and loudness."""
    def __init__(self):
        self.r = [0] * 0x18
        self.len = [0, 0, 0, 0]
        self.env = [Envelope(), Envelope(), None, Envelope()]
        self.timer = [0, 0, 0]
        self.sweep_div = [0, 0]
        self.sweep_reload = [False, False]
        self.lin = 0
        self.lin_reload = False
        self.enabled = 0

    def write(self, reg, v):
        self.r[reg] = v
        if reg in (2, 6, 0xA):
            ch = reg // 4
            self.timer[ch] = (self.timer[ch] & 0x700) | v
        elif reg in (3, 7, 0xB, 0xF):
            ch = reg // 4
            if ch < 3:
                self.timer[ch] = (self.timer[ch] & 0xFF) | (v & 7) << 8
            if self.enabled & (1 << ch):
                self.len[ch] = LENGTHS[v >> 3]
            if ch == 2:
                self.lin_reload = True
            else:
                self.env[ch].start = True
        elif reg in (1, 5):
            self.sweep_reload[reg // 4] = True
        elif reg == 0x15:
            self.enabled = v
            for ch in range(4):
                if not v & (1 << ch):
                    self.len[ch] = 0

    def _halted(self, ch):
        return self.r[8] & 0x80 if ch == 2 else self.r[ch * 4] & 0x20

    def _sweep_target(self, ch):
        t = self.timer[ch]
        s = self.r[ch * 4 + 1]
        c = t >> (s & 7)
        if s & 8:
            return t - c - (1 if ch == 0 else 0)
        return t + c

    def quarter(self):
        for ch in (0, 1, 3):
            self.env[ch].clock(self.r[ch * 4])
        if self.lin_reload:
            self.lin = self.r[8] & 0x7F
        elif self.lin:
            self.lin -= 1
        if not self.r[8] & 0x80:
            self.lin_reload = False

    def half(self):
        for ch in range(4):
            if self.len[ch] and not self._halted(ch):
                self.len[ch] -= 1
        for ch in (0, 1):
            s = self.r[ch * 4 + 1]
            target = self._sweep_target(ch)
            if (self.sweep_div[ch] == 0 and s & 0x80 and s & 7 and self.timer[ch] >= 8
                    and target <= 0x7FF):
                self.timer[ch] = max(0, target)
            if self.sweep_div[ch] == 0 or self.sweep_reload[ch]:
                self.sweep_div[ch] = (s >> 4) & 7
                self.sweep_reload[ch] = False
            else:
                self.sweep_div[ch] -= 1

    def frame_clocks(self):
        for q in range(4):              # 4-step sequence: quarters every step,
            self.quarter()              # halves on steps 2 and 4
            if q in (1, 3):
                self.half()

    def pulse(self, ch):
        """-> (period for the PSG, PSG volume) of pulse ch."""
        t = self.timer[ch]
        muted = (not self.len[ch] or t < 8 or
                 (not self.r[ch * 4 + 1] & 8 and self._sweep_target(ch) > 0x7FF))
        v = 0 if muted else psg_volume(self.env[ch].volume(self.r[ch * 4]))
        return min(t + 1, 0xFFF), v

    def triangle(self):
        t = self.timer[2]
        on = self.len[2] and self.lin and t >= 2
        return min(2 * (t + 1), 0xFFF), (TRI_VOLUME if on else 0)

    def noise(self):
        on = self.len[3]
        v = psg_volume(self.env[3].volume(self.r[0xC])) if on else 0
        if v:
            v = min(15, v + NOISE_BOOST)
        period = max(1, min(31, round(NOISE_PERIODS[self.r[0xE] & 15] / 16)))
        return period, v


def psg_frames(frames):
    """Per-frame NES writes -> per-frame PSG registers 0-10, and which PSG
    channels (bits 0-2: A, B, C) the sound uses."""
    apu = Apu()
    apu.write(0x15, 0x0F)
    out, used = [], 0
    for writes in frames:
        for reg, v in writes:
            apu.write(reg, v)
        apu.frame_clocks()
        pa, va = apu.pulse(0)
        pb, vb = apu.pulse(1)
        pc, vc = apu.triangle()
        pn, vn = apu.noise()
        mixer = 0x80 | 0x38             # port B out; noise off on A, B, C
        if vn:
            mixer &= ~0x20              # noise on C, C's tone off
            mixer |= 0x04
            vc = vn
        regs = [pa & 0xFF, pa >> 8, pb & 0xFF, pb >> 8, pc & 0xFF, pc >> 8,
                pn, mixer, va, vb, vc]
        for ch, v in enumerate((va, vb, vc)):
            if v:
                used |= 1 << ch
        if vn:
            used |= 4
        out.append(regs)
    return out, used


def convert(rom_path, out_dir):
    rom = CastlevaniaROM(rom_path)
    os.makedirs(out_dir, exist_ok=True)
    sounds = []
    for name, n in NES_SOUNDS.items():
        frames, loop = nes_sound.capture(rom, n)
        regs, used = psg_frames(frames)
        data, loop_off = encode(regs, loop)
        sounds.append((name, data, loop_off if loop is not None else None, used))
    return sound_out.write(out_dir, sounds)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    size, banks = convert(sys.argv[1], sys.argv[2])
    print(f"sounds from the ROM: {size} bytes in {banks} bank(s)")
