; ===========================================================================
;  Castlevania port for MSX turbo R - engine skeleton
;
;  Cartridge: ASCII16 MegaROM, 128 KB (8 banks of 16 KB)
;    bank 0    -> 0x4000-0x7FFF  code + data shared by all areas (fixed)
;    bank 1..n -> 0x8000-0xBFFF  one bank per area (see src/area.asm)
;
;  Runs on any MSX2+ (V9958 needed for hardware horizontal scroll); on a
;  turbo R it switches to the R800 CPU.
; ===========================================================================

        INCLUDE "msx.inc"
        INCLUDE "assets.inc"            ; generated: HUD tile numbers, MT_ROWS
        INCLUDE "config.inc"
        INCLUDE "ram.inc"

; ---------------------------------------------------------------------------
; Bank 0: code
; ---------------------------------------------------------------------------
        ORG 0x4000

        db "AB"                         ; ROM header
        dw init                         ; INIT
        dw 0                            ; STATEMENT
        dw 0                            ; DEVICE
        dw 0                            ; TEXT
        ds 6, 0

init:
        di
        call select_cpu
        call enable_page2
        ld a,1
        ld (ASCII16_PAGE2),a            ; also makes the mapper easy to detect

        ; clear engine RAM
        ld hl,RAM_BASE
        ld de,RAM_BASE+1
        ld bc,RAM_END-RAM_BASE-1
        ld (hl),0
        ldir

        call vdp_init
        call load_graphics
        call hud_draw
        ld a,5
        ld (hearts),a                   ; the game starts with 5 hearts
        ld a,HP_MAX
        ld (hp),a
        call install_irq
        xor a
        call load_area                  ; area 0: Stage 1 courtyard

; ---------------------------------------------------------------------------
; Main loop: one iteration per video frame
; ---------------------------------------------------------------------------
main_loop:
        call wait_frame

        ; --- VBLANK work: everything that touches VRAM ---
        di
        call upload_column
        call flip_sprites
        call hud_update
        call calc_scroll
        ei
vblank_done:                            ; (tests measure VBLANK work up to here)

        ; --- game logic ---
        call read_input
        call player_update
        call check_area_exit
        call objects_spawn
        call enemies_update
        call objects_update
        call check_death
        call camera_update
        call build_sat
        call write_player_sprites       ; into the hidden sprite page
        jp main_loop

wait_frame:
        ld a,(frame_ready)
        or a
        jr nz,.go
        halt
        jr wait_frame
.go:
        xor a
        ld (frame_ready),a
        ret

; ---------------------------------------------------------------------------
; On a turbo R, switch to the R800 in DRAM mode (BIOS copied to fast RAM).
; ---------------------------------------------------------------------------
select_cpu:
        ld a,(MSXVER)
        cp 3
        ret c
        ld a,0x82
        jp CHGCPU

; ---------------------------------------------------------------------------
; Make page 2 (0x8000-0xBFFF) show this cartridge's slot (same as page 1).
; ---------------------------------------------------------------------------
enable_page2:
        call RSLREG
        rrca
        rrca
        and 3                           ; primary slot of page 1
        ld c,a
        ld b,0
        ld hl,EXPTBL
        add hl,bc
        ld a,(hl)
        and 0x80                        ; expanded flag
        or c
        ld c,a
        inc hl
        inc hl
        inc hl
        inc hl                          ; -> SLTTBL entry
        ld a,(hl)
        and 0x0C                        ; secondary slot of page 1
        or c
        ld h,0x80
        jp ENASLT

; ---------------------------------------------------------------------------
        INCLUDE "vdp.asm"
        INCLUDE "irq.asm"
        INCLUDE "input.asm"
        INCLUDE "hud.asm"
        INCLUDE "scroll.asm"
        INCLUDE "player.asm"
        INCLUDE "objects.asm"
        INCLUDE "area.asm"

; ---------------------------------------------------------------------------
; Data shared by all areas (stays in bank 0)
; ---------------------------------------------------------------------------
player_spt:     INCBIN "player_spt.bin"         ; 32 bytes per 16x16 pattern
player_sct:     INCBIN "player_sct.bin"         ; 16 colour bytes per sprite
player_frames:  INCBIN "player_frames.bin"      ; count, then (dy, dx, pattern, colour)
        INCLUDE "player_frames.inc"             ; player_frame_table
jump_table:     INCBIN "player_jump.bin"        ; JUMP_LEN signed dy, rising half
kb_table:       INCBIN "player_kb.bin"          ; knock-back arc, same format
kb_table_end:
KB_LEN          equ kb_table_end - kb_table
hud_pgt:        INCBIN "hud_pgt.bin"
hud_ct:         INCBIN "hud_ct.bin"

code_end:
        ASSERT code_end <= 0x8000
        ds 0x8000-$, 0xFF

; ---------------------------------------------------------------------------
; Banks 1..n: one per area (generated), then empty banks up to 128 KB
; ---------------------------------------------------------------------------
        INCLUDE "areas.asm"
