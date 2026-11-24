; ---------------------------------------------------------------------------
; Player: walking, a Castlevania-style committed jump (horizontal speed is
; locked at take-off), gravity, tile collision and animation.
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
        ld hl,0
        ld (vy),hl
        xor a
        ld (py_frac),a
        ld (facing),a
        ld (pframe),a
        ld (air_dx),a
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
        ; ---- horizontal intent ----
        ld a,(on_ground)
        or a
        jr z,.in_air
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
        ld hl,JUMP_VY
        ld (vy),hl
        xor a
        ld (on_ground),a
        ld (py_frac),a
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
        xor a                           ; walked off a ledge: drop straight down
        ld (on_ground),a
        ld (air_dx),a
        ld (py_frac),a
        ld hl,0
        ld (vy),hl

.airborne:
        ld hl,(vy)
        ld de,GRAVITY
        add hl,de
        bit 7,h
        jr nz,.no_cap
        push hl
        ld de,MAX_FALL+1
        or a
        sbc hl,de
        pop hl
        jr c,.no_cap
        ld hl,MAX_FALL
.no_cap:
        ld (vy),hl
        ld a,h
        ld e,a
        rla
        sbc a,a
        ld d,a                          ; DE = integer part, sign-extended
        ld a,(py_frac)
        add a,l
        ld (py_frac),a
        ld hl,(py)
        adc hl,de
        ld (py),hl

        ld a,(vy+1)
        bit 7,a
        jr nz,.rising

        ld c,31                         ; feet inside something solid?
        call foot_probe
        jr nc,.check_pit
        ld hl,(py)                      ; land on top of the metatile
        ld de,31
        add hl,de
        ld a,l
        and 0xF0
        ld l,a
        ld de,-32
        add hl,de
        ld (py),hl
        xor a
        ld (py_frac),a
        ld hl,0
        ld (vy),hl
        inc a
        ld (on_ground),a
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
        xor a
        ld (py_frac),a
        ld hl,0
        ld (vy),hl

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
        ld a,(on_ground)
        or a
        ld a,3                          ; jump frame
        jr z,.set_frame
        ld a,(walk_dx)
        or a
        jr z,.set_frame                 ; A = 0: standing
        ld a,(anim_t)
        inc a
        ld (anim_t),a
        rrca
        rrca
        rrca
        and 3
        ld e,a
        ld d,0
        ld hl,walk_cycle
        add hl,de
        ld a,(hl)
.set_frame:
        ld (pframe),a
        ret

walk_cycle:
        db 1, 0, 2, 0

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
        ld a,(py)
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
