; ---------------------------------------------------------------------------
; Sound: music and sound effects on the PSG, played from the VBLANK interrupt.
;
; The data (made at build time by tools/convert_sound.py; see sound.inc) is a
; table of sounds, each a stream of PSG register changes in the ROM's sound
; banks (a stream may run on into the next bank). One music stream and one
; effect stream play at a time; an effect takes over only the PSG channels
; it uses (its table mask) and the music carries on underneath.
;
; Stream bytes: 0x01-0x7F = a frame of changes: bits 0-5 = registers 0-5
; follow, bit 6 = a second mask follows (bits 0-4 = registers 6-10), then
; the values; 0x80-0xFC = wait 1-125 frames; 0xFD = loop; 0xFE = end.
;
; Each stream's state (IX):
;   +0 on  +1 bank  +2 pointer  +4 wait  +5 loop bank  +6 loop pointer
;   +8 channel mask (bits 0-2: A, B, C)  +9 registers 0-10
; ---------------------------------------------------------------------------

SS_ON   equ 0
SS_BANK equ 1
SS_PTR  equ 2
SS_WAIT equ 4
SS_LBANK equ 5
SS_LPTR equ 6
SS_MASK equ 8
SS_REGS equ 9
SS_SIZE equ 20

PSG_ADDR equ 0xA0
PSG_DATA equ 0xA1

; Start music A (a SND_ number; 0xFF = none). The same music again carries
; on. Keeps BC, DE, HL, IX, IY.
music_play:
        cp 0xFF
        ret z
        push hl
        ld hl,mus_id
        cp (hl)
        jr nz,.new
        ld a,(mus_state+SS_ON)
        or a
        jr nz,.done                     ; already playing
        ld a,(hl)
.new:
        ld (hl),a
        push ix
        ld ix,mus_state
        call stream_start
        pop ix
.done:
        pop hl
        ret

; Start music A from its beginning even if it is playing (jingles)
music_restart:
        push af
        ld a,0xFF
        ld (mus_id),a
        pop af
        jr music_play

music_stop:
        di
        xor a
        ld (mus_state+SS_ON),a
        ld a,0xFF
        ld (mus_id),a
        ei
        ret

; Start sound effect A (a SND_ number; 0xFF = none). Keeps BC, DE, HL, IX, IY.
sfx_play:
        cp 0xFF
        ret z
        push ix
        ld ix,sfx_state
        call stream_start
        pop ix
        ret

; IX = stream state, A = sound number: from the table (8 bytes a sound:
; bank, pointer, loop bank, loop pointer, channel mask, unused). Keeps BC,
; DE, HL.
stream_start:
        cp SOUND_COUNT
        ret nc
        push bc
        push de
        push hl
        call .start
        pop hl
        pop de
        pop bc
        ret
.start:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,snd_table
        add hl,de
        di
        ld a,(hl)
        ld (ix+SS_BANK),a
        inc hl
        ld a,(hl)
        ld (ix+SS_PTR),a
        inc hl
        ld a,(hl)
        ld (ix+SS_PTR+1),a
        inc hl
        ld a,(hl)
        ld (ix+SS_LBANK),a
        inc hl
        ld a,(hl)
        ld (ix+SS_LPTR),a
        inc hl
        ld a,(hl)
        ld (ix+SS_LPTR+1),a
        inc hl
        ld a,(hl)
        ld (ix+SS_MASK),a
        ld (ix+SS_WAIT),0
        ld (ix+SS_ON),1
        ei
        ret

; Silence everything (area load, death, pause...)
sound_init:
        di
        xor a
        ld (mus_state+SS_ON),a
        ld (sfx_state+SS_ON),a
        ld a,0xFF
        ld (mus_id),a
        ld hl,mus_state+SS_REGS+8       ; volumes 0
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        ld hl,sfx_state+SS_REGS+8
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        ld a,0xBF
        ld (mus_state+SS_REGS+7),a
        ld (sfx_state+SS_REGS+7),a
        ei
        jp psg_write

; Main loop, after the VBLANK work: one step of the sound for every frame
; since the last call (up to 4), so the music keeps its tempo when the game
; runs late
sound_tick:
        ld hl,(frame_count)
        ld de,(snd_frame)
        ld (snd_frame),hl
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.one                      ; (first call, or a long pause)
        ld a,l
        or a
        ret z
        cp SOUND_CATCH_UP+1
        jr c,.n
.one:
        ld a,1
.n:
        ld b,a
.lp:
        push bc
        call sound_frame
        pop bc
        djnz .lp
        ret

; one frame of both streams, then the PSG; the ROM bank at 0x8000 is put
; back as the game had it
sound_frame:
        ld ix,mus_state
        call stream_step
        ld ix,sfx_state
        call stream_step
        ld a,(page2_bank)
        ld (ASCII16_PAGE2),a
        ; fall through

; mix (the effect's channels over the music's) and write registers 0-10
psg_write:
        ld hl,mus_state+SS_REGS
        ld de,psg_buf
        ld bc,11
        ldir
        ld a,(mus_state+SS_ON)
        or a
        jr nz,.music
        ld hl,psg_buf+8                 ; music off: silent
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
.music:
        ld a,(sfx_state+SS_ON)
        or a
        jr z,.out
        ld a,(sfx_state+SS_MASK)
        ld c,a
        ld ix,sfx_state
        bit 0,c                         ; channel A: tone, volume
        jr z,.no_a
        ld a,(ix+SS_REGS+0)
        ld (psg_buf+0),a
        ld a,(ix+SS_REGS+1)
        ld (psg_buf+1),a
        ld a,(ix+SS_REGS+8)
        ld (psg_buf+8),a
.no_a:
        bit 1,c
        jr z,.no_b
        ld a,(ix+SS_REGS+2)
        ld (psg_buf+2),a
        ld a,(ix+SS_REGS+3)
        ld (psg_buf+3),a
        ld a,(ix+SS_REGS+9)
        ld (psg_buf+9),a
.no_b:
        bit 2,c                         ; C, and the noise period
        jr z,.no_c
        ld a,(ix+SS_REGS+4)
        ld (psg_buf+4),a
        ld a,(ix+SS_REGS+5)
        ld (psg_buf+5),a
        ld a,(ix+SS_REGS+6)
        ld (psg_buf+6),a
        ld a,(ix+SS_REGS+10)
        ld (psg_buf+10),a
.no_c:
        ld a,c                          ; mixer: the effect's tone/noise bits
        and 7                           ; for its channels
        ld b,a
        add a,a
        add a,a
        add a,a
        or b
        ld b,a                          ; B = bits the effect owns
        ld a,(ix+SS_REGS+7)
        and b
        ld c,a
        ld a,b
        cpl
        ld hl,psg_buf+7
        and (hl)
        or c
        ld (hl),a
.out:
        ld a,(psg_buf+7)                ; I/O port A in, B out
        and 0x3F
        or 0x80
        ld (psg_buf+7),a
        ld hl,psg_buf
        ld c,PSG_DATA
        ld b,11
        xor a
.o:
        out (PSG_ADDR),a
        inc a
        outi
        jr nz,.o
        ret

; one frame of the stream at IX
stream_step:
        ld a,(ix+SS_ON)
        or a
        ret z
        ld a,(ix+SS_WAIT)
        or a
        jr z,.read
        dec (ix+SS_WAIT)
        ret
.read:
        ld a,(ix+SS_BANK)
        ld (ASCII16_PAGE2),a
        ld l,(ix+SS_PTR)
        ld h,(ix+SS_PTR+1)
.next:
        call .getb
        cp 0x80
        jr c,.frame
        cp 0xFD
        jr c,.wait
        jr nz,.end
        ld a,(ix+SS_LBANK)              ; loop
        ld (ix+SS_BANK),a
        ld (ASCII16_PAGE2),a
        ld l,(ix+SS_LPTR)
        ld h,(ix+SS_LPTR+1)
        jr .next
.end:
        ld (ix+SS_ON),0
        ld (ix+SS_REGS+8),0
        ld (ix+SS_REGS+9),0
        ld (ix+SS_REGS+10),0
        ret
.wait:
        sub 0x80                        ; this frame is the first of them
        ld (ix+SS_WAIT),a
        jr .save
.frame:
        ld c,a                          ; C = registers 0-5 (+ bit 6)
        ld b,0
        bit 6,a
        jr z,.one_mask
        call .getb
        ld b,a                          ; B = registers 6-10
.one_mask:
        push ix
        pop iy
        ld de,SS_REGS
        add iy,de
        ld e,6
.l1:
        srl c
        jr nc,.s1
        call .getb
        ld (iy+0),a
.s1:
        inc iy
        dec e
        jr nz,.l1
        ld e,5
.l2:
        srl b
        jr nc,.s2
        call .getb
        ld (iy+0),a
.s2:
        inc iy
        dec e
        jr nz,.l2
.save:
        ld (ix+SS_PTR),l
        ld (ix+SS_PTR+1),h
        ret
.getb:                                  ; A = next byte (on into the next bank)
        ld a,(hl)
        inc hl
        bit 6,h
        ret z                           ; still below 0xC000
        ld h,0x80
        inc (ix+SS_BANK)
        push af
        ld a,(ix+SS_BANK)
        ld (ASCII16_PAGE2),a
        pop af
        ret
