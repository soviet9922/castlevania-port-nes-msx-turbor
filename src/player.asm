; ---------------------------------------------------------------------------
; Player (Simon), following the NES game's movement model:
;  - walks at 1 px per frame; crouches with DOWN (and cannot walk then)
;  - the jump is a fixed arc read from jump_table: JUMP_LEN signed steps
;    while rising, the same steps mirrored while falling, then MAX_FALL_PX
;  - horizontal speed is decided at take-off and cannot be steered
;
; The player is a 16x32 box at (px, py); py is relative to the playfield top.
; ---------------------------------------------------------------------------

player_reset:
        ld hl,(area_hdr+AH_STARTX)
        ld (px),hl
        ld hl,(area_hdr+AH_STARTY)
        ld (py),hl
        xor a
        ld (jump_idx),a
        ld (stair_state),a
        ld (hurt_state),a
        ld (invuln_t),a
        ld (crouching),a
        ld (pyoff),a
        ld (pframe),a
        ld (air_dx),a
        ld (anim_t),a
        ld (anim_step),a
        ld (whip_t),a
        ld (whip_active),a
        ld (whip_wait),a
        ld (crouch_t),a
        ld (fall8),a
        ld (jump_skip),a
        ld (stair_frz),a
        inc a
        ld (on_ground),a
        ld a,(area_hdr+AH_FACE)
        ld (facing),a
        ret

; Fell into a pit: the life is lost straight away (no death animation).
respawn:
        ld a,1
        jr start_death

; Main loop: health or time ran out -> the death animation, then a life is lost
check_death:
        ld a,(player_dead)
        or a
        ret z
        xor a
        ld (player_dead),a
        ld a,DEATH_FRAMES
start_death:
        ld (dying_t),a
        ld a,SND_DEATH
        call music_restart
        xor a
        ld (whip_t),a
        ld (whip_active),a
        ld (hurt_state),a
        ld (invuln_t),a
        ld (pyoff),a
        ld (stair_state),a
        ld a,POSE_DEAD1
        ld (pframe),a
        ret

; One frame of the death animation (main loop, instead of the game logic).
; Falling pose for DEATH_POSE1 frames, then lying; at the end a life is lost.
dying_tick:
        ld hl,dying_t
        dec (hl)
        jr z,lose_life
        ld a,(hl)
        cp DEATH_FRAMES-DEATH_POSE1
        ret nc
        ld a,POSE_DEAD2
        ld (pframe),a
        ret

; Lose a life: restart the section (full health, 5 hearts, timer 300), or
; game over when none are left.
lose_life:
        ld a,(lives)
        or a
        jr z,game_over
        dec a
        ld (lives),a
restart_section:
        call restart_section_vars
        ld a,(area_hdr+AH_RESPAWN)
        jp load_area

game_over:
        ld a,SND_GAME_OVER
        call music_restart
        ld a,GAME_OVER_FRAMES
        ld (game_over_t),a
        jp hud_game_over

; Start (or restart after game over) a game: score 0, 3 lives, area 0
new_game:
        xor a
        ld hl,score
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,LIVES_START
        ld (lives),a
        ld a,BOSS_HP
        ld (boss_hp),a
        di
        call hud_draw
        ei
        call restart_section_vars
        ld hl,TIME_START                ; (area_hdr is still the old game's)
        ld (time_bcd),hl
        xor a
        jp load_area

restart_section_vars:
        xor a                           ; (NES: a death costs the whip upgrades
        ld (whip_level),a               ; and the sub-weapon)
        ld (subweapon),a
        ld a,HP_MAX
        ld (hp),a
        ld a,5
        ld (hearts),a
        call set_stage_time
        ld a,1
        ld (hud_dirty),a
        ret

; The timer for the current area's stage, from the NES's table at $C9F6:
; a death or a new block restarts it there (between stages it carries on).
set_stage_time:
        ld a,(area_hdr+AH_STAGE)        ; BCD 1-18 -> 1-18
        ld c,a
        and 0xF0
        rrca
        ld b,a                          ; tens * 8
        rrca
        rrca                            ; tens * 2
        add a,b
        ld b,a                          ; tens * 10
        ld a,c
        and 15
        add a,b
        add a,a
        ld e,a
        ld d,0
        ld hl,stage_times
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (time_bcd),hl
        xor a
        ld (time_t),a
        ret
stage_times:                            ; BCD, stage 0 (not used) to 9
        dw 0x0300, 0x0300, 0x0200, 0x0100, 0x0400, 0x0300, 0x0200, 0x0500, 0x0400, 0x0300
        dw 0x0400, 0x0300, 0x0200, 0x0500, 0x0400, 0x0300, 0x0700, 0x0600, 0x0500

; ---------------------------------------------------------------------------
; Stage clear (NES game mode $0C, measured after the stage 3 boss): the
; jingle, then the timer runs down one step a frame (10 points each, a tick
; every 8 frames), a pause, the hearts go one every 8 frames (100 points
; each), a pause, and the next block starts with 5 hearts and its stage's
; timer. Health was refilled when the orb was taken; the whip and the
; sub-weapon carry on.
; ---------------------------------------------------------------------------
clear_tick:
        ld a,(clear_phase)
        cp 2
        jr z,.timer
        ld hl,clear_t
        dec (hl)
        ret nz
        cp 1
        jr z,.to_timer
        cp 3
        jr z,.heart
        jp clear_done                   ; phase 4: the pause is over
.to_timer:
        ld a,2
        ld (clear_phase),a
        ret
.timer:
        ld hl,(time_bcd)
        ld a,h
        or l
        jr z,.to_hearts
        ld a,l
        sub 1
        daa
        ld l,a
        ld a,h
        sbc a,0
        daa
        ld h,a
        ld (time_bcd),hl
        ld hl,score                     ; + 10 points
        ld a,(hl)
        add a,0x10
        daa
        ld (hl),a
        call c,score_carry
        ld hl,hud_parts                 ; score and time (not the bars)
        set 1,(hl)
        ld hl,clear_t
        inc (hl)
        ld a,(hl)
        and 7
        cp 5
        ret nz
        ld a,SND_TICK
        jp sfx_play
.to_hearts:
        ld a,3
        ld (clear_phase),a
        ld a,CLEAR_HEART_WAIT
        ld (clear_t),a
        ret
.heart:
        ld a,(hearts)
        or a
        jr z,.to_outro
        dec a
        ld (hearts),a
        ld hl,score+1                   ; + 100 points
        ld a,(hl)
        add a,1
        daa
        ld (hl),a
        call c,score_carry
        ld hl,hud_parts                 ; score; hearts
        ld a,(hl)
        or 6
        ld (hl),a
        ld a,CLEAR_HEART_STEP
        ld (clear_t),a
        ld a,SND_TALLY
        jp sfx_play
.to_outro:
        ld a,4
        ld (clear_phase),a
        ld a,CLEAR_OUTRO
        ld (clear_t),a
        ret

; HL = a score byte that overflowed: carry 1 into the bytes above it
score_carry:
        inc hl
        ld a,l
        cp low (score+3)
        ret z
        ld a,(hl)
        add a,1
        daa
        ld (hl),a
        jr c,score_carry
        ret

clear_done:
        xor a
        ld (clear_phase),a
        ld a,BOSS_HP
        ld (boss_hp),a
        ld a,(area_hdr+AH_NEXT)         ; the next block's first area
        call load_area
        ld a,HP_MAX
        ld (hp),a
        ld a,5
        ld (hearts),a
        call set_stage_time
        ld a,1
        ld (hud_dirty),a
        ret

; The timer: one step every TIME_TICK frames; at 0 Simon dies.
timer_tick:
        ld a,(freeze_t)                 ; the stopwatch stops the timer too
        or a
        jr z,.running
        dec a
        ld (freeze_t),a
        ret
.running:
        ld hl,time_t
        inc (hl)
        ld a,(hl)
        cp TIME_TICK
        ret c
        ld (hl),0
        ld hl,(time_bcd)
        ld a,h
        or l
        ret z                           ; already out of time
        ld a,l
        sub 1
        daa
        ld l,a
        ld a,h
        sbc a,0
        daa
        ld h,a
        ld (time_bcd),hl
        ld a,1
        ld (hud_dirty),a
        ld a,h
        or l
        ret nz
        ld a,1                          ; time up
        ld (player_dead),a
        ret

; A = points / 100 (BCD): add to the score; counts the kill
add_score:
        push hl
        ld hl,kills
        inc (hl)
        ld hl,score+1
        add a,(hl)
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        ld a,1
        ld (hud_dirty),a
        pop hl
        ret

arc_jump:
        ld hl,jump_table
        ld (arc_ptr),hl
        ld a,JUMP_LEN
        ld (arc_len),a
        ret

; ---------------------------------------------------------------------------
; Getting hit (NES $96C1). B = direction to knock Simon (+1 right, -1 left).
; On the stairs: frozen STAIR_HIT_FREEZE frames (the whip paused), then
; invincible. Else: with a ceiling over his head he only crouches
; STUN_FRAMES; otherwise frozen HIT_FREEZE frames (his pose as it was), then
; knocked back along the NES arc (facing the enemy, moving away from it), and
; crouched STUN_FRAMES after landing. He blinks, invincible, INVULN_FRAMES
; from the landing (until then the knock-back itself keeps him safe). A hit
; that empties his health still knocks him back: he dies when he lands.
; ---------------------------------------------------------------------------
simon_hurt:
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld a,(stair_frz)
        or a
        ret nz
        ld a,(area_hdr+AH_STAGE)        ; NES $E74A: 8 in stages 1-6,
        cp 7                            ; 12 in 7-11, 16 from 12 (BCD)
        ld c,ZOMBIE_DAMAGE
        jr c,.dmg
        cp 0x12
        ld c,DAMAGE_LATE
        jr c,.dmg
        ld c,DAMAGE_LAST
.dmg:
        ld a,(hp)
        sub c
        jr nc,.hp
        xor a
.hp:
        ld (hp),a
        ld a,1
        ld (hud_dirty),a
        ld a,SND_HURT
        call sfx_play
        ld a,(stair_state)
        cp 2
        jr nz,.not_stairs
        ld a,STAIR_HIT_FREEZE           ; on the stairs: frozen, then invincible
        ld (stair_frz),a
        ld a,INVULN_FRAMES
        ld (invuln_t),a
        ret
.not_stairs:
        xor a
        ld (whip_t),a
        ld (whip_active),a
        ld (whip_wait),a
        ld (stair_state),a
        ld a,b
        ld (air_dx),a
        rlca                            ; knocked right -> face left
        and 1
        xor 1
        ld (facing),a
        ld a,(on_ground)                ; (in the air his y is the jump's)
        or a
        jr z,.no_snap
        ld a,(py)
        and 0xF8
        ld (py),a
.no_snap:
        call head_probe                 ; a ceiling: no knock-back, a crouch
        jr nc,.knock
        ld a,(hp)
        or a
        jr z,.dies
        ld a,STUN_FRAMES
        ld (crouch_t),a
        ld a,1
        ld (crouching),a
        ld a,INVULN_FRAMES
        ld (invuln_t),a
        ret
.knock:
        xor a
        ld (crouching),a
        ld (crouch_t),a
        ld a,HURT_FREEZE
        ld (hurt_state),a
        ld a,HIT_FREEZE
        ld (hurt_t),a
        ret
.dies:
        ld a,1
        ld (player_dead),a
        ret

; Carry if the tile over his head is solid (NES $9998: y - 19 at x - 7, x,
; x + 7: port py - 3 at px + 1, 8, 15)
head_probe:
        ld b,1
        call .at
        ret c
        ld b,8
        call .at
        ret c
        ld b,15
.at:
        ld hl,(py)
        ld de,-3
        add hl,de
        ex de,hl
        ld l,b
        ld h,0
        push bc
        ld bc,(px)
        add hl,bc
        pop bc
        jp solid_at

; Count down the freeze, then start the knock-back.
hurt_tick:
        ld hl,hurt_t
        dec (hl)
        ret nz
        ld a,HURT_FLY
        ld (hurt_state),a
        xor a
        ld (jump_idx),a
        ld (on_ground),a
        ld (fall8),a
        ld hl,kb_table
        ld (arc_ptr),hl
        ld a,KB_LEN
        ld (arc_len),a
        ret

; One frame of Simon (NES $934C): the x move first, then the stairs, A (jump),
; B (whip), DOWN (crouch), in that order
player_update:
        ld a,(invuln_t)
        or a
        jr z,.not_invuln
        dec a
        ld (invuln_t),a
.not_invuln:
        ld a,(hurt_state)               ; hit: frozen (his pose as it was) or
        or a                            ; knocked back
        jr z,.not_hurt
        cp HURT_FLY
        jp z,.in_air
        jp hurt_tick
.not_hurt:
        ld a,(stair_state)
        or a
        jp nz,stairs_update

        ; ---- whip: once started it runs to the end ----
        ld a,(whip_wait)                ; (pressed on the ground last frame)
        or a
        jr z,.no_wait
        xor a
        ld (whip_wait),a
        inc a
        ld (whip_t),a
.no_wait:
        ld a,(whip_t)
        or a
        jr z,.intent
        ld a,(on_ground)
        or a
        jp z,.in_air                    ; in the air the jump arc carries on
        xor a
        ld (walk_dx),a                  ; on the ground Simon stands still
        jp .vertical

        ; ---- intent ----
.intent:
        ld a,(on_ground)
        or a
        jp z,.in_air
        ld a,(crouch_t)                 ; crouched after a landing or a hit:
        or a                            ; he can turn and whip
        jr z,.no_stun
        dec a
        ld (crouch_t),a
        jr nz,.crouched
        xor a                           ; (the last frame: he stands up)
        ld (crouching),a
        ld (walk_dx),a
        jp .vertical
.no_stun:
        ld a,(crouching)                ; crouched: DOWN still held?
        or a
        jr z,.standing
        ld a,(stick)
        cp 4
        jr c,.stand_up
        cp 7
        jr c,.crouched
.stand_up:
        xor a                           ; DOWN let go: he stands up (nothing
        ld (crouching),a                ; else this frame)
        ld (walk_dx),a
        jp .vertical
.crouched:
        ld a,1
        ld (crouching),a
        xor a
        ld (walk_dx),a
        call .turn
        ld a,(whip_pressed)
        or a
        call nz,.whip_ground
        jp .vertical
.standing:
        ld a,(stick)
        call stick_to_dx
        ld (walk_dx),a
        call .turn
        ld a,(stick)                    ; UP near the foot of a staircase
        call stick_vertical
        cp 1
        jr nz,.not_up
        ld c,ST_FOOTX
        call find_stair
        jp c,stairs_begin_up
.not_up:
        ld a,(stick)                    ; DOWN near the top of one
        cp 4
        jr c,.not_down
        cp 7
        jr nc,.not_down
        ld c,ST_TOPX
        call find_stair
        jp c,stairs_begin_down
.not_down:
        ld a,(jump_pressed)             ; A: a jump, if his head is clear
        or a
        jr z,.no_jump
        call head_probe
        jr c,.no_jump
        call arc_jump
        xor a
        ld (jump_idx),a
        ld (on_ground),a
        ld (fall8),a
        inc a
        ld (jump_skip),a                ; (no y move on the take-off frame)
        ld a,(walk_dx)
        ld (air_dx),a
        jr .move_h
.no_jump:
        ld a,(whip_pressed)             ; B: the whip
        or a
        jr z,.no_whip
        call .whip_ground
        jr .move_h
.no_whip:
        ld a,(stick)                    ; DOWN: crouch (the move still happens)
        cp 4
        jr c,.move_h
        cp 7
        jr nc,.move_h
        ld a,1
        ld (crouching),a
        jr .move_h
.turn:                                  ; face the way L/R points
        ld a,(stick)
        call stick_to_dx
        or a
        ret z
        rlca
        and 1                           ; 1 if moving left
        ld (facing),a
        ret
.whip_ground:                           ; starts the next frame
        ld a,1
        ld (whip_wait),a
        jp start_throw
.in_air:
        ld a,(whip_t)                   ; B in the air: a whip at once
        or a
        jr nz,.air_move
        ld a,(hurt_state)
        or a
        jr nz,.air_move
        ld a,(whip_pressed)
        or a
        jr z,.air_move
        ld a,1
        ld (whip_t),a
        call start_throw
.air_move:
        ld a,(air_dx)
        ld (walk_dx),a

        ; ---- horizontal move with collision (NES $9809, $9ECE) ----
.move_h:
        ld a,(walk_dx)
        or a
        jr z,.vertical
        ld e,a
        rla
        sbc a,a
        ld d,a                          ; DE = sign-extended dx
        ld hl,(px)
        add hl,de
        ld (new_x),hl
        ld de,(cam_x)
        or a
        sbc hl,de
        dec hl                          ; his middle stays at screen x 9..239
        bit 7,h
        jr nz,.vertical
        ld de,231
        or a
        sbc hl,de
        jr nc,.vertical
        ld a,(walk_dx)                  ; walls 8 px from his middle, now
        ld c,1                          ; (px + 0 / px + 16 of the old x)
        bit 7,a
        jr nz,.left_edge
        ld c,15
.left_edge:
        ld a,c
        ld (probe_off),a
        ld hl,wall_rows
        ld b,5
.wall:
        ld c,(hl)
        inc hl
        push hl
        push bc
        call side_probe
        pop bc
        pop hl
        jr c,.vertical
        djnz .wall
        ld hl,(new_x)
        ld (px),hl

        ; ---- vertical ----
.vertical:
        ld a,(on_ground)
        or a
        jr z,.airborne
        ld c,32                         ; anything under the feet?
        call foot_probe
        jp c,player_animate
        call arc_jump                   ; walked off a ledge (NES $9757): 8 px
        xor a                           ; a frame at once, 1 px a frame on
        ld (on_ground),a                ; the way he faces
        ld (crouching),a
        ld (crouch_t),a
        ld a,1
        ld (fall8),a                    ; (the NES counts the landing frame)
        ld a,JUMP_LEN*2
        ld (jump_idx),a
        ld a,(facing)
        or a
        ld a,1
        jr z,.fwd
        ld a,-1
.fwd:
        ld (air_dx),a
        jp player_animate

.airborne:
        ld a,(jump_skip)                ; take-off: the arc starts next frame
        or a
        jr z,.arc
        xor a
        ld (jump_skip),a
        jp player_animate
.arc:                                   ; arc: jump or knock-back table
        ld a,(arc_len)
        ld b,a
        ld a,(jump_idx)
        ld c,a
        cp b
        jr nc,.descend
        ld e,a                          ; rising: dy = table[idx]
        ld d,0
        ld hl,(arc_ptr)
        add hl,de
        ld a,(hl)
        jr .step
.descend:
        ld a,b
        add a,a
        ld b,a                          ; 2 * length
        ld a,c
        cp b
        jr nc,.terminal
        ld a,b                          ; falling: dy = -table[2*LEN-1-idx]
        dec a
        sub c
        ld e,a
        ld d,0
        ld hl,(arc_ptr)
        add hl,de
        ld a,(hl)
        neg
        jr .step
.terminal:
        ld hl,fall8
        inc (hl)
        ld a,MAX_FALL_PX
        jr .apply
.step:
        inc c
        ld b,a
        ld a,c
        ld (jump_idx),a
        ld a,b
.apply:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(py)
        add hl,de
        ld (py),hl

        ld a,(arc_len)                  ; only falling: the floor
        ld b,a
        ld a,(jump_idx)
        dec a
        cp b
        jr c,.check_pit

        ld c,32                         ; feet on something solid?
        call foot_probe
        jr nc,.check_pit
        ld a,(py)                       ; land: y on the 16-px grid (8 with
        ld b,0xF0                       ; a whip going on, and in stage 10)
        ld hl,whip_t
        inc (hl)
        dec (hl)
        jr nz,.grid8
        ld a,(area_hdr+AH_STAGE)
        cp 0x10
        ld a,(py)
        jr nz,.grid
.grid8:
        ld b,0xF8
.grid:
        and b
        ld (py),a
        ld a,1
        ld (on_ground),a
        xor a
        ld (jump_idx),a
        ld a,(hurt_state)               ; landing from a knock-back: dead, or
        cp HURT_FLY                     ; crouched and invincible
        jr nz,.landed
        xor a
        ld (hurt_state),a
        ld a,(hp)
        or a
        jr nz,.stun
        inc a
        ld (player_dead),a
        jp player_animate
.stun:
        ld a,INVULN_FRAMES
        ld (invuln_t),a
        jr .crouch_land
.landed:
        ld a,(fall8)                    ; a long fall: a crouched landing
        cp LAND_CROUCH
        jp c,player_animate
        ld a,(whip_t)
        or a
        jp nz,player_animate
.crouch_land:
        ld a,STUN_FRAMES+1
        ld (crouch_t),a
        ld a,1
        ld (crouching),a
        jp player_animate

.check_pit:
        ld hl,(py)
        bit 7,h
        jp nz,player_animate
        ld de,MT_ROWS*16
        or a
        sbc hl,de
        jp nc,respawn

        ; ---- animation ----
player_animate:
        xor a
        ld (pyoff),a
        ld a,(stair_state)
        cp 1
        jr z,.walk_anim                 ; walking to the stairs
        jr c,.not_stairs
        ld a,(py)                       ; on the stairs (NES $9586): mid-step
        add a,6                         ; (y & 7 in 2..5) walk1, else the
        and 7                           ; stair pose up or down
        cp 4
        ld a,POSE_WALK1
        jr c,.set_frame
        ld a,(stair_going)
        rlca
        and 1
        add a,POSE_STAIR_UP
        jr .set_frame
.not_stairs:
        ld a,(hurt_state)
        cp HURT_FLY
        jr nz,.not_hurt_pose
        ld a,POSE_HURT
        jr .set_frame
.not_hurt_pose:
        ld a,(on_ground)
        or a
        jr nz,.ground_anim
        ld a,(jump_idx)                 ; in the air: tucked in mid-jump
        cp JUMP_TUCK_FROM
        jr c,.stand
        cp JUMP_TUCK_TO
        jr nc,.stand
        ld a,TUCK_Y
        jr .tucked
.ground_anim:
        ld a,(crouching)
        or a
        jr z,.walk_anim
        ld a,CROUCH_Y
.tucked:
        ld (pyoff),a
        ld a,3
        jr .set_frame
.walk_anim:
        ld a,(walk_dx)                  ; (the step and its counter carry on
        or a                            ; over stops, as the NES's)
        jr z,.stand
        ld a,(anim_acc)
        add a,WALK_ANIM_ADD
        ld (anim_acc),a
        jr nc,.same_step
        ld hl,anim_step
        inc (hl)
.same_step:
        ld a,(anim_step)
        and 3
        ld e,a
        ld d,0
        ld hl,walk_cycle
        add hl,de
        ld a,(hl)
        jr .set_frame
.stand:
        xor a
.set_frame:
        ld (pframe),a

        ; ---- whip pose override and hit box ----
        xor a
        ld (whip_active),a
        ld a,(whip_t)
        or a
        ret z
        ld c,a
        cp WHIP_SND_T                   ; the swing's sound
        jr nz,.no_snd
        push bc
        call whip_sound
        pop bc
.no_snd:
        ld a,c
        ld b,0                          ; B = phase 0-3
        cp WHIP_P2
        jr c,.whip_pose
        inc b
        cp WHIP_P3
        jr c,.whip_pose
        inc b
        cp WHIP_P4
        jr c,.whip_strike
        inc b
        jr .whip_pose
.whip_strike:
        push bc
        ld a,(throwing)
        or a
        jr nz,.throw_now
        call whip_hitbox                ; (it hits on WHIP_HIT_T only)
        jr .struck
.throw_now:
        ld a,c                          ; the dagger leaves his hand on the
        cp WHIP_HIT_T                   ; NES's frame 17
        jr nz,.struck
        ld a,(thrown)
        or a
        call z,throw_dagger
.struck:
        pop bc
.whip_pose:
        ld a,(crouching)                ; crouched: the crouched set, drawn
        or a                            ; lower; standing / in the air: the
        ld a,0                          ; standing set
        jr z,.py
        ld a,CROUCH_Y
.py:
        ld (pyoff),a
        ld a,(stair_state)              ; on the stairs: their own poses
        cp 2
        jr nz,.not_stair_whip
        ld a,(stair_going)
        rlca
        and 1
        ld e,a                          ; E = 1 going down
        ld a,(throwing)
        or a
        jr z,.stair_whip
        ld a,b                          ; throw: + down*3 + phase (0-2)
        cp 3
        jr c,.sth
        ld a,2
.sth:
        add a,POSE_STHROW
        bit 0,e
        jr z,.sw_set
        add a,3
        jr .sw_set
.stair_whip:
        ld a,(whip_level)               ; + whip*8 + down*4 + phase
        add a,a
        add a,a
        add a,e
        add a,a
        add a,a
        add a,b
        add a,POSE_SWHIP
.sw_set:
        ld (pframe),a
        jr .whip_count
.not_stair_whip:
        ld a,(throwing)                 ; throwing: arm poses without a whip
        or a
        jr z,.whip_kind
        ld a,b
        cp 3
        jr c,.throw_phase
        ld a,2
.throw_phase:
        add a,POSE_THROW
        ld b,a
        ld e,3                          ; crouched set: +3
        jr .crouched
.whip_kind:
        ld a,(whip_level)               ; leather, chain or morning star
        or a
        ld a,POSE_WHIP
        jr z,.base
        ld a,(whip_level)
        dec a
        ld a,POSE_CHAIN
        jr z,.base
        ld a,POSE_STAR
.base:
        add a,b
        ld b,a
        ld e,4                          ; crouched set: +4
.crouched:
        ld a,(crouching)
        or a
        ld a,b
        jr z,.whip_standing
        add a,e
.whip_standing:
        ld (pframe),a
.whip_count:
        ld a,c
        inc a
        cp WHIP_END
        jr c,.whip_next
        xor a
.whip_next:
        ld (whip_t),a
        ret

walk_cycle:                             ; stand, walk1, walk2, walk1 (NES)
        db 0, 1, 2, 1

; side probes: rows py + 7, 12, 16, 24, 31 (NES y - 9, -4, 0, +8, +15)
wall_rows:
        db 7, 12, 16, 24, 31

; A whip action starts: UP held, the dagger, a heart and no dagger flying ->
; it throws the dagger instead (one heart)
; the sound of what the B press did: stopwatch, a throw, or the whip
; the swing's sound, on its 11th frame (NES $9A71): the whip's, or the
; throw's for the dagger only
whip_sound:
        ld a,(throwing)
        or a
        ld a,SND_WHIP
        jr z,.play
        ld a,(sub_kind)
        cp 1
        ret nz
        ld a,SND_THROW
.play:
        jp sfx_play

start_throw:
        xor a
        ld (throwing),a
        ld (thrown),a
        ld a,(subweapon)
        or a
        ret z
        ld a,(dagger_on)
        or a
        ret nz
        ld a,(hearts)
        or a
        ret z
        ld a,(stick)
        call stick_vertical
        cp 1
        ret nz
        ld a,(subweapon)
        cp 4
        jr z,.stopwatch
        ld hl,hearts
        dec (hl)
        ld a,1
        ld (throwing),a
        ld (hud_dirty),a
        ld a,(subweapon)
        ld (sub_kind),a
        ret
.stopwatch:                             ; 5 hearts: enemies freeze
        ld a,(freeze_t)
        or a
        ret nz
        ld a,(hearts)
        cp STOPWATCH_COST
        ret c
        sub STOPWATCH_COST
        ld (hearts),a
        ld a,STOPWATCH_FRAMES
        ld (freeze_t),a
        ld a,1
        ld (hud_dirty),a
        ld a,SND_STOPWATCH              ; (and the whip swings, as the NES's)
        jp sfx_play

; The dagger leaves Simon's hand: an object flying the way he faces
throw_dagger:
        ld a,1
        ld (thrown),a
        push ix
        call obj_free_slot
        jr c,.none
        ld a,(sub_kind)
        cp 2
        jr z,.axe
        cp 3
        jp z,.holy
        ld hl,(px)
        ld (ix+1),l
        ld (ix+2),h
        ld a,(pyoff)                    ; NES: his y - 8 (crouched: 4 lower)
        rrca
        ld b,a
        ld a,(py)
        add a,b
        ld (ix+3),a
        ld a,(facing)
        or a
        ld a,DAGGER_SPEED
        jr z,.dir
        neg
.dir:
        ld (ix+5),a
        ld (ix+0),OBJ_DAGGER
        ld (ix+4),0
        ld (ix+7),KIND_BAT              ; (16x16; never hit by the whip)
        ld (ix+8),0xFF
        ld a,1
        ld (dagger_on),a
        call dagger_box
.none:
        pop ix
        ret
.axe:                                   ; the axe: thrown up and forward
        ld hl,(px)
        ld (ix+1),l
        ld (ix+2),h
        ld a,(pyoff)
        ld b,a
        ld a,(py)
        add a,b
        sub 16
        ld (ix+3),a
        ld (ix+0),OBJ_AXE
        ld (ix+9),AXE_VY0
        jr .thrown
.holy:                                  ; holy water: lobbed low
        ld hl,(px)
        ld (ix+1),l
        ld (ix+2),h
        ld a,(pyoff)
        ld b,a
        ld a,(py)
        add a,b
        add a,2
        ld (ix+3),a
        ld (ix+0),OBJ_HOLY
        ld (ix+9),HOLY_VY0
.thrown:
        ld a,(facing)
        or a
        ld a,1
        jr z,.d
        ld a,-1
.d:
        ld (ix+5),a
        ld (ix+4),0
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+10),0
        ld (ix+11),0
        ld a,1
        ld (dagger_on),a
        call sub_box16
        pop ix
        ret

; C = y offset from py; probes x = new_x + probe_off
side_probe:
        ld hl,(py)
        ld b,0
        add hl,bc
        ex de,hl
        ld a,(probe_off)
        ld c,a
        ld hl,(new_x)
        add hl,bc
        jp solid_at

; C = y offset from py; probes px+4 and px+12 (NES x - 4, x + 4). Carry if
; either is solid.
foot_probe:
        push bc
        ld hl,(py)
        ld b,0
        add hl,bc
        ex de,hl
        ld hl,(px)
        ld bc,4
        add hl,bc
        call solid_at
        pop bc
        ret c
        ld hl,(py)
        ld b,0
        add hl,bc
        ex de,hl
        ld hl,(px)
        ld bc,12
        add hl,bc
        jp solid_at

; ---------------------------------------------------------------------------
; Fill sat_buf from the current metasprite frame, then the end marker.
; Sprites that would be off the left/right edge are parked below the screen.
; ---------------------------------------------------------------------------
build_sat:
        ld hl,(px)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld (spr_bx),hl
        ld a,(pyoff)
        ld e,a
        ld d,0
        ld hl,(py)
        add hl,de
        ld de,PF_TOP_PX-1+PLAYER_DRAW_DY ; (the VDP shows a sprite 1 line lower;
                                        ; his pictures may end above his box's
                                        ; bottom: drawn lower to stand on the floor)
        ld a,(stair_state)
        cp 2
        jr nz,.on_floor
        ld de,PF_TOP_PX-1               ; on the stairs his y already puts his
.on_floor:                              ; feet on the steps
        add hl,de
        ld (spr_by),hl

        ld a,(facing)
        or a
        ld a,(pframe)
        jr z,.right
        add a,NPOSES
.right:
        ld (cur_frame),a
        ld a,PLAYER_BANK                ; (his frames are in his bank; the
        ld (page2_bank),a               ; sound interrupt puts it back)
        ld (ASCII16_PAGE2),a
        ld a,(invuln_t)                 ; invincible: blink (not while flying back)
        or a
        jr z,.no_blink
        ld a,(hurt_state)
        cp HURT_FLY
        ld a,0
        jr z,.no_blink
        ld a,(frame_count)
        and 1
.no_blink:
        ld b,a                          ; (or gone into the castle gate)
        ld a,(seq_hidden)
        or b
        ld (spr_hide),a
        ld a,(cur_frame)
        call frame_address
        ld b,(ix+0)
        inc ix
        xor a
        ld (spr_pat),a
        ld iy,sat_buf
.lp:
        ld a,(ix+0)                     ; y = base + dy
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(spr_by)
        add hl,de
        ld a,h
        or a
        jr nz,.y_neg
        ld a,l
        cp 192
        jr nc,.hide
        jr .y_ok
.y_neg:
        inc a
        jr nz,.hide                     ; far above the screen
        ld a,l
        cp 0xF0
        jr c,.hide                      ; more than 16 lines above
.y_ok:
        ld c,a
        ld a,(spr_hide)
        or a
        jr nz,.hide
        ld a,(ix+1)                     ; x = base + dx
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(spr_bx)
        add hl,de
        ld a,h
        or a
        jr nz,.hide                     ; off the left or right edge
        ld (iy+0),c
        ld (iy+1),l
        jr .store
.hide:
        ld (iy+0),SPRITE_HIDE_Y
        ld (iy+1),0
.store:
        ld a,(spr_pat)
        ld (iy+2),a
        add a,4
        ld (spr_pat),a
        ld de,4
        add ix,de
        add iy,de
        djnz .lp
        ld a,(spr_pat)                  ; Simon's sprite count = slots used
        rrca
        rrca
        and 0x3F
        ld (spr_player_n),a
        ld (spr_total),a
        ld a,(cur_area)                 ; the area's bank again
        call area_bank
        ld (page2_bank),a
        ld (ASCII16_PAGE2),a
        call objects_draw               ; objects follow Simon's sprites
        ld (iy+0),SAT_END_Y
        ret

