; ---------------------------------------------------------------------------
; Areas
;
; Each area (courtyard, entrance hall, ...) lives in its own 16 KB ROM bank
; (area n = bank n+1) that starts with a header (tools/areas_asm.py). The
; current area's bank stays mapped at 0x8000 while it is played, because
; column streaming and collision read its map directly. The header is copied
; to area_hdr so the engine can use its values without banking.
; ---------------------------------------------------------------------------

; A = area number. Loads everything and restarts the player at the start.
load_area:
        ld (cur_area),a
        inc a
        ld (ASCII16_PAGE2),a            ; ASCII16: bank seen at 0x8000
        ld hl,0x8000
        ld de,area_hdr
        ld bc,AH_SIZE
        ldir

        di
        ld a,(RG1SAV)                   ; display off while loading
        and 0xBF
        ld b,a
        ld c,1
        call vdp_wreg

        ld bc,0x0010                    ; palette
        call vdp_wreg
        ld hl,(area_hdr+AH_PALETTE)
        ld b,32
        ld c,VDP_PAL
        otir

        ld hl,(area_hdr+AH_PGT0)        ; background tiles, band by band
        ld de,(area_hdr+AH_CT0)
        ld bc,(area_hdr+AH_BGSZ0)
        xor a
        call load_band
        ld hl,(area_hdr+AH_PGT1)
        ld de,(area_hdr+AH_CT1)
        ld bc,(area_hdr+AH_BGSZ1)
        ld a,1
        call load_band
        ld hl,(area_hdr+AH_PGT2)
        ld de,(area_hdr+AH_CT2)
        ld bc,(area_hdr+AH_BGSZ2)
        ld a,2
        call load_band

        call objects_load_patterns      ; (enables interrupts)
        di
        ld hl,0
        ld (cam_x),hl
        call objects_reset
        call player_reset
        call full_redraw
        ld a,0xFF
        ld (loaded_frames),a            ; Simon's patterns must be streamed again
        ld (loaded_frames+1),a
        call objects_spawn
        call build_sat
        call write_player_sprites       ; (enables interrupts)
        di

        ld a,(RG1SAV)                   ; display on
        or 0x40
        ld b,a
        ld c,1
        call vdp_wreg
        ei
        ret

; Copy one band's background tiles.  A = band, HL = patterns, DE = colours,
; BC = size in bytes. Tiles start at pattern BG_TILE_BASE of the band.
load_band:
        push de
        push bc
        push hl
        add a,a
        add a,a
        add a,a                         ; band * 8 = high byte of band * 0x800
        ld h,a
        ld l,0
        ld de,BG_TILE_BASE*8
        add hl,de
        ld (tmp_w),hl
        ex de,hl                        ; DE = VRAM pattern address
        pop hl
        pop bc
        push bc
        call vram_copy
        pop bc
        pop hl                          ; colours
        ld de,(tmp_w)
        push hl
        ld hl,VRAM_CT
        add hl,de
        ex de,hl
        pop hl
        jp vram_copy

; Walking into the area's exit (the castle gate) enters the next area.
check_area_exit:
        ld hl,(area_hdr+AH_EXITX)
        ld a,h
        and l
        inc a
        ret z                           ; 0xFFFF: this area has no exit
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
        ld a,(area_hdr+AH_NEXT)
        jp load_area
