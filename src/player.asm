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
        ld (facing),a
        ld (pframe),a
        ld (air_dx),a
        ld (anim_t),a
        ld (anim_step),a
        ld (whip_t),a
        ld (whip_active),a
        inc a
        ld (on_ground),a
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
        ld hl,TIME_START
        ld (time_bcd),hl
        xor a
        ld (time_t),a
        inc a
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
; Getting hit. B = direction to knock Simon (+1 right, -1 left).
; Frozen HIT_FREEZE frames, then knocked back along the NES knock-back arc
; (facing the enemy, moving away from it), stunned STUN_FRAMES after landing,
; and invincible (blinking) for INVULN_FRAMES. On the stairs he only takes
; the damage, as on the NES.
; ---------------------------------------------------------------------------
simon_hurt:
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld a,(hp)
        sub ZOMBIE_DAMAGE
        jr c,.dead
        jr z,.dead
        ld (hp),a
        ld a,1
        ld (hud_dirty),a
        ld a,INVULN_FRAMES
        ld (invuln_t),a
        xor a
        ld (whip_t),a
        ld (whip_active),a
        ld (crouching),a
        ld a,(stair_state)
        cp 2
        ret z                           ; on the stairs: no knock-back
        xor a
        ld (stair_state),a
        ld a,b
        ld (air_dx),a
        rlca                            ; knocked right -> face left
        and 1
        xor 1
        ld (facing),a
        ld a,HURT_FREEZE
        ld (hurt_state),a
        ld a,HIT_FREEZE
        ld (hurt_t),a
        ret
.dead:
        xor a
        ld (hp),a
        inc a
        ld (player_dead),a
        ld (hud_dirty),a
        ret

; Count down the freeze (then start the knock-back) or the stun.
hurt_tick:
        ld hl,hurt_t
        dec (hl)
        ret nz
        ld a,(hurt_state)
        cp HURT_FREEZE
        jr nz,.stun_over
        ld a,HURT_FLY
        ld (hurt_state),a
        xor a
        ld (jump_idx),a
        ld (on_ground),a
        ld hl,kb_table
        ld (arc_ptr),hl
        ld a,KB_LEN
        ld (arc_len),a
        ret
.stun_over:
        xor a
        ld (hurt_state),a
        ret

player_update:
        ld a,(invuln_t)
        or a
        jr z,.not_invuln
        dec a
        ld (invuln_t),a
.not_invuln:
        ld a,(hurt_state)               ; hit: frozen, knocked back or stunned
        or a
        jr z,.not_hurt
        cp HURT_FLY
        jp z,.in_air                    ; the knock-back arc carries him
        call hurt_tick
        jp player_animate
.not_hurt:
        ld a,(stair_state)
        or a
        jp nz,stairs_update

        ; ---- whip: once started it runs to the end ----
        ld a,(whip_t)
        or a
        jr nz,.whip_busy
        ld a,(whip_pressed)
        or a
        jr z,.intent
        ld a,1
        ld (whip_t),a
        call start_throw
.whip_busy:
        ld a,(on_ground)
        or a
        jr z,.in_air                    ; in the air the jump arc carries on
        xor a
        ld (walk_dx),a                  ; on the ground Simon stands still
        jp .vertical

        ; ---- intent ----
.intent:
        ld a,(on_ground)
        or a
        jr z,.in_air
        ld a,(stick)                    ; UP near the foot of a staircase
        call stick_vertical
        cp 1
        jr nz,.not_up
        ld c,ST_FOOTX
        call find_stair
        jp c,stairs_begin_up
.not_up:
        ld a,(stick)
        cp 4
        jr c,.not_down
        cp 7
        jr nc,.not_down
        ld c,ST_TOPX                    ; DOWN near the top of a staircase
        call find_stair
        jp c,stairs_begin_down
        ld a,1                          ; 4, 5, 6: down (incl. diagonals)
        ld (crouching),a
        xor a
        ld (walk_dx),a
        jp .vertical
.not_down:
        xor a
        ld (crouching),a
        ld a,(stick)
        call stick_to_dx
        ld (walk_dx),a
        or a
        jr z,.no_turn
        rlca
        and 1                           ; 1 if moving left
        ld (facing),a
.no_turn:
        ld a,(jump_pressed)
        or a
        jr z,.move_h
        call arc_jump
        xor a
        ld (jump_idx),a
        ld (on_ground),a
        ld a,(walk_dx)
        ld (air_dx),a
        jr .move_h
.in_air:
        ld a,(air_dx)
        ld (walk_dx),a

        ; ---- horizontal move with collision ----
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
        jr c,.vertical                  ; would leave the screen on the left
        ld de,241
        or a
        sbc hl,de
        jr nc,.vertical                 ; would leave the screen on the right
        ld a,(walk_dx)
        ld c,3
        bit 7,a
        jr nz,.left_edge
        ld c,12
.left_edge:
        ld a,c
        ld (probe_off),a
        ld c,2
        call side_probe
        jr c,.vertical
        ld c,16
        call side_probe
        jr c,.vertical
        ld c,29
        call side_probe
        jr c,.vertical
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
        call arc_jump
        xor a                           ; walked off a ledge
        ld (on_ground),a
        ld (air_dx),a
        ld a,FALL_START
        ld (jump_idx),a

.airborne:                              ; arc: jump or knock-back table
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

        ld a,(arc_len)
        ld b,a
        ld a,(jump_idx)
        dec a
        cp b
        jr c,.rising

        ld c,31                         ; falling: feet inside something solid?
        call foot_probe
        jr nc,.check_pit
        ld hl,(py)                      ; land on top of the tile
        ld de,31
        add hl,de
        ld a,l
        and 0xF8
        ld l,a
        ld de,-32
        add hl,de
        ld (py),hl
        ld a,1
        ld (on_ground),a
        xor a
        ld (jump_idx),a
        ld a,(hurt_state)               ; landing from a knock-back: stunned
        cp HURT_FLY
        jp nz,player_animate
        ld a,HURT_STUN
        ld (hurt_state),a
        ld a,STUN_FRAMES
        ld (hurt_t),a
        jp player_animate

.rising:
        ld c,0                          ; head inside something solid?
        call foot_probe
        jr nc,.check_pit
        ld hl,(py)                      ; push back below the tile
        ld a,l
        and 0xF8
        ld l,a
        ld de,8
        add hl,de
        ld (py),hl
        ld a,(jump_idx)                 ; continue with the mirrored fall
        ld b,a
        ld a,(arc_len)
        add a,a
        sub b
        ld (jump_idx),a

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
        ld a,(stair_anim)               ; on the stairs: stair pose / walk1
        and 8
        ld a,POSE_WALK1
        jr z,.set_frame
        ld a,POSE_STAIR
        jr .set_frame
.not_stairs:
        ld a,(hurt_state)
        or a
        jr z,.not_hurt_pose
        cp HURT_STUN
        ld a,CROUCH_Y
        jr z,.tucked                    ; stunned: crouched
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
        ld a,(walk_dx)
        or a
        jr nz,.walking
        ld (anim_t),a
        ld (anim_step),a
.stand:
        xor a
        jr .set_frame
.walking:
        ld a,(anim_t)
        inc a
        cp WALK_FRAME_TIME
        jr c,.same_step
        ld a,(anim_step)
        inc a
        and 3
        ld (anim_step),a
        xor a
.same_step:
        ld (anim_t),a
        ld a,(anim_step)
        ld e,a
        ld d,0
        ld hl,walk_cycle
        add hl,de
        ld a,(hl)
.set_frame:
        ld (pframe),a

        ; ---- whip pose override and hit box ----
        xor a
        ld (whip_active),a
        ld a,(whip_t)
        or a
        ret z
        ld c,a
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
        call whip_hitbox
        jr .struck
.throw_now:
        ld a,(thrown)                   ; the dagger leaves his hand once
        or a
        call z,throw_dagger
.struck:
        pop bc
.whip_pose:
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
        ld a,(pframe)
        cp POSE_TUCK                    ; crouching / tucked: crouched set
        ld a,b
        jr nz,.whip_standing
        add a,e
.whip_standing:
        ld (pframe),a
        ld a,c
        inc a
        cp WHIP_END
        jr c,.whip_next
        xor a
.whip_next:
        ld (whip_t),a
        ret

; Hit box of the extended whip in world coordinates (mirrored when facing left).
whip_hitbox:
        ld a,1
        ld (whip_active),a
        ld hl,(px)
        ld a,(facing)
        or a
        jr nz,.left
        ld de,WHIP_HIT_X1
        add hl,de
        ld (whip_x1),hl
        ld de,WHIP_HIT_X2-WHIP_HIT_X1
        add hl,de
        ld (whip_x2),hl
        jr .y
.left:
        ld de,15-WHIP_HIT_X2
        add hl,de
        ld (whip_x1),hl
        ld de,WHIP_HIT_X2-WHIP_HIT_X1
        add hl,de
        ld (whip_x2),hl
.y:
        ld a,(whip_level)               ; the morning star reaches further
        cp 2
        jr c,.reach_ok
        ld a,(facing)
        or a
        ld hl,(whip_x2)
        ld de,STAR_EXTRA
        jr z,.longer
        ld hl,(whip_x1)
        ld de,-STAR_EXTRA
        add hl,de
        ld (whip_x1),hl
        jr .reach_ok
.longer:
        add hl,de
        ld (whip_x2),hl
.reach_ok:
        ld a,(pyoff)
        ld e,a
        ld d,0
        ld hl,(py)
        add hl,de
        ld de,WHIP_HIT_Y1
        add hl,de
        ld (whip_y1),hl
        ld de,WHIP_HIT_Y2-WHIP_HIT_Y1
        add hl,de
        ld (whip_y2),hl
        ret

walk_cycle:
        db 1, 2, 1, 0

; A whip action starts: UP held, the dagger, a heart and no dagger flying ->
; it throws the dagger instead (one heart)
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
.stopwatch:                             ; 5 hearts: enemies freeze (no throw)
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
        xor a
        ld (whip_t),a                   ; no whip action either
        ret

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
        ld a,(pyoff)
        ld b,a
        ld a,(py)
        add a,b
        add a,4                         ; at chest height (NES: top row)
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

; C = y offset from py; probes px+4 and px+11. Carry if either is solid.
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
        ld bc,11
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
        add hl,de
        ld (spr_by),hl

        ld a,(facing)
        or a
        ld a,(pframe)
        jr z,.right
        add a,NPOSES
.right:
        ld (cur_frame),a
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
        call objects_draw               ; objects follow Simon's sprites
        ld (iy+0),SAT_END_Y
        ret

; ---------------------------------------------------------------------------
; Stairs (data: area header AH_STAIRS, from the NES stair table)
;
; UP near a staircase's foot, or DOWN near its top, makes Simon walk to the
; exact spot (1 px per frame) and get on. On the stairs he moves diagonally,
; one pixel across and one pixel up/down on alternating frames, while the
; stick points up or down (or along the stairs); he whips standing still,
; and gets off at either end. Measured on the NES hall's first staircase.
; ---------------------------------------------------------------------------

; A = stick -> A = +1 (up, up-left, up-right), -1 (down...), 0 otherwise
stick_vertical:
        or a
        ret z
        cp 3
        jr c,.up                        ; 1, 2
        cp 8
        jr z,.up
        cp 4
        jr c,.none                      ; 3
        cp 7
        jr nc,.none                     ; 7
        ld a,-1
        ret
.up:
        ld a,1
        ret
.none:
        xor a
        ret

; C = ST_FOOTX or ST_TOPX: find a staircase end at Simon's height within
; STAIR_REACH pixels. Carry set if found: stair_ptr, stair_tx, stair_dir.
find_stair:
        ld hl,(area_hdr+AH_STAIRS)
        ld a,(hl)
        inc hl
        or a
        ret z
        ld b,a
.lp:
        push bc
        push hl
        ld b,0
        add hl,bc
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = x of this end
        inc hl
        ld a,(py+1)
        or a
        jr nz,.next
        ld a,(py)
        cp (hl)                         ; same height?
        jr nz,.next
        ld hl,(px)
        or a
        sbc hl,de
        ld bc,STAIR_REACH
        add hl,bc                       ; 0 .. 2*STAIR_REACH if close enough
        ld a,h
        or a
        jr nz,.next
        ld a,l
        cp STAIR_REACH*2+1
        jr nc,.next
        pop hl
        pop bc
        ld (stair_ptr),hl
        ld (stair_tx),de
        push hl
        pop ix
        ld a,(ix+ST_DIR)
        ld (stair_dir),a
        scf
        ret
.next:
        pop hl
        pop bc
        ld de,ST_SIZE
        add hl,de
        djnz .lp
        or a
        ret

stairs_begin_up:
        ld a,1
        jr stairs_begin
stairs_begin_down:
        ld a,-1
stairs_begin:
        ld (stair_going),a
        ld a,1
        ld (stair_state),a
        xor a
        ld (crouching),a
        ld (stair_phase),a
        jp player_animate

stairs_update:
        ld a,(whip_t)                   ; whipping: stand still until it ends
        or a
        jr nz,.still
        ld a,(whip_pressed)
        or a
        jr z,.no_whip
        ld a,1
        ld (whip_t),a
.still:
        xor a
        ld (walk_dx),a
        jp player_animate
.no_whip:
        ld a,(stair_state)
        cp 2
        jr z,.on_stairs

        ; --- walking to the end of the staircase ---
        ld hl,(px)
        ld de,(stair_tx)
        or a
        sbc hl,de
        jr z,.arrived
        ld a,1
        jr c,.step
        ld a,-1
.step:
        ld (walk_dx),a
        ld e,a
        rlca
        and 1
        ld (facing),a
        ld a,e
        rla
        sbc a,a
        ld d,a
        ld hl,(px)
        add hl,de
        ld (px),hl
        jp player_animate
.arrived:
        ld a,2
        ld (stair_state),a
        xor a
        ld (walk_dx),a
        call stair_face
        jp player_animate

        ; --- on the stairs ---
.on_stairs:
        xor a
        ld (walk_dx),a
        ld a,(stick)
        call stick_vertical
        or a
        jr nz,.move
        ld a,(stick)                    ; left/right: along the stairs
        call stick_to_dx
        or a
        jp z,player_animate
        ld b,a
        ld a,(stair_dir)
        xor b                           ; same sign: up, else down
        ld a,1
        jp p,.move
        ld a,-1
.move:
        ld (stair_going),a
        call stair_face
        ld hl,stair_anim
        inc (hl)
        ld a,(stair_phase)
        xor 1
        ld (stair_phase),a
        jr z,.y_step
        ld a,(stair_going)              ; x step: going * dir
        ld b,a
        ld a,(stair_dir)
        xor b
        ld e,1
        jp p,.dx
        ld e,-1
.dx:
        ld a,e
        rla
        sbc a,a
        ld d,a
        ld hl,(px)
        add hl,de
        ld (px),hl
        jp player_animate
.y_step:
        ld a,(stair_going)              ; y step: up = -1
        neg
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(py)
        add hl,de
        ld (py),hl
        call section_link               ; off the playfield: next section
        ld a,(stair_state)
        or a
        jp z,player_animate

        ; reached the end it is moving towards?
        ld ix,(stair_ptr)
        ld a,(stair_going)
        or a
        ld a,(ix+ST_TOPY)
        ld c,ST_TOPX
        jp p,.end_y
        ld a,(ix+ST_FOOTY)
        ld c,ST_FOOTX
.end_y:
        ld hl,py
        cp (hl)
        jp nz,player_animate
        ld b,0                          ; step off: exactly on the end point
        add ix,bc
        ld l,(ix+0)
        ld h,(ix+1)
        ld (px),hl
        xor a
        ld (stair_state),a
        ld (jump_idx),a
        inc a
        ld (on_ground),a
        jp player_animate

; Face the way Simon is moving on the stairs (going * dir > 0: right).
stair_face:
        ld a,(stair_going)
        ld b,a
        ld a,(stair_dir)
        xor b
        rlca
        and 1
        ld (facing),a
        ret
