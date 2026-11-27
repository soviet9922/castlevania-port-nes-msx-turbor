; ---------------------------------------------------------------------------
; Simon's code that runs from RAM (bank 0 is full): the whip's hit box and
; the stairs. Part of the resident RAM code (src/ramcode.asm).
; ---------------------------------------------------------------------------

; Hit box of the extended whip in world coordinates (NES $E40B: centre x + 24,
; 26 or 34 by the whip, y - 2; crouched y + 3; half sizes 16/6, 18/8, 26/8
; added to the enemy's): as an inclusive box, facing right, px + X1..X2,
; py + Y1..Y2; facing left mirrored around his middle (px + 16 - X)
whip_hitbox:
        ld a,c                          ; the NES tests the whip on one frame
        cp WHIP_HIT_T                   ; of the strike only: one hit a swing
        jr nz,.box
        ld a,1
        ld (whip_active),a
.box:
        ld a,(whip_level)
        cp 2
        jr c,.lvl
        ld a,2
.lvl:
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,whip_boxes
        add hl,de                       ; X1, X2, Y1, Y2
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        push hl
        ld a,(facing)
        or a
        jr z,.right
        ld a,16                         ; facing left: 16 - X2 .. 16 - X1
        sub b
        ld e,a
        ld a,16
        sub c
        ld b,a
        ld c,e
.right:
        ld a,c
        call .x
        ld (whip_x1),hl
        ld a,b
        call .x
        ld (whip_x2),hl
        pop hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld a,(crouching)                ; crouched: 9 px lower
        or a
        jr z,.yrow
        ld a,9
        add a,c
        ld c,a
        ld a,9
        add a,b
        ld b,a
.yrow:
        ld hl,(py)
        ld e,c
        ld d,0
        add hl,de
        ld (whip_y1),hl
        ld hl,(py)
        ld e,b
        add hl,de
        ld (whip_y2),hl
        ret
.x:                                     ; HL = px + A (signed)
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(px)
        add hl,de
        ret
whip_boxes:                             ; X1, X2, Y1, Y2 (standing)
        db 17, 47, 9, 19                ; leather
        db 17, 51, 7, 21                ; chain
        db 17, 67, 7, 21                ; morning star


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
        ld a,(stair_frz)                ; hit: frozen, the whip paused (NES $47)
        or a
        jr z,.not_frozen
        dec a
        ld (stair_frz),a
        ret nz
        ld a,(hp)                       ; (health gone: he dies)
        or a
        ret nz
        inc a
        ld (player_dead),a
        ret
.not_frozen:
        ld a,(whip_t)                   ; whipping: stand still until it ends
        or a
        jr nz,.still
        ld a,(whip_pressed)
        or a
        jr z,.no_whip
        ld a,(stair_state)              ; (not while walking to the stairs)
        cp 2
        jr nz,.no_whip
        ld a,(py)                       ; only near a step's end: y & 7 in
        add a,2                         ; 6, 7, 0, 1 (NES $9586)
        and 7
        cp 4
        jr nc,.no_whip
        ld a,1
        ld (whip_t),a
        call start_throw                ; (UP + B: a sub-weapon, as on the floor)
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

        ; --- on the stairs: a step (8 px across, 8 up or down) once started
        ; always ends; the stick is read only at a step's end (NES $9586) ---
.on_stairs:
        xor a
        ld (walk_dx),a
        ld a,(stair_phase)
        or a
        jr nz,.go_on
        ld a,(py)
        and 7
        jr nz,.go_on
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
.go_on:
        ld a,(stair_going)
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
