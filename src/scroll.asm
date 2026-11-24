; ---------------------------------------------------------------------------
; Horizontal scrolling with the V9958 scroll registers.
;
; The name table is a ring of 32 tile columns. For camera position X the
; visible world tile columns are X/8+1 .. X/8+32 (the column at X/8 is
; always under the 8-pixel left mask), which map to 32 distinct ring slots.
; When X/8 changes by one, exactly one new column has to be written.
; ---------------------------------------------------------------------------

; HL >>= 3
hl_shr3:
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ret

; Compute the playfield scroll registers from cam_x.
;   R#26 = (X + 7) / 8,  R#27 = (-X) & 7   ->  picture moves left by X
calc_scroll:
        ld hl,(cam_x)
        ld a,l
        neg
        and 7
        ld (scroll_r27),a
        ld de,7
        add hl,de
        call hl_shr3
        ld a,l
        and 31
        ld (scroll_r26),a
        ret

; ---------------------------------------------------------------------------
; Build col_buf for world tile column DE and mark it for upload.
; ---------------------------------------------------------------------------
prepare_column:
        ld a,e
        and 31
        ld (col_slot),a

        ld hl,LEVEL_TILE_COLS-1
        or a
        sbc hl,de
        jr c,.blank                     ; DE >= LEVEL_TILE_COLS

        ld a,e
        and 1
        ld c,a                          ; C = left (0) or right (1) half
        srl d
        rr e                            ; DE = metatile column
        ld h,d
        ld l,e
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl
        add hl,de                       ; HL = column * 11
        ASSERT MT_ROWS == 11
        ld de,level_map
        add hl,de
        ld de,col_buf
        ld b,MT_ROWS
.lp:
        push bc
        ld a,(hl)                       ; metatile id
        inc hl
        push hl
        add a,a
        add a,a
        add a,c
        ld l,a
        ld h,0
        ld bc,metatiles
        add hl,bc
        ld a,(hl)                       ; top tile
        ld (de),a
        inc de
        inc hl
        inc hl
        ld a,(hl)                       ; bottom tile
        ld (de),a
        inc de
        pop hl
        pop bc
        djnz .lp
        jr .done

.blank:
        ld hl,col_buf
        ld b,PF_ROWS
.blp:
        ld (hl),BLANK_TILE
        inc hl
        djnz .blp

.done:
        ld a,1
        ld (col_pending),a
        ret

; ---------------------------------------------------------------------------
; Write col_buf into the name table (interrupts must be disabled).
; ---------------------------------------------------------------------------
upload_column:
        ld a,(col_pending)
        or a
        ret z
        xor a
        ld (col_pending),a

        ld a,(col_slot)
        ld l,a
        ld h,0
        ld de,VRAM_PNT + HUD_ROWS*32
        add hl,de
        ld de,32
        ld ix,col_buf
        ld b,PF_ROWS
.lp:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        or 0x40
        out (VDP_CTRL),a
        ld a,(ix+0)
        out (VDP_DATA),a
        inc ix
        add hl,de
        djnz .lp
        ret

; ---------------------------------------------------------------------------
; Redraw the whole playfield for the current cam_x (interrupts disabled).
; ---------------------------------------------------------------------------
full_redraw:
        ld hl,(cam_x)
        call hl_shr3
        inc hl
        ld b,32
.lp:
        push bc
        push hl
        ex de,hl
        call prepare_column
        call upload_column
        pop hl
        pop bc
        inc hl
        djnz .lp
        jp calc_scroll

; ---------------------------------------------------------------------------
; Follow the player; queue the column that scrolls into view.
; The camera moves at most 8 px per frame (one tile column).
; ---------------------------------------------------------------------------
camera_update:
        ld hl,(px)
        ld de,-CAM_LEAD
        add hl,de
        jr c,.not_neg                   ; px >= CAM_LEAD
        ld hl,0
.not_neg:
        push hl
        ld de,MAX_CAM+1
        or a
        sbc hl,de
        pop hl
        jr c,.not_max
        ld hl,MAX_CAM
.not_max:
        ld (cam_new),hl
        call hl_shr3
        ld (new_col),hl
        ld hl,(cam_x)
        call hl_shr3
        ex de,hl                        ; DE = old column
        ld hl,(cam_new)
        ld (cam_x),hl
        ld hl,(new_col)
        or a
        sbc hl,de
        ret z                           ; same tile column
        ld hl,(new_col)
        jr c,.left
        ld de,32                        ; moving right: new column on the right edge
        add hl,de
        ex de,hl
        jp prepare_column
.left:
        inc hl                          ; moving left: new column on the left edge
        ex de,hl
        jp prepare_column

; ---------------------------------------------------------------------------
; Collision: is world pixel (HL = x, DE = y, signed) inside a solid metatile?
; Returns carry set if solid. Clobbers AF, BC, DE, HL.
; Above the top or below the bottom of the playfield counts as empty;
; beyond the right end of the level counts as solid.
; ---------------------------------------------------------------------------
solid_at:
        ld a,d
        or a
        jr nz,.empty                    ; y < 0 or y >= 256
        ld a,e
        cp MT_ROWS*16
        jr nc,.empty
        rrca
        rrca
        rrca
        rrca
        and 0x0F
        ld c,a                          ; C = metatile row
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                            ; HL = metatile column
        ld a,h
        or a
        jr nz,.solid
        ld a,l
        cp LEVEL_W
        jr nc,.solid
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl
        add hl,de                       ; * 11
        ld b,0
        add hl,bc
        ld de,level_map
        add hl,de
        ld e,(hl)
        ld d,0
        ld hl,mt_solid
        add hl,de
        ld a,(hl)
        or a
        jr z,.empty
.solid:
        scf
        ret
.empty:
        or a
        ret
