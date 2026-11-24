#!/usr/bin/env python3
"""Headless smoke test: boot the ROM in openMSX, play a few seconds, check RAM.

Uses the free C-BIOS MSX2+ machine (V9958), so no copyrighted system ROMs
are needed. Screenshots are written to build/test/ for manual inspection.

Requires: openmsx, and either a $DISPLAY or xvfb-run.
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
ROM = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(BUILD, "cvmsx.rom")
SYM = os.path.splitext(ROM)[0] + ".sym"
OUT = os.path.join(BUILD, "test", os.path.splitext(os.path.basename(ROM))[0])
MACHINE = os.environ.get("TEST_MACHINE", "C-BIOS_MSX2+")

# RAM variable -> size in bytes
WATCH = {"frame_count": 2, "line_irq_count": 2, "px": 2, "py": 2, "cam_x": 2,
         "on_ground": 1, "facing": 1, "scroll_r26": 1, "scroll_r27": 1}


def load_symbols():
    syms = {}
    with open(SYM) as f:
        for line in f:
            m = re.match(r"^(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
            if m:
                syms[m.group(1)] = int(m.group(2), 16)
    return syms


def tcl_script(syms, result_file):
    def dump(tag):
        parts = []
        for name, size in WATCH.items():
            a = syms[name]
            expr = f"[peek {a}]" if size == 1 else f"([peek {a}] + 256*[peek {a + 1}])"
            parts.append(f"{name}=[expr {{{expr}}}]")
        line = " ".join(parts)
        return (f'set f [open "{result_file}" a]; puts $f "{tag} {line}"; close $f; '
                f'screenshot -raw "{OUT}/{tag}.png"')

    fc = syms["frame_count"]
    py = syms["py"]
    # keyboard matrix row 8: bit0 SPACE, bit4 LEFT, bit7 RIGHT
    # Times are relative to the moment the game's main loop is running.
    return f"""
# normal speed: with "throttle off" openMSX skips rendering and screenshots are black
proc play {{}} {{
    after time 0.5  {{ {dump('01_boot')}; keymatrixdown 8 0x80 }}
    after time 3.5  {{ {dump('02_walk_right')}; keymatrixup 8 0x80 }}
    after time 3.7  {{ keymatrixdown 8 0x01; rec_py 60 }}
    after time 3.8  {{ keymatrixup 8 0x01 }}
    after time 4.0  {{ {dump('03_jump')} }}
    after time 5.0  {{ {dump('04_landed')}; keymatrixdown 8 0x10 }}
    after time 6.0  {{ {dump('05_walk_left')}; keymatrixup 8 0x10 }}
    after time 6.1  {{ exit }}
}}
# record py (signed) once per game frame, sampled when the VBLANK interrupt
# updates frame_count (game logic for the frame has finished by then)
set ::jumpy {{}}
set ::jump_left 0
proc sample_py {{}} {{
    if {{$::jump_left <= 0}} return
    set v [expr {{[peek {py}] + 256*[peek {py + 1}]}}]
    if {{$v >= 32768}} {{ set v [expr {{$v - 65536}}] }}
    lappend ::jumpy $v
    incr ::jump_left -1
    if {{$::jump_left == 0}} {{
        set f [open "{result_file}" a]; puts $f "jumpy $::jumpy"; close $f
    }}
}}
proc rec_py {{n}} {{ set ::jump_left $n }}
debug set_watchpoint write_mem {fc} {{}} sample_py
proc wait_game {{}} {{
    # wait until the main loop has run ~30 frames (C-BIOS logo comes first)
    if {{[peek {fc}] + 256*[peek {fc + 1}] < 30 || [peek {fc + 1}] > 0x20}} {{
        after time 0.1 wait_game
    }} else {{
        play
    }}
}}
after time 0.1 wait_game
after time 60 {{ exit }}
"""


def run():
    if not os.path.exists(ROM):
        sys.exit("build the ROM first (make)")
    syms = load_symbols()
    os.makedirs(OUT, exist_ok=True)
    result_file = os.path.join(OUT, "results.txt")
    if os.path.exists(result_file):
        os.remove(result_file)
    script = os.path.join(OUT, "smoke.tcl")
    with open(script, "w") as f:
        f.write(tcl_script(syms, result_file))

    cmd = ["openmsx", "-machine", MACHINE, "-cart", ROM, "-romtype", "ASCII16",
           "-script", script]
    if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a"] + cmd
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if not os.path.exists(result_file):
        print(proc.stdout, proc.stderr)
        sys.exit("FAIL: openMSX produced no results")

    snaps = {}
    jump_y = []
    with open(result_file) as f:
        for line in f:
            tag, *kv = line.split()
            if tag == "jumpy":
                jump_y = [int(v) for v in kv]
                continue
            snaps[tag] = {k: int(v) for k, v in (x.split("=") for x in kv)}

    # expected jump: the table's 20 rising steps, then the same steps mirrored
    gen = "converted" if os.path.basename(ROM).startswith("cvmsx-nes") else "placeholder"
    table = [b - 256 if b >= 128 else b
             for b in open(os.path.join(BUILD, "gen", gen, "player_jump.bin"), "rb").read()]
    expected_arc = table + [-v for v in reversed(table)]
    deltas = [b - a for a, b in zip(jump_y, jump_y[1:])]
    while deltas and deltas[0] == 0:
        deltas.pop(0)
    # the arc may legitimately end with zero steps; compare the first 40 frames
    actual_arc = deltas[:len(expected_arc)]
    actual_arc += [0] * (len(expected_arc) - len(actual_arc))
    for tag, vals in snaps.items():
        print(f"{tag:16} " + " ".join(f"{k}={v}" for k, v in vals.items()))

    def s16(v):
        return v - 65536 if v >= 32768 else v

    boot, walk, jump, land, left = (snaps[t] for t in
                                    ("01_boot", "02_walk_right", "03_jump",
                                     "04_landed", "05_walk_left"))
    checks = [
        # 3 s of emulated time between boot and walk_right snapshots
        ("main loop runs at 60 fps", 170 <= walk["frame_count"] - boot["frame_count"] <= 190),
        ("line interrupt split runs every frame",
         abs((walk["line_irq_count"] - boot["line_irq_count"])
             - (walk["frame_count"] - boot["frame_count"])) <= 2),
        ("player starts on the ground", boot["on_ground"] == 1),
        ("walking right moves the player", walk["px"] > boot["px"] + 100),
        ("camera scrolls", walk["cam_x"] > 0),
        ("camera keeps player at lead position", walk["px"] - walk["cam_x"] == 120),
        # registers are latched in VBLANK, so they may lag the camera by a frame
        ("scroll registers follow camera",
         any(walk["scroll_r26"] == ((c + 7) >> 3) & 31 and walk["scroll_r27"] == (-c) & 7
             for c in (walk["cam_x"], walk["cam_x"] - 1))),
        ("jump leaves the ground", s16(jump["py"]) < s16(walk["py"]) - 8
         and jump["on_ground"] == 0),
        ("player lands again", land["on_ground"] == 1
         and land["py"] == walk["py"]),
        ("jump follows the jump table frame by frame", actual_arc == expected_arc),
        ("walking left turns the player", left["facing"] == 1
         and left["px"] < land["px"]),
    ]
    failed = 0
    for name, ok in checks:
        print(("PASS " if ok else "FAIL ") + name)
        failed += not ok
    print(f"screenshots in {OUT}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
