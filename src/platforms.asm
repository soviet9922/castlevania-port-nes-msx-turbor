; ---------------------------------------------------------------------------
; Moving platforms (NES $D052 creates them, 6:$AAE2 moves them, 6:$AC70 lets
; Simon stand on them): 32x8 bars swinging left and right over gaps in
; stages 4, 5 and 10. Each is a spring: every frame
;     P += sign_extend(V.hi) << n,   V -= sign_extend(P.hi) << n
; (P, V 8.8 fixed point) and its middle is at C + P.hi.
;
; Simon stands on one fully on the screen when his feet are within -1..+8 px
; of its top and his middle within -17..+16 px of its middle; he is carried
; by its steps while no left/right is held (a wall stops him and it slides
; away from under him). Platforms ignore enemies, items and weapons.
;
; plat_table: PLAT_MAX entries laid out like objects so that draw_obj
; draws them: +0 OBJ_PLATFORM (0: none), +1/+2 left x, +3 top y, +4/+5 P,
; +6 frame, +7/+8 V, +9/+10 C (middle), +11 n.
; AH_PLATS: count, then per platform: P (2), V (2), C (2), n, top y.
; ---------------------------------------------------------------------------

; area load: the area's platforms at their starting points
platforms_load:
        ld hl,plat_table
        ld b,PLAT_MAX*OBJ_SIZE+3        ; (and plat_ride, hit_nomark, cq_n: this RAM
                                        ; isn't cleared at start-up)
        xor a
.clear:
        ld (hl),a
        inc hl
        djnz .clear
        ld hl,(area_hdr+AH_PLATS)
        ld a,(hl)
        or a
        ret z
        cp PLAT_MAX+1
        ret nc
        ld b,a
        inc hl
        push ix
        ld ix,plat_table
.lp:
        ld a,(hl)
        ld (ix+4),a
        inc hl
        ld a,(hl)
        ld (ix+5),a
        inc hl
        ld a,(hl)
        ld (ix+7),a
        inc hl
        ld a,(hl)
        ld (ix+8),a
        inc hl
        ld a,(hl)
        ld (ix+9),a
        inc hl
        ld a,(hl)
        ld (ix+10),a
        inc hl
        ld a,(hl)
        ld (ix+11),a
        inc hl
        ld a,(hl)
        ld (ix+3),a
        inc hl
        ld (ix+0),OBJ_PLATFORM
        ld (ix+6),OBJF_PLAT
        push hl
        call plat_x
        pop hl
        ld de,OBJ_SIZE
        add ix,de
        djnz .lp
        pop ix
        ret

; IX = platform: +1/+2 = C + P.hi - 16; -> HL = the new left x
plat_x:
        ld a,(ix+5)
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+9)
        ld h,(ix+10)
        add hl,de
        ld de,-16
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ret

; HL = sign_extend(A) << n (n = IX+11, 1-3)
plat_shift:
        ld l,a
        rla
        sbc a,a
        ld h,a
        ld b,(ix+11)
.s:
        add hl,hl
        djnz .s
        ret

; each frame, after Simon: the platforms move; the one he stands on (no
; left/right held) carries him
platforms_update:
        ld a,(plat_table)
        or a
        ret z
        push ix
        ld ix,plat_table
        ld c,1                          ; C = index + 1
.lp:
        ld a,(ix+0)
        or a
        jr z,.next
        push bc
        ld a,(ix+8)                     ; P += V.hi << n
        call plat_shift
        ld e,(ix+4)
        ld d,(ix+5)
        add hl,de
        ld (ix+4),l
        ld (ix+5),h
        ld a,h                          ; V -= P.hi << n
        call plat_shift
        ex de,hl
        ld l,(ix+7)
        ld h,(ix+8)
        or a
        sbc hl,de
        ld (ix+7),l
        ld (ix+8),h
        ld e,(ix+1)
        ld d,(ix+2)
        push de
        call plat_x
        pop de
        or a
        sbc hl,de                       ; L = its step (-1, 0, +1)
        pop bc
        ld a,l
        or a
        jr z,.next
        ld b,a
        ld a,(plat_ride)
        cp c
        jr nz,.next
        ld a,(on_ground)
        or a
        jr z,.next
        push bc
        ld a,(stick)                    ; walking on it: it doesn't carry him
        call stick_to_dx
        pop bc
        or a
        jr nz,.next
        ld a,b
        push bc
        call plat_carry
        pop bc
.next:
        ld de,OBJ_SIZE
        add ix,de
        inc c
        ld a,c
        cp PLAT_MAX+1
        jr c,.lp
        pop ix
        ret

; Simon moves A (-1 / +1) px with the platform, unless a wall is there
plat_carry:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(px)
        add hl,de
        bit 7,h
        ret nz                          ; (not left of the area)
        push hl
        bit 7,e
        jr nz,.left
        ld de,15
        add hl,de                       ; his right edge
.left:
        push hl
        ld de,(py)
        ld hl,8
        add hl,de
        ex de,hl
        pop hl
        push hl
        call solid_at
        pop hl
        jr c,.wall
        ld de,(py)
        push hl
        ld hl,24
        add hl,de
        ex de,hl
        pop hl
        call solid_at
        jr c,.wall
        pop hl
        ld (px),hl
        ret
.wall:
        pop hl
        ret

; Carry if Simon stands on a platform fully on the screen (his feet within
; -1..+8 px of its top, his middle within -17..+16 px of its middle): his
; feet go onto its top and plat_ride = its index + 1 (0 when none)
plat_check:
        xor a
        ld (plat_ride),a
        ld a,(plat_table)
        or a
        ret z
        ld a,(py+1)
        or a
        ret nz
        push ix
        ld ix,plat_table
        ld c,1
.lp:
        ld a,(ix+0)
        or a
        jr z,.next
        ld a,(py)                       ; feet - top in -1..+8
        add a,32+1
        sub (ix+3)
        cp 10
        jr nc,.next
        ld l,(ix+1)                     ; fully on the screen: left - cam x
        ld h,(ix+2)                     ; in 0..223
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.next
        ld a,l
        cp 224
        jr nc,.next
        ld hl,(px)                      ; px - left in -9..+24
        ld de,9
        add hl,de
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.next
        ld a,l
        cp 34
        jr nc,.next
        ld a,(ix+3)                     ; on it
        sub 32
        ld (py),a
        xor a
        ld (py+1),a
        ld a,c
        ld (plat_ride),a
        pop ix
        scf
        ret
.next:
        ld de,OBJ_SIZE
        add ix,de
        inc c
        ld a,c
        cp PLAT_MAX+1
        jr c,.lp
        pop ix
        or a
        ret
