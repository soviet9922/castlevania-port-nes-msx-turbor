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
         "on_ground": 1, "facing": 1, "scroll_r26": 1, "scroll_r27": 1,
         "pframe": 1, "whip_active": 1, "whip_x1": 2, "whip_x2": 2,
         "hearts": 1, "obj_table": 1,     # obj_table = type of object slot 0
         "cur_area": 1, "stair_state": 1, "hp": 1, "hurt_state": 1, "invuln_t": 1,
         "kills": 1}


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
    pf, wa = syms["pframe"], syms["whip_active"]
    irq_vbl, vbl_done, load = syms["irq_vblank"], syms["vblank_done"], syms["load_area"]
    waitf = syms["wait_frame"]
    px_a, fa, obj = syms["px"], syms["facing"], syms["obj_table"]
    exit_x = syms["area_hdr"] + 42      # AH_EXITX
    stairs = syms["area_hdr"] + 46      # AH_STAIRS
    eoff, hurt, objt = syms["enemies_off"], syms["hurt_state"], syms["obj_table"]
    obj_size = 12                       # OBJ_SIZE in src/config.inc
    cand = syms["area_hdr"] + 32        # AH_CANDLES
    cdead = syms["candle_dead"]
    cur = syms["cur_area"]
    areas = syms.get("AREA_COUNT", 1)
    # with more than one area: walk into the exit (courtyard gate) and on
    hall = f"""
    after time 9.0  {{ poke {eoff} 3; poke {px_a} [peek {exit_x}]; poke {px_a + 1} [peek {exit_x + 1}] }}
    after time 11.6 {{ {dump('09_next_area')}; keymatrixdown 8 0x80 }}
    after time 13.9 {{ {dump('10_next_area_walk')}; keymatrixup 8 0x80
                       # first staircase of the area (if any): stand 6 px right of its foot
                       set sp [expr {{[peek {stairs}] + 256*[peek {stairs + 1}]}}]
                       set ::nst [peek $sp]
                       if {{$::nst > 0}} {{
                           set fx [expr {{[peek [expr {{$sp+1}}]] + 256*[peek [expr {{$sp+2}}]] + 6}}]
                           poke {px_a} [expr {{$fx & 255}}]; poke {px_a + 1} [expr {{$fx >> 8}}]
                           set f [open "{result_file}" a]
                           puts $f "stair foot=[expr {{[peek [expr {{$sp+1}}]] + 256*[peek [expr {{$sp+2}}]]}}],[peek [expr {{$sp+3}}]] top=[expr {{[peek [expr {{$sp+4}}]] + 256*[peek [expr {{$sp+5}}]]}}],[peek [expr {{$sp+6}}]]"
                           close $f
                       }} }}
    after time 14.1 {{ keymatrixdown 8 0x20 }}
    after time 17.1 {{ keymatrixup 8 0x20; {dump('11_stairs_up')}; keymatrixdown 8 0x40 }}
    after time 20.1 {{ keymatrixup 8 0x40; {dump('12_stairs_down')}
                       # zombies on: stand near the hall's start and wait to be hit
                       poke {eoff} 2; poke {px_a} 200; poke {px_a + 1} 0; set ::wait_hit 1 }}
    after time 30.5 {{ if {{[peek {exit_x}] != 255}} {{
                           # the hall's door: on the upper floor, 24 px before the exit
                           set ::hunting 0; poke {eoff} 3
                           set x [expr {{[peek {exit_x}] + 256*[peek {exit_x + 1}] - 24}}]
                           poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                           poke {py} [expr {{[peek {exit_x + 8}] - 8}}]; poke {py + 1} 0
                           keymatrixdown 8 0x80 }} }}
    after time 36.5 {{ keymatrixup 8 0x80; {dump('18_through_the_door')}
                       set f [open "{result_file}" a]
                       puts $f "seqs gate=$::gate_seen,$::gate_px0,$::gate_pxmax door=$::door_cam,$::door_opened,$::door_closed"
                       close $f
                       # a staircase that leads to the section below (foot off the playfield)
                       set sp [expr {{[peek {stairs}] + 256*[peek {stairs + 1}]}}]
                       for {{set i 0}} {{$i < [peek $sp]}} {{incr i}} {{
                           set r [expr {{$sp + 1 + 7*$i}}]
                           if {{[peek [expr {{$r+2}}]] > 176 && [peek [expr {{$r+5}}]] < 176}} {{
                               set x [expr {{[peek [expr {{$r+3}}]] + 256*[peek [expr {{$r+4}}]] + 4}}]
                               poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                               poke {py} [peek [expr {{$r+5}}]]; poke {py + 1} 0
                               keymatrixdown 8 0x40
                               break
                           }}
                       }} }}
    after time 38.5 {{ keymatrixup 8 0x40; {dump('19_section_below')}; keymatrixdown 8 0x20 }}
    after time 40.5 {{ keymatrixup 8 0x20; {dump('20_section_above')}
                       # bats: enemies on, wait for one and whip it
                       set ::bat_seen 0; poke {eoff} 0; set ::hunting 1
                       poke {syms["bat_spawn_t"]} 150 }}
    after time 44.5 {{ set ::hunting 0; poke {eoff} 3; {dump('21_bat')}
                       set f [open "{result_file}" a]; puts $f "bat $::bat_seen"; close $f
                       # back down into the waterway
                       set sp [expr {{[peek {stairs}] + 256*[peek {stairs + 1}]}}]
                       for {{set i 0}} {{$i < [peek $sp]}} {{incr i}} {{
                           set r [expr {{$sp + 1 + 7*$i}}]
                           if {{[peek [expr {{$r+2}}]] > 176 && [peek [expr {{$r+5}}]] < 176}} {{
                               set x [expr {{[peek [expr {{$r+3}}]] + 256*[peek [expr {{$r+4}}]] + 4}}]
                               poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                               poke {py} [peek [expr {{$r+5}}]]; poke {py + 1} 0
                               keymatrixdown 8 0x40
                               break
                           }}
                       }} }}
    after time 46.6 {{ keymatrixup 8 0x40
                       # fishmen: stand on the walkway, enemies on, whip what comes
                       set ::fish_seen 0; poke {px_a} 150; poke {px_a + 1} 0; poke {py} 48; poke {py + 1} 0
                       poke {eoff} 0; set ::hunting 1 }}
    after time 54 {{ set ::hunting 0; poke {eoff} 3; {dump('22_fishmen')}
                       set f [open "{result_file}" a]; puts $f "fish $::fish_seen"; close $f }}
    after time 54.2 {{ # up the stairs from the waterway (foot on the playfield, top off it)
                       set sp [expr {{[peek {stairs}] + 256*[peek {stairs + 1}]}}]
                       for {{set i 0}} {{$i < [peek $sp]}} {{incr i}} {{
                           set r [expr {{$sp + 1 + 7*$i}}]
                           if {{[peek [expr {{$r+2}}]] < 176 && [peek [expr {{$r+5}}]] > 176}} {{
                               set x [expr {{[peek $r] + 256*[peek [expr {{$r+1}}]] + 4}}]
                               poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                               poke {py} [peek [expr {{$r+2}}]]; poke {py + 1} 0
                               keymatrixdown 8 0x20
                               break
                           }}
                       }} }}
    after time 56.5 {{ keymatrixup 8 0x20; {dump('23_back_up')}
                       # stage 2's door: on the ledge, 24 px before the exit
                       if {{[peek {exit_x}] != 255}} {{
                           set x [expr {{[peek {exit_x}] + 256*[peek {exit_x + 1}] - 24}}]
                           poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                           poke {py} [expr {{[peek {exit_x + 8}] - 8}}]; poke {py + 1} 0
                           keymatrixdown 8 0x80 }} }}
    after time 62.5 {{ keymatrixup 8 0x80; {dump('24_stage3')}
                       # a fishman's fireball at standing height, flying at crouching Simon
                       # (back at the area's start, away from the stairs)
                       poke {eoff} 3; poke {px_a} 40; poke {px_a + 1} 0
                       keymatrixdown 8 0x40; fireball_at_simon }}
    after time 64 {{ {dump('25_crouched_fireball')}; keymatrixup 8 0x40 }}
    after time 65.5 {{ fireball_at_simon }}
    after time 66.8 {{ {dump('26_standing_fireball')}
                       # the boss: stand on the ledge at the end of stage 3
                       if {{[peek {cur}] == 4}} {{
                           poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                           poke {py} 64; poke {py + 1} 0; set ::boss_hunt 1 }} }}
    after time 73.5 {{ set ::boss_hunt 0
                       # on the floor at the screen's left edge: unlocked, the camera would follow
                       poke {px_a} [expr {{524 & 255}}]; poke {px_a + 1} [expr {{524 >> 8}}]
                       poke {py} 128; poke {py + 1} 0; keymatrixdown 8 0x10 }}
    after time 74 {{ keymatrixup 8 0x10; {dump('27a_boss_left')}
                       poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                       poke {py} 64; poke {py + 1} 0; set ::boss_hunt 1 }}
    after time 74.1 {{ # wait on the floor without whipping: the boss must come down
                       set ::boss_hunt 0; set ::boss_floor 1
                       poke {px_a} [expr {{700 & 255}}]; poke {px_a + 1} [expr {{700 >> 8}}]
                       poke {py} 128; poke {py + 1} 0 }}
    after time 74.15 {{ {dump('27b_floor_start')} }}
    after time 79 {{ {dump('27c_floor_end')}; set ::boss_floor 0
                       # fireballs: boss hovering at the screen's left, Simon on the ledge far right
                       boss_place 512 1; poke {px_a} [expr {{750 & 255}}]; poke {px_a + 1} [expr {{750 >> 8}}]
                       poke {py} 64; poke {py + 1} 0 }}
    after time 79.3 {{ set ::boss_fire [count_type 9]
                       # and close to Simon: no fireball
                       clear_type 9; boss_place 700 0 }}
    after time 79.6 {{ set ::boss_near_fire [count_type 9]
                       set f [open "{result_file}" a]; puts $f "boss_maxy $::boss_maxy"; close $f
                       poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                       poke {py} 64; poke {py + 1} 0; set ::boss_hunt 1 }}
    after time 79.5 {{ {dump('27_boss')}
                       set f [open "{result_file}" a]; puts $f "boss_hp [peek {syms["boss_hp"]}] $::boss_awake"; close $f
                       poke {syms["boss_hp"]} 1 }}
    after time 79.7 {{ boss_place 0 0 }}
    after time 85.5 {{ set ::boss_hunt 0; {dump('28_boss_dead')}
                       # walk onto the orb
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 11}} {{
                               poke {px_a} [peek [expr {{$b+1}}]]; poke {px_a + 1} [peek [expr {{$b+2}}]]
                               poke {py} [expr {{[peek [expr {{$b+3}}]] - 16}}]; poke {py + 1} 0
                               set ::orb_seen 1
                           }}
                       }} }}
    after time 86 {{ {dump('29_stage_clear')}
                       set f [open "{result_file}" a]; puts $f "orb $::orb_seen [peek {syms["clear_t"]}] $::boss_fire $::boss_near_fire"; close $f }}
    after time 90 {{ {dump('30_restart')}; rules "after_clear"
                       # time runs out: death animation, then a life is lost
                       poke {syms["time_bcd"]} 1; poke {syms["time_bcd"] + 1} 0; poke {syms["time_t"]} 60 }}
    after time 90.7 {{ rules "dying"; {dump('31_dying')} }}
    after time 93 {{ rules "after_death"
                       # the last life: game over, then a new game
                       poke {syms["lives"]} 0
                       poke {syms["time_bcd"]} 1; poke {syms["time_bcd"] + 1} 0; poke {syms["time_t"]} 60 }}
    after time 95.1 {{ rules "game_over" }}
    after time 99 {{ rules "new_game"
                       # the chain whip
                       poke {syms["whip_level"]} 1; poke {fa} 0; set ::wpn_tag chain; set ::wpn_on 1
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 99.8 {{ wpn_report
                       # the morning star
                       poke {syms["whip_level"]} 2; set ::wpn_tag star; set ::wpn_on 1
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 100.6 {{ wpn_report
                       # the dagger: 60 px left of the first brazier, UP + whip
                       set bx [expr {{[peek {obj + 1}] + 256*[peek {obj + 2}] - 60}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {fa} 0; poke {syms["subweapon"]} 1; poke {syms["hearts"]} 10
                       set ::wpn_tag dagger; set ::wpn_on 1; set ::dagger_xs {{}}
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 101.8 {{ wpn_report
                       # the axe: standing still, UP + whip
                       poke {syms["subweapon"]} 2; poke {syms["hearts"]} 10; poke {fa} 0
                       set ::wpn_tag axe; set ::wpn_on 1; set ::sub_track {{}}
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 103.5 {{ wpn_report
                       # holy water, 40 px left of the second brazier
                       set bx [expr {{[peek {obj + 1 + obj_size}] + 256*[peek {obj + 2 + obj_size}] - 40}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {syms["subweapon"]} 3; poke {syms["hearts"]} 10; poke {fa} 0
                       set ::wpn_tag holy; set ::wpn_on 1; set ::sub_track {{}}; set ::brazier_x [peek {obj + 1 + obj_size}]
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 105.5 {{ wpn_report
                       # the stopwatch: on the hall's floor with zombies about
                       poke {syms["subweapon"]} 4; poke {syms["hearts"]} 10 }}
    after time 105.6 {{ sub_report "watch_hud" }}
    after time 105.7 {{ # a zombie in front of Simon, enemies on; UP + whip
                       poke {eoff} 2
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 0}} {{
                               set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + 90}}]
                               poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
                               poke [expr {{$b+3}}] [peek {py}]; poke [expr {{$b+4}}] 1; poke [expr {{$b+5}}] 255
                               poke [expr {{$b+7}}] 0; poke [expr {{$b+8}}] 255; poke $b 5
                               set ::zslot $b
                               break
                           }}
                       }}
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.2 {{ keymatrixup 8 0x20 }} }}
    after time 105.9 {{ sub_report "watch_start" }}
    after time 107.5 {{ sub_report "watch_frozen"; poke {eoff} 3; {dump('35_stopwatch')} }}
    after time 109.5 {{ sub_report "watch_end"
                       # the drop rule: an axe item while Simon holds the axe -> a heart
                       poke {syms["subweapon"]} 2
                       set b [expr {{{objt} + 7*{obj_size}}}]
                       poke [expr {{$b+1}}] 100; poke [expr {{$b+2}}] 0; poke [expr {{$b+3}}] 60
                       poke [expr {{$b+4}}] 0; poke [expr {{$b+5}}] 4; poke [expr {{$b+6}}] 2; poke $b 2 }}
    after time 110.1 {{ sub_report "drop_rule" }}
    after time 110.3 {{ set f [open "{result_file}" a]; puts $f "vblank_us [expr {{int($::vbl_worst)}}]"; puts $f "overruns $::overruns $::frames"; close $f; exit }}
""" if areas > 1 else f"""
    after time 9.0  {{ set f [open "{result_file}" a]; puts $f "vblank_us [expr {{int($::vbl_worst)}}]"; puts $f "overruns $::overruns $::frames"; close $f; exit }}
"""
    # keyboard matrix row 8: bit0 SPACE, bit4 LEFT, bit7 RIGHT
    # Times are relative to the moment the game's main loop is running.
    return f"""
# normal speed: with "throttle off" openMSX skips rendering and screenshots are black
proc play {{}} {{
    set ::vbl_on 1
    after time 0.5  {{ {dump('01_boot')}; keymatrixdown 8 0x80 }}
    after time 3.5  {{ {dump('02_walk_right')}; keymatrixup 8 0x80 }}
    after time 3.7  {{ keymatrixdown 8 0x01; rec_py 60 }}
    after time 3.8  {{ keymatrixup 8 0x01 }}
    after time 4.0  {{ {dump('03_jump')} }}
    after time 5.0  {{ {dump('04_landed')}; keymatrixdown 8 0x10 }}
    after time 6.0  {{ {dump('05_walk_left')}; keymatrixup 8 0x10 }}
    after time 6.3  {{ keymatrixdown 4 0x04; rec_whip 40 }}
    after time 6.4  {{ keymatrixup 4 0x04 }}
    after time 6.55 {{ {dump('06_whip_strike')} }}
    # brazier: stand 26 px left of the first one, facing right, and whip it
    after time 7.2  {{ set bx [expr {{[peek {obj + 1}] + 256*[peek {obj + 2}] - 26}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {fa} 0 }}
    after time 7.3  {{ keymatrixdown 4 0x04 }}
    after time 7.35 {{ keymatrixup 4 0x04 }}
    after time 8.1  {{ {dump('07_brazier_hit')}; keymatrixdown 8 0x80 }}
    after time 8.6  {{ keymatrixup 8 0x80 }}
    after time 8.8  {{ {dump('08_item_collected')}
                       set f [open "{result_file}" a]
                       puts $f "hud_hearts [format %c [vpeek {0x1800 + 32 + 24}]][format %c [vpeek {0x1800 + 32 + 25}]]"
                       close $f }}
{hall}
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
# record "pose:whip_active" once per game frame while whipping
set ::whipseq {{}}
set ::whip_left 0
proc sample_whip {{}} {{
    if {{$::whip_left <= 0}} return
    lappend ::whipseq "[peek {pf}]:[peek {wa}]"
    incr ::whip_left -1
    if {{$::whip_left == 0}} {{
        set f [open "{result_file}" a]; puts $f "whipseq $::whipseq"; close $f
    }}
}}
proc rec_whip {{n}} {{ set ::whip_left $n }}
debug set_watchpoint write_mem {fc} {{}} sample_whip
debug set_watchpoint write_mem {fc} {{}} sample_py
# worst time from the VBLANK interrupt to the end of the main loop's VBLANK work
set ::vbl_t0 0
set ::vbl_worst 0
set ::vbl_on 0
set ::vbl_fc 0
# frames whose logic was still running when the next VBLANK came (overruns)
set ::waiting 0
set ::frames 0
set ::overruns 0
proc vbl_start {{}} {{
    set ::vbl_t0 [machine_info time]; set ::vbl_fc [peek {fc}]
    if {{$::vbl_on}} {{ incr ::frames; if {{!$::waiting}} {{ incr ::overruns; set ::vbl_t0 -1 }} }}
}}
debug set_bp {waitf} {{}} {{ set ::waiting 1 }}
proc vbl_end {{}} {{
    if {{!$::vbl_on}} return
    # area loading spans several frames with the display off: not VBLANK work
    # skip loads (display off) and the first frames after one
    if {{$::vbl_skip > 0}} {{ incr ::vbl_skip -1; return }}
    set ::waiting 0
    if {{(([peek {fc}] - $::vbl_fc) & 255) > 1 || $::vbl_t0 < 0}} return
    set dt [expr {{([machine_info time] - $::vbl_t0) * 1e6}}]
    if {{$dt > $::vbl_worst}} {{ set ::vbl_worst $dt }}
}}
debug set_bp {irq_vbl} {{}} vbl_start
debug set_bp {vbl_done} {{}} vbl_end
set ::vbl_skip 0
debug set_bp {load} {{}} {{ set ::vbl_skip 4 }}
# zombie test: snapshot when hit, then whip any zombie that comes in reach
set ::wait_hit 0
set ::hunting 0
set ::bat_seen 0
set ::fish_seen 0
# panther test: no more zombies; stand on the floor within the first
# panther's wake distance and let the hunter whip it
proc panther_test {{}} {{
    poke {eoff} 1
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] == 5}} {{ poke $b 0 }}
    }}
    set c [expr {{[peek {cand}] + 256*[peek {cand + 1}]}}]
    set n [peek $c]
    for {{set i 0}} {{$i < $n}} {{incr i}} {{
        set r [expr {{$c + 1 + $i*5}}]
        if {{[peek [expr {{$r+4}}]] == 2}} {{
            set x [expr {{[peek $r] + 256*[peek [expr {{$r+1}}]] + 16 - 8 - 55}}]
            poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
            after time 0.5 [list panther_state $i]
            after time 0.6 {{ set ::hunting 1 }}
            after time 3.6 {{ set ::hunting 0; {dump('17_panther_whipped')} }}
            return
        }}
    }}
}}
# boss fight: whip the boss whenever its body is in the whip's reach
set ::boss_hunt 0
set ::boss_awake 0
set ::orb_seen 0
set ::boss_maxy 0
set ::boss_fire 0
set ::boss_near_fire 0
set ::boss_floor 0
proc boss_watch {{}} {{
    if {{$::boss_floor || $::boss_hunt}} {{
        for {{set i 0}} {{$i < 8}} {{incr i}} {{
            set b [expr {{{objt} + $i*{obj_size}}}]
            if {{$::boss_floor && [peek $b] == 10 && [peek [expr {{$b+3}}]] > $::boss_maxy}} {{ set ::boss_maxy [peek [expr {{$b+3}}]] }}
        }}
    }}
    if {{!$::boss_hunt}} return
    # the scripted fighter can't dodge 2 px-per-frame swoops: keep him invincible
    poke {syms["invuln_t"]} 2
    if {{[peek {hurt}] != 0}} return
    set px [expr {{[peek {px_a}] + 256*[peek {px_a + 1}]}}]
    set py [peek {py}]
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] != 10}} continue
        if {{[peek [expr {{$b+9}}]] != 0}} {{ set ::boss_awake 1 }}
        set d [expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]] + 24 - $px - 8}}]
        set dy [expr {{[peek [expr {{$b+3}}]] + 12 - $py - 8}}]
        if {{$dy < -20 || $dy > 20}} continue
        if {{$d >= 16 && $d <= 52}} {{ poke {fa} 0; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
        if {{$d <= -16 && $d >= -52}} {{ poke {fa} 1; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    }}
}}
debug set_watchpoint write_mem {fc} {{}} boss_watch
# the game-rules state, as one result line
proc rules {{tag}} {{
    set f [open "{result_file}" a]
    puts $f "rules $tag time=[format %02x%02x [peek {syms["time_bcd"] + 1}] [peek {syms["time_bcd"]}]] score=[format %02x%02x%02x [peek {syms["score"] + 2}] [peek {syms["score"] + 1}] [peek {syms["score"]}]] lives=[peek {syms["lives"]}] dying=[peek {syms["dying_t"]}] over=[peek {syms["game_over_t"]}] pose=[peek {pf}] hp=[peek {syms["hp"]}] area=[peek {cur}] hud=[string map {{" " _}} [format %c%c%c%c%c%c [vpeek {0x1800 + 7}] [vpeek {0x1800 + 8}] [vpeek {0x1800 + 9}] [vpeek {0x1800 + 10}] [vpeek {0x1800 + 11}] [vpeek {0x1800 + 12}]]]"
    close $f
}}
# weapons: poses shown, whip reach, dagger positions, while ::wpn_on
set ::wpn_on 0
set ::wpn_tag ""
set ::wpn_poses {{}}
set ::wpn_reach 0
set ::dagger_xs {{}}
set ::sub_track {{}}
set ::brazier_x 0
proc wpn_watch {{}} {{
    if {{!$::wpn_on}} return
    set p [peek {pf}]
    if {{[lsearch $::wpn_poses $p] < 0}} {{ lappend ::wpn_poses $p }}
    if {{[peek {wa}]}} {{
        set r [expr {{[peek {syms["whip_x2"]}] + 256*[peek {syms["whip_x2"] + 1}] - [peek {px_a}] - 256*[peek {px_a + 1}]}}]
        if {{$r > $::wpn_reach}} {{ set ::wpn_reach $r }}
    }}
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] == 12}} {{ lappend ::dagger_xs [expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]]}}] }}
        if {{[peek $b] == 13 || [peek $b] == 14}} {{
            set y [peek [expr {{$b+3}}]]; if {{$y > 127}} {{ set y [expr {{$y - 256}}] }}
            lappend ::sub_track "[expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]]}}]:$y:[peek [expr {{$b+11}}]]"
        }}
    }}
}}
debug set_watchpoint write_mem {fc} {{}} wpn_watch
proc wpn_report {{}} {{
    set f [open "{result_file}" a]
    puts $f "weapon $::wpn_tag poses=[join [lsort -integer $::wpn_poses] ,] reach=$::wpn_reach hearts=[peek {syms["hearts"]}] daggers=[join [lrange $::dagger_xs 0 5] ,] obj0=[peek {obj}] obj1=[peek {obj + obj_size}] track=[join $::sub_track ,]"
    close $f
    set ::wpn_on 0; set ::wpn_poses {{}}; set ::wpn_reach 0; set ::sub_track {{}}
}}
set ::zslot 0
proc sub_report {{tag}} {{
    set z 0
    if {{$::zslot}} {{ set z [expr {{[peek [expr {{$::zslot+1}}]] + 256*[peek [expr {{$::zslot+2}}]]}}] }}
    set f [open "{result_file}" a]
    puts $f "sub $tag hearts=[peek {syms["hearts"]}] freeze=[peek {syms["freeze_t"]}] time=[format %02x%02x [peek {syms["time_bcd"] + 1}] [peek {syms["time_bcd"]}]] zx=$z ztype=[expr {{$::zslot ? [peek $::zslot] : 0}}] icon=[vpeek {0x1800 + 30}],[vpeek {0x1800 + 31}],[vpeek {0x1800 + 62}],[vpeek {0x1800 + 63}] item7=[peek {objt + 7*obj_size + 5}]"
    close $f
}}
# exit sequences: castle gate (1) and door (2), watched every frame
set ::gate_seen 0
set ::gate_px0 0
set ::gate_pxmax 0
set ::door_cam 0
set ::door_opened 0
set ::door_closed 0
proc seq_watch {{}} {{
    set k [peek {syms["seq_kind"]}]
    set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}]}}]
    if {{$k == 1}} {{
        if {{!$::gate_seen}} {{ set ::gate_seen 1; set ::gate_px0 $x }}
        set ::gate_pxmax $x
    }}
    if {{$k == 2}} {{
        set c [expr {{[peek {syms["cam_x"]}] + 256*[peek {syms["cam_x"] + 1}]}}]
        if {{$c > $::door_cam}} {{ set ::door_cam $c }}
        set col [expr {{[peek {syms["area_hdr"] + 56}] & 31}}]
        set t [vpeek [expr {{0x1800 + 6*32 + $col}}]]
        if {{$t == [peek {syms["area_hdr"] + 45}]}} {{
            if {{!$::door_opened && [peek {cur}] == 1}} {{ after time 0.3 {{ {dump('18a_door_open')} }} }}
            set ::door_opened 1
        }} elseif {{$::door_opened}} {{ set ::door_closed 1 }}
    }}
}}
debug set_watchpoint write_mem {fc} {{}} seq_watch
proc count_type {{t}} {{
    set n 0
    for {{set i 0}} {{$i < 8}} {{incr i}} {{ if {{[peek [expr {{{objt} + $i*{obj_size}}}]] == $t}} {{ incr n }} }}
    return $n
}}
proc clear_type {{t}} {{
    for {{set i 0}} {{$i < 8}} {{incr i}} {{ set b [expr {{{objt} + $i*{obj_size}}}]; if {{[peek $b] == $t}} {{ poke $b 0 }} }}
}}
# put the boss at box x (y 40), hovering, a few frames before it may fire
proc boss_place {{x far}} {{
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] != 10}} continue
        poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
        poke [expr {{$b+3}}] 40; poke [expr {{$b+9}}] 2; poke [expr {{$b+4}}] 70
        if {{!$far}} {{
            # right in front of Simon, at his chest
            set sx [expr {{[peek {px_a}] + 256*[peek {px_a + 1}]}}]
            poke [expr {{$b+1}}] [expr {{($sx - 40) & 255}}]; poke [expr {{$b+2}}] [expr {{($sx - 40) >> 8}}]
            poke [expr {{$b+3}}] [expr {{[peek {py}] - 4}}]
        }}
    }}
}}
proc fireball_at_simon {{}} {{
    set b [expr {{{objt} + 7*{obj_size}}}]
    set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + 40}}]
    poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
    poke [expr {{$b+3}}] [expr {{[peek {py}] + 8}}]
    poke [expr {{$b+4}}] 0; poke [expr {{$b+5}}] 255; poke [expr {{$b+6}}] 36
    poke [expr {{$b+7}}] 4; poke [expr {{$b+8}}] 255; poke $b 9
}}
proc panther_state {{idx}} {{
    set s 0
    set dead [expr {{([peek [expr {{{cdead} + $idx/8}}]] >> ($idx%8)) & 1}}]
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] == 6}} {{ set s [expr {{[peek [expr {{$b+9}}]] + 1}}] }}
    }}
    set f [open "{result_file}" a]; puts $f "panther $s $dead"; close $f
}}
proc zombie_watch {{}} {{
    if {{$::wait_hit && [peek {hurt}] != 0}} {{
        set ::wait_hit 0
        {dump('13_hit')}
        after time 1.4 {{ {dump('14_after_knockback')}; set ::hunting 1 }}
        after time 6.0 {{ set ::hunting 0; {dump('15_whipped')}; panther_test }}
    }}
    if {{$::hunting && [peek {hurt}] == 0}} {{
        set px [expr {{[peek {px_a}] + 256*[peek {px_a + 1}]}}]
        for {{set i 0}} {{$i < 8}} {{incr i}} {{
            set b [expr {{{objt} + $i*{obj_size}}}]
            if {{[peek $b] != 5}} continue
            set d [expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]] - $px}}]
            if {{$d >= 14 && $d <= 36}} {{ poke {fa} 0; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
            if {{$d <= -14 && $d >= -36}} {{ poke {fa} 1; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
        }}
        for {{set i 0}} {{$i < 8}} {{incr i}} {{
            set b [expr {{{objt} + $i*{obj_size}}}]
            if {{[peek $b] == 7}} {{ set ::bat_seen 1 }}
            if {{[peek $b] == 8}} {{ set ::fish_seen 1 }}
            if {{[peek $b] < 6 || [peek $b] > 8}} continue
            set d [expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]] - $px}}]
            if {{$d >= 14 && $d <= 36}} {{ poke {fa} 0; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
            if {{$d <= -14 && $d >= -50}} {{ poke {fa} 1; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
        }}
    }}
}}
debug set_watchpoint write_mem {fc} {{}} zombie_watch
proc wait_game {{}} {{
    # wait until the main loop has run ~30 frames (C-BIOS logo comes first)
    if {{[peek {fc}] + 256*[peek {fc + 1}] < 30 || [peek {fc + 1}] > 0x20}} {{
        after time 0.1 wait_game
    }} else {{
        play
    }}
}}
after time 0.1 wait_game
after time 135 {{ exit }}
"""


def axe_ok(track):
    """the axe's path (x:y:state, one per frame): x +2 per frame, up then down"""
    pts = [tuple(int(v) for v in p.split(":")[:2]) for p in track.split(",") if p]
    if len(pts) < 20:
        return False
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    top = ys.index(min(ys))
    return (all(b - a == 2 for a, b in zip(xs, xs[1:]))
            and 3 < top < len(ys) - 3 and ys[-1] > ys[top] + 20 and ys[0] > ys[top] + 20)


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

    # no -romtype: the ROM must be detected as ASCII16 automatically, as it
    # is when a user simply opens it in an emulator
    cmd = ["openmsx", "-machine", MACHINE, "-cart", ROM, "-script", script]
    if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a"] + cmd
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if not os.path.exists(result_file):
        print(proc.stdout, proc.stderr)
        sys.exit("FAIL: openMSX produced no results")

    snaps = {}
    jump_y = []
    whip_seq = []
    vblank_us = 10 ** 9
    hud_hearts = ""
    overruns = (0, 0)
    panther = None
    bat_seen = None
    fish_seen = None
    boss_hp = boss_awake = None
    boss_maxy = boss_fire = boss_near_fire = 0
    rules = {}
    weapons = {}
    subs = {}
    seqs = {}
    whip_reach = 43                     # WHIP_HIT_X2 in src/config.inc (leather whip)
    orb_seen = clear_t = None
    panther_dead = 0
    stair = None
    with open(result_file) as f:
        for line in f:
            tag, *kv = line.split()
            if tag == "jumpy":
                jump_y = [int(v) for v in kv]
                continue
            if tag == "stair":
                stair = {k: tuple(int(v) for v in val.split(",")) for k, val in (x.split("=") for x in kv)}
                continue
            if tag == "hud_hearts":
                hud_hearts = kv[0] if kv else ""
                continue
            if tag == "seqs":
                seqs = dict(x.split("=") for x in kv)
                continue
            if tag == "sub":
                subs[kv[0]] = dict(x.split("=") for x in kv[1:])
                continue
            if tag == "weapon":
                weapons[kv[0]] = dict(x.split("=") for x in kv[1:])
                continue
            if tag == "rules":
                rules[kv[0]] = dict(x.split("=") for x in kv[1:])
                continue
            if tag == "boss_maxy":
                boss_maxy = int(kv[0])
                continue
            if tag == "boss_hp":
                boss_hp, boss_awake = int(kv[0]), int(kv[1])
                continue
            if tag == "orb":
                orb_seen, clear_t, boss_fire, boss_near_fire = (int(v) for v in kv)
                continue
            if tag == "fish":
                fish_seen = int(kv[0])
                continue
            if tag == "bat":
                bat_seen = int(kv[0])
                continue
            if tag == "panther":
                panther = int(kv[0])
                panther_dead = int(kv[1])
                continue
            if tag == "overruns":
                overruns = (int(kv[0]), int(kv[1]))
                continue
            if tag == "vblank_us":
                vblank_us = int(kv[0])
                continue
            if tag == "whipseq":
                whip_seq = [tuple(int(x) for x in v.split(":")) for v in kv]
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

    boot, walk, jump, land, left, strike, hit, got = (
        snaps[t] for t in ("01_boot", "02_walk_right", "03_jump", "04_landed",
                           "05_walk_left", "06_whip_strike", "07_brazier_hit",
                           "08_item_collected"))
    # expected whip (NES timing): wind-up 5, swing 7, strike 9 (hits), recovery 2
    poses = [p for p, _ in whip_seq]
    start = next((i for i, p in enumerate(poses) if p >= 4), None)
    expected_whip = [(4, 0)] * 5 + [(5, 0)] * 7 + [(6, 1)] * 9 + [(7, 0)] * 2 + [(0, 0)]
    actual_whip = whip_seq[start:start + len(expected_whip)] if start is not None else []
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
        ("whip runs wind-up 5 / swing 7 / strike 9 / recovery 2 frames",
         actual_whip == expected_whip),
        ("whip hit box reaches 28 px in front (facing left)",
         strike["whip_active"] == 1
         and strike["whip_x1"] == strike["px"] - 28 and strike["whip_x2"] == strike["px"] - 5),
        # NTSC VBLANK is 70 lines of 63.7 us; the HUD split follows soon after
        (f"VBLANK work fits in the vertical blank ({vblank_us} us of 4450)",
         vblank_us < 4450),
        ("whipped brazier turns into an item (hearts still 5)",
         hit["obj_table"] == 3 and hit["hearts"] == 5),
        ("walking into the big heart collects it: 10 hearts",
         got["obj_table"] == 0 and got["hearts"] == 10),
        (f"HUD shows the new heart count ({hud_hearts!r})", hud_hearts == "10"),
        *([("walking into the gate loads the next area at its start",
            snaps["09_next_area"]["cur_area"] == 1 and snaps["09_next_area"]["px"] == 40
            and snaps["09_next_area"]["on_ground"] == 1),
           ("the next area scrolls and its floor holds Simon",
            snaps["10_next_area_walk"]["cam_x"] > 0
            and snaps["10_next_area_walk"]["py"] == snaps["09_next_area"]["py"]
            and snaps["10_next_area_walk"]["on_ground"] == 1)]
          if "09_next_area" in snaps else []),
        *([("at the castle gate Simon walks in by himself, slowly (1 px every 3 frames)",
            seqs["gate"].split(",")[0] == "1"
            and 30 <= int(seqs["gate"].split(",")[2]) - int(seqs["gate"].split(",")[1]) <= 42),
           ("at the hall's door the screen scrolls on to the door (camera 1408)",
            seqs["door"].split(",")[0] == "1408" or int(seqs["door"].split(",")[0]) > 1408),
           ("the door opens, and closes again behind Simon",
            seqs["door"].split(",")[1:] == ["1", "1"])]
          if seqs else []),
        *([("the hall's door on the upper floor leads to stage 2",
            snaps["18_through_the_door"]["cur_area"] == 2
            and snaps["18_through_the_door"]["on_ground"] == 1)]
          if syms.get("AREA_COUNT", 1) > 2 and "18_through_the_door" in snaps else []),
        *([("down the stairs into the section below, to the staircase's foot",
            snaps["19_section_below"]["cur_area"] == 3
            and snaps["19_section_below"]["stair_state"] == 0
            and snaps["19_section_below"]["on_ground"] == 1
            and 0 <= snaps["19_section_below"]["py"] < 144),
           ("and back up into the section above, to the top",
            snaps["20_section_above"]["cur_area"] == 2
            and snaps["20_section_above"]["stair_state"] == 0
            and snaps["20_section_above"]["on_ground"] == 1)]
          if syms.get("AREA_COUNT", 1) > 3 and "19_section_below" in snaps else []),
        *([("a bat flies at Simon in stage 2 and the whip (or Simon) stops it",
            bat_seen == 1 and (snaps["21_bat"]["kills"] > snaps["20_section_above"]["kills"]
                               or snaps["21_bat"]["hp"] < snaps["20_section_above"]["hp"]))]
          if bat_seen is not None and "21_bat" in snaps else []),
        *([("fishmen jump out of the waterway and are whipped (or hit Simon)",
            fish_seen == 1 and snaps["22_fishmen"]["cur_area"] == 3
            and (snaps["22_fishmen"]["kills"] > snaps["21_bat"]["kills"]
                 or snaps["22_fishmen"]["hp"] < snaps["21_bat"]["hp"]))]
          if fish_seen is not None and "22_fishmen" in snaps else []),
        *([("stage 2's door on the top-right ledge leads to stage 3",
            snaps["23_back_up"]["cur_area"] == 2
            and snaps["24_stage3"]["cur_area"] == 4
            and snaps["24_stage3"]["on_ground"] == 1)]
          if syms.get("AREA_COUNT", 1) > 4 and "24_stage3" in snaps else []),
        *([("a fishman's fireball passes over Simon when he crouches",
            snaps["25_crouched_fireball"]["hp"] == snaps["24_stage3"]["hp"]
            and snaps["25_crouched_fireball"]["hurt_state"] == 0),
           ("and hits him when he stands",
            snaps["26_standing_fireball"]["hp"] < snaps["25_crouched_fireball"]["hp"])]
          if "26_standing_fireball" in snaps else []),
        *([("the stage 3 boss wakes up and the whip hurts it", boss_awake == 1 and boss_hp < 64),
           ("the screen locks at the boss: walking left doesn't scroll back",
            snaps["27a_boss_left"]["cam_x"] == 512 and snaps["27a_boss_left"]["px"] < 530),
           (f"the boss swoops down to Simon waiting on the floor (lowest box top {boss_maxy})",
            boss_maxy >= 112 and snaps["27c_floor_end"]["hp"] < snaps["27b_floor_start"]["hp"]),
           ("hovering far from Simon, the boss spits a fireball at him", boss_fire >= 1),
           ("close to him, it doesn't", boss_near_fire == 0),
           ("beaten, it leaves an orb; taking it clears the stage", orb_seen == 1 and clear_t > 0
            and snaps["29_stage_clear"]["hp"] == 64),
           ("after the stage clear the game starts again", snaps["30_restart"]["cur_area"] == 0)]
          if boss_hp is not None and "30_restart" in snaps else []),
        *([("kills score points, shown in the HUD",
            int(rules["after_clear"]["score"]) > 0
            and rules["after_clear"]["hud"] == rules["after_clear"]["score"]),
           ("the timer counts down from 300",
            0 < int(rules["after_clear"]["time"]) < 300),
           ("when time runs out Simon dies (death animation)",
            int(rules["dying"]["dying"]) > 0 and int(rules["dying"]["pose"]) in (14, 15)),
           ("then he loses a life and restarts with full health and time",
            int(rules["after_death"]["lives"]) == int(rules["after_clear"]["lives"]) - 1
            and rules["after_death"]["dying"] == "0" and rules["after_death"]["hp"] == "64"
            and int(rules["after_death"]["time"]) >= 298),
           ("dying with no lives left is game over",
            int(rules["game_over"]["over"]) > 0),
           ("after game over a new game starts: score 0, 3 lives",
            rules["new_game"]["score"] == "000000" and rules["new_game"]["lives"] == "3"
            and rules["new_game"]["area"] == "0")]
          if "new_game" in rules else []),
        *([("the chain whip has its own poses, the same reach as the leather whip",
            any(16 <= int(p) < 24 for p in weapons["chain"]["poses"].split(","))
            and int(weapons["chain"]["reach"]) == whip_reach),
           ("the morning star has its own poses and reaches 16 px further",
            any(24 <= int(p) < 32 for p in weapons["star"]["poses"].split(","))
            and int(weapons["star"]["reach"]) == whip_reach + 16),
           ("UP + whip throws the dagger: one heart, throwing poses",
            weapons["dagger"]["hearts"] == "9"
            and any(32 <= int(p) < 38 for p in weapons["dagger"]["poses"].split(","))),
           ("the dagger flies at 4 px per frame and breaks a brazier",
            len(weapons["dagger"]["daggers"].split(",")) >= 3
            and int(weapons["dagger"]["daggers"].split(",")[1]) - int(weapons["dagger"]["daggers"].split(",")[0]) == 4
            and weapons["dagger"]["obj0"] in ("2", "3"))]
          if "dagger" in weapons else []),
        *([("the axe costs one heart and flies up and forward, 2 px per frame, then down",
            weapons["axe"]["hearts"] == "9" and axe_ok(weapons["axe"]["track"])),
           ("holy water costs one heart, lands, burns, and burns down a brazier",
            weapons["holy"]["hearts"] == "9" and ":1" in weapons["holy"]["track"]
            and weapons["holy"]["obj1"] in ("0", "2", "3"))]
          if "holy" in weapons else []),
        *([("the HUD shows the sub-weapon's icon (stopwatch)",
            subs["watch_start"]["icon"] == f"{syms['HUDT_I_WATCH_TL']},{syms['HUDT_I_WATCH_TR']},"
                                         f"{syms['HUDT_I_WATCH_BL']},{syms['HUDT_I_WATCH_BR']}"),
           ("the stopwatch costs 5 hearts and freezes enemies and the timer",
            subs["watch_start"]["hearts"] == "5" and int(subs["watch_start"]["freeze"]) > 0
            and subs["watch_frozen"]["zx"] == subs["watch_start"]["zx"]
            and subs["watch_frozen"]["time"] == subs["watch_start"]["time"]),
           ("after about 3 seconds they move again",
            subs["watch_end"]["freeze"] == "0" and subs["watch_end"]["zx"] != subs["watch_frozen"]["zx"]),
           ("a candle drops a heart instead of the sub-weapon Simon holds (NES)",
            subs["drop_rule"]["item7"] == "3")]
          if "drop_rule" in subs else []),
        *([("UP at a staircase's foot climbs it to the top",
            (snaps["11_stairs_up"]["px"], snaps["11_stairs_up"]["py"]) == stair["top"]
            and snaps["11_stairs_up"]["stair_state"] == 0 and snaps["11_stairs_up"]["on_ground"] == 1),
           ("DOWN at its top walks back down to the foot",
            (snaps["12_stairs_down"]["px"], snaps["12_stairs_down"]["py"]) == stair["foot"]
            and snaps["12_stairs_down"]["stair_state"] == 0)]
          if stair else []),
        *([("a zombie hits Simon: 64 -> 56 health, hurt",
            snaps["13_hit"]["hp"] == 56 and snaps["13_hit"]["hurt_state"] in (1, 2)),
           ("knocked back away from it, then back on his feet and invincible",
            snaps["14_after_knockback"]["hurt_state"] == 0
            and snaps["14_after_knockback"]["on_ground"] == 1
            and snaps["14_after_knockback"]["invuln_t"] > 0
            and abs(snaps["14_after_knockback"]["px"] - snaps["13_hit"]["px"]) >= 20),
           ("the whip kills zombies", snaps["15_whipped"]["kills"] >= 1)]
          if "13_hit" in snaps else []),
        *([("a black panther wakes up when Simon comes near", panther >= 2),
           ("a woken panther never respawns (marked dead at once)", panther_dead == 1),
           ("the whip kills the panther",
            snaps["17_panther_whipped"]["kills"] > snaps["15_whipped"]["kills"])]
          if panther is not None else []),
        ("walking left turns the player", left["facing"] == 1
         and left["px"] < land["px"]),
    ]
    failed = 0
    for name, ok in checks:
        print(("PASS " if ok else "FAIL ") + name)
        failed += not ok
    print(f"frames over budget on this {MACHINE} (3.58 MHz Z80): {overruns[0]} of {overruns[1]}")
    print(f"screenshots in {OUT}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
