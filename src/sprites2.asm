; Simon's sprite streaming, run from RAM (see src/vdp.asm: write_player_sprites)

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

; ---------------------------------------------------------------------------
; VRAM write primitives (in RAM: bank 0 is full). The VBLANK work runs with
; interrupts on, so that the line interrupt splitting the HUD's scroll from
; the playfield's comes on time however long the VDP takes (it did not on a
; Goa'uld MSX2+). An interrupt between two data writes is harmless (it moves
; no VRAM address); only the bytes of an address or register write must not
; be split, so these turn interrupts off for them (and on again: no code
; that writes VRAM needs them off; every page 2 bank switch sets page2_bank,
; which the sound interrupt maps back).
; ---------------------------------------------------------------------------

; Set the VRAM write address anywhere in 128 KB.
; A = address bits 16-14 (R#14), HL = address bits 13-0. Interrupts on after.
vram_set_write_far:
        di
        out (VDP_CTRL),a
        ld a,0x80|14
        out (VDP_CTRL),a
        jr vram_set_write.addr

; Set VRAM write address.  HL = address. Interrupts on after.
vram_set_write:
        di
.addr:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        and 0x3F
        or 0x40
        out (VDP_CTRL),a
        ei
        ret

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
