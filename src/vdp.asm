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

        ; background tiles: each band has its own set
        ld ix,bg_band_table
        ld b,3
.band:
        push bc
        ld l,(ix+0)
        ld h,(ix+1)                     ; patterns
        ld e,(ix+4)
        ld d,(ix+5)                     ; VRAM pattern address
        ld c,(ix+8)
        ld b,(ix+9)                     ; size
        call vram_copy
        ld l,(ix+2)
        ld h,(ix+3)                     ; colours
        ld e,(ix+6)
        ld d,(ix+7)                     ; VRAM colour address
        ld c,(ix+8)
        ld b,(ix+9)
        call vram_copy
        ld de,10
        add ix,de
        pop bc
        djnz .band

        ; empty sprite list
        ld hl,VRAM_SAT
        call vram_set_write
        ld a,SAT_END_Y
        out (VDP_DATA),a
        ret

bg_band_table:
        dw bg_pgt_b0, bg_ct_b0, VRAM_PGT+0*BAND_SIZE+BG_TILE_BASE*8, VRAM_CT+0*BAND_SIZE+BG_TILE_BASE*8, BG_TILES_B0*8
        dw bg_pgt_b1, bg_ct_b1, VRAM_PGT+1*BAND_SIZE+BG_TILE_BASE*8, VRAM_CT+1*BAND_SIZE+BG_TILE_BASE*8, BG_TILES_B1*8
        dw bg_pgt_b2, bg_ct_b2, VRAM_PGT+2*BAND_SIZE+BG_TILE_BASE*8, VRAM_CT+2*BAND_SIZE+BG_TILE_BASE*8, BG_TILES_B2*8

; ---------------------------------------------------------------------------
; Player metasprites
;
; A frame (tools/msx_sprites.py) is: count, then count x (dy, dx, pattern,
; colour). The player owns hardware sprites 0..PLAYER_SPRITES-1; sprite i
; always uses pattern slot i (pattern number i*4). When the frame changes,
; its patterns and colour columns are copied into those slots, so only the
; current frame occupies VRAM.
; ---------------------------------------------------------------------------

; A = frame id -> IX = frame data
frame_address:
        ld l,a
        ld h,0
        add hl,hl
        ld de,player_frame_table
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        pop ix
        ret

; Set the VRAM write address anywhere in 128 KB (interrupts disabled).
; A = address bits 16-14 (R#14), HL = address bits 13-0
vram_set_write_far:
        out (VDP_CTRL),a
        ld a,0x80|14
        out (VDP_CTRL),a
        jp vram_set_write

; Back to R#14 = 0, which every other VRAM routine assumes.
vram_r14_zero:
        di
        xor a
        out (VDP_CTRL),a
        ld a,0x80|14
        out (VDP_CTRL),a
        ei
        ret

; Write B bytes from HL to the VDP at a pace that is safe during display.
vram_out_slow:
        ld c,VDP_DATA
.lp:
        outi
        jp nz,.lp
        ret

; ---------------------------------------------------------------------------
; Double-buffered sprites
;
; Two complete sprite pages exist in VRAM; page 1 is page 0 + 0x4000:
;   page 0: patterns 0x3800, attributes 0x1E00, colours 0x1C00
;   page 1: patterns 0x7800, attributes 0x5E00, colours 0x5C00
; The game logic writes the next frame into the page that is NOT shown,
; at any time during the frame. In VBLANK, flip_sprites just points R#5 and
; R#6 at it, so VBLANK work no longer depends on how many sprites change.
; ---------------------------------------------------------------------------

; Write the current frame (cur_frame, sat_buf) into the hidden page.
write_player_sprites:
        ld a,(spr_page)
        xor 1
        ld (spr_back),a
        ld e,a
        ld d,0
        ld hl,loaded_frames
        add hl,de
        ld a,(cur_frame)
        cp (hl)
        jr z,.sat
        ld (hl),a
        call stream_frame
.sat:
        di
        ld a,(spr_back)
        ld hl,VRAM_SAT
        call vram_set_write_far
        ei
        ld hl,sat_buf
        ld a,(spr_total)                ; (sprites + end marker) * 4 bytes
        inc a
        add a,a
        add a,a
        ld b,a
        call vram_out_slow

        ; colour columns of the object sprites (their sprite numbers change
        ; with Simon's sprite count, so they are written every frame)
        ld a,(spr_player_n)
        ld c,a
        ld a,(spr_total)
        sub c
        jr z,.no_objects
        ld b,a
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_SCT
        add hl,de
        di
        ld a,(spr_back)
        call vram_set_write_far
        ei
        ld e,c
        ld d,0
        ld hl,obj_sct_list
        add hl,de
.obj_lp:
        push bc
        push hl
        ld l,(hl)
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,obj_sct
        add hl,de
        ld b,16
        call vram_out_slow
        pop hl
        inc hl
        pop bc
        djnz .obj_lp
.no_objects:
        call vram_r14_zero
        ld a,1
        ld (flip_pending),a
        ret

; Copy the patterns and colour columns of cur_frame into the hidden page.
stream_frame:
        ld a,(cur_frame)
        call frame_address
        ld b,(ix+0)
        inc ix
        ld c,0                          ; sprite / pattern slot
.lp:
        push bc
        ld l,(ix+2)                     ; pattern: player_spt + n*32
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,player_spt
        add hl,de
        ex de,hl
        ld l,c                          ; -> VRAM_SPT + slot*32
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,VRAM_SPT
        add hl,bc
        di
        ld a,(spr_back)
        call vram_set_write_far
        ei
        ex de,hl
        ld b,32
        call vram_out_slow
        pop bc
        push bc
        ld l,(ix+3)                     ; colours: player_sct + n*16
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,player_sct
        add hl,de
        ex de,hl
        ld l,c                          ; -> VRAM_SCT + slot*16
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,VRAM_SCT
        add hl,bc
        di
        ld a,(spr_back)
        call vram_set_write_far
        ei
        ex de,hl
        ld b,16
        call vram_out_slow
        ld de,4
        add ix,de
        pop bc
        inc c
        djnz .lp
        ret

; VBLANK: show the page written last frame (interrupts disabled).
flip_sprites:
        ld a,(flip_pending)
        or a
        ret z
        xor a
        ld (flip_pending),a
        ld a,(spr_page)
        xor 1
        ld (spr_page),a
        ld b,VRAM_SAT >> 7 | 7          ; page 0: R#5, R#6
        ld c,VRAM_SPT >> 11
        jr z,.set
        ld b,(VRAM_SAT + 0x4000) >> 7 | 7
        ld c,(VRAM_SPT + 0x4000) >> 11
.set:
        ld a,b
        out (VDP_CTRL),a
        ld a,0x80|5
        out (VDP_CTRL),a
        ld a,c
        out (VDP_CTRL),a
        ld a,0x80|6
        out (VDP_CTRL),a
        ret
