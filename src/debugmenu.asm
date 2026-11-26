; ---------------------------------------------------------------------------
; Debug menu (built in with DEBUG=1, the default; make DEBUG=0 leaves it out).
; Shown at power-up and after a game over: the start stage, infinite health,
; infinite time, and a sound test (music and effects, from the sound set the
; ROM was built with). Cursor keys or joystick: up/down choose a line,
; left/right change it; SPACE or the whip (M, X, button B) plays the music or
; effect shown, or starts the game on START (or on any other line).
; Runs from RAM (src/ramcode.asm).
; ---------------------------------------------------------------------------

DBG_LINES       equ 6                   ; stage, health, time, music, effect, start
DBG_TOP         equ 6                   ; screen row of the first line

debug_menu:
        di
        call music_stop
        xor a
        ld (dbg_go),a
        ld (scroll_r26),a               ; (the line interrupt sets these)
        ld (scroll_r27),a
        ld a,1
        ld (dbg_active),a
        ld a,(dbg_stage)                ; first time: stage 1, music 0, the
        or a                            ; first effect
        jr nz,.kept
        inc a
        ld (dbg_stage),a
        call dbg_first_sfx
        ld a,DBG_LINES-1
        ld (dbg_sel),a                  ; on START: SPACE starts at once
.kept:
        ld a,(RG8SAV)                   ; no sprites while the menu is up
        or 0x02
        ld (RG8SAV),a
        ld b,a
        ld c,8
        call vdp_wreg
        ld hl,VRAM_PNT                  ; a blank screen
        ld bc,32*24
        ld a,' '
        call vram_fill
        ld b,2                          ; the font in all three bands
.font:
        push bc
        ld a,b
        add a,a
        add a,a
        add a,a
        inc a
        ld d,a                          ; DE = band * 0x800 + 0x20 * 8
        ld e,0
        push de
        ld hl,(CGTABL)
        ld bc,0x20*8
        add hl,bc
        ex de,hl
        ld bc,VRAM_PGT
        add hl,bc
        ex de,hl
        ld bc,64*8
        call vram_copy
        pop hl
        ld bc,VRAM_CT
        add hl,bc
        ld bc,64*8
        ld a,0xF1
        call vram_fill
        pop bc
        djnz .font
        ld hl,dbg_title
        ld de,VRAM_PNT+2*32+2
        call dbg_print
        ld hl,dbg_help1
        ld de,VRAM_PNT+20*32+1
        call dbg_print
        ld hl,dbg_help2
        ld de,VRAM_PNT+21*32+1
        call dbg_print
        ei
.loop:
        call wait_frame
        call sound_tick
        call read_input
        call dbg_draw
        ld a,(dbg_go)                   ; (tests)
        or a
        jr nz,.start
        ld a,(stick)                    ; one step per press
        ld hl,dbg_stick
        cp (hl)
        ld (hl),a
        jr z,.buttons
        cp 1
        jr z,.up
        cp 5
        jr z,.down
        cp 3
        jr z,.right
        cp 7
        jr z,.left
        jr .buttons
.up:
        ld a,(dbg_sel)
        or a
        jp z,.loop
        dec a
        ld (dbg_sel),a
        jp .loop
.down:
        ld a,(dbg_sel)
        cp DBG_LINES-1
        jp nc,.loop
        inc a
        ld (dbg_sel),a
        jp .loop
.right:
        ld c,1
        jr .change
.left:
        ld c,-1
.change:
        call dbg_change
        jp .loop
.buttons:
        ld a,(jump_pressed)
        ld hl,whip_pressed
        or (hl)
        jp z,.loop
        ld a,(dbg_sel)
        cp 3
        jr z,.play_music
        cp 4
        jr z,.play_sfx
        cp 1
        jr z,.toggle
        cp 2
        jr nz,.start
.toggle:
        ld c,1
        call dbg_change
        jp .loop
.play_music:
        ld a,(dbg_music)
        call music_restart
        jp .loop
.play_sfx:
        ld a,(dbg_sfx)
        call sfx_play
        jp .loop

.start:
        xor a
        ld (dbg_active),a
        ld (dbg_go),a
        call music_stop
        di
        ld a,(RG8SAV)                   ; sprites back on
        and 0xFD
        ld (RG8SAV),a
        ld b,a
        ld c,8
        call vdp_wreg
        ei
        call new_game                   ; (area 0)
        ld a,(dbg_stage)
        dec a
        ret z
        ld e,a                          ; another stage: its first area
        ld d,0
        ld hl,dbg_stage_area
        add hl,de
        ld a,(hl)
        call load_area
        call set_stage_time
        ld a,1
        ld (hud_dirty),a
        ret

; C = +1 / -1: change the chosen line
dbg_change:
        ld a,(dbg_sel)
        or a
        jr z,.stage
        cp 1
        jr z,.hp
        cp 2
        jr z,.time
        cp 3
        jr z,.music
        cp 4
        jr z,.sfx
        ret
.stage:
        ld a,(dbg_stage)
        add a,c
        ret z                           ; below 1
        cp 10
        ret nc
        ld e,a                          ; only stages this ROM has
        dec e
        ld d,0
        ld hl,dbg_stage_area
        add hl,de
        ld b,a
        ld a,(hl)
        cp AREA_COUNT
        ret nc
        ld a,b
        ld (dbg_stage),a
        ret
.hp:
        ld a,(dbg_hp)
        xor 1
        ld (dbg_hp),a
        ret
.time:
        ld a,(dbg_time)
        xor 1
        ld (dbg_time),a
        ret
.music:
        ld hl,dbg_music
        ld b,1
        jr dbg_next_sound
.sfx:
        ld hl,dbg_sfx
        ld b,0
        ; (fall through)

; HL = dbg_music / dbg_sfx, B = 1 music / 0 effects, C = +1 / -1: the next
; sound of that kind (round the list)
dbg_next_sound:
        ld e,SOUND_COUNT
.lp:
        ld a,(hl)
        add a,c
        cp 0xFF
        jr nz,.not_under
        ld a,SOUND_COUNT-1
.not_under:
        cp SOUND_COUNT
        jr c,.in
        xor a
.in:
        ld (hl),a
        push hl
        push de
        ld e,a
        ld d,0
        ld hl,snd_is_music
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        cp b
        ret z
        dec e
        jr nz,.lp
        ret

dbg_first_sfx:
        ld a,0xFF
        ld (dbg_sfx),a
        ld hl,dbg_sfx
        ld bc,0*256 + 1
        call dbg_next_sound
        ld a,0xFF
        ld (dbg_music),a
        ld hl,dbg_music
        ld bc,1*256 + 1
        jp dbg_next_sound

; the menu's lines with their values, and the cursor
dbg_draw:
        di
        ld b,0
.line:
        push bc
        ld a,b                          ; DE = VRAM_PNT + (DBG_TOP + 2*line)*32 + 1
        add a,a
        add a,DBG_TOP
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_PNT+1
        add hl,de
        call vram_set_write
        ld a,(dbg_sel)                  ; cursor
        cp b
        ld a,'>'
        jr z,.cur
        ld a,' '
.cur:
        out (VDP_DATA),a
        ld a,' '
        out (VDP_DATA),a
        ld a,b                          ; label: 16 characters
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,dbg_labels
        add hl,de
        ld b,16
.lab:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .lab
        pop bc
        push bc
        ld a,b                          ; value
        or a
        jr z,.v_stage
        cp 1
        jr z,.v_hp
        cp 2
        jr z,.v_time
        cp 3
        jr z,.v_music
        cp 4
        jr z,.v_sfx
        jr .next
.v_stage:
        ld a,(dbg_stage)
        add a,'0'
        out (VDP_DATA),a
        jr .next
.v_hp:
        ld a,(dbg_hp)
        jr .onoff
.v_time:
        ld a,(dbg_time)
.onoff:
        ld hl,dbg_off
        or a
        jr z,.str
        ld hl,dbg_on
.str:
        ld b,3
.s:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .s
        jr .next
.v_music:
        ld a,(dbg_music)
        jr .name
.v_sfx:
        ld a,(dbg_sfx)
.name:
        ld l,a                          ; snd_names + 10 * number
        ld h,0
        add hl,hl
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,de
        ld de,snd_names
        add hl,de
        ld b,10
.n:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .n
.next:
        pop bc
        inc b
        ld a,b
        cp DBG_LINES
        jp c,.line
        ei
        ret

; HL = text (0 at the end), DE = name table address
dbg_print:
        ex de,hl
        call vram_set_write
        ex de,hl
.lp:
        ld a,(hl)
        or a
        ret z
        out (VDP_DATA),a
        inc hl
        jr .lp

; every frame of the game: infinite health and time
debug_tick:
        ld a,(dbg_hp)
        or a
        jr z,.time
        ld a,(hp)
        cp HP_MAX
        jr z,.time
        ld a,HP_MAX
        ld (hp),a
        ld a,1
        ld (hud_dirty),a
.time:
        ld a,(dbg_time)
        or a
        ret z
        xor a                           ; the timer never reaches a step
        ld (time_t),a
        ret

; the first area of stages 1-9
dbg_stage_area:
        db 0, 2, 4, 5, 7, 9, 11, 13, 15

dbg_title:      db "CASTLEVANIA MSX  DEBUG MENU", 0
dbg_help1:      db "UP DOWN CHOOSE, LEFT RIGHT SET", 0
dbg_help2:      db "SPACE OR WHIP: PLAY OR START", 0
dbg_labels:
        db "START STAGE     "
        db "INFINITE HEALTH "
        db "INFINITE TIME   "
        db "MUSIC           "
        db "SOUND EFFECT    "
        db "START GAME      "
dbg_on:         db "ON "
dbg_off:        db "OFF"

        INCLUDE "sound_names.inc"
