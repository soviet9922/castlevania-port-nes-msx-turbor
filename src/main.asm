; ===========================================================================
;  Castlevania port for MSX turbo R - engine skeleton
;
;  Cartridge: ASCII16 MegaROM, 256 or 512 KB (banks of 16 KB)
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
        xor a                           ; no BIOS key click on key presses
        ld (CLIKSW),a
        call select_cpu
        call enable_page2
        ld a,1
        ld (page2_bank),a
        ld (ASCII16_PAGE2),a            ; also makes the mapper easy to detect

        ; clear engine RAM
        ld hl,RAM_BASE
        ld de,RAM_BASE+1
        ld bc,RAM_END-RAM_BASE-1
        ld (hl),0
        ldir

        ld a,PLAYER_BANK                ; the RAM code (src/ramcode.asm)
        ld (ASCII16_PAGE2),a
        ld hl,ramcode_src
        ld de,RAMCODE
        ld bc,RAMCODE_LEN
        ldir
        ld a,1
        ld (ASCII16_PAGE2),a

        call vdp_init
        call load_graphics
        call install_irq
        call sound_init
        call start_game                 ; (the debug menu first, if built in)

; ---------------------------------------------------------------------------
; Main loop: one iteration per video frame
; ---------------------------------------------------------------------------
main_loop:
        call wait_frame

        ; --- VBLANK work: everything that touches VRAM ---
        di
        ld a,(col_pending)              ; a new map column this frame: the HUD
        push af                         ; waits a frame (both at once can
        call upload_column              ; overrun the vertical blank)
        call door_vram
        call medusa_vram
        call flip_sprites
        pop af
        or a
        call z,hud_or_crusher           ; (one of them: the VBLANK is short)
        call calc_scroll
        ei
vblank_done:                            ; (tests measure VBLANK work up to here)
        call sound_tick                 ; music and effects, one step per frame

        ; --- game logic ---
        ld a,(game_over_t)              ; game over: wait, then a new game
        or a
        jr z,.not_over
        dec a
        ld (game_over_t),a
        jr nz,.frozen
        call start_game
        jr .frozen
.not_over:
        ld a,(dying_t)                  ; dying: only the death animation
        or a
        jr z,.alive
        call dying_tick
.frozen:
        call build_sat
        call write_player_sprites
        jp main_loop
.alive:
        ld a,(seq_kind)                 ; castle gate / door sequence
        or a
        jr z,.no_seq
        call seq_tick
        jr .frozen
.no_seq:
        ld a,(clear_phase)              ; stage clear: the tally, then the
        or a                            ; next block
        jr z,.playing
        call clear_tick
        jr .frozen
.playing:
        IF DEBUG_MENU
        call debug_tick                 ; infinite health / time
        ENDIF
        call timer_tick
        call read_input
        call player_update
        call check_area_exit
        call objects_spawn
        call enemies_update
        call crushers_tick
        call objects_update
        call check_death
        call camera_update
        call build_sat
        call write_player_sprites       ; into the hidden sprite page
        jp main_loop

; Wait for the next VBLANK, so that the VBLANK work that follows runs in the
; vertical blank. A frame whose logic ran late (the flag is already set) goes
; on at once if the VDP is still in the vertical retrace (S#2 bit 6), and
; otherwise waits for the next VBLANK rather than doing its VRAM work while
; the screen is being drawn (and staying out of step from then on). The flag
; is tested with interrupts off, and EI comes right before HALT (interrupts
; are taken only after the instruction that follows EI), so no VBLANK can
; slip in between the test and the HALT.
; A new game: the debug menu (it starts the game when it is left), or at once
start_game:
        IF DEBUG_MENU
        jp debug_menu
        ELSE
        jp new_game
        ENDIF

wait_frame:
        di
        ld a,(frame_ready)
        or a
        jr z,.wait
        ld a,2                          ; late: still in the vertical retrace?
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        in a,(VDP_CTRL)                 ; S#2
        ld b,a
        xor a                           ; back to S#0 for the BIOS
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        bit 6,b
        jr nz,.go                       ; VR: go on now
        xor a                           ; no: that one is gone, the next
        ld (frame_ready),a
.wait:
        ei
        halt
        di
        ld a,(frame_ready)
        or a
        jr z,.wait                      ; (a line interrupt: keep waiting)
.go:
        xor a
        ld (frame_ready),a
        ei
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
        INCLUDE "sound.asm"
        INCLUDE "sound.inc"             ; generated: the sound table, SND_ numbers

; ---------------------------------------------------------------------------
; Data shared by all areas (stays in bank 0; Simon's sprite patterns and
; colours are in the last bank, see areas.asm)
; ---------------------------------------------------------------------------
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
; Banks 1..n: one per area (generated; see tools/areas_asm.py for the layout)
; ---------------------------------------------------------------------------
        INCLUDE "areas.asm"
