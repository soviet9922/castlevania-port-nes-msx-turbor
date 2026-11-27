; ---------------------------------------------------------------------------
; RAM variables (page 3). Laid out as an equ chain: name, then size.
; Keep RAM_END below the BIOS work area (0xF380).
; ---------------------------------------------------------------------------

RAM_BASE        equ 0xC000

frame_ready     equ RAM_BASE            ; 1  set by VBLANK interrupt
frame_count     equ frame_ready+1       ; 2  total VBLANKs (debug / tests)
line_irq_count  equ frame_count+2       ; 2  total line interrupts (debug / tests)
scroll_r26      equ line_irq_count+2    ; 1  playfield horizontal scroll, coarse
scroll_r27      equ scroll_r26+1        ; 1  playfield horizontal scroll, fine

cam_x           equ scroll_r27+1        ; 2  camera world x (px)
cam_new         equ cam_x+2             ; 2  scratch
new_col         equ cam_new+2           ; 2  scratch

col_pending     equ new_col+2           ; 1  1 = col_buf must be uploaded
col_slot        equ col_pending+1       ; 1  name table column (0..31)
col_buf         equ col_slot+1          ; PF_ROWS tile numbers

stick           equ col_buf+PF_ROWS     ; 1  direction 0..8
trig_prev       equ stick+1             ; 1
jump_pressed    equ trig_prev+1         ; 1  non-zero on the frame jump is pressed

px              equ jump_pressed+1      ; 2  player world x (left edge of 16x32 box)
py              equ px+2                ; 2  player y in playfield px (signed)
jump_idx        equ py+2                ; 1  position in the jump arc (0..2*JUMP_LEN)
crouching       equ jump_idx+1          ; 1
pyoff           equ crouching+1         ; 1  sprite y offset for the current pose
anim_step       equ pyoff+1             ; 1  walk cycle position 0..3
on_ground       equ anim_step+1         ; 1
walk_dx         equ on_ground+1         ; 1  -1/0/+1 this frame
air_dx          equ walk_dx+1           ; 1  horizontal speed locked at take-off
facing          equ air_dx+1            ; 1  0 = right, 1 = left
pframe          equ facing+1            ; 1  animation frame 0..3
anim_t          equ pframe+1            ; 1
new_x           equ anim_t+1            ; 2  scratch
probe_off       equ new_x+2             ; 1  scratch

whip_t          equ probe_off+1         ; 1  0 = not whipping, else frame 1..WHIP_END-1
whip_prev       equ whip_t+1            ; 1
whip_pressed    equ whip_prev+1         ; 1
whip_active     equ whip_pressed+1      ; 1  1 while the whip can hit
whip_x1         equ whip_active+1       ; 2  hit box, world coordinates
whip_x2         equ whip_x1+2           ; 2
whip_y1         equ whip_x2+2           ; 2  playfield y
whip_y2         equ whip_y1+2           ; 2
cur_frame       equ whip_y2+2           ; 1  metasprite frame shown (facing*NPOSES+pose)
loaded_frames   equ cur_frame+1         ; 2  frame whose patterns are in sprite page 0 / 1
spr_page        equ loaded_frames+2     ; 1  sprite page being displayed (0/1)
spr_back        equ spr_page+1          ; 1  scratch: page being written
flip_pending    equ spr_back+1          ; 1  1 = show the other page at VBLANK
spr_bx          equ flip_pending+1      ; 2  scratch: player screen x
spr_by          equ spr_bx+2            ; 2  scratch: player sprite y
spr_pat         equ spr_by+2            ; 1  scratch
spr_total       equ spr_pat+1           ; 1  sprites in sat_buf this frame
spr_player_n    equ spr_total+1         ; 1  of which Simon's
obj_sct_list    equ spr_player_n+1      ; MAX_SPRITES colour column per sprite
obj_table       equ obj_sct_list+MAX_SPRITES ; OBJ_MAX*OBJ_SIZE
hearts          equ obj_table+OBJ_MAX*OBJ_SIZE ; 1
whip_level      equ hearts+1            ; 1  0 leather, 1 chain, 2 morning star
subweapon       equ whip_level+1        ; 1  0 none, 1 dagger, 2 axe, 3 holy water, 4 stopwatch
hud_dirty       equ subweapon+1         ; 1

area_hdr        equ hud_dirty+1         ; AH_SIZE copy of the current area's header
cur_area        equ area_hdr+AH_SIZE    ; 1
candle_dead     equ cur_area+1          ; MAX_CANDLES/8 bits: destroyed candles
candle_live     equ candle_dead+MAX_CANDLES/8 ; bits: candles that have an object
spawn_last      equ candle_live+MAX_CANDLES/8 ; 2  camera x / 16 at the last spawn pass
tmp_w           equ spawn_last+2        ; 2  scratch
stair_state     equ tmp_w+2             ; 1  0 off, 1 walking to the stair end, 2 on the stairs
stair_ptr       equ stair_state+1       ; 2  stair record
stair_tx        equ stair_ptr+2         ; 2  x of the end being walked to
stair_dir       equ stair_tx+2          ; 1  +1 / -1: which way the stairs rise
stair_going     equ stair_dir+1         ; 1  +1 up / -1 down
stair_phase     equ stair_going+1       ; 1  alternates x and y steps
stair_anim      equ stair_phase+1       ; 1  climbing animation counter
hp              equ stair_anim+1        ; 1  Simon's health (0..HP_MAX)
invuln_t        equ hp+1                ; 1  frames left of invincibility (blinking)
hurt_state      equ invuln_t+1          ; 1  0, HURT_FREEZE, HURT_FLY, HURT_STUN
hurt_t          equ hurt_state+1        ; 1  frames left in the hurt state
arc_ptr         equ hurt_t+1            ; 2  arc table in use (jump or knock-back)
arc_len         equ arc_ptr+2           ; 1  its rising length
zombie_spawn_t  equ arc_len+1           ; 1
zombie_side     equ zombie_spawn_t+1    ; 1  alternates the screen edge
zombie_wave     equ zombie_side+1    ; 1  zombies made, counted to 3 (the NES's $63)
enemies_off     equ zombie_wave+1       ; 1  test hook: bit 0 = no zombies, bit 1 = no panthers
player_dead     equ enemies_off+1       ; 1  set when health runs out
spr_hide        equ player_dead+1       ; 1  Simon blinks this frame
kills           equ spr_hide+1          ; 1  enemies defeated (for the score later)
sct_cache       equ kills+1             ; 2*MAX_SPRITES: colour column per sprite, per page
spr_sat_ptr     equ sct_cache+2*MAX_SPRITES ; 2  next sat_buf entry (objects_draw)

sat_buf         equ spr_sat_ptr+2       ; (MAX_SPRITES+1)*4

keep_player     equ sat_buf+(MAX_SPRITES+1)*4 ; 1  load_area keeps Simon (section change)
spawner_type    equ keep_player+1       ; 1  type of the spawner being handled
bat_spawn_t     equ spawner_type+1      ; 1  frames until the next bat
fish_spawn_t    equ bat_spawn_t+1       ; 1
fish_pick       equ fish_spawn_t+1      ; 1  last fishman spawner used
boss_hp         equ fish_pick+1         ; 1  shown in the HUD's enemy bar
boss_inv        equ boss_hp+1           ; 1  frames until it can be hit again
boss_tx         equ boss_inv+1          ; 2  where it is flying to
boss_ty         equ boss_tx+2           ; 1
clear_t         equ boss_ty+1           ; 1  frames left in this stage clear phase
clear_phase     equ clear_t+1           ; 1  stage clear: 0 playing, 1 jingle, 2 timer,
                                        ;    3 hearts, 4 outro
cam_lock        equ clear_phase+1       ; 1  camera can't go back left (boss)
cam_min         equ cam_lock+1          ; 2  leftmost camera x while locked
score           equ cam_min+2           ; 3  BCD, low byte first (always 00)
time_bcd        equ score+3             ; 2  BCD, 0x0300 at the start
time_t          equ time_bcd+2          ; 1  frames to the next timer step
lives           equ time_t+1            ; 1
dying_t         equ lives+1             ; 1  death animation countdown (0 = alive)
game_over_t     equ dying_t+1           ; 1
hit_x1          equ game_over_t+1       ; 8  box tested by whip_hits_object (x1 x2 y1 y2)
hit_x2          equ hit_x1+2
hit_y1          equ hit_x1+4
hit_y2          equ hit_x1+6
sub_out         equ hit_x1+8            ; 1  sub-weapons flying (counted each frame)
throwing        equ sub_out+1           ; 1  this whip action throws the sub-weapon
thrown          equ throwing+1          ; 1  ... and it has left his hand
sub_kind        equ thrown+1            ; 1  what is thrown: 1 dagger, 2 axe, 3 holy water, 5 cross
freeze_t        equ sub_kind+1          ; 1  stopwatch: frames the enemies stand still
seq_kind        equ freeze_t+1          ; 1  exit sequence: 0 none, 1 gate, 2 door
seq_phase       equ seq_kind+1          ; 1
seq_t           equ seq_phase+1         ; 2  frames into the phase
door_pending    equ seq_t+2             ; 1  VBLANK: 1 open the door, 2 close it
door_mode       equ door_pending+1      ; 1
hud_parts       equ door_mode+1         ; 1  HUD parts still to redraw (bits 0-2)
seq_hidden      equ hud_parts+1         ; 1  Simon is behind the castle gate
door_src        equ seq_hidden+1        ; 2
door_dst        equ door_src+2          ; 2
clip_l          equ door_dst+2          ; 1  gate: pattern masks for Simon's left
clip_r          equ clip_l+1            ; 1  and right 8 columns
clip_buf        equ clip_r+1            ; 32 a masked pattern
sub_src         equ clip_buf+32         ; 2
sub_len         equ sub_src+2           ; 2
win_slot        equ sub_len+2           ; window being loaded: first pattern
swap_boss       equ win_slot+1          ; 1 = the boss's patterns are in the swap window
page2_bank      equ swap_boss+1         ; 1  the ROM bank the game has at 0x8000
mus_id          equ page2_bank+1        ; 1  music playing (SND_ number, 0xFF none)
mus_state       equ mus_id+1            ; SS_SIZE  music stream (src/sound.asm)
sfx_state       equ mus_state+20        ; SS_SIZE  sound effect stream
snd_frame       equ sfx_state+20        ; 2  frame_count at the last sound step
psg_buf         equ snd_frame+2         ; 11 PSG registers being written
medusa_t        equ psg_buf+11          ; 1  frames to the next Medusa head check
crush_state     equ medusa_t+1          ; 2*CRUSH_MAX  per crusher: cycle step, frames left
crush_next      equ crush_state+8       ; 1  crusher redrawn in the next VBLANK
crush_drawn     equ crush_next+1        ; CRUSH_MAX  spike row last drawn (0xFF = redraw)
med_t           equ crush_drawn+CRUSH_MAX ; 1  Medusa: frames to her next pause / in it
med_erase       equ med_t+1             ; 1  VBLANK: erase her statue
med_col         equ med_erase+1         ; 2  the statue's first tile column
med_row         equ med_col+2           ; 1  ... and playfield row
obj_hits        equ med_row+1           ; OBJ_MAX  block 3's tough enemies: hits taken
                                        ;    (bits 5-7) and frames of flash (0-4)
dbg_active      equ obj_hits+8          ; 1  the debug menu is up
dbg_go          equ dbg_active+1        ; 1  (tests: leave the menu, as START)
dbg_sel         equ dbg_go+1            ; 1  menu line chosen
dbg_stage       equ dbg_sel+1           ; 1  start stage (1-9)
dbg_hp          equ dbg_stage+1         ; 1  infinite health
dbg_time        equ dbg_hp+1            ; 1  infinite time
dbg_music       equ dbg_time+1          ; 1  sound test: music number (SND_)
dbg_sfx         equ dbg_music+1         ; 1  ... effect number
dbg_stick       equ dbg_sfx+1           ; 1  stick last frame (one step a press)
hit_src         equ dbg_stick+1         ; 1  weapon_hits: what hit (0 whip, else sub_kind)
medusa_on       equ hit_src+1           ; 1  bit 0: a head spawner near now, bit 1: last frame
med_wake        equ medusa_on+1         ; 1  Medusa: frames until she starts (0: asleep / awake)
med_idx         equ med_wake+1          ; 1  ... her next flight length (index)
med_vy          equ med_idx+1           ; 2  ... y speed (8.8, + down in the wave)
med_yf          equ med_vy+2            ; 1  ... y fraction
med_frz         equ med_yf+1            ; 1  ... frames frozen by a hit
rng             equ med_frz+1           ; 1  random byte (as the NES's $6F, a step a frame)
drop_idx        equ rng+1               ; 1  enemies' sub-weapon drops: next of the stage's 4
obj_ext         equ drop_idx+1          ; 4*OBJ_MAX  per slot: x fraction, y fraction, speed (2)
spawner_sx      equ obj_ext+4*OBJ_MAX   ; 2  the active spawner's screen x
spawner_x       equ spawner_sx+2        ; 2  the active spawner's world x
spawner_i       equ spawner_x+2         ; 1  its index in the area's list
spawn_tick      equ spawner_i+1         ; SPAWNERS_MAX  per spawner: ticks (2 frames) to wait
spawn_st        equ spawn_tick+SPAWNERS_MAX ; SPAWNERS_MAX  0 off the screen, 1 just on, 2 on
spawn_cnt       equ spawn_st+SPAWNERS_MAX ; SPAWNERS_MAX  per spawner: a counter (eagles' heights)
boss_t          equ spawn_cnt+SPAWNERS_MAX ; 1  the bat boss: frames in its state
boss_frz        equ boss_t+1            ; 1  ... frames stopped by a hit
boss_vx         equ boss_frz+1          ; 2  ... speed across (8.8, along its facing)
boss_vy         equ boss_vx+2           ; 2  ... speed down (8.8, signed)
boss_xf         equ boss_vy+2           ; 1  ... fractions
boss_yf         equ boss_xf+1           ; 1
part_table      equ boss_yf+1           ; PARTS_MAX*OBJ_SIZE  drawn-only objects (as obj_table)
drg_state       equ part_table+PARTS_MAX*OBJ_SIZE ; 1  the bone dragon's head: state
drg_t           equ drg_state+1         ; 1  ... its timer
drg_frz         equ drg_t+1             ; 1  ... frames frozen by a hit
drg_dmg         equ drg_frz+1           ; 1  ... damage taken (192: dead)
drg_parts       equ drg_dmg+1           ; 6*6  head, vertebrae 1-5: x offset, y dir,
                                        ;      y offset (8.8), speed (8.8)
cur_ovl         equ drg_parts+36        ; 1  the RAM overlay loaded (0 none, 1, 2)
fire_speed      equ cur_ovl+1           ; 1  fire_aimed: speed (1/64 px)
fire_dy         equ fire_speed+1        ; 1  ... its target below Simon's top (+ 8)
fire_max        equ fire_dy+1           ; 1  ... at most this many out
drac_form       equ fire_max+1          ; 1  Dracula: 0 first form, 1 the monster
drac_set        equ drac_form+1         ; 1  ... the swap set loaded (drac_show)
drac_vis        equ drac_set+1          ; 1  ... his body is drawn
drac_head       equ drac_vis+1          ; 1  ... head: 0 none, 1 shown, 2 flying off
drac_frac       equ drac_head+1         ; 1  ... damage fraction (1/16)
drac_hvy        equ drac_frac+1         ; 2  ... the flying head: vy (8.8, + = up)
drac_hyf        equ drac_hvy+2          ; 1  ... its y fraction
drac_box        equ drac_hyf+1          ; OBJ_SIZE  his head's box (whip tests)
whip_wait       equ drac_box+OBJ_SIZE   ; 1  a whip pressed on the ground starts next frame
crouch_t        equ whip_wait+1         ; 1  frames crouched after a landing / a hit
fall8           equ crouch_t+1          ; 1  frames falling at 8 px (crouched landing)
anim_acc        equ fall8+1             ; 1  walk animation counter (+36 a frame)
jump_skip       equ anim_acc+1          ; 1  the take-off frame: no y move yet
stair_frz       equ jump_skip+1         ; 1  hit on the stairs: frozen frames
pwr_out         equ stair_frz+1         ; 1  a power-up item is out (NES $72)
subhits         equ pwr_out+1           ; 1  sub-weapon hits since the last shot item ($79)
shot_n          equ subhits+1           ; 1  0 single, 1 double, 2 triple shot ($64)
potion_t        equ shot_n+1            ; 1  invisible: frames / 2 left ($5B)
rosary_t        equ potion_t+1          ; 1  rosary: frames / 2 left ($015D)
shot_blink      equ rosary_t+1          ; 1  the HUD's II/III mark blinks: frames left ($0141)
WALL_BYTES      equ 8                   ;    2 bits per area (src/walls.asm)
wall_bits       equ shot_blink+1        ; 8  broken walls of every area
walls_now       equ wall_bits+WALL_BYTES ; 1  ... of the current area
probe_col       equ walls_now+1         ; 2  solid_at's tile column
probe_row       equ probe_col+2         ; 1  ... and row
wall_row        equ probe_row+1         ; 1  wall_redraw
RAM_END         equ wall_row+1
        ASSERT RAM_END < 0xF380
        ASSERT RAM_END <= RAMCODE
RAMCODE         equ 0xC400              ; code copied from ROM (src/ramcode.asm)
RAMCODE_TOP     equ 0xF000              ; (the stack is above, from about 0xF370 down: 880 bytes)
