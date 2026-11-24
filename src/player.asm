; ---------------------------------------------------------------------------
; Player (Simon), following the NES game's movement model:
;  - walks at 1 px per frame; crouches with DOWN (and cannot walk then)
;  - the jump is a fixed arc read from jump_table: JUMP_LEN signed steps
;    while rising, the same steps mirrored while falling, then MAX_FALL_PX
;  - horizontal speed is decided at take-off and cannot be steered
;
; The player is a 16x32 box at (px, py); py is relative to the playfield top.
; ---------------------------------------------------------------------------

level_start:
        ld hl,0
        ld (cam_x),hl
        call player_reset
        jp full_redraw

player_reset:
        ld hl,START_X
        ld (px),hl
        ld hl,START_Y
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
        inc a
        ld (on_ground),a
        ret

; Fell into a pit: restart at the beginning of the level.
respawn:
        ld hl,0
        ld (cam_x),hl
        call player_reset
        di
        call full_redraw
        ei
        ret

player_update:
        ; ---- intent ----
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
        ld hl,(py)                      ; land on top of the cell
        ld de,31
        add hl,de
        ld a,l
        and 0xF0
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
        ld hl,(py)
        ld a,l
        and 0xF0
        ld l,a
        ld de,16
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
; Fill sat_buf: 4 sprites (2 OR-coloured layers x 2 halves) + end marker.
; Pattern layout per (facing, frame): topA, topB, botA, botB (see tools/).
; ---------------------------------------------------------------------------
build_sat:
        ld hl,(px)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld c,l                          ; C = screen x
        ld a,(pyoff)
        ld b,a
        ld a,(py)
        add a,b
        add a,PF_TOP_PX-1
        ld b,a                          ; B = sprite Y of the top half

        ld a,(facing)
        add a,a
        add a,a
        ld e,a
        ld a,(pframe)
        add a,e
        add a,a
        add a,a
        add a,a
        add a,a
        ld d,a                          ; D = first pattern number

        ld hl,sat_buf
        ld e,2                          ; two halves
.half:
        ld (hl),b
        inc hl
        ld (hl),c
        inc hl
        ld (hl),d
        inc hl
        inc hl
        ld a,d
        add a,4
        ld d,a
        ld (hl),b
        inc hl
        ld (hl),c
        inc hl
        ld (hl),d
        inc hl
        inc hl
        ld a,d
        add a,4
        ld d,a
        ld a,b
        add a,16
        ld b,a
        dec e
        jr nz,.half
        ld (hl),SAT_END_Y
        ret
