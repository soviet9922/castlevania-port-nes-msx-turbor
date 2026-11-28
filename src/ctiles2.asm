; Wall candles in the background, the part run from RAM (see src/ctiles.asm)

; HL = a candle's record, A = 0 wall, 1 flame 1, 2 flame 2: its four tiles
; into the queue when both its columns are on the screen
ctile_show:
        ld (ct_var),a
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        ld (ct_row),a
        inc hl
        ld (ct_cells),hl
        push de
        ld hl,(cam_x)
        call hl_shr3                    ; the first column shown
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 31
        ret nc
        add a,e
        and 31
        ld (ct_slot),a
        ld b,0
.cell:
        ld a,b                          ; its name table slot
        and 1
        ld c,a
        ld a,(ct_slot)
        add a,c
        and 31
        ld c,a
        ld a,b
        srl a
        ld hl,ct_row
        add a,(hl)
        add a,HUD_ROWS
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        or c
        ld l,a
        ld de,VRAM_PNT
        add hl,de
        push hl
        ld a,b                          ; its tile: cells + b * 3 + variant
        ld e,a
        add a,a
        add a,e
        ld e,a
        ld a,(ct_var)
        add a,e
        ld e,a
        ld d,0
        ld hl,(ct_cells)
        add hl,de
        ld a,(hl)
        pop hl
        call cq_put
        inc b
        ld a,b
        cp 4
        jr c,.cell
        ret

; HL = name table address, A = tile: into the queue (keeps B)
cq_put:
        push bc
        ld c,a
        ld a,(cq_n)
        cp CQ_MAX
        jr nc,.full
        ld e,a
        inc a
        ld (cq_n),a
        ld a,e
        add a,a
        add a,e
        ld e,a
        ld d,0
        push hl
        ld hl,cq_buf
        add hl,de
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),c
.full:
        pop bc
        ret


; vertical blank: the queued tiles
candle_vram:
        ld a,(cq_n)
        or a
        ret z
        ld b,a
        ld hl,cq_buf
.lp:
        ld a,(hl)
        out (VDP_CTRL),a
        inc hl
        ld a,(hl)
        or 0x40
        out (VDP_CTRL),a
        inc hl
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .lp
        xor a
        ld (cq_n),a
        ret

