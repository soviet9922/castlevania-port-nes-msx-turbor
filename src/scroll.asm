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
        push bc                         ; (a new column shows crushers at rest:
        push hl                         ; draw them again)
        call crushers_redraw
        pop hl
        pop bc
        ld a,e
        and 31
        ld (col_slot),a

        ld hl,(area_hdr+AH_TCOLS)
        dec hl
        or a
        sbc hl,de
        jr c,.blank                     ; DE >= tile columns of the area

        ld h,d
        ld l,e
        add hl,hl                       ; *2
        ld b,h
        ld c,l
        add hl,hl                       ; *4
        add hl,bc                       ; *6
        add hl,hl                       ; *12
        add hl,hl                       ; *24
        or a
        sbc hl,bc                       ; *22
        ASSERT PF_ROWS == 22
        ld de,(area_hdr+AH_TILES)
        add hl,de
        ld de,col_buf
        ld bc,PF_ROWS
        ldir
        jr .done

.blank:
        ld hl,col_buf
        ld b,PF_ROWS
        ld a,(area_hdr+AH_BLANK)
.blp:
        ld (hl),a
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
        ld de,(area_hdr+AH_MAXCAM)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.not_max
        ex de,hl                        ; clamp to the area's maximum
.not_max:
        ld de,(area_hdr+AH_MINCAM)      ; and to its minimum
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.not_min
        ex de,hl
.not_min:
        ld a,(cam_lock)                 ; boss fight: never scroll back left
        or a
        jr z,.unlocked
        ld de,(cam_min)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.raise
        ex de,hl                        ; left of the lock: stay
        jr .unlocked
.raise:
        ld (cam_min),hl
.unlocked:
; HL = new camera x (at most 8 px from the old one): move there, queueing the
; tile column that comes into view
camera_goto:
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
; Collision: is world pixel (HL = x, DE = y, signed) inside a solid tile?
; Collision is per 8x8 tile, as on the NES (tiles $60-$6B are solid there).
; Returns carry set if solid. Clobbers AF, BC, DE, HL.
; Above the top or below the bottom of the playfield counts as empty;
; beyond the right end of the area counts as solid.
; ---------------------------------------------------------------------------
solid_at:
        ld a,d
        or a
        jr nz,.empty                    ; y < 0 or y >= 256
        ld a,e
        cp PF_ROWS*8
        jr nc,.empty
        rrca
        rrca
        rrca
        and 0x1F
        ld c,a                          ; C = tile row
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                            ; HL = tile column
        ld de,(area_hdr+AH_TCOLS)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.solid
        add hl,hl                       ; column * 22
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        add hl,hl
        add hl,hl
        or a
        sbc hl,de
        ASSERT PF_ROWS == 22
        ld b,0
        add hl,bc
        ld de,(area_hdr+AH_COLL)
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
