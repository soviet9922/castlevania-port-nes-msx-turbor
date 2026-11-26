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
    after time 8.95 {{ keymatrixdown 8 0x01 }}
    after time 9 {{ keymatrixup 8 0x01
                       # in the middle of a jump at the gate: the sequence waits for the landing
                       poke {eoff} 3; poke {px_a} [peek {exit_x}]; poke {px_a + 1} [peek {exit_x + 1}] }}
    after time 12.4 {{ {dump('09_next_area')}; keymatrixdown 8 0x80 }}
    after time 14 {{ {dump('10_next_area_walk')}; keymatrixup 8 0x80
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
    after time 37.1 {{ keymatrixup 8 0x80; {dump('18_through_the_door')}
                       set f [open "{result_file}" a]
                       puts $f "seqs gate=$::gate_seen,$::gate_px0,$::gate_pxmax door=$::door_cam ys=[join $::seq_ys ,] doorstates=[join $::door_states /] gatemasks=[join $::gate_masks /] walk=$::door_pxmax,$::door_walk_end screenx=$::door_screen_x"
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
    after time 39.1 {{ keymatrixup 8 0x40; {dump('19_section_below')}; keymatrixdown 8 0x20 }}
    after time 41.1 {{ keymatrixup 8 0x20; {dump('20_section_above')}
                       # bats: enemies on, wait for one and whip it
                       set ::bat_seen 0; poke {eoff} 0; set ::hunting 1
                       poke {syms["bat_spawn_t"]} 150 }}
    after time 45.1 {{ set ::hunting 0; poke {eoff} 3; {dump('21_bat')}
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
    after time 47.2 {{ keymatrixup 8 0x40
                       # fishmen: stand on the walkway, enemies on, whip what comes
                       set ::fish_seen 0; poke {px_a} 150; poke {px_a + 1} 0; poke {py} 48; poke {py + 1} 0
                       poke {eoff} 0; set ::hunting 1 }}
    after time 54.6 {{ set ::hunting 0; poke {eoff} 3; {dump('22_fishmen')}
                       set f [open "{result_file}" a]; puts $f "fish $::fish_seen"; close $f }}
    after time 54.8 {{ # up the stairs from the waterway (foot on the playfield, top off it)
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
    after time 57.1 {{ keymatrixup 8 0x20; {dump('23_back_up')}
                       # stage 2's door: on the ledge, 24 px before the exit
                       if {{[peek {exit_x}] != 255}} {{
                           set x [expr {{[peek {exit_x}] + 256*[peek {exit_x + 1}] - 24}}]
                           poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                           poke {py} [expr {{[peek {exit_x + 8}] - 8}}]; poke {py + 1} 0
                           keymatrixdown 8 0x80 }} }}
    after time 63.1 {{ keymatrixup 8 0x80; {dump('24_stage3')}
                       # a fishman's fireball at standing height, flying at crouching Simon
                       # (back at the area's start, away from the stairs)
                       poke {eoff} 3; poke {px_a} 40; poke {px_a + 1} 0
                       keymatrixdown 8 0x40; fireball_at_simon }}
    after time 64.6 {{ {dump('25_crouched_fireball')}; keymatrixup 8 0x40
                       # a zombie on stage 3's upper platform, walking left off its edge
                       set z [expr {{{objt} + 6*{obj_size}}}]
                       poke [expr {{$z+1}}] 150; poke [expr {{$z+2}}] 0; poke [expr {{$z+3}}] 64
                       poke [expr {{$z+4}}] 0; poke [expr {{$z+5}}] 255; poke [expr {{$z+7}}] 3
                       poke [expr {{$z+8}}] 255; poke [expr {{$z+9}}] 0; poke [expr {{$z+10}}] 0
                       poke [expr {{$z+11}}] 0; poke $z 5 }}
    after time 65.0 {{ set z [expr {{{objt} + 6*{obj_size}}}]
                       set ::zfall "[peek $z],[peek [expr {{$z+1}}]],[peek [expr {{$z+3}}]],[peek [expr {{$z+9}}]]" }}
    after time 66.0 {{ set z [expr {{{objt} + 6*{obj_size}}}]
                       set f [open "{result_file}" a]
                       puts $f "zfall $::zfall [peek $z],[peek [expr {{$z+1}}]],[peek [expr {{$z+3}}]],[peek [expr {{$z+9}}]]"
                       close $f
                       if {{[peek $z] == 5}} {{ poke $z 0 }} }}
    after time 66.1 {{ fireball_at_simon }}
    after time 67.4 {{ {dump('26_standing_fireball')}
                       # the boss: stand on the ledge at the end of stage 3
                       # (first on the floor out of its reach, to see it asleep)
                       if {{[peek {cur}] == 4}} {{
                           poke {px_a} [expr {{530 & 255}}]; poke {px_a + 1} [expr {{530 >> 8}}]
                           poke {py} 128; poke {py + 1} 0; set ::boss_hunt 1 }} }}
    after time 67.6 {{ # asleep it can't be hurt: a flying dagger right on it
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 10}} {{
                               set x [expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]] + 16}}]
                               set d {syms["dagger_x1"]}
                               poke $d [expr {{$x & 255}}]; poke [expr {{$d+1}}] [expr {{$x >> 8}}]
                               poke [expr {{$d+2}}] [expr {{($x+16) & 255}}]; poke [expr {{$d+3}}] [expr {{($x+16) >> 8}}]
                               poke [expr {{$d+4}}] [peek [expr {{$b+3}}]]; poke [expr {{$d+5}}] 0
                               poke [expr {{$d+6}}] [expr {{[peek [expr {{$b+3}}]] + 16}}]; poke [expr {{$d+7}}] 0
                               poke {syms["sub_kind"]} 1; poke {syms["dagger_on"]} 1
                           }}
                       }} }}
    after time 67.85 {{ set f [open "{result_file}" a]
                        set st -1
                        for {{set i 0}} {{$i < 8}} {{incr i}} {{
                            set b [expr {{{objt} + $i*{obj_size}}}]
                            if {{[peek $b] == 10}} {{ set st [peek [expr {{$b+9}}]] }}
                        }}
                        puts $f "asleep_hit [peek {syms["boss_hp"]}] $st"; close $f
                        poke {syms["dagger_on"]} 0 }}
    after time 67.9 {{ if {{[peek {cur}] == 4}} {{
                           poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                           poke {py} 64; poke {py + 1} 0 }} }}
    after time 74.1 {{ set ::boss_hunt 0
                       # on the floor at the screen's left edge: unlocked, the camera would follow
                       poke {px_a} [expr {{524 & 255}}]; poke {px_a + 1} [expr {{524 >> 8}}]
                       poke {py} 128; poke {py + 1} 0; keymatrixdown 8 0x10 }}
    after time 74.6 {{ keymatrixup 8 0x10; {dump('27a_boss_left')}
                       poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                       poke {py} 64; poke {py + 1} 0; set ::boss_hunt 1 }}
    after time 74.7 {{ # wait on the floor without whipping: the boss must come down
                       set ::boss_hunt 0; set ::boss_floor 1
                       poke {px_a} [expr {{700 & 255}}]; poke {px_a + 1} [expr {{700 >> 8}}]
                       poke {py} 128; poke {py + 1} 0
                       # (hovering 30 frames more: then, Simon below it, it swoops:
                       # a dive that goes below his middle)
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 10}} {{ poke [expr {{$b + 9}}] 3; poke {syms["boss_t"]} 30 }}
                       }} }}
    after time 74.75 {{ {dump('27b_floor_start')} }}
    after time 78.8 {{ # holy water's fire on the boss: held in it, and hurt again and again
                       set ::boss_hunt 0
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 10}} {{ set ::bossb $b }}
                       }}
                       set f [expr {{{objt} + 7*{obj_size}}}]
                       set x [expr {{[peek [expr {{$::bossb+1}}]] + 256*[peek [expr {{$::bossb+2}}]] + 16}}]
                       poke [expr {{$f+1}}] [expr {{$x & 255}}]; poke [expr {{$f+2}}] [expr {{$x >> 8}}]
                       poke [expr {{$f+3}}] [peek [expr {{$::bossb+3}}]]; poke [expr {{$f+4}}] 0
                       poke [expr {{$f+11}}] 1; poke [expr {{$f+5}}] 1; poke $f 14
                       poke {syms["sub_kind"]} 3; poke {syms["dagger_on"]} 1; poke {syms["holy_fire"]} 1
                       }}
    after time 78.9 {{ # (from the frame after the fire took hold)
                       set ::stun0 "[peek [expr {{$::bossb+1}}]],[peek [expr {{$::bossb+3}}]],[peek {syms["boss_hp"]}]" }}
    after time 79.4 {{ set f [open "{result_file}" a]
                       puts $f "stun $::stun0 [peek [expr {{$::bossb+1}}]],[peek [expr {{$::bossb+3}}]],[peek {syms["boss_hp"]}]"
                       close $f
                       set fo [expr {{{objt} + 7*{obj_size}}}]; poke $fo 0; poke {syms["dagger_on"]} 0; poke {syms["holy_fire"]} 0 }}
    after time 79.6 {{ {dump('27c_floor_end')}; set ::boss_floor 0
                       set f [open "{result_file}" a]; puts $f "floor_fires $::floor_fires"; close $f
                       # fireballs (NES): a hover ends with Simon's middle above
                       # the boss's: a fireball at him; Simon below it: a swoop
                       poke {px_a} [expr {{750 & 255}}]; poke {px_a + 1} [expr {{750 >> 8}}]
                       poke {py} 64; poke {py + 1} 0; boss_place 600 1 }}
    after time 79.9 {{ set ::boss_fire [count_type 9]
                       clear_type 9; boss_place 600 0 }}
    after time 80.2 {{ set ::boss_near_fire [count_type 9]
                       set f [open "{result_file}" a]; puts $f "boss_maxy $::boss_maxy"; close $f
                       poke {px_a} [expr {{711 & 255}}]; poke {px_a + 1} [expr {{711 >> 8}}]
                       poke {py} 64; poke {py + 1} 0; set ::boss_hunt 1 }}
    after time 80.1 {{ {dump('27_boss')}
                       set f [open "{result_file}" a]; puts $f "boss_hp [peek {syms["boss_hp"]}] $::boss_awake $::boss_sleepf"; close $f
                       poke {syms["boss_hp"]} 1 }}
    # (the NES boss hovers 41 px above Simon: held in the whip's reach to end it)
    after time 80.3 {{ set ::boss_hunt 0; poke {fa} 0; boss_pin 60 }}
    after time 80.5 {{ keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 86.1 {{ set ::boss_hunt 0; {dump('28_boss_dead')}
                       # a known tally: 12 timer steps and 3 hearts
                       poke {syms["time_bcd"]} 0x12; poke {syms["time_bcd"] + 1} 0; poke {syms["time_t"]} 0
                       poke {syms["hearts"]} 3; rules "before_orb"
                       # walk onto the orb
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{
                           set b [expr {{{objt} + $i*{obj_size}}}]
                           if {{[peek $b] == 11}} {{
                               # (NES: hidden 60 frames, flashing 32: skip them)
                               poke [expr {{$b+4}}] 92
                               poke {px_a} [peek [expr {{$b+1}}]]; poke {px_a + 1} [peek [expr {{$b+2}}]]
                               poke {py} [expr {{[peek [expr {{$b+3}}]] - 16}}]; poke {py + 1} 0
                               set ::orb_seen 1
                           }}
                       }} }}
    after time 86.6 {{ {dump('29_stage_clear')}
                       set f [open "{result_file}" a]; puts $f "orb $::orb_seen [peek {syms["clear_t"]}] $::boss_fire $::boss_near_fire"; close $f }}
    after time 90.5 {{ rules "tally_time" }}
    after time 92 {{ rules "tally_hearts" }}
    after time 94.6 {{ {dump('30_restart')}; rules "after_clear"
                       # time runs out: death animation, then a life is lost
                       poke {syms["time_bcd"]} 1; poke {syms["time_bcd"] + 1} 0; poke {syms["time_t"]} 60 }}
    after time 95.3 {{ rules "dying"; {dump('31_dying')} }}
    after time 97.6 {{ rules "after_death"
                       # the last life: game over, then a new game
                       poke {syms["lives"]} 0
                       poke {syms["time_bcd"]} 1; poke {syms["time_bcd"] + 1} 0; poke {syms["time_t"]} 60 }}
    after time 99.7 {{ rules "game_over" }}
    after time 103.6 {{ rules "new_game"
                       # the chain whip
                       poke {syms["whip_level"]} 1; poke {fa} 0; set ::wpn_tag chain; set ::wpn_on 1
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 104.4 {{ wpn_report
                       # the morning star
                       poke {syms["whip_level"]} 2; set ::wpn_tag star; set ::wpn_on 1
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 105.2 {{ wpn_report
                       # the dagger: 60 px left of the first brazier, UP + whip
                       set bx [expr {{[peek {obj + 1}] + 256*[peek {obj + 2}] - 60}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {fa} 0; poke {syms["subweapon"]} 1; poke {syms["hearts"]} 10
                       set ::wpn_tag dagger; set ::wpn_on 1; set ::dagger_xs {{}}
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 106.4 {{ wpn_report
                       # the axe: standing still, UP + whip
                       poke {syms["subweapon"]} 2; poke {syms["hearts"]} 10; poke {fa} 0
                       set ::wpn_tag axe; set ::wpn_on 1; set ::sub_track {{}}
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 108.1 {{ wpn_report
                       # holy water, 40 px left of the second brazier
                       set bx [expr {{[peek {obj + 1 + obj_size}] + 256*[peek {obj + 2 + obj_size}] - 40}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {syms["subweapon"]} 3; poke {syms["hearts"]} 10; poke {fa} 0
                       set ::wpn_tag holy; set ::wpn_on 1; set ::sub_track {{}}; set ::brazier_x [peek {obj + 1 + obj_size}]
                       keymatrixdown 8 0x20; keymatrixdown 4 0x04
                       after time 0.05 {{ keymatrixup 4 0x04 }}; after time 0.3 {{ keymatrixup 8 0x20 }} }}
    after time 110.1 {{ wpn_report
                       # the stopwatch: on the hall's floor with zombies about
                       poke {syms["subweapon"]} 4; poke {syms["hearts"]} 10 }}
    after time 110.2 {{ sub_report "watch_hud" }}
    after time 110.3 {{ # a zombie in front of Simon, enemies on; UP + whip
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
    after time 110.5 {{ sub_report "watch_start" }}
    after time 112.1 {{ sub_report "watch_frozen"; poke {eoff} 3; {dump('35_stopwatch')} }}
    after time 114.1 {{ sub_report "watch_end"
                       # the drop rule: an axe item while Simon holds the axe -> a heart
                       poke {syms["subweapon"]} 2
                       set b [expr {{{objt} + 7*{obj_size}}}]
                       poke [expr {{$b+1}}] 100; poke [expr {{$b+2}}] 0; poke [expr {{$b+3}}] 60
                       poke [expr {{$b+4}}] 0; poke [expr {{$b+5}}] 4; poke [expr {{$b+6}}] 2; poke $b 2 }}
    after time 114.7 {{ sub_report "drop_rule"
                       # an item from a candle above the playfield's top (y -8, as the
                       # hall's holy water candle): it must fall into view, not vanish
                       set b [expr {{{objt} + 6*{obj_size}}}]
                       set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + 60}}]
                       poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
                       poke [expr {{$b+3}}] 248; poke [expr {{$b+4}}] 10; poke [expr {{$b+5}}] 5
                       poke [expr {{$b+6}}] 50; poke [expr {{$b+9}}] 0; poke $b 3 }}
    after time 115.5 {{ set b [expr {{{objt} + 6*{obj_size}}}]
                       set f [open "{result_file}" a]; puts $f "high_item [peek $b] [peek [expr {{$b+3}}]]"; close $f }}
    # ---- block 2 (stages 4-6), when the converted build has it ----
    after time 116 {{ if {{{areas} > 5}} {{ poke {syms["area_hdr"] + 44} 5; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4; poke {eoff} 3 }} }}
    after time 116.6 {{ {dump('40_stage4')}
                       # up stage 4's first staircase
                       set x 622; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       keymatrixdown 8 0x20 }}
    after time 118.9 {{ keymatrixup 8 0x20; {dump('41_stage4_stairs')}
                       # the long staircase up into section 1, from its foot
                       set x 590; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 32; poke {py + 1} 0; keymatrixdown 8 0x20 }}
    after time 124.2 {{ keymatrixup 8 0x20; {dump('42_stage4_upper')}
                       # onto the ledge at the door, at the left end
                       set x 276; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 32; poke {py + 1} 0; keymatrixdown 8 0x10 }}
    after time 124.6 {{ keymatrixup 8 0x10 }}
    after time 127.6 {{ {dump('43_door_left')} }}
    after time 132.6 {{ {dump('44_stage5')} }}
    # block 2's enemies: Medusa heads in stage 5, the hanging bat and a knight in stage 4
    after time 132.7 {{ poke {eoff} 0 }}
    after time 134.2 {{ set f [open "{result_file}" a]; puts $f "medusa [count_type 16]"; close $f
                       poke {syms["area_hdr"] + 44} 5; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }}
    after time 134.8 {{ set ::hb [find_type 17]
                       set f [open "{result_file}" a]
                       puts $f "s4enemies [count_type 15] [count_type 17] [expr {{$::hb >= 0 ? [peek [expr {{$::hb + 6}}]] : -1}}]"
                       close $f
                       # onto the bat's ledge, near it: it wakes and flies at him
                       set x 600; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 32; poke {py + 1} 0; poke {fa} 1 }}
    after time 136.4 {{ set f [open "{result_file}" a]; puts $f "hbat [count_type 17] [peek {syms["hp"]}]"; close $f
                       # 40 px left of the knight, facing it, whip twice
                       set k [find_type 15]
                       set x [expr {{[peek [expr {{$k+1}}]] + 256*[peek [expr {{$k+2}}]] - 40}}]
                       poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 32; poke {py + 1} 0; poke {fa} 0; poke {syms["invuln_t"]} 250
                       set ::score0 [format %02x%02x [peek {syms["score"] + 2}] [peek {syms["score"] + 1}]]
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 136.9 {{ set f [open "{result_file}" a]; puts $f "knight1 [count_type 15]"; close $f }}
    after time 137.2 {{ set k [find_type 15]
                       if {{$k >= 0}} {{
                           set x [expr {{[peek [expr {{$k+1}}]] + 256*[peek [expr {{$k+2}}]] - 40}}]
                           poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]; poke {fa} 0 }}
                       keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 138 {{ set f [open "{result_file}" a]
                     puts $f "knight2 [count_type 15] $::score0 [format %02x%02x [peek {syms["score"] + 2}] [peek {syms["score"] + 1}]]"
                     close $f }}
    # stage 6's ceiling crushers: under one, Simon is crushed within its cycle
    after time 138.1 {{ poke {eoff} 3; poke {syms["area_hdr"] + 44} 9; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }}
    after time 138.7 {{ set ::lives0 [peek {syms["lives"]}]
                       set x 680; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 96; poke {py + 1} 0; set ::crushed 0; crush_watch 200 }}
    after time 142 {{ set f [open "{result_file}" a]; puts $f "crush [peek {cur}] $::crushed"; close $f }}
    # Medusa: in her room she wakes (the statue's tiles go blank, the screen
    # locks); with little health left a whip hit burns her into the orb
    after time 142.1 {{ poke {eoff} 3; poke {syms["area_hdr"] + 44} 10; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }}
    after time 142.6 {{ set x 372; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 96; poke {py + 1} 0; poke {syms["invuln_t"]} 250 }}
    # (NES: she starts 180 frames after the lock; the test skips the wait)
    after time 143.2 {{ if {{[peek {syms["med_wake"]}] > 1}} {{ poke {syms["med_wake"]} 1 }} }}
    after time 143.6 {{ set m [find_type 18]
                       set col [expr {{[peek {syms["med_col"]}] & 31}}]
                       set row [expr {{[peek {syms["med_row"]}] + 3}}]
                       set f [open "{result_file}" a]
                       puts $f "medusa_wake [expr {{$m >= 0 ? [peek [expr {{$m + 9}}]] : -1}}] [peek {syms["cam_lock"]}] [vpeek [expr {{0x1800 + $row*32 + $col}}]] [peek {syms["area_hdr"] + 45}] [peek {syms["boss_hp"]}]"
                       close $f
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{ set b [expr {{{objt} + $i*{obj_size}}}]; if {{[peek $b] == 19}} {{ poke $b 0 }} }}
                       poke {syms["boss_hp"]} 3; poke {syms["invuln_t"]} 250; poke {fa} 0; medusa_pin 80 }}
    after time 143.9 {{ keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 146 {{ set f [open "{result_file}" a]; puts $f "medusa_dead [peek {syms["boss_hp"]}] [count_type 11]"; close $f }}
    # block 3: stage 7 starts at its right end, facing left (NES: x 720, camera 512)
    after time 146.1 {{ poke {eoff} 0; if {{{areas} > 11}} {{ poke {syms["area_hdr"] + 44} 11; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }} }}
    after time 146.7 {{ {dump('50_stage7')} }}
    # (the ghost comes out when its place reaches the screen's edge strip)
    after time 146.75 {{ set x 620; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                        keymatrixdown 8 0x10 }}
    after time 147.95 {{ keymatrixup 8 0x10 }}
    # block 3's enemies: stage 7's ghost appears and follows Simon; a bone
    # pillar in stage 9 fires at him
    after time 148 {{ set g [find_type 25]
                     set f [open "{result_file}" a]
                     puts $f "b3ghost [expr {{$g >= 0 ? [peek [expr {{$g + 9}}]] : -1}}] [expr {{$g >= 0 ? [peek [expr {{$g + 1}}]] + 256*[peek [expr {{$g + 2}}]] : -1}}]"
                     close $f
                     poke {syms["area_hdr"] + 44} 15; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }}
    after time 148.6 {{ set x 330; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 48; poke {py + 1} 0; poke {syms["invuln_t"]} 250; set ::fb_seen 0; fb_watch 300 }}
    after time 153.8 {{ set f [open "{result_file}" a]; puts $f "b3pillar [count_type 23] $::fb_seen"; close $f }}
    # the mummies: both wake when the screen reaches their room; beaten, the last
    # one leaves the orb
    after time 153.9 {{ poke {syms["area_hdr"] + 44} 15; poke {syms["clear_t"]} 1; poke {syms["clear_phase"]} 4 }}
    after time 154.5 {{ set x 1420; poke {px_a} [expr {{$x & 255}}]; poke {px_a + 1} [expr {{$x >> 8}}]
                       poke {py} 128; poke {py + 1} 0; poke {syms["invuln_t"]} 250 }}
    after time 155.5 {{ set n 0
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{ set b [expr {{{objt} + $i*{obj_size}}}]; if {{[peek $b] == 26 && [peek [expr {{$b + 9}}]] == 1}} {{ incr n }} }}
                       set f [open "{result_file}" a]; puts $f "mummies $n [peek {syms["swap_boss"]}] [peek {syms["cam_lock"]}] [peek {syms["boss_hp"]}]"; close $f
                       for {{set i 0}} {{$i < 8}} {{incr i}} {{ set b [expr {{{objt} + $i*{obj_size}}}]; if {{[peek $b] == 27}} {{ poke $b 0 }} }}
                       poke {syms["boss_hp"]} 4; poke {syms["invuln_t"]} 250; mummy_pin 150 }}
    after time 155.6 {{ keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 156.6 {{ keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
    after time 159.5 {{ set f [open "{result_file}" a]; puts $f "mummies_dead [peek {syms["boss_hp"]}] [count_type 26] [count_type 11]"; close $f }}
    after time 159.7 {{ set f [open "{result_file}" a]; puts $f "vblank_us [expr {{int($::vbl_worst)}}] $::vbl_worst_fc"; puts $f "overruns $::overruns $::frames"; close $f; snd_report; exit }}
""" if areas > 1 else f"""
    after time 9 {{ snd_report; set f [open "{result_file}" a]; puts $f "vblank_us [expr {{int($::vbl_worst)}}]"; puts $f "overruns $::overruns $::frames"; close $f; exit }}
"""
    # keyboard matrix row 8: bit0 SPACE, bit4 LEFT, bit7 RIGHT
    # Times are relative to the moment the game's main loop is running.
    return f"""
# normal speed: with "throttle off" openMSX skips rendering and screenshots are black
proc play {{}} {{
    set ::vbl_on 1
    after time 0.5 {{ {dump('01_boot')}; keymatrixdown 8 0x80 }}
    after time 3.5 {{ {dump('02_walk_right')}; keymatrixup 8 0x80 }}
    after time 3.7 {{ keymatrixdown 8 0x01; rec_py 60 }}
    after time 3.8 {{ keymatrixup 8 0x01 }}
    after time 4 {{ {dump('03_jump')} }}
    after time 5 {{ {dump('04_landed')}; keymatrixdown 8 0x10 }}
    after time 6 {{ {dump('05_walk_left')}; keymatrixup 8 0x10 }}
    after time 6.3 {{ keymatrixdown 4 0x04; rec_whip 40 }}
    after time 6.4 {{ keymatrixup 4 0x04 }}
    after time 6.55 {{ {dump('06_whip_strike')} }}
    # brazier: stand 26 px left of the first one, facing right, and whip it
    after time 7.2 {{ set bx [expr {{[peek {obj + 1}] + 256*[peek {obj + 2}] - 26}}]
                       poke {px_a} [expr {{$bx & 255}}]; poke {px_a + 1} [expr {{$bx >> 8}}]
                       poke {fa} 0 }}
    after time 7.3 {{ keymatrixdown 4 0x04 }}
    after time 7.35 {{ keymatrixup 4 0x04 }}
    after time 8.1 {{ {dump('07_brazier_hit')}; keymatrixdown 8 0x80 }}
    after time 8.6 {{ keymatrixup 8 0x80 }}
    after time 8.8 {{ {dump('08_item_collected')}
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
# sound: the loudest PSG volume seen, whether music and an effect ran
set ::psg_max 0
set ::mus_seen 0
set ::sfx_seen 0
proc snd_watch {{}} {{
    foreach r {{8 9 10}} {{
        set v [expr {{[debug read "PSG regs" $r] & 15}}]
        if {{$v > $::psg_max}} {{ set ::psg_max $v }}
    }}
    if {{[peek {syms["mus_state"]}]}} {{ set ::mus_seen 1 }}
    if {{[peek {syms["sfx_state"]}]}} {{ set ::sfx_seen 1 }}
}}
debug set_watchpoint write_mem {fc} {{}} snd_watch
proc snd_report {{}} {{
    set f [open "{result_file}" a]; puts $f "sound $::psg_max $::mus_seen $::sfx_seen"; close $f
}}
# worst time from the VBLANK interrupt to the end of the main loop's VBLANK work
set ::vbl_t0 0
set ::vbl_worst 0
set ::vbl_worst_fc 0
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
    if {{$dt > $::vbl_worst}} {{ set ::vbl_worst $dt; set ::vbl_worst_fc [peek16 {fc}] }}
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
            after time 0.05 {{ set ::hunting 1 }}
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
set ::bossb 0
set ::stun0 ""
set ::zfall ""
set ::boss_sleepf -1
set ::boss_fire 0
set ::boss_near_fire 0
set ::boss_floor 0
set ::floor_fires 0
proc boss_watch {{}} {{
    if {{$::boss_floor || $::boss_hunt}} {{
        for {{set i 0}} {{$i < 8}} {{incr i}} {{
            set b [expr {{{objt} + $i*{obj_size}}}]
            if {{$::boss_floor && [peek $b] == 10 && [peek [expr {{$b+3}}]] > $::boss_maxy}} {{ set ::boss_maxy [peek [expr {{$b+3}}]] }}
            if {{$::boss_sleepf < 0 && [peek $b] == 10 && [peek [expr {{$b+9}}]] == 0}} {{ set ::boss_sleepf [peek [expr {{$b+6}}]] }}
            if {{$::boss_floor || $::boss_hunt}} {{
                set t [peek $b]
                if {{$t == 9 && ![info exists ::fb_prev($i)]}} {{ incr ::floor_fires }}
                if {{$t == 9}} {{ set ::fb_prev($i) 1 }} else {{ unset -nocomplain ::fb_prev($i) }}
            }}
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
    puts $f "rules $tag time=[format %02x%02x [peek {syms["time_bcd"] + 1}] [peek {syms["time_bcd"]}]] score=[format %02x%02x%02x [peek {syms["score"] + 2}] [peek {syms["score"] + 1}] [peek {syms["score"]}]] lives=[peek {syms["lives"]}] dying=[peek {syms["dying_t"]}] over=[peek {syms["game_over_t"]}] pose=[peek {pf}] hp=[peek {syms["hp"]}] area=[peek {cur}] hearts=[peek {syms["hearts"]}] phase=[peek {syms["clear_phase"]}] hud=[string map {{" " _}} [format %c%c%c%c%c%c [vpeek {0x1800 + 7}] [vpeek {0x1800 + 8}] [vpeek {0x1800 + 9}] [vpeek {0x1800 + 10}] [vpeek {0x1800 + 11}] [vpeek {0x1800 + 12}]]]"
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
            lappend ::sub_track "[expr {{[peek [expr {{$b+1}}]] + 256*[peek [expr {{$b+2}}]]}}]:$y:[peek [expr {{$b+11}}]]:[peek [expr {{$b+6}}]]"
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
set ::door_states {{}}
set ::door_first ""
set ::gate_hidden 0
set ::gate_masks {{}}
set ::door_pxmax 0
set ::door_walk_end 0
set ::door_screen_x 0
set ::seq_ys {{}}
proc seq_watch {{}} {{
    set k [peek {syms["seq_kind"]}]
    set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}]}}]
    set y [peek {py}]
    if {{$k == 1}} {{
        set m "[peek {syms["clip_l"]}].[peek {syms["clip_r"]}]"
        if {{[lindex $::gate_masks end] != $m}} {{ lappend ::gate_masks $m }}
        if {{!$::gate_seen}} {{ set ::gate_seen 1; set ::gate_px0 $x }}
        set ::gate_pxmax $x
        if {{[lsearch $::seq_ys "g$y"] < 0}} {{ lappend ::seq_ys "g$y" }}
    }}
    if {{$k == 2 && [lsearch $::seq_ys "d$y"] < 0}} {{ lappend ::seq_ys "d$y" }}
    if {{$k == 2 && [peek {cur}] == 1}} {{
        if {{$x > $::door_pxmax}} {{ set ::door_pxmax $x }}
        set ::door_walk_end [expr {{[peek {syms["area_hdr"] + 62}] + 256*[peek {syms["area_hdr"] + 63}]}}]
        set ::door_screen_x [expr {{$x - [peek {syms["cam_x"]}] - 256*[peek {syms["cam_x"] + 1}]}}]
    }}
    if {{$k == 2}} {{
        set c [expr {{[peek {syms["cam_x"]}] + 256*[peek {syms["cam_x"] + 1}]}}]
        if {{$c > $::door_cam}} {{ set ::door_cam $c }}
        set col [expr {{[peek {syms["area_hdr"] + 56}] & 31}}]
        set t "[vpeek [expr {{0x1800 + 7*32 + $col}}]].[vpeek [expr {{0x1800 + 7*32 + (($col + 1) & 31)}}]]"
        if {{[peek {cur}] == 1}} {{
            if {{$::door_first == ""}} {{ set ::door_first $t }}
            if {{[lindex $::door_states end] != $t}} {{
                lappend ::door_states $t
                if {{[llength $::door_states] == 3}} {{ after time 0.3 {{ {dump('18a_door_open')} }} }}
            }}
        }}
    }}
}}
debug set_watchpoint write_mem {fc} {{}} seq_watch
proc medusa_pin {{n}} {{
    if {{$n <= 0}} return
    set b [find_type 18]
    if {{$b >= 0 && [peek [expr {{$b + 9}}]] != 4}} {{
        set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + 12}}]
        poke [expr {{$b + 1}}] [expr {{$x & 255}}]; poke [expr {{$b + 2}}] [expr {{$x >> 8}}]
        poke [expr {{$b + 10}}] 90
    }}
    after frame "medusa_pin [expr {{$n - 1}}]"
}}
proc mummy_pin {{n}} {{
    if {{$n <= 0}} return
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] == 26 && [peek [expr {{$b + 9}}]] == 1}} {{ poke [expr {{$b + 4}}] 1 }}
        if {{[peek $b] == 26 && [peek [expr {{$b + 9}}]] != 5}} {{
            set off [expr {{[peek {fa}] ? -28 : 28}}]
            set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + $off}}]
            poke [expr {{$b + 1}}] [expr {{$x & 255}}]; poke [expr {{$b + 2}}] [expr {{$x >> 8}}]
            poke [expr {{$b + 10}}] 2
        }}
    }}
    after frame "mummy_pin [expr {{$n - 1}}]"
}}
proc fb_watch {{n}} {{
    if {{$n <= 0}} return
    if {{[count_type 9] > 0}} {{ set ::fb_seen 1 }}
    after frame "fb_watch [expr {{$n - 1}}]"
}}
proc crush_watch {{n}} {{
    if {{$n <= 0}} return
    if {{[peek {syms["dying_t"]}] > 0}} {{ set ::crushed 1; return }}
    after frame "crush_watch [expr {{$n - 1}}]"
}}
proc find_type {{t}} {{
    for {{set i 0}} {{$i < 8}} {{incr i}} {{ if {{[peek [expr {{{objt} + $i*{obj_size}}}]] == $t}} {{ return [expr {{{objt} + $i*{obj_size}}}] }} }}
    return -1
}}
proc count_type {{t}} {{
    set n 0
    for {{set i 0}} {{$i < 8}} {{incr i}} {{ if {{[peek [expr {{{objt} + $i*{obj_size}}}]] == $t}} {{ incr n }} }}
    return $n
}}
proc clear_type {{t}} {{
    for {{set i 0}} {{$i < 8}} {{incr i}} {{ set b [expr {{{objt} + $i*{obj_size}}}]; if {{[peek $b] == $t}} {{ poke $b 0 }} }}
}}
# put the boss at box x (y 40), hovering, a few frames before it may fire
proc boss_pin {{n}} {{
    if {{$n <= 0}} return
    set b [find_type 10]
    if {{$b >= 0 && [peek [expr {{$b + 9}}]] != 4}} {{
        set x [expr {{[peek {px_a}] + 256*[peek {px_a + 1}] + 10}}]
        poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
        poke [expr {{$b+3}}] [expr {{[peek {py}] + 4}}]; poke [expr {{$b+9}}] 3
        poke {syms["boss_t"]} 200; poke {syms["boss_frz"]} 0
    }}
    after frame "boss_pin [expr {{$n - 1}}]"
}}
# the boss hovering at x, its hover ending the next frame: below Simon (1)
# or above him (0)
proc boss_place {{x below}} {{
    for {{set i 0}} {{$i < 8}} {{incr i}} {{
        set b [expr {{{objt} + $i*{obj_size}}}]
        if {{[peek $b] != 10}} continue
        poke [expr {{$b+1}}] [expr {{$x & 255}}]; poke [expr {{$b+2}}] [expr {{$x >> 8}}]
        poke [expr {{$b+3}}] [expr {{$below ? [peek {py}] + 40 : 8}}]; poke [expr {{$b+9}}] 3
        poke {syms["boss_t"]} 2; poke {syms["boss_frz"]} 0
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
            # the whip hits on one frame, 17 frames into the swing (NES): a
            # running panther (2 px a frame) is struck at ~34 px nearer
            if {{[peek $b] == 6 && $d >= 14 && $d <= 60}} {{ poke {fa} 0; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
            if {{[peek $b] == 6 && $d <= -14 && $d >= -60}} {{ poke {fa} 1; keymatrixdown 4 0x04; after time 0.05 {{ keymatrixup 4 0x04 }} }}
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
# the debug menu (when built in): leave it as START would, whenever it is up
proc menu_watch {{}} {{
    if {{{1 if "debug_menu" in syms else 0} && [peek {syms.get("dbg_active", 0)}] == 1}} {{
        if {{![info exists ::menu_seen]}} {{
            set ::menu_seen 1
            set f [open "{result_file}" a]; puts $f "debug_menu 1"; close $f
        }}
        poke {syms.get("dbg_go", 0)} 1
    }}
    after time 0.05 menu_watch
}}
menu_watch
after time 0.1 wait_game
after time 200 {{ exit }}
"""


def gate_ok(masks):
    """pattern masks (left.right) during the gate walk: from whole (255.255),
    through every width, to nothing (0.0), each narrower than the last"""
    def width(m):
        l, r = (int(v) for v in m.split("."))
        return bin(l).count("1") + bin(r).count("1")
    ws = [width(m) for m in masks.split("/")]
    if ws and ws[0] == 0:
        ws = ws[1:]             # (the masks' RAM before the sequence's first frame)
    return ws[0] == 16 and ws[-1] == 0 and ws == sorted(ws, reverse=True) and len(ws) == 17


def door_ok(states):
    """door tiles seen at the door's column (row 5) and the next: ... half open,
    open, half open, shut, where shut is the map's own door (the first entry
    can be a column the test's teleport left on screen)"""
    st = states.split("/")
    tiles_path = os.path.join(os.path.dirname(ROM), "gen", "converted", "area_1", "level_tiles.bin")
    if not os.path.exists(tiles_path):
        return False
    t = open(tiles_path, "rb").read()
    door = f"{t[191 * 22 + 5]}.{t[192 * 22 + 5]}"    # the hall's door column (see convert_stage.py)
    # (later the screen scrolls on and other columns take these places)
    return any(half == half2 and opened not in (half, shut) and shut == door
               for half, opened, half2, shut in zip(st, st[1:], st[2:], st[3:]))


def axe_ok(track):
    """the axe's path (x:y:state, one per frame): x +2 per frame, up then down"""
    raw = [tuple(int(v) for v in p.split(":")[:2]) for p in track.split(",") if p]
    # a frame the game ran late shows the same point twice, then a double
    # step: drop the repeat and allow 4 px right after it
    pts, steps = [], []
    for p in raw:
        if pts and p == pts[-1]:
            steps.append("late")
            continue
        if pts:
            steps.append(p[0] - pts[-1][0])
        pts.append(p)
    if len(pts) < 20:
        return False
    ok_steps, late = True, False
    for st in steps:
        if st == "late":
            late = True
            continue
        ok_steps &= st == 2 or (late and st == 4)
        late = False
    xs, ys = [p[0] for p in pts], [p[1] % 256 for p in pts]   # (y is a byte)
    top = ys.index(min(ys))
    falling = ys[top:]
    return (ok_steps
            and 3 < top < len(ys) - 3 and ys[-1] > ys[top] + 20 and ys[0] > ys[top] + 20
            and all(b >= a for a, b in zip(falling, falling[1:])))   # never back up


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
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
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
    boss_hp = boss_awake = boss_sleepf = None
    zfall = None
    floor_fires = None
    sound = None
    asleep_hit = None
    boss_maxy = boss_fire = boss_near_fire = 0
    rules = {}
    weapons = {}
    subs = {}
    seqs = {}
    high_item = None
    stun = None
    whip_reach = 43                     # WHIP_HIT_X2 in src/config.inc (leather whip)
    orb_seen = clear_t = None
    block2_enemies = {}
    menu_seen = False
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
            if tag == "sound":
                sound = tuple(int(v) for v in kv)
                continue
            if tag == "asleep_hit":
                asleep_hit = (int(kv[0]), int(kv[1]))
                continue
            if tag == "floor_fires":
                floor_fires = int(kv[0])
                continue
            if tag == "zfall":
                zfall = [[int(v) for v in k.split(",")] for k in kv]
                continue
            if tag == "stun":
                stun = (kv[0].split(","), kv[1].split(","))
                continue
            if tag == "high_item":
                high_item = (int(kv[0]), int(kv[1]))
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
                boss_hp, boss_awake, boss_sleepf = int(kv[0]), int(kv[1]), int(kv[2])
                continue
            if tag == "orb":
                orb_seen, clear_t, boss_fire, boss_near_fire = (int(v) for v in kv)
                continue
            if tag == "fish":
                fish_seen = int(kv[0])
                continue
            if tag == "debug_menu":
                menu_seen = True
                continue
            if tag in ("medusa", "s4enemies", "hbat", "knight1", "knight2", "crush",
                       "medusa_wake", "medusa_dead", "b3ghost", "b3pillar", "mummies",
                       "mummies_dead"):
                block2_enemies[tag] = kv
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
    # strike: 9 frames; the whip hits on one of them, the 5th (NES $E40B)
    expected_whip = ([(4, 0)] * 5 + [(5, 0)] * 7 + [(6, 0)] * 4 + [(6, 1)] + [(6, 0)] * 4
                     + [(7, 0)] * 2 + [(0, 0)])
    actual_whip = whip_seq[start:start + len(expected_whip)] if start is not None else []
    def frame_bytes(area, name):
        """an area's sprite list for a frame (from its frame table)"""
        d = os.path.join(BUILD, "gen", gen, f"area_{area}")
        inc = open(os.path.join(d, f"a{area}_obj_frames.inc")).read()
        off = int(re.search(rf"_frames\+(\d+)\s*; {name}\n", inc).group(1))
        data = open(os.path.join(d, f"a{area}_obj_frames.bin"), "rb").read()
        return data[off:off + 1 + 4 * data[off]]
    stage3_walk = (gen == "converted" and
                   frame_bytes(4, "zombie_l1") != frame_bytes(4, "zombie_l2") and
                   frame_bytes(4, "zombie_r1") != frame_bytes(4, "zombie_r2"))
    n_areas = len([d for d in os.listdir(os.path.join(BUILD, "gen", gen)) if d.startswith("area_")])
    block2 = n_areas > 5
    stage4, stage4_time = (5, 400) if block2 else (0, 300)    # after the stage 3 boss
    checks = [
        *([("the debug menu comes up at power-up", menu_seen)] if "debug_menu" in syms else []),
        ("the music plays on the PSG and the whip has a sound effect",
         sound is not None and sound[0] > 0 and sound[1] == 1 and sound[2] == 1),
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
        ("whip runs wind-up 5 / swing 7 / strike 9 (hits on 1) / recovery 2 frames",
         actual_whip == expected_whip),
        ("whip hit box reaches 28 px in front (facing left)",
         strike["whip_x1"] == strike["px"] - 28 and strike["whip_x2"] == strike["px"] - 5),
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
           (f"jumping into the gate or a door: the sequence waits for the landing, "
            f"Simon stays on the floor ({seqs['ys']})",
            sorted(seqs["ys"].split(",")) == ["d32", "g112"]),
           ("at the hall's door the screen scrolls on to the door (camera 1408)",
            seqs["door"].split(",")[0] == "1408" or int(seqs["door"].split(",")[0]) > 1408),
           ("the door opens (half open, then open), and closes again behind Simon",
            door_ok(seqs["doorstates"])),
           (f"Simon goes behind the castle gate's pillar a column at a time ({seqs['gatemasks']})",
            gate_ok(seqs["gatemasks"])),
           (f"the next stage takes over without a jump: Simon's screen x at the end of the "
            f"door is his start x there ({seqs['screenx']})",
            int(seqs["screenx"]) in (39, 40) and snaps["18_through_the_door"]["cur_area"] == 2),
           ("after the door he walks on only to the next stage's start (not off the ledge)",
            # (the next area loads on the frame he gets there: the test sees 1 px less)
            int(seqs["walk"].split(",")[1]) > 0
            and 0 <= int(seqs["walk"].split(",")[1]) - int(seqs["walk"].split(",")[0]) <= 1)]
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
        *([("stage 3's zombies keep both walking frames (they share patterns with the boss)",
            stage3_walk)] if gen == "converted" else []),
        *([("asleep (Simon left of the screen's middle), the boss stays asleep and can't be hurt",
            asleep_hit == (64, 0))] if asleep_hit else []),
        *([("asleep, the stage 3 boss is the small hanging bat (NES)", boss_sleepf == 55)]
          if boss_sleepf is not None else []),
        *([("a zombie walking off stage 3's upper platform falls to the floor and walks on",
            zfall[0][0] == 5 and zfall[1][0] == 5 and zfall[0][2] == 64
            and zfall[1][2] == 128 and zfall[1][3] == 0 and zfall[1][1] < zfall[0][1])]
          if zfall else []),
        *([("the stage 3 boss wakes up and the whip hurts it", boss_awake == 1 and boss_hp < 64),
           ("the screen locks at the boss: walking left doesn't scroll back",
            snaps["27a_boss_left"]["cam_x"] == 512 and snaps["27a_boss_left"]["px"] < 530),
           (f"the boss swoops down to Simon waiting on the floor (lowest box top {boss_maxy})",
            boss_maxy >= 112 and snaps["27c_floor_end"]["hp"] < snaps["27b_floor_start"]["hp"]),
           ("a hover ending with Simon above it: the boss spits a fireball at him (NES)",
            boss_fire >= 1),
           ("with Simon below it, it swoops instead", boss_near_fire == 0),
           ("beaten, it leaves an orb; taking it clears the stage", orb_seen == 1 and clear_t > 0
            and snaps["29_stage_clear"]["hp"] == 64),
           ("the tally: the timer runs down to 0, 10 points a step (NES)",
            rules["tally_time"]["time"] == "0000" and rules["tally_time"]["phase"] == "3"
            and int(rules["tally_time"]["score"]) == int(rules["before_orb"]["score"]) + 120),
           ("then the hearts, 100 points each (NES)",
            rules["tally_hearts"]["hearts"] == "0" and rules["tally_hearts"]["phase"] == "4"
            and int(rules["tally_hearts"]["score"]) == int(rules["tally_time"]["score"])
            + 100 * int(rules["tally_time"]["hearts"])),
           ("after the stage clear the next block starts: 5 hearts, the stage's timer",
            snaps["30_restart"]["cur_area"] == stage4 and snaps["30_restart"]["hearts"] == 5
            and rules["after_clear"]["phase"] == "0"
            and stage4_time - 10 < int(rules["after_clear"]["time"]) <= stage4_time)]
          if boss_hp is not None and "30_restart" in snaps else []),
        *([("kills score points, shown in the HUD",
            int(rules["after_clear"]["score"]) > 0
            and rules["after_clear"]["hud"] == rules["after_clear"]["score"]),
           ("the timer counts down from the stage's start",
            0 < int(rules["after_clear"]["time"]) < stage4_time),
           ("when time runs out Simon dies (death animation)",
            int(rules["dying"]["dying"]) > 0 and int(rules["dying"]["pose"]) in (14, 15)),
           ("then he loses a life and restarts with full health and time",
            int(rules["after_death"]["lives"]) == int(rules["after_clear"]["lives"]) - 1
            and rules["after_death"]["dying"] == "0" and rules["after_death"]["hp"] == "64"
            and int(rules["after_death"]["time"]) >= stage4_time - 2),
           ("dying with no lives left is game over",
            int(rules["game_over"]["over"]) > 0),
           ("after game over a new game starts: score 0, 3 lives",
            rules["new_game"]["score"] == "000000" and rules["new_game"]["lives"] == "3"
            and rules["new_game"]["area"] == "0")]
          if "new_game" in rules else []),
        *([("stage 4 starts on its floor, the camera at its one screen (NES: x 320, camera 256)",
            snaps["40_stage4"]["cur_area"] == 5 and snaps["40_stage4"]["px"] == 568
            and snaps["40_stage4"]["cam_x"] == 512),
           ("stage 4's first staircase leads up to the ledge",
            snaps["41_stage4_stairs"]["py"] == 64 and snaps["41_stage4_stairs"]["stair_state"] == 0),
           ("its long staircase leads up into section 1",
            snaps["42_stage4_upper"]["cur_area"] == 6 and snaps["42_stage4_upper"]["py"] == 64),
           ("the door at the left end: the screen scrolls left to it, Simon walks through",
            snaps["43_door_left"]["cur_area"] == 6 and snaps["43_door_left"]["cam_x"] < 256
            and snaps["43_door_left"]["facing"] == 1),
           ("stage 5 starts at its right end, facing left (NES: x 720, camera 512)",
            snaps["44_stage5"]["cur_area"] == 7 and snaps["44_stage5"]["px"] == 968
            and snaps["44_stage5"]["cam_x"] == 768 and snaps["44_stage5"]["facing"] == 1)]
          if block2 and "44_stage5" in snaps else []),
        *([("Medusa heads fly at Simon in stage 5", int(block2_enemies["medusa"][0]) >= 1),
           ("stage 4 has its spear knight and its bat, hanging",
            block2_enemies["s4enemies"][:3] == ["1", "1", "60"]),
           ("the bat flies at Simon when he comes near it and hurts him",
            block2_enemies["hbat"][0] == "0" and int(block2_enemies["hbat"][1]) < 64),
           ("a spear knight takes two whip hits, then gives 400 points",
            block2_enemies["knight1"][0] == "1" and block2_enemies["knight2"][0] == "0"
            and int(block2_enemies["knight2"][2]) - int(block2_enemies["knight2"][1]) == 4)]
          if block2 and "knight2" in block2_enemies else []),
        *([("stage 6's ceiling crushers crush Simon standing under one",
            block2_enemies["crush"] == ["9", "1"])]
          if block2 and "crush" in block2_enemies else []),
        *([("Medusa wakes in her room: the statue goes, the screen locks, her health in the HUD",
            block2_enemies["medusa_wake"][0] in ("1", "2", "3") and block2_enemies["medusa_wake"][1] == "1"
            and block2_enemies["medusa_wake"][2] == block2_enemies["medusa_wake"][3]
            and block2_enemies["medusa_wake"][4] == "64"),
           ("beaten, Medusa burns and leaves the orb",
            block2_enemies["medusa_dead"] == ["0", "1"])]
          if block2 and "medusa_dead" in block2_enemies else []),
        *([("stage 7 starts at its right end, facing left (NES: x 720, camera 512)",
            snaps["50_stage7"]["cur_area"] == 11 and snaps["50_stage7"]["px"] == 712
            and snaps["50_stage7"]["cam_x"] == 512 and snaps["50_stage7"]["facing"] == 1)]
          if n_areas > 11 and "50_stage7" in snaps else []),
        *([("stage 7's ghost appears when Simon comes near and floats at him",
            block2_enemies["b3ghost"][0] == "1" and int(block2_enemies["b3ghost"][1]) != 664),
           ("stage 9's bone pillars stand and fire at Simon",
            int(block2_enemies["b3pillar"][0]) >= 1 and block2_enemies["b3pillar"][1] == "1")]
          if n_areas > 11 and "b3pillar" in block2_enemies else []),
        *([("the mummies both wake when the screen reaches their room; it locks",
            block2_enemies["mummies"] == ["2", "1", "1", "64"]),
           ("beaten, the mummies burst and the last leaves the orb",
            block2_enemies["mummies_dead"] == ["0", "0", "1"])]
          if n_areas > 11 and "mummies_dead" in block2_enemies else []),
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
           ("holy water's fire burns through the NES flame pictures (small 1-3, wide)",
            {47, 48, 49, 52} <= {int(p.split(":")[3]) for p in weapons["holy"]["track"].split(",")
                                 if p and p.split(":")[2] == "1"}),
           ("holy water costs one heart, lands, burns, and burns down a brazier",
            weapons["holy"]["hearts"] == "9" and ":1:" in weapons["holy"]["track"]
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
        *([("an item from a candle above the playfield's top falls into view (holy water)",
            high_item[0] == 3 and high_item[1] < 176)]
          if high_item else []),
        *([("holy water's fire holds the boss (it can't move) and keeps hurting it",
            stun[0][:2] == stun[1][:2] and int(stun[1][2]) <= int(stun[0][2]) - 5)]
          if stun else []),
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
