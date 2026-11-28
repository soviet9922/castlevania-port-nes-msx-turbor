; ---------------------------------------------------------------------------
; Breakable walls (NES 6:$A825, list $FC78): 16x16 blocks of the map that
; the whip breaks with one hit. A broken block is drawn with the area's
; blank tile and is no longer solid; the first time, it drops the wall's
; item (as a candle's: through candle_item, so the NES's rules apply).
;
; The area's list (AH_WALLS): count (at most 2), then per wall: tile column
; (2 bytes), tile row, item code (ITEM_NONE: nothing). Broken walls stay
; broken until a restart: 2 bits per area in wall_bits, the current area's
; in walls_now.
; ---------------------------------------------------------------------------

; HL = the wall_bits byte of the current area, B = its bits' shift (0-6)
wall_bits_of:
        ld a,(cur_area)
        ld c,a
        and 3
        add a,a
        ld b,a
        ld a,c
        rrca
        rrca
        and 0x3F
        ld e,a
        ld d,0
        ld hl,wall_bits
        add hl,de
        ret

; area load: the area's broken walls
walls_load:
        call wall_bits_of
        ld a,(hl)
        inc b
.shift:
        dec b
        jr z,.got
        rrca
        jr .shift
.got:
        and 3
        ld (walls_now),a
        ret


; Each frame, while the whip can hit (not a throw's swing): a wall it
; reaches breaks.
walls_update:
        ld a,(whip_active)
        or a
        ret z
        ld a,(throwing)
        or a
        ret nz
        ld hl,(area_hdr+AH_WALLS)
        ld a,(hl)
        or a
        ret z
        ld b,a
        inc hl
        ld c,1                          ; C = this wall's bit
.lp:
        ld a,(walls_now)
        and c
        jr nz,.next
        push bc
        push hl
        call wall_whipped
        pop hl
        pop bc
        jr c,wall_break
.next:
        inc hl
        inc hl
        inc hl
        inc hl
        sla c
        djnz .lp
        ret

; Carry if the whip reaches the wall at HL (NES $A8C6, sub_6_A048): its
; middle within 16 px of Simon's feet, and across within 8 + 16 px of a point
; 24 px in front of his middle (the morning star: 8 + 24 px of a point 40 px
; in front, table $A8D2)
wall_whipped:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(py+1)
        or a
        ret nz                          ; (no carry)
        ld a,(hl)                       ; the wall's middle: row * 8 + 8
        add a,a
        add a,a
        add a,a
        add a,8
        ld c,a
        ld a,(py)                       ; his feet: py + 32
        add a,32
        sub c
        add a,15
        cp 31
        ret nc
        ex de,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,8
        add hl,de                       ; the wall's middle across
        push hl
        ld a,(whip_level)
        cp 2
        ld de,24
        ld c,8+16
        jr c,.reach
        ld de,40
        ld c,8+24
.reach:
        ld a,(facing)
        or a
        jr z,.right
        ld hl,0
        or a
        sbc hl,de
        ex de,hl
.right:
        ld hl,(px)                      ; his middle: px + 8
        add hl,de
        ld de,8
        add hl,de
        pop de
        or a
        sbc hl,de
        bit 7,h
        jr z,.abs
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
.abs:
        ld a,h
        or a
        ret nz                          ; (no carry: |dx| > 255)
        ld a,l
        cp c
        ret

; The wall at HL (bit C) breaks: sound, the map shows it broken, its item.
wall_break:
        ld a,(walls_now)
        or c
        ld (walls_now),a
        push hl
        push bc
        call wall_bits_of
        pop de                          ; (E = the wall's bit)
        ld a,e
        inc b
.shift:
        dec b
        jr z,.set
        rlca
        jr .shift
.set:
        or (hl)
        ld (hl),a
        ld a,SND_BREAK
        call sfx_play
        pop hl
        push hl
        call wall_redraw
        pop hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)                       ; its item: as a candle's burst at
        cp ITEM_NONE                    ; its end (burst_update: the NES's
        ret z                           ; rules, the power-up's window)
        ld c,a
        dec hl
        ld b,(hl)                       ; B = row
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)                       ; DE = column
        push ix
        push bc
        push de
        call obj_free_slot
        pop hl
        pop bc
        jr c,.none
        add hl,hl
        add hl,hl
        add hl,hl
        ld (ix+1),l
        ld (ix+2),h
        ld a,b
        add a,a
        add a,a
        add a,a
        sub 8                           ; (the item is drawn 8 px down)
        ld (ix+3),a
        ld (ix+5),c
        ld (ix+0),OBJ_BURST
        ld (ix+4),20                    ; (the burst's last frame: the item next)
        ld (ix+6),OBJF_BURST+3
        ld (ix+7),KIND_CANDLE
        ld (ix+8),0xFF
.none:
        pop ix
        ret

; the broken wall at HL on the screen: its 2x2 tiles become the blank tile
; where its columns are among the 32 shown (the others: walls_patch when
; they come in)
wall_redraw:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)                       ; row
        ld (wall_row),a
        call .column
        inc de
.column:                                ; DE = tile column
        push de
        ld hl,(cam_x)
        call hl_shr3                    ; first column shown
        ex de,hl
        or a
        sbc hl,de                       ; column - first
        ld a,h
        or a
        jr nz,.off
        ld a,l
        cp 32
        jr nc,.off
        pop de
        push de
        ld a,(wall_row)
        add a,HUD_ROWS
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl                       ; * 32
        ld a,e
        and 31
        or l
        ld l,a
        ld bc,VRAM_PNT
        add hl,bc
        ld a,(area_hdr+AH_BLANK)
        ld c,a
        di
        call .tile
        ld de,32
        add hl,de
        call .tile
        ei
.off:
        pop de
        ret
.tile:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        or 0x40
        out (VDP_CTRL),a
        ld a,c
        out (VDP_DATA),a
        ret

; prepare_column: col_buf holds tile column DE; broken walls in it become
; blank (DE kept)
walls_patch:
        ld a,(walls_now)
        or a
        ret z
        ld c,a
        ld hl,(area_hdr+AH_WALLS)
        ld b,(hl)
        inc hl
.lp:
        srl c
        jr nc,.next
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; the wall's column
        or a
        sbc hl,de
        jr z,.in
        inc hl                          ; (the column right of it)
        ld a,h
        or l
        jr nz,.out
.in:
        pop hl
        push hl
        inc hl
        inc hl
        push de
        ld e,(hl)                       ; row
        ld d,0
        ld hl,col_buf
        add hl,de
        ld a,(area_hdr+AH_BLANK)
        ld (hl),a
        inc hl
        ld (hl),a
        pop de
.out:
        pop hl
.next:
        inc hl
        inc hl
        inc hl
        inc hl
        djnz .lp
        ret

; solid_at found a solid tile at (probe_col, probe_row): carry if a broken
; wall is there (then it isn't solid)
wall_open:
        ld a,(walls_now)
        ld c,a
        ld hl,(area_hdr+AH_WALLS)
        ld b,(hl)
        inc hl
.lp:
        srl c
        jr nc,.next
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)                       ; row: probe_row - row is 0 or 1
        ld hl,probe_row
        sub (hl)
        neg
        cp 2
        jr nc,.out
        ld hl,(probe_col)               ; column: probe_col - column is 0 or 1
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.out
        ld a,l
        cp 2
        jr nc,.out
        pop hl
        scf
        ret
.out:
        pop hl
.next:
        inc hl
        inc hl
        inc hl
        inc hl
        djnz .lp
        or a
        ret
