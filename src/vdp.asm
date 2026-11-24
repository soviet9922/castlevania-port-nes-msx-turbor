; ---------------------------------------------------------------------------
; VDP helpers. All VRAM addresses used by the engine are < 0x4000, so R#14
; stays 0 and a 14-bit address is enough.
; Callers must have interrupts disabled while using these (the line
; interrupt writes VDP registers through the same port).
; ---------------------------------------------------------------------------

; Write register.  B = value, C = register number
vdp_wreg:
        ld a,b
        out (VDP_CTRL),a
        ld a,c
        or 0x80
        out (VDP_CTRL),a
        ret

; Set VRAM write address.  HL = address
vram_set_write:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        and 0x3F
        or 0x40
        out (VDP_CTRL),a
        ret

; Copy RAM/ROM -> VRAM.  HL = source, DE = VRAM address, BC = length (>0)
vram_copy:
        ex de,hl
        call vram_set_write
        ex de,hl
.lp:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.lp
        ret

; Fill VRAM.  HL = VRAM address, BC = length (>0), A = value
vram_fill:
        ld e,a
        call vram_set_write
.lp:
        ld a,e
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,.lp
        ret

; ---------------------------------------------------------------------------
; Initialise the VDP: Screen 4 (Graphic 3), 16x16 sprites, palette, clear VRAM.
; Display stays off; install_irq turns it on.
; ---------------------------------------------------------------------------
vdp_init:
        ld hl,vdp_reg_table
.lp:
        ld a,(hl)
        cp 0xFF
        jr z,.regs_done
        ld c,a
        inc hl
        ld b,(hl)
        inc hl
        call vdp_wreg
        jr .lp
.regs_done:
        ; palette
        ld bc,0x0010                    ; R#16 = 0 (palette index)
        call vdp_wreg
        ld hl,palette
        ld b,32
        ld c,VDP_PAL
        otir
        ; clear all 16 KB used by Screen 4
        ld hl,0
        ld bc,0x4000
        xor a
        call vram_fill
        ; the address counter carried past 0x3FFF into R#14: reset it,
        ; otherwise every later write would land at 0x4000+
        ld bc,0x000E
        jp vdp_wreg

vdp_reg_table:
        db 0,  0x04                     ; Graphic 3, line interrupt off (for now)
        db 1,  0x02                     ; display off, VBLANK int off, 16x16 sprites
        db 2,  VRAM_PNT >> 10
        db 3,  0xFF                     ; colour table at 0x2000 (3 bands)
        db 4,  0x03                     ; pattern table at 0x0000 (3 bands)
        db 5,  0x3F                     ; SAT at 0x1E00 (colour table at 0x1C00)
        db 6,  VRAM_SPT >> 11
        db 7,  0x00                     ; backdrop colour 0
        db 8,  0x08                     ; 64K VRAM, sprites on, colour 0 transparent
        db 9,  0x00                     ; 192 lines, NTSC timing as set by BIOS
        db 10, 0x00
        db 11, 0x00
        db 14, 0x00
        db 15, 0x00
        db 19, SPLIT_LINE               ; line interrupt position
        db 23, 0x00                     ; no vertical scroll
        db 25, 0x02                     ; V9958: MSK = hide leftmost 8 px
        db 26, 0x00
        db 27, 0x00
        db 0xFF

; ---------------------------------------------------------------------------
; Upload all static graphics.
; ---------------------------------------------------------------------------
load_graphics:
        ; BIOS font, characters 0x20-0x5F, into band 0 (HUD lives there)
        ld hl,(CGTABL)
        ld de,0x20*8
        add hl,de
        ld de,VRAM_PGT+0x20*8
        ld bc,64*8
        call vram_copy
        ld hl,VRAM_CT+0x20*8
        ld bc,64*8
        ld a,0xF1                       ; white on black
        call vram_fill

        ; HUD tiles
        ld hl,hud_pgt
        ld de,VRAM_PGT+HUDT_HEART*8
        ld bc,HUD_TILE_COUNT*8
        call vram_copy
        ld hl,hud_ct
        ld de,VRAM_CT+HUDT_HEART*8
        ld bc,HUD_TILE_COUNT*8
        call vram_copy

        ; background tiles into all three bands
        ld de,BG_TILE_BASE*8
        ld b,3
.band:
        push bc
        push de
        ld hl,bg_pgt
        ld bc,BG_TILE_COUNT*8
        call vram_copy                  ; pattern
        pop de
        push de
        ld hl,VRAM_CT
        add hl,de
        ex de,hl
        ld hl,bg_ct
        ld bc,BG_TILE_COUNT*8
        call vram_copy                  ; colour
        pop de
        ld hl,BAND_SIZE
        add hl,de
        ex de,hl
        pop bc
        djnz .band

        ; sprite patterns and the player's sprite colours
        ld hl,player_spt
        ld de,VRAM_SPT
        ld bc,PLAYER_SPT_SIZE
        call vram_copy
        ld hl,player_sprite_colors
        ld de,VRAM_SCT
        ld bc,PLAYER_SPRITES*16
        call vram_copy

        ; empty sprite list
        ld hl,VRAM_SAT
        call vram_set_write
        ld a,SAT_END_Y
        out (VDP_DATA),a
        ret

; Sprite colour table entries for sprites 0..3 (16 lines each).
; Odd sprites set CC (bit 6): their colour is ORed with the sprite below,
; giving 3 colours per 16-pixel-wide figure: A, B and A|B.
player_sprite_colors:
        ds 16, PLAYER_COLOR_A           ; sprite 0: top, layer A
        ds 16, 0x40 | PLAYER_COLOR_B    ; sprite 1: top, layer B (CC)
        ds 16, PLAYER_COLOR_A           ; sprite 2: bottom, layer A
        ds 16, 0x40 | PLAYER_COLOR_B    ; sprite 3: bottom, layer B (CC)

; Copy sat_buf to the sprite attribute table (VBLANK only).
upload_sat:
        ld hl,VRAM_SAT
        call vram_set_write
        ld hl,sat_buf
        ld bc,(PLAYER_SPRITES+1)*4*256 + VDP_DATA
        otir
        ret
