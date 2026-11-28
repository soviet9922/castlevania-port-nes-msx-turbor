; ---------------------------------------------------------------------------
; Wall candles drawn in the background (tools/convert_stage.py, TILE_CANDLES):
; the map has every wall candle's first flame frame in its tiles; the
; candle's object (spawned, whipped and bursting as before) draws no sprite
; but swaps the tiles: the second flame frame, the first again, and the
; plain wall once it is destroyed. Writes go through a small queue flushed
; in the vertical blank (candle_vram); columns coming onto the screen show
; destroyed candles as wall (ctiles_patch).
;
; AH_CTILES: count (0: the candles are sprites), then per candle in the
; candle list's order: its left tile column (2; 0xFFFF: a sprite candle),
; top tile row, and per cell (top left, top right, bottom left, bottom
; right) three tiles: wall, flame 1, flame 2.
; ---------------------------------------------------------------------------

CQ_MAX          equ 16

; IX = a candle object -> HL = its record, NZ; Z: no tiles for it
ctile_rec:
        ld hl,(area_hdr+AH_CTILES)
        ld a,(hl)
        or a
        ret z
        inc hl
        ld e,(ix+8)
        ld d,0
        push hl
        ld h,d
        ld l,e
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de                       ; * 15
        pop de
        add hl,de
        inc hl
        ld a,(hl)                       ; (column high byte 0xFF: a sprite)
        dec hl
        inc a
        ret

; prepare_column: col_buf holds tile column DE; destroyed candles in it
; show the wall (keeps DE)
ctiles_patch:
        ld hl,(area_hdr+AH_CTILES)
        ld a,(hl)
        or a
        ret z
        ld b,a
        inc hl
        ld c,0                          ; C = candle index
.lp:
        push bc
        push hl
        push de
        inc hl
        ld a,(hl)
        dec hl
        inc a
        jr z,.skip                      ; (a sprite candle)
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,de
        ld a,0
        jr z,.side                      ; its left column
        inc hl
        ld a,h
        or l
        jr nz,.skip
        inc a                           ; its right column
.side:
        ld (ct_var),a
        ld a,c
        call candle_bit
        ld a,(hl)
        and b
        jr z,.skip                      ; still there
        pop de
        pop hl
        push hl
        push de
        inc hl
        inc hl
        ld a,(hl)                       ; its top row
        inc hl
        push hl
        ld l,a
        ld h,0
        ld bc,col_buf
        add hl,bc
        ex de,hl                        ; DE = col_buf + row
        pop hl
        ld a,(ct_var)                   ; cell side's wall tile
        ld c,a
        add a,a
        add a,c
        ld c,a
        ld b,0
        add hl,bc
        ld a,(hl)
        ld (de),a
        ld bc,6                         ; the cell below's
        add hl,bc
        inc de
        ld a,(hl)
        ld (de),a
.skip:
        pop de
        pop hl
        ld bc,15
        add hl,bc
        pop bc
        inc c
        djnz .lp
        ret
