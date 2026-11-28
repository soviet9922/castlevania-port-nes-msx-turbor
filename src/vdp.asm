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
        call vpace
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
        call vpace
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
        ; clear both sprite pages (0x0000-0x7FFF): a real MSX's VRAM holds
        ; garbage at power-on (C-BIOS clears it), and a garbage sprite list
        ; keeps the VDP busy enough to drop writes
        ld hl,0
        ld bc,0x8000
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
        db 25, 0x42                     ; V9958: CMD = VDP commands in screen 4
                                        ; (src/player_bank.asm), MSK = hide
                                        ; the leftmost 8 px
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

        ; empty sprite lists on both pages (a list of zeros is 32 sprites
        ; on the top lines: the VDP then has no time left for our writes)
        xor a
        call .end
        ld a,1
.end:
        di
        ld hl,VRAM_SAT
        call vram_set_write_far
        ld a,SAT_END_Y
        out (VDP_DATA),a
        jp vram_r14_zero

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


; ---------------------------------------------------------------------------
; Double-buffered sprites
;
; Two complete sprite pages exist in VRAM; page 1 is page 0 + 0x4000:
;   page 0: patterns 0x3800, attributes 0x1E00, colours 0x1C00
;   page 1: patterns 0x7800, attributes 0x5E00, colours 0x5C00
; While the picture is drawn, the VDP (sprite mode 2: it reads the sprite
; list on every line) leaves the CPU so few memory slots that writes closer
; than ~32 us get lost on a real V9938/V9958 (openMSX models it too). So
; the game logic only notes what the hidden page needs (write_player_sprites:
; Simon's new pose, the colour columns that changed; sat_buf), and the
; vertical blank writes it there and shows that page (sprite_vram).
; ---------------------------------------------------------------------------

; The current frame (cur_frame, sat_buf): note the hidden page's changes.
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
        jr z,.cols
        ld (hl),a
        call stream_frame               ; his new pose, now (src/player_bank.asm)
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
.cols:
        ; colour columns of the object sprites. Their sprite numbers change
        ; with Simon's sprite count, so each page remembers which column
        ; every hardware sprite has (sct_cache) and only changes are noted.
        ld a,(spr_back)
        ld hl,sct_cache
        or a
        jr z,.cache0
        ld hl,sct_cache+MAX_SPRITES
.cache0:
        ld (tmp_w),hl                   ; this page's cache
        xor a
        ld (sv_ncol),a
        ld a,(spr_player_n)
        ld c,a
        ld a,(spr_total)
        sub c
        jr z,.done
        ld b,a
.obj_lp:
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
        push bc
        ld e,a
        ld a,(sv_ncol)                  ; note (sprite, column)
        ld l,a
        inc a
        ld (sv_ncol),a
        ld h,0
        add hl,hl
        ld a,e
        ld de,sv_cols
        add hl,de
        ld (hl),c
        inc hl
        ld (hl),a
        pop bc
.obj_same:
        inc c
        djnz .obj_lp
.done:
        ld a,1
        ld (flip_pending),a
        ret

; Vertical blank (interrupts off): the hidden page gets Simon's new pose,
; the changed colour columns and the sprite list, then it is shown.
sprite_vram:
        ld a,(flip_pending)
        or a
        ret z
        ld a,(sv_simon)
        or a
        call nz,stream_frame
        ld a,(sv_ncol)
        or a
        jr z,.sat
        ld b,a
        ld hl,sv_cols
.col:
        push bc
        ld a,(hl)                       ; sprite: VRAM_SCT + sprite * 16
        inc hl
        ld c,(hl)                       ; its column
        inc hl
        push hl
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_SCT
        add hl,de
        ld a,(spr_back)
        call vram_set_write_far
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(area_hdr+AH_OBJSCT)
        add hl,de
        ld b,16
        call vram_out_vb
        pop hl
        pop bc
        djnz .col
.sat:
        ld a,(spr_back)
        ld hl,VRAM_SAT
        call vram_set_write_far
        ld hl,sat_buf
        ld a,(spr_total)                ; (sprites + end marker) * 4 bytes
        inc a
        add a,a
        add a,a
        ld b,a
        call vram_out_vb
        xor a
        ld (sv_simon),a
        ld (sv_ncol),a
        out (VDP_CTRL),a                ; R#14 = 0 (interrupts stay off)
        ld a,0x80|14
        out (VDP_CTRL),a
        jp flip_sprites

; B bytes from HL to the VDP, about 100 T-states apart: screen 4 drops CPU
; writes closer than about 90 (a turbo R also spaces the R800's)
vram_out_vb:
        ld c,VDP_DATA
.lp:
        outi
        call vpace
        jp nz,.lp
        ret

; After a VDP data write: 69 T-states (with the call) before the next one
; (keeps every register and flag)
vpace:
        ex (sp),hl
        ex (sp),hl
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
