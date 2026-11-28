; ---------------------------------------------------------------------------
; Simon's sprite frames, in his own ROM bank (run with it mapped at 0x8000).
;
; A Z80 MSX cannot write the VDP fast enough for a whole pose in the
; vertical blank: in screen 4 the V99x8 gives the CPU few access slots there
; and drops writes closer than about 90 T-states. So every frame of his is
; kept in the VRAM above 0x8000 (player_vram_fill, once at start-up: see
; tools/areas_asm.py, player_vram) and a pose change is 2 or 3 VDP commands
; (HMMM: the V9958 runs them in screen 4 with R#25 CMD set, on the screen 8
; layout of 256-byte lines) instead of up to 528 CPU writes.
; ---------------------------------------------------------------------------

fv_f            equ sv_cols                     ; (start-up scratch)
fv_n            equ sv_cols+1
fv_spr          equ sv_cols+2

; Start-up (interrupts off): every frame into the VRAM, as player_vram_tab
; places it
player_vram_fill:
        xor a
.frame:
        ld (fv_f),a
        call frame_address              ; IX = count, then 4 bytes per sprite
        ld a,(ix+0)
        ld (fv_n),a
        inc ix
        ld (fv_spr),ix
        ld a,(fv_f)
        ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,de                       ; * 9
        ld de,player_vram_tab
        add hl,de
        call fv_addr                    ; the first (up to) 8 patterns
        ld a,(fv_n)
        cp 9
        jr c,.p1
        ld a,8
.p1:
        ld b,a
        call fv_pats
        ld a,(fv_n)
        sub 9
        jr c,.no_p2
        inc a
        push af
        call fv_addr                    ; the others
        pop bc
        call fv_pats
        jr .colours
.no_p2:
        inc hl
        inc hl
        inc hl
.colours:
        call fv_addr
        ld ix,(fv_spr)
        ld a,(fv_n)
        ld b,a
.c:
        push bc
        push hl
        ld l,(ix+3)                     ; player_sct + n*16
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,player_sct
        add hl,de
        ld b,16
        call vram_out_vb
        ld de,4
        add ix,de
        pop hl
        pop bc
        djnz .c
        ld a,(fv_f)
        inc a
        cp PLAYER_FRAME_COUNT
        jr c,.frame
        jp vram_r14_zero

; B patterns of the sprites at IX (advanced) to the VDP; keeps HL
fv_pats:
        push bc
        push hl
        ld l,(ix+2)                     ; player_spt + n*32
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,player_spt
        add hl,de
        ld b,32
        call vram_out_vb
        ld de,4
        add ix,de
        pop hl
        pop bc
        djnz fv_pats
        ret

; HL = x, y, width of a player_vram_tab rectangle: write address there
; (line 128 + y: from 0x8000); HL += 3
fv_addr:
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        inc hl
        add a,128
        ld e,a
        ld a,0
        adc a,a                         ; line bit 8
        add a,a
        add a,a
        ld c,a
        ld a,e
        rlca
        rlca
        and 3
        or c                            ; address bits 16-14
        out (VDP_CTRL),a
        ld a,0x80|14
        out (VDP_CTRL),a
        ld a,d
        out (VDP_CTRL),a
        ld a,e
        and 0x3F
        or 0x40
        out (VDP_CTRL),a
        ret

; The game logic, after write_player_sprites (interrupts on): cur_frame's
; patterns and colours into the hidden page (spr_back), which the next
; VBLANK shows. Done when this returns. (Not in the VBLANK: on a turbo R
; every VDP access of the R800 waits, and the wait for the commands made
; the VBLANK work run past the HUD's scroll split.) At the castle gate
; (seq_kind 1): the CPU copy.
player_pose:
        ld a,(seq_kind)
        cp 1
        jp z,stream_cpu
        ld a,(cur_frame)
        ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,de                       ; * 9
        ld de,player_vram_tab
        add hl,de
        ld b,0x38                       ; patterns: VRAM_SPT, line 0x38
        call .rect
        ld b,0x39                       ; (sprites 8-10: the next line)
        inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        or a
        call nz,.rect                   ; (width 0: none)
        jr nz,.colours
        inc hl
        inc hl
        inc hl
.colours:
        ld b,0x1C                       ; colours: VRAM_SCT, line 0x1C
        call .rect
        jp ce_wait                      ; the last one finished
; HL = x, y, width (0: 256) of the source; B = destination line in page 0.
; One HMMM to x 0 of that line in the hidden page; HL += 3; NZ.
.rect:
        ld a,(spr_back)                 ; page 1: 0x4000 on = 64 lines on
        rrca
        rrca
        add a,b
        ld b,a
        call ce_wait                    ; the one before finished
        di                              ; (a register write: 2 bytes)
        ld a,32                         ; R#32 on, auto-increment
        out (VDP_CTRL),a
        ld a,0x80|17
        out (VDP_CTRL),a
        ei                              ; (the interrupts leave R#17 alone)
        ld c,VDP_IND
        ld d,(hl)
        inc hl
        ld e,(hl)
        inc hl
        out (c),d                       ; SX
        xor a
        out (c),a
        ld a,e                          ; SY = 128 + y
        add a,128
        out (c),a
        ld a,0
        adc a,a
        out (c),a
        xor a
        out (c),a                       ; DX = 0
        out (c),a
        out (c),b                       ; DY
        out (c),a
        ld a,(hl)                       ; NX
        inc hl
        out (c),a
        or a
        ld a,0
        jr nz,.nx
        inc a                           ; (0: 256)
.nx:
        out (c),a
        ld a,1                          ; NY = 1
        out (c),a
        xor a
        out (c),a
        out (c),a                       ; CLR
        out (c),a                       ; ARG: VRAM to VRAM, right, down
        ld a,0xD0                       ; HMMM
        out (c),a
        or a                            ; (NZ)
        ret

; Wait until the VDP's command is done (S#2 CE), interrupts allowed between
; reads (the line interrupt selects S#1 and then S#0 itself). Keeps B.
ce_wait:
        di
        ld a,2
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        in a,(VDP_CTRL)
        ld c,a
        xor a
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        ei
        rr c
        jr c,ce_wait
        ret

; The castle gate: the CPU writes the frame (clip_pattern cuts it), into
; the hidden page while the picture is drawn: interrupts stay on
stream_cpu:
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
        ld a,(spr_back)
        di                              ; (the address: no interrupt between)
        call vram_set_write_far
        ei
        ex de,hl
        call clip_pattern               ; (entering the castle gate: cut off)
        ld b,32
        call vram_out_vb
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
        ld a,(spr_back)
        di                              ; (the address: no interrupt between)
        call vram_set_write_far
        ei
        ex de,hl
        ld b,16
        call vram_out_vb
        ld de,4
        add ix,de
        pop bc
        inc c
        djnz .lp
        jp vram_r14_zero

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
