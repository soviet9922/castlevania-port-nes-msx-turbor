#!/usr/bin/env python3
"""Original placeholder sounds for the PSG (no game data): simple effects and
short tunes written for this port, so the sound player and every trigger
work in any build.

    python3 tools/gen_sound.py <out_dir>

Builds made with SOUND=rom use tools/convert_sound.py instead, which turns
the music and effects of your own NES ROM into the same format.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sound_out                        # noqa: E402

CLOCK = 1789773                         # PSG clock on the MSX


def period(midi):
    f = 440 * 2 ** ((midi - 69) / 12)
    return max(1, min(0xFFF, round(CLOCK / (16 * f))))


def frame(a=None, b=None, c=None, noise=None, va=0, vb=0, vc=0):
    """One frame of PSG registers 0-10. a, b, c: tone periods (None = tone
    off); noise: (period, on channel C) or None."""
    regs = [0] * 11
    mixer = 0x80 | 0x3F
    for ch, p in enumerate((a, b, c)):
        if p is not None:
            regs[2 * ch], regs[2 * ch + 1] = p & 0xFF, p >> 8
            mixer &= ~(1 << ch)
    if noise is not None:
        regs[6] = noise
        mixer &= ~0x20
    regs[7] = mixer
    regs[8], regs[9], regs[10] = va, vb, vc
    return regs


# --- effects (B: tones, C: noise) ---

def sfx_whip():
    return [frame(noise=4 + i, vc=max(0, 13 - 2 * i)) for i in range(8)]


def sfx_hit():
    return ([frame(b=period(76 - 3 * i), vb=13 - i, noise=8, vc=12 - 2 * i) for i in range(6)]
            + [frame()])


def sfx_heart():
    return ([frame(b=period(84), vb=12)] * 4 + [frame(b=period(91), vb=12)] * 6
            + [frame(b=period(91), vb=12 - 2 * i) for i in range(6)])


def sfx_item():
    out = []
    for n in (72, 76, 79, 84, 88):
        out += [frame(b=period(n), vb=13)] * 4
    return out + [frame(b=period(88), vb=12 - 2 * i) for i in range(6)]


def sfx_hurt():
    return [frame(b=period(64 - i), vb=14 - i // 2) for i in range(20)] + [frame()]


def sfx_throw():
    return [frame(noise=2 + i, vc=10 - i) for i in range(10)]


def sfx_holy():
    return [frame(noise=12 + (i * 7) % 8, vc=max(0, 13 - i // 3)) for i in range(36)]


def sfx_stopwatch():
    out = []
    for n in (96, 89, 96, 89):
        out += [frame(b=period(n), vb=12)] * 3 + [frame()] * 5
    return out


def sfx_splash():
    return [frame(noise=20 + i // 4, vc=max(0, 14 - i // 2)) for i in range(28)]


def sfx_door():
    return [frame(noise=31, vc=12 - (i // 4) % 3, b=period(36), vb=8 if i < 30 else 0)
            for i in range(40)] + [frame()]


def sfx_kill():
    return [frame(b=period(70 - 2 * i), vb=12 - i, noise=6 + i, vc=13 - i) for i in range(12)]


def sfx_tick():
    return [frame(b=period(100), vb=11)] * 3 + [frame()]


# --- tunes (original): A melody, B harmony, C bass ---

def tune(bars, step, loop=True):
    """bars: list of (melody, harmony, bass) note lists, one note (MIDI, or
    None for rest) per step; each note sounds for `step` frames with a small
    decay."""
    frames = []
    for mel, har, bas in bars:
        for i in range(len(mel)):
            for t in range(step):
                def v(base, note):
                    return 0 if note is None else max(0, base - t // 3)
                frames.append(frame(a=period(mel[i]) if mel[i] else None,
                                    b=period(har[i]) if har[i] else None,
                                    c=period(bas[i]) if bas[i] else None,
                                    va=v(12, mel[i]), vb=v(9, har[i]), vc=v(11, bas[i])))
    return frames, (0 if loop else None)


def arp(root, minor, n=8):
    third = 3 if minor else 4
    pat = [0, third, 7, 12, 7, third, 0, 7]
    return [root + pat[i % 8] for i in range(n)]


def stage_tune():
    # an original 4-bar loop over Am - F - C - E
    chords = [(57, True), (53, False), (48, False), (52, False)]
    mel = [[69, 72, 76, 74, 72, 71, 69, 71], [69, 72, 77, 76, 74, 72, 74, 72],
           [67, 72, 76, 79, 76, 74, 72, 71], [68, 71, 76, 74, 71, 68, 71, 76]]
    bars = []
    for (root, minor), m in zip(chords, mel):
        bars.append((m, arp(root + 12, minor), [root - 12, None, root - 12, None,
                                                root - 5, None, root - 12, None]))
    return tune(bars, 9)


def boss_tune():
    bars = []
    for root in (50, 50, 46, 48):
        bars.append(([root + 24, None, root + 27, root + 24, root + 31, None, root + 30, root + 27],
                     arp(root + 12, True), [root - 12, root - 12, None, root - 12,
                                            root - 12, None, root - 5, root - 12]))
    return tune(bars, 6)


def clear_tune():
    return tune([([72, 76, 79, 84, 84, 84, None, None], [64, 67, 72, 76, 76, 76, None, None],
                  [48, 48, 48, 48, 48, 48, None, None])], 8, loop=False)


def death_tune():
    return tune([([76, 74, 72, 71, 69, 69, None, None], [72, 71, 69, 68, 64, 64, None, None],
                  [45, None, 44, None, 45, 45, None, None])], 10, loop=False)


def game_over_tune():
    return tune([([69, 67, 65, 64, 62, 64, 57, None], [65, 64, 62, 60, 57, 61, 52, None],
                  [50, None, 46, None, 45, None, 45, None])], 14, loop=False)


SOUNDS = [("STAGE", stage_tune), ("BOSS", boss_tune), ("CLEAR", clear_tune),
          ("DEATH", death_tune), ("GAME_OVER", game_over_tune),
          ("WHIP", sfx_whip), ("HIT", sfx_hit), ("HEART", sfx_heart), ("ITEM", sfx_item),
          ("HURT", sfx_hurt), ("THROW", sfx_throw), ("HOLY", sfx_holy),
          ("STOPWATCH", sfx_stopwatch), ("SPLASH", sfx_splash), ("DOOR", sfx_door),
          ("KILL", sfx_kill), ("TICK", sfx_tick)]


def channel_mask(frames):
    m = 0
    for r in frames:
        for ch in range(3):
            if r[8 + ch]:
                m |= 1 << ch
    return m


def build():
    out = []
    for name, fn in SOUNDS:
        res = fn()
        frames, loop = res if isinstance(res, tuple) else (res, None)
        frames = frames + [frame()]             # end silent
        data, loop_off = sound_out.encode(frames, loop)
        out.append((name, data, loop_off if loop is not None else None,
                    channel_mask(frames)))
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    size, banks = sound_out.write(sys.argv[1], build())
    print(f"placeholder sounds: {size} bytes in {banks} bank(s)")
