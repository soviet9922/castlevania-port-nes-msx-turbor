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

; Fell into a pit: restart at the beginning of the level.
respawn:
        ld a,(cur_area)
        jp load_area

player_update:
        ; ---- whip: once started it runs to the end ----
        ld a,(whip_t)
        or a
        jr nz,.whip_busy
        ld a,(whip_pressed)
        or a
        jr z,.intent
        ld a,1
        ld (whip_t),a
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
        ld a,(stick)
        cp 4
        jr c,.not_down
        cp 7
        jr nc,.not_down
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
        jp c,.animate
        xor a                           ; walked off a ledge
        ld (on_ground),a
        ld (air_dx),a
        ld a,FALL_START
        ld (jump_idx),a

.airborne:
        ld a,(jump_idx)
        ld c,a
        cp JUMP_LEN
        jr nc,.descend
        ld e,a                          ; rising: dy = table[idx]
        ld d,0
        ld hl,jump_table
        add hl,de
        ld a,(hl)
        jr .step
.descend:
        cp JUMP_LEN*2
        jr nc,.terminal
        ld a,JUMP_LEN*2-1               ; falling: dy = -table[2*LEN-1-idx]
        sub c
        ld e,a
        ld d,0
        ld hl,jump_table
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

        ld a,(jump_idx)
        cp JUMP_LEN+1
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
        jr .animate

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
        ld a,JUMP_LEN*2
        sub b
        ld (jump_idx),a

.check_pit:
        ld hl,(py)
        bit 7,h
        jr nz,.animate
        ld de,MT_ROWS*16
        or a
        sbc hl,de
        jp nc,respawn

        ; ---- animation ----
.animate:
        xor a
        ld (pyoff),a
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
        ld b,POSE_WHIP
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
        call whip_hitbox
        pop bc
.whip_pose:
        ld a,(pframe)
        cp POSE_TUCK                    ; crouching / tucked: crouched set
        ld a,b
        jr nz,.whip_standing
        add a,4
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
        ld de,PF_TOP_PX-1
        add hl,de
        ld (spr_by),hl

        ld a,(facing)
        or a
        ld a,(pframe)
        jr z,.right
        add a,NPOSES
.right:
        ld (cur_frame),a
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
