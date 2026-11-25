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
subweapon       equ whip_level+1        ; 1  0 none, 1 dagger
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
zombie_wave     equ zombie_side+1    ; 1  zombies spawned in this wave
enemies_off     equ zombie_wave+1       ; 1  test hook: bit 0 = no zombies, bit 1 = no panthers
player_dead     equ enemies_off+1       ; 1  set when health runs out
spr_hide        equ player_dead+1       ; 1  Simon blinks this frame
kills           equ spr_hide+1          ; 1  enemies defeated (for the score later)
sct_cache       equ kills+1             ; 2*MAX_SPRITES: colour column per sprite, per page
spr_sat_ptr     equ sct_cache+2*MAX_SPRITES ; 2  next sat_buf entry (objects_draw)

sat_buf         equ spr_sat_ptr+2       ; (MAX_SPRITES+1)*4

keep_player     equ sat_buf+(MAX_SPRITES+1)*4 ; 1  load_area keeps Simon (section change)
RAM_END         equ keep_player+1
        ASSERT RAM_END < 0xF380
