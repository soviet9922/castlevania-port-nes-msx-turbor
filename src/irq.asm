; ---------------------------------------------------------------------------
; Interrupts
;
;  VBLANK (H.TIMI): reset horizontal scroll to 0 so the HUD stays fixed,
;                   signal the main loop.
;  Line   (H.KEYI): at SPLIT_LINE, apply the camera scroll for the playfield,
;                   then step the music and effects: one step every frame
;                   however long the game's frame takes, out of the vertical
;                   blank the game's VRAM work needs (the BIOS has saved
;                   every register).
;
; The BIOS calls H.KEYI for every interrupt before it reads S#0, so the
; line interrupt flag (S#1 bit 0) must be cleared here and S#0 must be
; selected again before returning.
; ---------------------------------------------------------------------------

install_irq:
        di
        ld a,0xC3                       ; JP opcode
        ld (H_KEYI),a
        ld (H_TIMI),a
        ld hl,irq_line
        ld (H_KEYI+1),hl
        ld hl,irq_vblank
        ld (H_TIMI+1),hl

        ld bc,0x6201                    ; R#1: display on, VBLANK int, 16x16 sprites
        call vdp_wreg
        ld a,b
        ld (RG1SAV),a
        ld bc,0x1400                    ; R#0: Graphic 3 + line interrupt (IE1)
        call vdp_wreg
        ld a,b
        ld (RG0SAV),a
        ret

irq_vblank:
        xor a
        out (VDP_CTRL),a
        ld a,0x80|27
        out (VDP_CTRL),a
        xor a
        out (VDP_CTRL),a
        ld a,0x80|26
        out (VDP_CTRL),a

        ld a,1
        ld (frame_ready),a
        ld hl,(frame_count)
        inc hl
        ld (frame_count),hl
        ret

irq_line:
        ld a,1                          ; select S#1
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        in a,(VDP_CTRL)                 ; read S#1 (clears FH)
        ld b,a
        xor a                           ; back to S#0 for the BIOS
        out (VDP_CTRL),a
        ld a,0x80|15
        out (VDP_CTRL),a
        rr b                            ; FH -> carry
        ret nc

        ld a,(scroll_r27)
        out (VDP_CTRL),a
        ld a,0x80|27
        out (VDP_CTRL),a
        ld a,(scroll_r26)
        out (VDP_CTRL),a
        ld a,0x80|26
        out (VDP_CTRL),a

        ld hl,(line_irq_count)
        inc hl
        ld (line_irq_count),hl
        jp sound_frame                  ; (puts page2_bank back at 0x8000)
