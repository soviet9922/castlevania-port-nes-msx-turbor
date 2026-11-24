; ===========================================================================
;  Castlevania port for MSX turbo R - engine skeleton
;
;  Cartridge: ASCII16 MegaROM, 128 KB (8 banks of 16 KB)
;    bank 0 -> 0x4000-0x7FFF (code, fixed)
;    bank 1 -> 0x8000-0xBFFF (data, switchable)
;
;  Runs on any MSX2+ (V9958 needed for hardware horizontal scroll); on a
;  turbo R it switches to the R800 CPU.
; ===========================================================================

        INCLUDE "msx.inc"
        INCLUDE "assets.inc"            ; generated: HUD + sprites
        INCLUDE "level.inc"             ; generated: the area (placeholder or converted)
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
        ld (ASCII16_PAGE2),a            ; data bank -> 0x8000

        ; clear engine RAM
        ld hl,RAM_BASE
        ld de,RAM_BASE+1
        ld bc,RAM_END-RAM_BASE-1
        ld (hl),0
        ldir

        call vdp_init
        call load_graphics
        call hud_draw
        call objects_load_patterns
        ld a,5
        ld (hearts),a                   ; the game starts with 5 hearts
        call level_start
        ld a,0xFF
        ld (loaded_frames),a            ; no sprite patterns loaded yet
        ld (loaded_frames+1),a
        call build_sat
        call write_player_sprites       ; first frame goes to page 1
        call install_irq
        ei

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
        call objects_update
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

code_end:
        ASSERT code_end <= 0x8000
        ds 0x8000-$, 0xFF

; ---------------------------------------------------------------------------
; Bank 1: data (mapped at 0x8000)
; ---------------------------------------------------------------------------
        ORG 0x8000
        INCLUDE "data_bank1.asm"
data1_end:
        ASSERT data1_end <= 0xC000
        ds 0xC000-$, 0xFF

; ---------------------------------------------------------------------------
; Banks 2..7: reserved for converted game data (stages, music, graphics)
; ---------------------------------------------------------------------------
        DUP 6
        ORG 0x8000
        ds 0x4000, 0xFF
        EDUP
