; Simon's sprite streaming, run from RAM (see src/vdp.asm: sprite_vram)

; Vertical blank: the patterns and colour columns of cur_frame into the
; hidden page (src/player_bank.asm, in Simon's bank: mapped meanwhile).
stream_frame:
        ld a,PLAYER_BANK                ; Simon's bank at 0x8000 instead of
        ld (page2_bank),a               ; the area's
        ld (ASCII16_PAGE2),a
        call player_pose
        ld a,(cur_area)                 ; the area's bank again
        call area_bank
        ld (page2_bank),a
        ld (ASCII16_PAGE2),a
        ret
