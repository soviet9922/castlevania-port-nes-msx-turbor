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
        ; (the palette comes with each area, see load_area)
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

        ; empty sprite list
        ld hl,VRAM_SAT
        call vram_set_write
        ld a,SAT_END_Y
        out (VDP_DATA),a
        ret

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

        ; colour columns of the object sprites. Their sprite numbers change
        ; with Simon's sprite count, so each page remembers which column
        ; every hardware sprite has (sct_cache) and only changes are written.
        ld a,(spr_back)
        ld hl,sct_cache
        or a
        jr z,.cache0
        ld hl,sct_cache+MAX_SPRITES
.cache0:
        ld (tmp_w),hl                   ; this page's cache
        ld a,(spr_player_n)
        ld c,a
        ld a,(spr_total)
        sub c
        jr z,.no_objects
        ld b,a
.obj_lp:
        push bc
        ld e,c
        ld d,0
        ld hl,obj_sct_list
        add hl,de
        ld a,(hl)                       ; wanted column
        ld hl,(tmp_w)
        add hl,de
        cp (hl)
        jr z,.obj_same
        ld (hl),a
        push af
        ld l,c                          ; VRAM_SCT + sprite * 16
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
        pop af
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(area_hdr+AH_OBJSCT)
        add hl,de
        ld b,16
        call vram_out_slow
.obj_same:
        pop bc
        inc c
        djnz .obj_lp
.no_objects:
        call vram_r14_zero
        ld a,1
        ld (flip_pending),a
        ret

; Copy the patterns and colour columns of cur_frame into the hidden page.
stream_frame:
        ld a,(spr_back)                 ; Simon's colours replace these entries
        ld hl,sct_cache
        or a
        jr z,.inval
        ld hl,sct_cache+MAX_SPRITES
.inval:
        ld b,PLAYER_SPRITES
.inv_lp:
        ld (hl),0xFF
        inc hl
        djnz .inv_lp
        ld a,PLAYER_BANK                ; Simon's patterns: the last ROM bank,
        ld (page2_bank),a               ; (the sound interrupt puts it back)
        ld (ASCII16_PAGE2),a            ; at 0x8000 instead of the area's
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
        call clip_pattern               ; (entering the castle gate: cut off)
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
        ld a,(cur_area)                 ; the area's bank again
        call area_bank
        ld (page2_bank),a
        ld (ASCII16_PAGE2),a
        ret

; HL = a 16x16 pattern (32 bytes: left 8 columns, then right 8). While Simon
; walks into the castle gate, the columns past the gate's pillar are cleared
; (the NES draws him behind it); returns HL = the pattern to copy.
clip_pattern:
        ld a,(seq_kind)
        cp 1
        ret nz
        push de
        push bc
        ld de,clip_buf
        push de
        ld b,16
        ld a,(clip_l)
        ld c,a
.left:
        ld a,(hl)
        and c
        ld (de),a
        inc hl
        inc de
        djnz .left
        ld b,16
        ld a,(clip_r)
        ld c,a
.right:
        ld a,(hl)
        and c
        ld (de),a
        inc hl
        inc de
        djnz .right
        pop hl
        pop bc
        pop de
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
