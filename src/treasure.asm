; ---------------------------------------------------------------------------
; Hidden treasures (NES 6:$A63A, the treasure 6:$A4AA): standing on a spot
; the right way makes a treasure rise: Simon's feet within 22 px of the
; spot's y and his middle within 14 px of its x, and
;   trigger 0: no button or direction held for 128 frames
;   trigger 1: DOWN held
;   trigger 2: pushing against a wall (a direction held, not moving) for
;              128 frames
;   trigger 3: just being there
; Once per spot until the area is loaded again; sound $23. The treasure
; rises 16 px over 64 frames, stays 255 frames, and its palette cycles every
; 2 frames. Touched: type 1 is a 1-up (sound $25), the others score (bag
; 1000, types 2 and 3 2000) with a popup.
;
; AH_TREASURES: count, then per spot: x (2: Simon's middle), y (his feet),
; trigger, the treasure's x (2) and y (its sprite's top as it starts), type.
; ---------------------------------------------------------------------------

TREASURE_RISE   equ 64
TREASURE_STAY   equ 255

; area load: every spot can give its treasure again
treasures_load:
        xor a
        ld (tr_done),a
        ld (tr_t),a
        ret

; each frame
treasures_update:
        ld hl,(area_hdr+AH_TREASURES)
        ld a,(hl)
        or a
        ret z
        ld b,a
        inc hl
        ld c,1                          ; C = this spot's bit
        xor a
        ld (tr_on),a
.lp:
        ld a,(tr_done)
        and c
        jr nz,.next
        push bc
        push hl
        call tr_check
        pop hl
        pop bc
        call c,tr_fire
.next:
        ld de,8
        add hl,de
        sla c
        djnz .lp
        ld a,(tr_on)                    ; on no spot: the count starts again
        or a
        jr nz,.on
        ld (tr_t),a
.on:
        ld hl,(px)
        ld (tr_px),hl
        ret

; carry if Simon is on the spot at HL and its trigger fires
tr_check:
        ld a,(py+1)
        or a
        ret nz
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = the spot's x
        inc hl
        ld a,(py)                       ; feet: py + 32
        add a,32
        sub (hl)
        add a,21
        cp 43
        ret nc                          ; |dy| > 21
        inc hl
        ld b,(hl)                       ; B = the trigger
        ld hl,(px)                      ; middle: px + 8
        push bc
        ld bc,8+13
        add hl,bc
        pop bc
        or a
        sbc hl,de
        ld a,h
        or a
        ret nz                          ; (no carry)
        ld a,l
        cp 27
        ret nc                          ; |dx| > 13
        ld a,1
        ld (tr_on),a
        ld a,b
        cp 3
        jr z,.fire                      ; just being there
        cp 1
        jr nz,.timed
        ld a,(stick)                    ; DOWN held (down-right, down, down-left)
        sub 4
        cp 3
        ret                             ; carry: fires
.timed:
        cp 2
        ld a,(stick)
        jr z,.wall
        ld hl,trig_prev                 ; standing still: nothing held
        or (hl)
        ld hl,whip_prev
        or (hl)
        jr nz,.reset
.count:
        ld hl,tr_t                      ; 128 frames
        inc (hl)
        ld a,(hl)
        cp 128
        jr c,.wait
        ld (hl),0
.fire:
        scf
        ret
.wall:                                  ; a direction held against a wall:
        call stick_to_dx                ; he doesn't move
        or a
        jr z,.reset
        ld hl,(px)
        ld de,(tr_px)
        or a
        sbc hl,de
        jr z,.count
.reset:
        xor a
        ld (tr_t),a
.wait:
        or a
        ret

; the spot at HL (bit C) gives its treasure
tr_fire:
        push bc
        push hl
        push ix
        push hl
        call obj_free_slot
        pop hl
        jr c,.none
        ld a,(tr_done)
        or c
        ld (tr_done),a
        ld de,4
        add hl,de
        ld a,(hl)
        ld (ix+1),a
        inc hl
        ld a,(hl)
        ld (ix+2),a
        inc hl
        ld a,(hl)
        ld (ix+3),a
        inc hl
        ld a,(hl)
        ld (ix+5),a                     ; type
        ld (ix+0),OBJ_TREASURE
        xor a
        ld (ix+4),a
        ld (ix+9),a                     ; rising
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        call treasure_frame
        ld a,SND_TREASURE
        call sfx_play
.none:
        pop ix
        pop hl
        pop bc
        ret

; The treasure (IX): +4 frames, +5 type, +9 0 rising / 1 there
treasure_update:
        ld a,(ix+9)
        or a
        jr nz,.there
        ld a,(ix+4)                     ; rising: 1 px every 4 frames
        and 3
        jr nz,.risen
        dec (ix+3)
.risen:
        inc (ix+4)
        ld a,(ix+4)
        cp TREASURE_RISE
        jr c,.touch
        ld (ix+9),1
        ld (ix+4),TREASURE_STAY
        jr .touch
.there:
        dec (ix+4)
        jr nz,.touch
        ld (ix+0),OBJ_NONE
        ret
.touch:
        call treasure_frame
        ld l,(ix+1)                     ; Simon's middle within 14 px of its
        ld h,(ix+2)                     ; middle, his feet within 22 px of it
        ld de,(px)
        or a
        sbc hl,de
        ld de,13
        add hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 27
        ret nc
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)
        add a,8                         ; (its middle: the sprite's top + 8)
        ld c,a
        ld a,(py)
        add a,32
        sub c
        add a,21
        cp 43
        ret nc
        ld a,(ix+5)                     ; collected
        cp 1
        jr nz,.score
        ld hl,lives                     ; the 1-up
        inc (hl)
        ld a,1
        ld (hud_dirty),a
        ld (ix+0),OBJ_NONE
        ld a,SND_ONEUP
        jp sfx_play
.score:
        cp 2                            ; 1000 or 2000, and its popup 16 px
        ld a,0x10                       ; to the right for 48 frames
        ld c,OBJF_POP1000
        jr c,.add
        ld a,0x20
        ld c,OBJF_POP2000
.add:
        push bc
        call add_score
        ld hl,kills                     ; (not a kill)
        dec (hl)
        ld a,SND_MONEY
        call sfx_play
        pop bc
        ld (ix+6),c
        ld (ix+0),OBJ_POPUP
        ld (ix+4),48
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+3)
        sub 8                           ; (the popups are drawn 8 px down)
        ld (ix+3),a
        ret

; +6 = its picture: type * 4 + palette, the palette changing every 2 frames
treasure_frame:
        ld a,(frame_count)
        rrca
        and 3
        ld c,a
        ld a,(ix+5)
        add a,a
        add a,a
        add a,c
        add a,OBJF_TREASURE
        ld (ix+6),a
        ret
