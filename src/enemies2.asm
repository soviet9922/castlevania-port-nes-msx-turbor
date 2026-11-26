; ---------------------------------------------------------------------------
; Enemies of blocks 2 and 3 and Medusa. This code runs from RAM: it is stored
; in Simon's ROM bank (src/ramcode.asm) and copied to RAMCODE at start-up,
; because bank 0 (the code page) is full. It calls the engine in bank 0 and
; reads the current area's bank at 0x8000 like the rest of the object code.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Block 2's enemies, from the NES code
;
; Medusa heads (spawner bank 6 $8435, object $06 ai_medusa_head $EF9E):
;  - while a spawner is near, its timer ticks every other frame; the first
;    head comes 18 frames after it gets near, then one every 128 frames;
;  - a head waits (the timer stays at 0) while 3 are about or Simon is on
;    the stairs, and comes the first frame that clears;
;  - it starts at the screen edge Simon faces (x $F8 / $08) 33 px above his
;    middle, and flies at him 1 1/4 px a frame on a spring around his middle
;    (wave_y: vy -= (y - centre)/256 a frame): mhead_wave is that path,
;    worked out from the NES's arithmetic (34 px up and down, ~100 frames);
;  - one whip hit, 300 points; touching Simon hurts him and it flies on;
;    it is gone when its middle leaves the screen.
;   +4 frames flown   +5 direction   +9 centre y (port top)   +10 x fraction
; ---------------------------------------------------------------------------
medusa_spawner:                         ; HL = its state, DE = its timer
        ld a,(hl)                       ; just on the screen: 9 ticks
        cp 1
        jr nz,.timer
        ld a,9
        ld (de),a
        ret
.timer:
        ld a,(de)
        or a
        ret nz
        push de
        ld ix,obj_table                 ; how many heads are about?
        ld de,OBJ_SIZE
        ld bc,OBJ_MAX*256
.count:
        ld a,(ix+0)
        cp OBJ_MHEAD
        jr nz,.not_head
        inc c
.not_head:
        add ix,de
        djnz .count
        pop de
        ld a,c
        cp MEDUSA_MAX
        ret nc
        ld a,(stair_state)              ; not while Simon is on the stairs
        cp 2
        ret z
        push de
        call obj_free_slot
        pop de
        ret c
        ld a,MEDUSA_EVERY/2
        ld (de),a
        ld hl,(cam_x)
        ld a,(facing)
        or a
        jr nz,.left_edge
        ld de,240                       ; facing right: from the right edge
        add hl,de
        ld (ix+5),-1
        jr .place
.left_edge:
        ld (ix+5),1
.place:
        ld (ix+1),l
        ld (ix+2),h
        ld a,(py)                       ; wave centre: Simon's middle
        add a,8
        ld (ix+9),a
        ld (ix+0),OBJ_MHEAD
        ld (ix+4),0
        ld (ix+7),KIND_BAT              ; 16x16 box
        ld (ix+8),0xFF
        ld (ix+10),0
        ld (ix+11),1                    ; (made after this frame's update on
        jr mhead_place                  ; the NES: it moves from the next)

mhead_update:
        ld a,(ix+11)
        or a
        ld (ix+11),0
        jp nz,mhead_checks
        ld a,(freeze_t)                 ; the stopwatch holds it
        or a
        jp nz,mhead_checks
        ld a,(ix+4)
        cp MHEAD_WAVE_LEN-1
        jr nc,.x
        inc (ix+4)
.x:
        ld a,(ix+10)                    ; x: 1 + 1/4 px per frame
        add a,0x40
        ld (ix+10),a
        ld a,1
        adc a,0
        bit 7,(ix+5)
        jr z,.dx
        neg
.dx:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
mhead_place:
        ld e,(ix+4)
        ld d,0
        ld hl,mhead_wave
        add hl,de
        ld a,(ix+9)
        add a,(hl)
        ld (ix+3),a
        ld a,(ix+4)                     ; frame: 9 frames each
        ld c,0
.div9:
        sub 9
        jr c,.d9
        inc c
        jr .div9
.d9:
        ld a,c
        and 1
        bit 7,(ix+5)
        jr nz,.left
        add a,2
.left:
        add a,OBJF_MHEAD
        ld (ix+6),a
mhead_checks:
        ld l,(ix+1)                     ; its middle left the screen: gone
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        bit 7,h
        jr nz,.gone
        ld de,241
        sbc hl,de
        jp c,bat_update.hits
.gone:
        ld (ix+0),OBJ_NONE
        ret

; its path: y - centre, frame by frame (the NES's spring, from 33 px above)
mhead_wave:
        db -33, -33, -33, -33, -32, -32, -31, -30, -29, -28, -27, -25, -24, -22, -21, -19, -17, -15, -13, -12
        db -10, -8, -5, -3, -1, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 20, 22, 23, 25, 26
        db 27, 29, 30, 31, 31, 32, 33, 33, 33, 33, 34, 33, 33, 33, 32, 32, 31, 30, 29, 28
        db 27, 26, 24, 23, 21, 19, 18, 16, 14, 12, 10, 8, 6, 4, 2, 0, -2, -4, -6, -9
        db -11, -12, -14, -16, -18, -20, -21, -23, -25, -26, -27, -28, -29, -30, -31, -32, -33, -33, -33, -34
        db -34, -34, -33, -33, -33, -32, -31, -31, -30, -29, -27, -26, -25, -23, -22, -20, -18, -17, -15, -13
        db -11, -9, -7, -5, -3, 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 19, 21, 23, 24, 26
        db 27, 28, 29, 30, 31, 32, 33, 33, 34, 34, 34, 34, 34, 33, 33, 32, 32, 31, 30, 29
        db 28, 27, 25, 24, 22, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1, -1, -3, -5, -7
        db -10, -12, -14, -15, -17, -19, -21, -22, -24, -25, -27, -28, -29, -30, -31, -32, -33, -33, -33, -34
MHEAD_WAVE_LEN  equ $-mhead_wave

; ---------------------------------------------------------------------------
; Hanging bat (object $07, bank 5 $841B): it hangs until Simon's middle is
; 1..56 px below its middle and -95..+96 px across from it; then (without
; moving that frame) it flies at him 1 1/2 px a frame across, dropping with
; a speed of 1 1/2 px that slows by 9/256 px a frame (31 px over 42 frames,
; hbat_drop), then flies level. Touching Simon hurts him and kills it (200
; points); once awake it doesn't come back, one that scrolls off hanging does.
; +9 = state (0 hanging, 1 flying), +10 = x fraction, +11 = drop step.
; ---------------------------------------------------------------------------
hbat_update:
        ld a,(ix+9)
        or a
        jr nz,.flying
        ld a,(freeze_t)
        or a
        jr nz,.hang
        ld a,(py+1)                     ; Simon's middle 1..56 px below its
        or a                            ; middle: py - y in -7..48
        jr nz,.hang
        ld a,(py)
        sub (ix+3)
        add a,7
        cp 56
        jr nc,.hang
        ld hl,(px)                      ; across: px - x in -95..+96
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld de,95
        add hl,de
        ld a,h
        or a
        jr nz,.hang
        ld a,l
        cp 95+96+1
        jr nc,.hang
        cp 95                           ; facing Simon
        ld (ix+5),1
        jr nc,.right
        ld (ix+5),-1
.right:
        ld (ix+9),1                     ; awake: it never comes back
        ld (ix+4),0
        ld (ix+11),0
        ld a,(ix+8)
        cp 0xFF
        jr z,.hang
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
.hang:
        ld a,(ix+9)
        or a
        jr nz,.woke
        ld (ix+6),OBJF_HBAT_HANG
.woke:
        jp bat_update.checks
.flying:
        ld a,(freeze_t)
        or a
        jp nz,bat_update.checks
        inc (ix+4)
        ld a,(ix+10)                    ; x: 1 + 1/2 px per frame
        add a,0x80
        ld (ix+10),a
        ld a,1
        adc a,0
        bit 7,(ix+5)
        jr z,.dx
        neg
.dx:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+11)                    ; y: the recorded drop
        cp hbat_drop_end-hbat_drop
        jr nc,.level
        inc (ix+11)
        ld e,a
        ld d,0
        ld hl,hbat_drop
        add hl,de
        ld a,(ix+3)
        add a,(hl)
        ld (ix+3),a
.level:
        call bat_frame                  ; wings as the stage 2 bat's
        sub OBJF_BAT-OBJF_HBAT
        ld (ix+6),a
        jp bat_update.checks

hbat_drop:                              ; (the NES's vy 1 1/2 px, -9/256 a frame)
        db 1, 1, 2, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1
        db 0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1
        db 0, 0, 0, 1, 0, 0, 0, 0
hbat_drop_end:

; ---------------------------------------------------------------------------
; Spear knight (object $08), from the NES code (bank 5 $847E):
;  - it walks 1/2 px a frame (an 8-bit fraction) and starts facing Simon;
;  - patrol: it turns round every 192 frames (the first time after 256);
;  - when Simon is level with it (his y - its y in -3..+4) it faces him at
;    once and again every 192 frames while he stays level; each change
;    between the two restarts the 192 frames and skips that frame's step;
;  - after each step: no floor under its middle -> it falls (gravity 1/8 px
;    a frame, landing on a 16-px row); a wall 16 px ahead of its middle at
;    its waist, or no floor 4 px ahead -> it turns (from the next step);
;  - whip hits add up (hit_damage: 24 leather, 32 chain/morning star) and
;    kill it at 64; a hit that doesn't freezes it 16 frames (no movement,
;    no animation; it can still be hit and still hurts).
;   +4 x fraction (falling: speed, 1/8 px)  +5 direction (+1/-1)
;   +9 damage taken  +10 frames to the next turn (falling: y fraction, 1/8)
;   +11 state (bits 7-6: 0 patrol, 1 level, 2 falling) | frames frozen
; ---------------------------------------------------------------------------
KN_LEVEL        equ 0x40
KN_FALL         equ 0x80

knight_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+11)
        and 0x1F
        jr z,.ai
        dec (ix+11)                     ; frozen by a hit
        jp .hits
.ai:
        ld a,(ix+11)
        cp KN_FALL
        jp z,.falling
        ld b,a                          ; B = state (0 or KN_LEVEL)
        call knight_level
        ld a,b
        jr c,.is_level
        or a
        jr z,.patrol
        ld (ix+11),0                    ; no longer level: patrol
        ld (ix+10),KNIGHT_TURN
        jp .frame
.patrol:
        dec (ix+10)
        jr nz,.step
        ld (ix+10),KNIGHT_TURN
        ld a,(ix+5)                     ; turn round
        neg
        ld (ix+5),a
        jr .step
.is_level:
        or a
        jr nz,.level
        ld (ix+11),KN_LEVEL             ; Simon comes level: face him
        ld (ix+10),KNIGHT_TURN
        call knight_face
        jp .frame
.level:
        dec (ix+10)
        jr nz,.step
        ld (ix+10),KNIGHT_TURN
        call knight_face
.step:
        ld a,(ix+4)                     ; 1/2 px a frame
        add a,0x80
        ld (ix+4),a
        jr nc,.probe
        ld a,(ix+5)
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
.probe:
        ld de,8                         ; floor under its middle?
        ld a,32
        call knight_probe
        jr c,.floor
        ld (ix+11),KN_FALL
        xor a
        ld (ix+4),a
        ld (ix+10),a
        jr .frame
.floor:
        ld de,8+16                      ; a wall 16 px ahead at its waist?
        bit 7,(ix+5)
        jr z,.wall
        ld de,8-16
.wall:
        ld a,16
        call knight_probe
        jr c,.turn
        ld de,8+4                       ; floor 4 px ahead?
        bit 7,(ix+5)
        jr z,.ahead
        ld de,8-4
.ahead:
        ld a,36
        call knight_probe
        jr c,.frame
.turn:
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jr .frame
.falling:
        ld a,(ix+4)                     ; speed += 1/8 px
        inc a
        ld (ix+4),a
        add a,(ix+10)
        ld c,a
        and 7
        ld (ix+10),a
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        add a,(ix+3)
        jr c,.fell_out
        cp 0xE0
        jr nc,.fell_out
        ld (ix+3),a
        ld de,8
        ld a,32
        call knight_probe
        jr nc,.frame
        ld a,(ix+3)                     ; landed: on a 16-px row
        add a,16
        and 0xF0
        sub 16
        ld (ix+3),a
        ld (ix+11),0
        ld (ix+4),0
        ld (ix+10),KNIGHT_TURN
.frame:
        call knight_frame
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,(ix+11)                    ; frozen: only the whip hits again
        and 0x1F
        jr z,.hit
        ld a,(hit_src)
        or a
        jr nz,.touch
.hit:
        ld a,SND_HIT
        call sfx_play
        call hit_damage
        add a,(ix+9)
        cp 64
        jr nc,.dead
        ld (ix+9),a
        ld a,(ix+11)
        and 0xC0
        or 16
        ld (ix+11),a
        jr .touch
.dead:
        call mark_dead                  ; it stays dead
        ld a,SCORE_KNIGHT
        ld c,1                          ; (a big heart)
        jp enemy_killed
.fell_out:
        ld (ix+0),OBJ_NONE
        ret
.touch:
        jp zombie_update.touch

; Carry if the 16x32 enemy at IX can't step on: no floor 4 px ahead of its
; middle, or a wall 4 px ahead at its waist (the skeleton)
knight_blocked:
        ld de,8+4
        bit 7,(ix+5)
        jr z,.ahead
        ld de,8-4
.ahead:
        push de
        ld a,32
        call knight_probe
        pop de
        ccf
        ret c
        ld a,16
        jr knight_probe

; Carry if the tile at the knight's x + DE, y + A is solid
knight_probe:
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        add a,(ix+3)
        ld e,a
        ld d,0
        jp solid_at

; Carry if Simon is level with the knight at IX (py - y in -3..+4)
knight_level:
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)
        sub (ix+3)
        add a,3
        cp 8
        ret

; Face Simon (the middles: Simon's px+8, the knight's x+8)
knight_face:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld (ix+5),1
        ret p
        ld (ix+5),-1
        ret

; the knight's walk: the NES's frames $9A, $9B, $9C, $9B (17 frames each,
; about 8 px walked): a picture every 8 px
knight_frame:
        ld a,(ix+1)
        rrca
        rrca
        rrca
        and 3
        cp 3
        jr nz,.step
        ld a,1
.step:
        bit 7,(ix+5)
        jr nz,.left
        add a,3
.left:
        add a,OBJF_KNIGHT
        ld (ix+6),a
        ret

; the skeleton's two pictures (NES $B1, $B2, 17 frames each: every 16 here)
skel_frame:
        ld a,(frame_count)
        rrca
        rrca
        rrca
        rrca
        and 1
        bit 7,(ix+5)
        jr nz,.left
        add a,2
.left:
        add a,OBJF_SKEL
        ld (ix+6),a
        ret

; ---------------------------------------------------------------------------
; Medusa (stage 6 boss), from the NES code (bank 5 $82ED, bank 6 $8425/$9967):
;  - asleep she is the statue in the map. When the screen reaches her room
;    (its left end) the camera locks, the boss music starts and every other
;    enemy bursts; 180 frames later the statue's 4x4 tiles go blank and she
;    starts (hittable and harmful only from then);
;  - rise: while her NES y is $A8 or more (port top 103) she rises 1/2 px a
;    frame; then a flight starts: a snake drops, she faces Simon, and flies
;    7/8 px a frame across for 15, 127, 63 or 159 frames (the table taken in
;    order, from a start picked at the wake), bobbing on a spring around her
;    y + 4 (wave_y, starting 1/2 px a frame downward). She turns when her
;    middle passes screen x 16 (going left) or 240 (going right), and after
;    hurting Simon. Then she hovers still for 60 frames and rises again;
;  - a hit takes half the weapon's damage (3 leather, 4 chain/morning star)
;    from the HUD's bar and freezes her 8 frames; at 0 she burns and leaves
;    the orb (boss_update.dead/.burning).
;   +4 picture counter  +5 direction  +9 state (0 asleep/waking, 1 rise,
;   2 flying, 3 hovering, 4 burning)  +10 the wave's centre  +11 x fraction
; ---------------------------------------------------------------------------
medusa_update:
        ld a,(ix+9)
        cp 4
        jp z,.burning
        or a
        jp z,.asleep
        ld a,(med_frz)                  ; frozen by a hit: no AI, no picture
        or a
        jr z,.ai
        dec a
        ld (med_frz),a
        jp medusa_hits
.ai:
        inc (ix+4)
        ld a,(ix+4)                     ; her two pictures, 9 frames each
        ld c,0
.div9:
        sub 9
        jr c,.d9
        inc c
        jr .div9
.d9:
        ld a,c
        and 1
        add a,OBJF_MEDUSA
        ld (ix+6),a
        ld a,(ix+9)
        cp 2
        jp z,.flying
        jp nc,.hover
        ld hl,(med_yf)                  ; rise: y -= vy (1/2 px)
        ld a,l
        ld de,(med_vy)
        sub e
        ld (med_yf),a
        ld a,(ix+3)
        sbc a,d
        ld (ix+3),a
        cp MEDUSA_TOP
        jp nc,medusa_hits
        call snake_drop                 ; a flight: a snake, face Simon
        ld a,(ix+3)
        add a,4
        ld (ix+10),a
        call boss_simon_dx
        ld (ix+5),1
        bit 7,h
        jr z,.face
        ld (ix+5),-1
.face:
        ld a,(med_idx)
        inc a
        ld (med_idx),a
        and 3
        ld e,a
        ld d,0
        ld hl,medusa_flights
        add hl,de
        ld a,(hl)
        ld (med_t),a
        ld (ix+9),2
        jp medusa_hits
.flying:
        ld hl,med_t
        dec (hl)
        jr nz,.fly
        ld (hl),MEDUSA_PAUSE
        ld (ix+9),3
        jp medusa_hits
.fly:
        ld a,(ix+3)                     ; wave_y: vy -= y - centre (1/256 px)
        sub (ix+10)
        ld c,a
        sbc a,a
        ld b,a
        ld hl,(med_vy)
        or a
        sbc hl,bc
        ld (med_vy),hl
        ccf                             ; (the NES's carry: no borrow)
        ld a,(med_yf)                   ; y += vy
        adc a,l
        ld (med_yf),a
        ld a,(ix+3)
        adc a,h
        ld (ix+3),a
        ld a,(ix+11)                    ; x: 7/8 px a frame
        add a,0xE0
        ld (ix+11),a
        jr nc,.edges
        ld a,(ix+5)
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
.edges:
        ld l,(ix+1)                     ; HL = her middle on the screen
        ld h,(ix+2)
        ld de,24
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        bit 7,(ix+5)
        jr z,.going_right
        bit 7,h                         ; going left: turn below x 16
        jr nz,.turn
        ld a,h
        or a
        jp nz,medusa_hits
        ld a,l
        cp 16
        jp nc,medusa_hits
        jr .turn
.going_right:
        bit 7,h                         ; going right: turn from x 240
        jp nz,medusa_hits
        ld a,h
        or a
        jr nz,.turn
        ld a,l
        cp 240
        jp c,medusa_hits
.turn:
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jp medusa_hits
.hover:
        ld hl,med_t
        dec (hl)
        jp nz,medusa_hits
        ld hl,0x0080                    ; then rise again
        ld (med_vy),hl
        ld (ix+9),1
        jp medusa_hits

.burning:
        inc (ix+4)
        jp boss_update.burning

.asleep:
        ld a,(med_wake)
        or a
        jr nz,.waking
        ld hl,(cam_x)                   ; the screen reached her room (the
        ld de,(area_hdr+AH_MINCAM)      ; area's left end)
        or a
        sbc hl,de
        ret nz
        ld a,SND_BOSS
        call music_restart
        ld hl,(cam_x)                   ; the screen locks
        ld (cam_min),hl
        ld (area_hdr+AH_MAXCAM),hl
        ld a,1
        ld (cam_lock),a
        call enemies_burst              ; every other enemy bursts
        ld a,MEDUSA_WAKE_T
        ld (med_wake),a
        ret
.waking:
        dec a
        ld (med_wake),a
        ret nz
        ld (med_wake),a                 ; (stays 0: awake from now)
        ld l,(ix+1)                     ; the statue's 4 x 4 tiles from box
        ld h,(ix+2)                     ; x + 8, y + 1
        ld de,8
        add hl,de
        call hl_shr3
        ld (med_col),hl
        ld a,(ix+3)
        inc a
        rrca
        rrca
        rrca
        and 31
        ld (med_row),a
        ld a,1
        ld (med_erase),a
        ld a,(frame_count)
        and 3
        ld (med_idx),a
        ld hl,0x0080
        ld (med_vy),hl
        xor a
        ld (med_yf),a
        ld (med_frz),a
        ld (ix+11),a
        ld (ix+4),a
        ld (ix+9),1
        ld (ix+7),KIND_MEDUSA           ; her 28x28 box
        ret

; flight lengths + 1 (NES 5:$8378)
medusa_flights:
        db 16, 128, 64, 160

; Medusa's hits (none while asleep) and touch
medusa_hits:
        call weapon_hits
        jr nc,.touch
        call hit_damage                 ; half the weapon's damage
        rrca
        rrca
        rrca
        and 31
        ld b,a
        ld a,1
        ld (hud_dirty),a
        ld a,(boss_hp)
        sub b
        jp z,boss_update.dead
        jp c,boss_update.dead
        ld (boss_hp),a
        ld a,MEDUSA_FREEZE
        ld (med_frz),a
        ret
.touch:                                 ; |dx| < 18, |dy| < 26 between middles
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        call boss_simon_dx
        ld de,17
        add hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 35
        ret nc
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)
        sub (ix+3)
        add a,25
        cp 51
        ret nc
        call boss_simon_dx
        ld b,1
        bit 7,h
        jr z,.hurt
        ld b,-1
.hurt:
        call simon_hurt
        ld a,(ix+5)                     ; she turns round
        neg
        ld (ix+5),a
        ret

; every enemy but Medusa bursts (her spawner, NES $F47C)
enemies_burst:
        push ix
        ld ix,obj_table
        ld b,OBJ_MAX
.lp:
        ld a,(ix+0)
        cp OBJ_ZOMBIE
        jr c,.next
        cp OBJ_BOSS
        jr c,.burst
        cp OBJ_KNIGHT
        jr c,.next
        cp OBJ_MEDUSA
        jr z,.next
        cp OBJ_DRAGON+1
        jr nc,.next
        cp OBJ_DRAGON
        jr nz,.burst
        push bc
        call dragon_parts_clear         ; (and its parts)
        pop bc
.burst:
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
.next:
        ld de,OBJ_SIZE
        add ix,de
        djnz .lp
        pop ix
        ret

; a snake drops from Medusa (IX), at most SNAKE_MAX about
snake_drop:
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld b,(ix+3)
        push hl
        push bc
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld bc,OBJ_MAX*256
.count:
        ld a,(ix+0)
        cp OBJ_SNAKE
        jr nz,.not_snake
        inc c
.not_snake:
        add ix,de
        djnz .count
        ld a,c
        pop bc
        pop hl
        cp SNAKE_MAX
        jr nc,.done
        call obj_free_slot
        jr c,.done
        ld (ix+1),l
        ld (ix+2),h
        ld a,b
        add a,8
        ld (ix+3),a
        ld (ix+0),OBJ_SNAKE
        ld (ix+4),0
        ld (ix+5),-1
        ld (ix+6),OBJF_SNAKE
        ld (ix+7),KIND_BAT              ; 16x16 box
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),0
        ld (ix+11),0
.done:
        pop ix
        ret

; ---------------------------------------------------------------------------
; Snake (Medusa's, bank 5 $83B1): it faces Simon, falls (gravity 1/8 px a
; frame) to a floor, then slides along it 1 1/2 px a frame, 23 frames on and
; 2 still, again and again; walking off a floor it faces Simon and falls
; again. One whip hit (100 points); touching Simon hurts him, it goes on.
;   +4 timer  +9 state (0 face, 1 falling, 2 sliding, 3 still)
;   +10 fall speed (1/8 px) / x fraction  +11 y fraction (1/8 px)
; ---------------------------------------------------------------------------
snake_update:
        ld a,(freeze_t)
        or a
        jp nz,.frame
        ld a,(ix+9)
        or a
        jr nz,.not_face
        call knight_face                ; face Simon, then fall
        ld (ix+10),0
        ld (ix+9),1
        jp .frame
.not_face:
        dec a
        jr nz,.not_falling
        ld a,(ix+10)                    ; falling
        inc a
        ld (ix+10),a
        add a,(ix+11)
        ld c,a
        and 7
        ld (ix+11),a
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        add a,(ix+3)
        jp c,.gone
        cp MT_ROWS*16
        jp nc,.gone
        ld (ix+3),a
        call snake_ground
        jr nc,.frame
        ld a,(ix+3)                     ; on the floor
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+10),0
        jr .slide_on
.not_falling:
        dec a
        jr nz,.still
        dec (ix+4)                      ; sliding
        jr nz,.slide
        ld (ix+4),1
        ld (ix+9),3
        jr .frame
.slide:
        ld a,(ix+10)                    ; 1 + 1/2 px per frame
        add a,0x80
        ld (ix+10),a
        ld a,1
        adc a,0
        bit 7,(ix+5)
        jr z,.dx
        neg
.dx:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        call snake_ground
        jr c,.frame
        ld (ix+9),0                     ; off the floor: fall again
        jr .frame
.still:
        dec (ix+4)
        jr nz,.frame
.slide_on:
        ld (ix+4),24
        ld (ix+9),2
.frame:
        ld a,OBJF_SNAKE
        bit 7,(ix+5)
        jr nz,.left
        inc a
.left:
        ld (ix+6),a
        jp bat_update.checks
.gone:
        ld (ix+0),OBJ_NONE
        ret

; Carry if there is floor under the snake at IX (its middle, feet at y+16)
snake_ground:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        jp solid_at

; VBLANK: Medusa woke: her statue's 4 x 4 tiles go blank
medusa_vram:
        ld a,(med_erase)
        or a
        ret z
        xor a
        ld (med_erase),a
        ld a,(med_row)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_PNT+HUD_ROWS*32
        add hl,de
        ld a,(med_col)
        and 31
        ld e,a
        ld d,0
        add hl,de
        ld c,4
.row:
        push hl
        call vram_set_write
        ld a,(area_hdr+AH_BLANK)
        ld b,4
.t:
        out (VDP_DATA),a
        djnz .t
        pop hl
        ld de,32
        add hl,de
        dec c
        jr nz,.row
        ret

; ---------------------------------------------------------------------------
; Block 3's enemies (recorded on the NES in stages 7-9). All are placed in the
; candle list. 16x16: fleaman, raven, ghost; 16x32: skeleton, bone pillar.
;   fleaman  waits until Simon is within WAKE_DX px, then hops at him (about
;            44 px high, 1 px per frame across), FLEA_REST frames between hops
;   raven    perches until Simon is near, swoops down to his head's height,
;            hovers RAVEN_HOVER frames, then chases him across, speeding up
;   ghost    appears when Simon is near and floats at him, 3 px every 4
;            frames on both axes; GHOST_HP hits
;   skeleton paces and turns to face Simon now and then (as the knight), and
;            throws a bone every SKEL_THROW frames: up and towards him, under
;            gravity (the NES's also jumps about: left out)
;   pillar   stands; every PILLAR_EVERY frames two fireballs, 40 frames apart,
;            2 px per frame at Simon's side; PILLAR_HP hits
; Common: +4 timer, +5 direction, +9 state, +10/+11 speeds or counters.
; ---------------------------------------------------------------------------
; IX = new object, A = kind (spawn_candle)
block3_spawn:
        cp KIND_FRANK
        jp z,frank_spawn
        cp KIND_RSKEL
        jp z,rskel_spawn
        cp KIND_DRAGON
        jp z,dragon_spawn
        sub KIND_FLEA
        add a,OBJ_FLEA
        cp OBJ_BONE                     ; (KIND_PILLAR.. -> OBJ_PILLAR..)
        jr c,.type
        inc a
.type:
        ld (ix+0),a
        push af
        call obj_hits_of                ; no hits taken yet
        ld (hl),0
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,(ix+5)                     ; (a ghost: 1 = the right edge strip)
        and 1
        ld (ix+10),a
        pop af
        ld (ix+5),-1
        cp OBJ_MUMMY
        jp z,mummy_spawn
        ld (ix+7),KIND_BAT              ; 16x16 box
        cp OBJ_SKEL
        jr z,.tall
        cp OBJ_PILLAR
        jr nz,.frame
.tall:
        ld (ix+7),KIND_BRAZIER          ; 16x32 box
.frame:
        jp block3_frame

block3_update:
        ld a,(ix+0)                     ; block 4's
        cp OBJ_EAGLE
        jp z,eagle_update
        cp OBJ_RSKEL
        jp z,rskel_update
        cp OBJ_DRAGON
        jp z,dragon_update
        cp OBJ_FRANK
        jp z,frank_update
        cp OBJ_IGOR
        jp z,igor_update                ; the mummies and their bandages
        cp OBJ_MUMMY
        jp z,mummy_update
        cp OBJ_BANDAGE
        jp z,bandage_update
        ld a,(ix+0)
        cp OBJ_FLEA
        jp z,flea_update
        cp OBJ_SKEL
        jp z,skel_update
        cp OBJ_BONE
        jp z,bone_update
        cp OBJ_PILLAR
        jp z,pillar_update
        cp OBJ_RAVEN
        jp z,raven_update
        jp ghost_update

; Z if Simon is within WAKE_DX px across (and turns the object at IX to him)
wake_near:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de                       ; Simon - object (both 16 wide)
        ld (ix+5),1
        bit 7,h
        jr z,.pos
        ld (ix+5),-1
        ld a,l
        neg
        ld l,a
        ld a,h
        cpl
        ld h,a
.pos:
        ld a,h
        or a
        ret nz
        ld a,l
        cp WAKE_DX
        jr nc,.far
        xor a
        ret
.far:
        or 1
        ret

; Mark a placed enemy at IX dead for good (it doesn't come back)
mark_dead:
        ld a,(ix+8)
        cp 0xFF
        ret z
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
        ret

; x += direction * (1 px, + A/256 px fraction kept in +11)
step_x_frac:
        add a,(ix+11)
        ld (ix+11),a
        ld a,1
        adc a,0
        bit 7,(ix+5)
        jr z,.dx
        neg
.dx:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ret

; vy (+10, 1/16 px) += gravity A; y += vy/16 (fraction in +11). Carry if it
; fell out of the playfield
fall_step:
        add a,(ix+10)
        ld (ix+10),a
        ld c,a
        ld a,(ix+11)
        and 15
        add a,c
        ld c,a
        sra a
        sra a
        sra a
        sra a
        add a,(ix+3)
        ld (ix+3),a
        ld b,a
        ld a,c
        and 15
        ld (ix+11),a
        ld a,b                          ; out below: MT_ROWS*16 .. 0xBF (0xC0
        cp MT_ROWS*16                   ; and up: up to 64 px above the top)
        ccf
        ret nc
        cp 0xC0
        ret

; --- fleaman (NES $F58D, ai_fleaman $EFC4) ---
; It appears when its place is on the screen, sits 60 frames, drops straight
; down to the floor (gravity 1/8 px), crouches 8 frames and hops at Simon:
; a high hop (3 1/2 px up, 1 px across) when he is within 64 px and they face
; each other, else a long low one (1 px up, 2 1/4 px across); it lands on any
; floor (checked every frame in the air), crouches 8 frames, hops again. It
; turns to Simon before a hop unless he is blinking after a hit. One hit (500).
;   +4 timer  +9 state (0 wait, 1 drop, 2 crouch, 3 high hop, 4 long hop)
;   +10 vy (1/16 px, + down)  +11 its fraction
flea_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+9)
        cp 5
        jp z,.ride
        or a
        jr nz,.s1
        call b3_offscreen               ; it starts when it is on the screen
        ret c
        inc (ix+4)
        ld a,(ix+4)
        cp 60
        jp c,.hits
        ld (ix+9),1
        ld (ix+10),0
        ld (ix+11),0
        jp .hits
.s1:
        cp 1
        jr nz,.s2
        ld a,FLEA_GRAVITY
        call fall_step
        jp c,b3_gone_dead
        call snake_ground
        jp nc,.cull
.land:
        ld a,(ix+3)
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+9),2
        ld (ix+4),0
        jp .cull
.s2:
        cp 2
        jr nz,.air
        inc (ix+4)
        ld a,(ix+4)
        cp FLEA_REST
        jp c,.cull
        ld a,(invuln_t)                 ; a hop: towards Simon (not while he
        or a                            ; blinks)
        call z,knight_face
        ld (ix+11),0
        ld (ix+4),0
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.long
        ld a,l
        cp 64
        jr nc,.long
        ld c,0                          ; facing each other?
        bit 7,(ix+5)
        jr z,.fr
        inc c
.fr:
        ld a,(facing)
        cp c
        jr z,.long
        ld (ix+10),FLEA_HIGH
        ld (ix+9),3
        jp .cull
.long:
        ld (ix+10),FLEA_LONG
        ld (ix+9),4
        jp .cull
.air:
        ld c,1                          ; high hop: 1 px across
        cp 3
        jr z,.dx
        inc (ix+4)                      ; long hop: 2 1/4 px
        ld c,2
        ld a,(ix+4)
        and 3
        jr nz,.dx
        inc c
.dx:
        ld a,c
        bit 7,(ix+5)
        jr z,.dxr
        neg
.dxr:
        call move_dir_a
        ld a,FLEA_GRAVITY
        call fall_step
        jp c,b3_gone_dead
        call snake_ground
        jp c,.land
.cull:
        call b3_offscreen
        jp c,b3_gone_dead
        jr .hits
.ride:                                  ; 5: carried by an eagle (NES $EFD6)
        call obj_ext_of
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = its eagle
        ld a,(de)
        cp OBJ_EAGLE
        jr nz,.drop                     ; the eagle is gone: it drops
        ld a,(frame_count)              ; every 8 frames: Simon within 64 px
        and 7                           ; across: it drops
        jr nz,.carry
        ld hl,(px)
        push de
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        pop de
        call hl_abs
        ld a,h
        or a
        jr nz,.carry
        ld a,l
        cp 64
        jr c,.drop
.carry:
        ex de,hl                        ; x = the eagle's middle - 8
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,8
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        jr .hits
.drop:
        ld (ix+9),1
        ld (ix+10),0
        ld (ix+11),0
.hits:
        call block3_frame
        call weapon_hits
        jr nc,.touch
        call mark_dead
        ld a,SCORE_FLEA
        ld c,1
        jp enemy_killed
.touch:
        ld a,8
        ld bc,10*256+18
        jp b3_touch

; --- raven (NES 5:$87AF) ---
; It perches 60 frames once on the screen, then swoops: up or down towards
; Simon's height (fixed at the launch), with a random speed (1 1/4 .. 2 1/2 px)
; slowing by 9/256 px a frame, and 3/4 px across towards him; then hovers a
; random 24-121 frames. If Simon is then 32 px or more above or below it, it
; swoops again; else it dashes across at him from 1/4 px, 1/32 px faster a
; frame, for 60 frames (then a new swoop); 8 px past him it slows (from 1/2 px,
; -9/256 a frame), turns back and speeds up, for 120 frames (then a swoop).
; The picture always faces Simon. One hit (200); it dies touching Simon.
;   +4 timer  +5 facing  +9 state (bits 0-3) | bit 6: going left | bit 7: up
;   +10/+11 vy (8.8)  obj_ext: x fraction, y fraction, vx (8.8, signed)
raven_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        call knight_face
        ld a,(ix+9)
        and 15
        jr nz,.s1
        call b3_offscreen
        ret c
        ld (ix+9),1
        ld (ix+4),60
        jp .hits
.s1:
        dec a
        jr nz,.s2
        dec (ix+4)                      ; perched
        jp nz,.cull
        call raven_launch
        jp .cull
.s2:
        dec a
        jr nz,.s3
        ld l,(ix+10)                    ; swoop: vy -= 9/256
        ld h,(ix+11)
        ld de,-9
        add hl,de
        ld (ix+10),l
        ld (ix+11),h
        bit 7,h
        jr z,.swoop
        ld a,(ix+9)                     ; stopped: hover
        and 0xF0
        or 3
        ld (ix+9),a
        call rng_and3
        ld hl,raven_hovers
        call table_a
        ld (ix+4),a
        jp .cull
.swoop:
        call raven_move_y
        call raven_move_x
        jp .cull
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; hovering
        jp nz,.cull
        ld a,(py+1)
        or a
        jr nz,.again
        ld a,(py)                       ; Simon's middle 32 px or more away
        add a,8                         ; across his height: swoop again
        sub (ix+3)
        jr nc,.dyp
        neg
.dyp:
        cp 32
        jr nc,.again
        call raven_toward               ; else the dash
        call obj_ext_of
        inc hl
        inc hl
        ld (hl),0x40
        inc hl
        ld (hl),0
        ld a,(ix+9)
        and 0xF0
        or 4
        ld (ix+9),a
        ld (ix+4),61
        jp .cull
.again:
        call raven_launch
        jp .cull
.s4:
        dec a
        jr nz,.s5
        dec (ix+4)                      ; dash
        jr z,.again
        call obj_ext_of
        inc hl
        inc hl
        ld a,(hl)
        add a,8
        ld (hl),a
        inc hl
        jr nc,.vx
        inc (hl)
.vx:
        call raven_move_x
        ld hl,(px)                      ; more than 8 px past Simon?
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de                       ; HL = Simon - raven
        bit 6,(ix+9)
        jr z,.past_r
        ld de,8                         ; going left: Simon - raven >= 8
        or a
        sbc hl,de
        bit 7,h
        jr nz,.cull
        jr .overshoot
.past_r:
        ld de,8                         ; going right: Simon - raven < -8
        add hl,de
        bit 7,h
        jr z,.cull
.overshoot:
        call obj_ext_of
        inc hl
        inc hl
        ld (hl),0x80
        inc hl
        ld (hl),0
        ld a,(ix+9)
        and 0xF0
        or 5
        ld (ix+9),a
        ld (ix+4),121
        jr .cull
.s5:
        dec (ix+4)                      ; overshoot: slow down, turn back
        jr z,.again
        call obj_ext_of
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,-9
        add hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        call raven_move_x
.cull:
        ld a,(ix+3)                     ; out of the playfield (up or down)
        cp 192
        jr c,.y_in
        cp 208
        jr c,.out
.y_in:
        call b3_offscreen
        jr nc,.hits
.out:
        ld a,(ix+9)                     ; culled while perched: it comes back
        and 15
        cp 2
        jp c,obj_release
        jp b3_gone_dead
.hits:
        call block3_frame
        call weapon_hits
        jr nc,.touch
.kill:
        call mark_dead
        ld a,SCORE_RAVEN
        ld c,0
        jp enemy_killed
.touch:
        ld a,8
        ld bc,10*256+18
        call b3_touch
        ret nc
        jr .kill                        ; it dies touching Simon

raven_hovers:   db 24, 63, 37, 121
raven_swoops:   dw 0x01C0, 0x0280, 0x0140, 0x0200

; a new swoop: up or down to Simon's side, speed from the table, 3/4 px across
raven_launch:
        ld a,(ix+9)
        and 0x3F
        ld b,a
        ld a,(py)
        add a,8                         ; Simon's middle above its middle: up
        cp (ix+3)
        jr nc,.down
        set 7,b
.down:
        ld a,b
        and 0xF0
        or 2
        ld (ix+9),a
        call raven_toward
        call rng_and3
        add a,a
        ld e,a
        ld d,0
        ld hl,raven_swoops
        add hl,de
        ld a,(hl)
        ld (ix+10),a
        inc hl
        ld a,(hl)
        ld (ix+11),a
        call obj_ext_of
        inc hl
        inc hl
        ld (hl),0xC0
        inc hl
        ld (hl),0
        ret

; obj_dir2 towards Simon (bit 6: left)
raven_toward:
        res 6,(ix+9)
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret p
        set 6,(ix+9)
        ret

; y +/- vy (bit 7 of +9: up), with the fraction in obj_ext+1
raven_move_y:
        call obj_ext_of
        inc hl
        ld a,(hl)
        bit 7,(ix+9)
        jr nz,.up
        add a,(ix+10)
        ld (hl),a
        ld a,(ix+3)
        adc a,(ix+11)
        ld (ix+3),a
        ret
.up:
        sub (ix+10)
        ld (hl),a
        ld a,(ix+3)
        sbc a,(ix+11)
        ld (ix+3),a
        ret

; x +/- vx (obj_ext+2, signed 8.8) along obj_dir2 (bit 6 of +9: left)
raven_move_x:
        call obj_ext_of
        push hl
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        bit 6,(ix+9)
        jr z,.r
        xor a                           ; going left: -vx
        sub e
        ld e,a
        sbc a,a
        sub d
        ld d,a
.r:
        pop hl
        ld a,(hl)                       ; the fraction
        add a,e
        ld (hl),a
        ld a,d
        adc a,0
        ld e,a
        rla
        sbc a,a
        ld d,a                          ; whole px (sign-extended, with carry)
        bit 7,d
        jr nz,.add
        ld a,e
        or a
        ret z
.add:
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ret

; --- ghost (NES 6:$8588, ai_ghost $EDC7) ---
; It appears when its place is in the screen's left strip (record type $0D)
; or right strip ($8D), with Simon's middle within 48 px of its height, at
; most 2 at a time, once. It flies in a straight line, 3/4 px a frame along
; the longer axis (the other in proportion), aimed at Simon's middle at once
; and every 32 frames. Damage adds up (hit_damage), 64 kills it (300); a hit
; that doesn't freezes it 16 frames.
;   +4 frames to the next aim  +5 direction  +9 bit 0: out, bit 1: going up,
;   bits 3-7: frames frozen  +10 vx  +11 vy (1/256 px; at spawn +10: the strip)
;   obj_ext: x fraction, y fraction
ghost_update:
        ld a,(ix+9)
        or a
        jr nz,.out
        ld l,(ix+1)                     ; its middle in the edge strip?
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,8
        add hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        bit 0,(ix+10)
        jr nz,.right_strip
        cp 24
        ret nc
        jr .height
.right_strip:
        cp 216
        ret c
        cp 241
        ret nc
.height:
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)                       ; |Simon's middle - its middle| < 48
        add a,8
        sub (ix+3)
        jr nc,.hp
        neg
.hp:
        cp 48
        ret nc
        push ix                         ; at most 2 out
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld bc,OBJ_MAX*256
.count:
        ld a,(ix+0)
        cp OBJ_GHOST
        jr nz,.cn
        ld a,(ix+9)
        or a
        jr z,.cn
        inc c
.cn:
        add ix,de
        djnz .count
        pop ix
        ld a,c
        cp 2
        ret nc
        call mark_dead                  ; one ghost, once
        ld (ix+9),1
        ld (ix+4),1
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
.out:
        ld a,(freeze_t)
        or a
        jr nz,.hits
        ld a,(ix+9)
        cp 8
        jr c,.go
        sub 8                           ; frozen by a hit
        ld (ix+9),a
        jr .hits
.go:
        dec (ix+4)
        jr nz,.move
        ld (ix+4),32
        call ghost_aim
.move:
        call obj_ext_of
        ld a,(hl)
        add a,(ix+10)
        ld (hl),a
        jr nc,.ny
        ld a,(ix+5)
        call move_dir_a
        call obj_ext_of
.ny:
        inc hl
        ld a,(hl)
        add a,(ix+11)
        ld (hl),a
        jr nc,.cull
        bit 1,(ix+9)
        jr nz,.upm
        inc (ix+3)
        jr .cull
.upm:
        dec (ix+3)
.cull:
        call b3_offscreen
        jp c,obj_gone
.hits:
        call block3_frame
        call weapon_hits
        jr nc,.touch
        call hit_damage
        ld b,a
        call obj_hits_of
        ld a,(hl)
        add a,b
        cp 64
        jr nc,.dead
        ld (hl),a
        ld a,(ix+9)
        and 7
        or 16*8
        ld (ix+9),a
        ld a,SND_HIT
        call sfx_play
        jr .touch
.dead:
        ld a,SCORE_GHOST
        ld c,0
        jp enemy_killed
.touch:
        ld a,8
        ld bc,10*256+18
        jp b3_touch

; aim at Simon's middle: facing, up/down, the speeds (3/4 px on the long axis)
ghost_aim:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de                       ; dx = Simon - ghost (middles)
        ld (ix+5),1
        bit 7,h
        jr z,.dxp
        ld (ix+5),-1
.dxp:
        call hl_abs
        ld a,h
        or a
        ld b,l
        jr z,.bx
        ld b,255
.bx:
        res 1,(ix+9)
        ld a,(py)
        add a,8
        sub (ix+3)                      ; dy = Simon - ghost (middles)
        jr nc,.dyp
        set 1,(ix+9)
        neg
.dyp:
        ld c,a
        cp b
        jr nc,.y_long
        ld (ix+10),192                  ; x is the long axis
        ld d,c
        ld e,b
        call ratio192
        ld (ix+11),a
        ret
.y_long:
        ld (ix+11),192
        ld a,c
        or a
        jr nz,.yl
        ld (ix+10),192                  ; (on him: nothing to aim at)
        ld (ix+11),0
        ret
.yl:
        ld d,b
        ld e,c
        call ratio192
        ld (ix+10),a
        ret

; A = D * 192 / E (D <= E, E > 0)
ratio192:
        ld h,0
        ld l,d
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl                       ; * 64
        push hl
        add hl,hl                       ; * 128
        pop bc
        add hl,bc                       ; * 192
        xor a
        ld b,16
.div:
        add hl,hl
        rla
        jr c,.sub
        cp e
        jr c,.nx
.sub:
        sub e
        inc l
.nx:
        djnz .div
        ld a,l
        ret

; --- skeleton (NES 5:$8527) ---
; It always faces Simon. A cycle: 0-3 legs (random), each 15 frames walking
; 1 1/2 px (towards Simon when he is 72 px or more away, else away from him;
; the other way at a wall) and 4 frames still; then it stands 4 frames, throws
; a bone (on the screen only) and stands 8 more. Walking off a floor it jumps
; (1 1/4 px across, 2 1/2 px up) and lands on the next. One hit (300).
;   +4 timer  +5 facing  +9 state (bits 0-2) | bit 7: going left
;   +10 legs left  obj_ext: x fraction, y fraction, vy (8.8, + up)
skel_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        call knight_face
        ld a,(ix+9)
        and 7
        jr nz,.s1
.s0:
        call rng_and3                   ; legs: 4, 2, 3 or 1 (+1)
        ld hl,skel_legs
        call table_a
        ld (ix+10),a
        ld a,(ix+9)
        and 0xF8
        or 1
        ld (ix+9),a
        ld (ix+4),4
        jp .cull
.s1:
        dec a
        jr nz,.s2
        dec (ix+4)                      ; standing between legs
        jp nz,.cull
        dec (ix+10)
        jr nz,.leg
        ld a,(ix+9)                     ; no legs left: the throw
        and 0xF8
        or 3
        ld (ix+9),a
        ld (ix+4),4
        jp .cull
.leg:
        ld a,(ix+9)                     ; walk: towards Simon from 72 px,
        and 0x78                        ; else away from him
        or 2
        ld b,a
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld c,0                          ; C bit 7: Simon is left
        bit 7,h
        jr z,.sr
        ld c,0x80
.sr:
        call hl_abs
        ld a,h
        or a
        jr nz,.toward
        ld a,l
        cp 72
        jr nc,.toward
        ld a,c
        xor 0x80
        ld c,a
.toward:
        ld a,b
        or c
        ld (ix+9),a
        ld (ix+4),16
        jp .cull
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; walking
        jr nz,.walk
        ld a,(ix+9)
        and 0xF8
        or 1
        ld (ix+9),a
        ld (ix+4),4
        jp .cull
.walk:
        ld a,0x80                       ; 1 1/2 px
        call skel_step
        ld de,8+12                      ; a wall 12 px ahead at its waist?
        bit 7,(ix+9)
        jr z,.wr
        ld de,8-12
.wr:
        ld a,16
        call knight_probe
        jr nc,.no_wall
        ld a,(ix+9)
        xor 0x80
        ld (ix+9),a
        jp .cull
.no_wall:
        ld de,8                         ; floor under its feet?
        ld a,32
        call knight_probe
        jp c,.cull
        call obj_ext_of                 ; no: it jumps
        inc hl
        inc hl
        ld (hl),0x80
        inc hl
        ld (hl),2
        ld a,(ix+9)
        and 0xF8
        or 5
        ld (ix+9),a
        jp .cull
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; winding up
        jp nz,.cull
        call b3_offscreen
        call nc,skel_throw
        ld a,(ix+9)
        and 0xF8
        or 4
        ld (ix+9),a
        ld (ix+4),8
        jp .cull
.s4:
        dec a
        jr nz,.s5
        dec (ix+4)                      ; after the throw
        jp nz,.cull
        jp .s0
.s5:
        dec a
        jr nz,.s6
        ld a,0x40                       ; in the air: 1 1/4 px across
        call skel_step
        call obj_ext_of                 ; gravity: vy -= 33/256, y -= vy
        inc hl
        push hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,-33
        add hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        pop hl
        ld a,(hl)
        sub e
        ld (hl),a
        ld a,(ix+3)
        sbc a,d
        ld (ix+3),a
        cp MT_ROWS*16
        jr c,.in
        cp 0xE0
        jp c,b3_gone_dead
.in:
        ld de,8
        ld a,32
        call knight_probe
        jr nc,.cull
        ld a,(ix+3)                     ; landed: on a 16-px row
        add a,16
        and 0xF0
        sub 16
        ld (ix+3),a
        ld a,(ix+9)
        and 0xF8
        or 6
        ld (ix+9),a
        jr .cull
.s6:
        ld a,(ix+9)
        and 0xF8
        ld (ix+9),a
.cull:
        ld l,(ix+1)                     ; gone 64 px beyond the screen
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,64
        add hl,de
        bit 7,h
        jp nz,b3_gone_dead
        ld de,240+128+1
        or a
        sbc hl,de
        jp nc,b3_gone_dead
.hits:
        call skel_frame
        call b3_offscreen               ; no collision off the screen
        ret c
        call weapon_hits
        jr nc,.touch
        call mark_dead
        ld a,SCORE_SKEL
        ld c,0
        jp enemy_killed
.touch:
        ld a,16
        ld bc,10*256+26
        jp b3_touch

skel_legs:      db 5, 3, 4, 2           ; (one more: it counts down first)

; x += 1 px + A/256 along obj_dir2 (bit 7 of +9), the fraction in obj_ext
skel_step:
        ld c,a
        call obj_ext_of
        ld a,(hl)
        add a,c
        ld (hl),a
        ld a,1
        adc a,0
        bit 7,(ix+9)
        jr z,move_dir_a
        neg
        ; fall through
; x += A (signed)
move_dir_a:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ret

; a bone from the skeleton at IX: at its middle, towards Simon, 4 1/2 px up
; on even frames, 3 1/2 px on odd ones (NES 5:$8777)
skel_throw:
        push ix
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        ld b,(ix+3)
        call obj_free_slot
        jr c,.none
        ld (ix+1),l
        ld (ix+2),h
        ld a,b
        add a,8
        ld (ix+3),a
        ld (ix+5),c
        ld (ix+0),OBJ_BONE
        ld (ix+4),0
        ld (ix+6),OBJF_BONE
        ld (ix+7),KIND_FIREBALL         ; 8x8 box
        ld (ix+8),0xFF
        ld (ix+9),0
        ld a,(frame_count)
        and 1
        ld a,-72
        jr z,.vy
        ld a,-56
.vy:
        ld (ix+10),a
        ld (ix+11),0
.none:
        pop ix
        ret

; --- bone: 3/4 px across and up under gravity; it can be whipped (100);
; touching Simon hurts him and it flies on ---
bone_update:
        ld a,(freeze_t)
        or a
        jr nz,.hits
        inc (ix+4)
        ld a,(ix+4)                     ; 3 px every 4 frames across
        and 3
        jr z,.no_dx
        ld a,(ix+5)
        call move_dir_a
.no_dx:
        ld a,2
        call fall_step
        jp c,obj_gone
        call b3_offscreen
        jp c,obj_gone
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,SCORE_SNAKE
        ld c,2
        jp enemy_killed
.touch:
        ld a,8
        ld bc,8*256+16
        jp b3_touch

; --- bone pillar (NES $F5BF, ai_bone_pillar $F178) ---
; Once on the screen: 24 frames, 24 more (the NES flashes it), a fireball,
; another 40 frames later, then a random 240/60/120/180 frames and again.
; Fireballs from its middle, 2 px a frame at Simon's side. Damage adds up
; (hit_damage), 192 breaks it (400). Scrolled off, it comes back afresh.
;   +4 timer  +5 facing  +9 state (0 not yet on the screen, 1-4)
pillar_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+9)
        or a
        jr nz,.s1
        call b3_offscreen
        ret c
        ld (ix+9),1
        ld (ix+4),24
        jp .hits
.s1:
        call knight_face
        ld a,(ix+9)
        cp 3
        jr z,.fire1
        dec (ix+4)
        jr nz,.cull
        cp 4
        jr z,.fire2
        inc (ix+9)                      ; 1 -> 2 (the flash) -> 3
        ld (ix+4),24
        jr .cull
.fire1:
        call pillar_fire
        ld (ix+9),4
        ld (ix+4),40
        jr .cull
.fire2:
        call pillar_fire
        call rng_and3
        ld hl,pillar_waits
        call table_a
        ld (ix+4),a
        ld (ix+9),1
.cull:
        call b3_offscreen
        jp c,obj_release                ; it comes back when on the screen
.hits:
        call pillar_frame
        call weapon_hits
        jr nc,.touch
        call hit_damage
        ld b,a
        call obj_hits_of
        ld a,(hl)
        add a,b
        jr c,.dead
        cp PILLAR_HP
        jr nc,.dead
        ld (hl),a
        ld a,SND_HIT
        call sfx_play
        jr .touch
.dead:
        call mark_dead
        ld a,SCORE_PILLAR
        ld c,1
        jp enemy_killed
.touch:
        ld a,16
        ld bc,10*256+26
        jp b3_touch

pillar_waits:   db 240, 60, 120, 180

; the skulls face Simon; before firing it flashes (palette 3 every other
; frame, NES state 1)
pillar_frame:
        ld c,0
        bit 7,(ix+5)
        jr nz,.left
        inc c
.left:
        ld a,(ix+9)
        cp 2
        jr nz,.no_flash
        ld a,(frame_count)
        and 1
        jr z,.no_flash
        inc c
        inc c
.no_flash:
        ld a,c
        or a
        ld a,OBJF_PILLAR
        jr z,.set
        ld a,c
        add a,OBJF_PILLAR_R-1
.set:
        ld (ix+6),a
        ret

; a fireball from the pillar's middle, 2 px a frame its way
pillar_fire:
        push ix
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        ld b,(ix+3)
        call obj_free_slot
        jr c,.none
        ld (ix+1),l
        ld (ix+2),h
        ld a,b
        add a,8
        ld (ix+3),a
        ld (ix+5),c
        ld (ix+0),OBJ_FIREBALL
        ld (ix+4),0
        ld (ix+6),OBJF_FIREBALL
        ld (ix+7),KIND_FIREBALL
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),2                    ; 2 px per frame
.none:
        pop ix
        ret

; frame by kind and direction
block3_frame:
        ld a,(ix+0)
        cp OBJ_SKEL
        jp z,skel_frame
        ld c,OBJF_FLEA
        cp OBJ_FLEA
        jr nz,.not_flea
        ld a,(ix+9)                     ; the fleaman: $83 in the air, $82 on
        cp 2                            ; the floor; both in turn, 9 frames
        jr z,.floor                     ; each, waiting and riding
        or a
        jr z,.turns
        cp 5
        jr nz,.lr
.turns:
        ld a,(frame_count)
        ld b,0
.d9:
        sub 9
        jr c,.d9e
        inc b
        jr .d9
.d9e:
        bit 0,b
        jr z,.lr
.floor:
        ld c,OBJF_FLEA2
        jr .lr
.not_flea:
        ld a,(ix+0)
        ld c,OBJF_GHOST
        cp OBJ_GHOST
        jr z,.lr
        cp OBJ_RAVEN
        jr nz,.pillar
        ld a,(ix+9)
        and 15
        cp 2
        ld a,OBJF_RAVEN_PERCH
        jr c,.set
        ld a,(frame_count)              ; wings: 3 pictures, 8 frames each
        rrca
        rrca
        rrca
        and 3
        cp 3
        jr nz,.wing
        ld a,1
.wing:
        bit 7,(ix+5)
        jr nz,.wl
        add a,3
.wl:
        add a,OBJF_RAVEN
        jr .set
.pillar:
        jp pillar_frame
.lr:
        ld a,c
        bit 7,(ix+5)
        jr nz,.set
        inc a
.set:
        ld (ix+6),a
        ret

; --- shared ---
; Carry if the middle of the 16-wide object at IX is off the screen (NES:
; screen x outside 8..$F8: port x - cam_x outside 0..240)
b3_offscreen:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        scf
        ret nz
        ld a,l
        cp 241
        ccf
        ret

; Simon touches the object at IX: A = its middle's y offset, B = |dx| limit
; (box half width + 4), C = |dy| limit (half height + 12), between middles
; (Simon's: px+8, py+16). Hurts him; carry if it did.
b3_touch:
        ld e,a
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)
        add a,e
        ld e,a
        ld d,0
        jr nc,.y
        inc d
.y:
        ld hl,(py)
        push bc
        ld bc,16
        add hl,bc
        pop bc
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        ret nz
        ld a,l
        cp c
        ret nc
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        push hl
        call hl_abs
        ld a,h
        or a
        jr nz,.no
        ld a,l
        cp b
        jr nc,.no
        pop hl
        ld b,1                          ; knocked away from it
        bit 7,h
        jr z,.hurt
        ld b,-1
.hurt:
        call simon_hurt
        scf
        ret
.no:
        pop hl
        or a
        ret

; HL = |HL|
hl_abs:
        bit 7,h
        ret z
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; A = (rng) & 3
rng_and3:
        ld a,(rng)
        and 3
        ret

; A = (HL + A)
table_a:
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        ret

; A = the slot of IX
obj_slot:
        push ix
        pop hl
        ld de,obj_table
        or a
        sbc hl,de
        ld a,l
        ld c,0
.div12:
        sub OBJ_SIZE
        jr c,.d12
        inc c
        jr .div12
.d12:
        ld a,c
        ret

; HL = obj_ext + 4 * the slot of IX (BC kept)
obj_ext_of:
        push bc
        call obj_slot
        pop bc
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,obj_ext
        add hl,de
        ret

; the random byte, a step a frame (NES $C030: $6F = T[($6F | frame) & 15])
rng_step:
        ld a,(frame_count)
        ld hl,rng
        or (hl)
        and 15
        ld e,a
        ld d,0
        push hl
        ld hl,rng_table
        add hl,de
        ld a,(hl)
        pop hl
        ld (hl),a
        ret
rng_table:
        db 0x33, 0xBB, 0x3F, 0x80, 0x2E, 0xA9, 0x61, 0x87
        db 0xAD, 0xC3, 0xB2, 0xC8, 0x7C, 0x25, 0x48, 0x7A

; An enemy at IX is beaten: A = score, C = what it can drop (0: a small
; heart, 1: a big heart, 2: a small heart and never a sub-weapon). As the
; NES ($E0A2): a burst, then 1 time in 16 a sub-weapon from the stage's list,
; else 1 time in 8 the heart.
enemy_killed:
        push bc
        call add_score
        ld a,SND_HIT
        call sfx_play
        pop bc
        ld a,(frame_count)
        and 15
        cp 2
        jr nz,.no_sub
        ld a,c
        cp 2
        jr z,.no_sub
        ld hl,drop_idx
        inc (hl)
        ld a,(hl)
        and 3
        ld e,a
        ld d,0
        ld hl,drops_46
        ld a,(area_hdr+AH_STAGE)
        cp 7
        jr c,.list
        ld hl,drops_79
.list:
        cp 4
        jr nc,.pick
        ld hl,drops_13
.pick:
        add hl,de
        ld a,(hl)
        jr .set
.no_sub:
        ld a,(frame_count)
        and 7
        ld a,ITEM_NONE
        jr nz,.set
        ld a,ITEM_SMALLHEART
        dec c
        jr nz,.set
        ld a,ITEM_HEART
.set:
        ld (ix+5),a
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ret
; the sub-weapon drops by block (NES $E137; the NES's items the port doesn't
; have give a small heart)
drops_13:       db ITEM_SMALLHEART, ITEM_SMALLHEART, ITEM_SMALLHEART, ITEM_SMALLHEART
drops_46:       db ITEM_HOLYWATER, ITEM_SMALLHEART, ITEM_SMALLHEART, ITEM_SMALLHEART
drops_79:       db ITEM_SMALLHEART, ITEM_SMALLHEART, ITEM_STOPWATCH, ITEM_SMALLHEART

; gone (a placed enemy that won't come back)
b3_gone_dead:
        call mark_dead
        jp obj_gone

; gone, and its place can make it again (spawn_candle)
obj_release:
        ld (ix+0),OBJ_NONE
        ld a,(ix+8)
        cp 0xFF
        ret z
        call candle_bit
        ld de,MAX_CANDLES/8
        add hl,de
        ld a,b
        cpl
        and (hl)
        ld (hl),a
        ret

; HL = obj_hits + the slot index of IX (B kept)
obj_hits_of:
        push bc
        call obj_slot
        pop bc
        ld e,a
        ld d,0
        ld hl,obj_hits
        add hl,de
        ret

block3_scores:
        db SCORE_FLEA, SCORE_SKEL, 0, SCORE_PILLAR, SCORE_RAVEN, SCORE_GHOST

obj_gone:
        ld (ix+0),OBJ_NONE
        ret

; ---------------------------------------------------------------------------
; Block 4's enemies, from the NES code
; ---------------------------------------------------------------------------

; --- the eagle (NES spawner $F4DE, object $12 $ECFE): while its record is
; on the screen, one every 112 frames (at most 3), from screen x 18 flying
; right or 238 flying left (at random), at the record's height + 32, 16, 48,
; 0 in turn, carrying a fleaman 16 px below it. It flies 1 3/4 px a frame
; for 47 frames, hovers 17, again; its height never changes. One hit (300). ---
; HL = its state, DE = its timer, C = the record's y (an eagle's top)
eagle_spawner:
        ld a,(de)
        or a
        ret nz
        push de
        push bc
        ld a,OBJ_EAGLE                  ; (NES slots 9-11 for the eagles,
        call count_type                 ; 4-6 for the fleamen)
        cp 3
        jr nc,.no
        ld a,OBJ_FLEA
        call count_type
        cp 3
        jr nc,.no
        call obj_free_slot
        jr c,.no
        ld (ix+0),OBJ_EAGLE             ; (claimed: the next free slot is
        ld (tmp_w),ix                   ; the fleaman's)
        call obj_free_slot
        jr nc,.both
        ld ix,(tmp_w)
        ld (ix+0),OBJ_NONE
.no:
        pop bc
        pop de
        ret
.both:
        ld (ix+0),OBJ_FLEA
        push ix
        pop iy                          ; IY = the fleaman
        ld ix,(tmp_w)                   ; IX = the eagle
        pop bc
        pop de
        ld a,56                         ; 112 frames to the next
        ld (de),a
        ld hl,spawn_cnt                 ; its height: + 32, 16, 48, 0 in turn
        ld a,(spawner_i)
        and SPAWNERS_MAX-1
        ld e,a
        ld d,0
        add hl,de
        inc (hl)
        ld a,(hl)
        and 3
        ld hl,eagle_heights
        call table_a
        add a,c
        ld (ix+3),a
        add a,24                        ; the fleaman's top: 16 px below the
        ld (iy+3),a                     ; eagle's middle, - 8
        ld hl,(cam_x)
        ld a,(rng)
        and 1
        ld de,2                         ; screen x 18 (its middle), flying
        ld (ix+5),1                     ; right
        jr nz,.side
        ld de,222                       ; or 238, flying left
        ld (ix+5),-1
.side:
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld de,8
        add hl,de
        ld (iy+1),l
        ld (iy+2),h
        ld a,(ix+5)
        ld (iy+5),a
        xor a
        ld (ix+4),a
        ld (ix+9),a
        ld (ix+11),a
        ld (ix+7),KIND_EAGLE
        ld (ix+8),0xFF
        ld (iy+4),a
        ld (iy+10),a
        ld (iy+11),a
        ld (iy+9),5                     ; riding
        ld (iy+7),KIND_BAT
        ld (iy+8),0xFF
        push ix                         ; the fleaman's eagle (obj_ext)
        push iy
        pop ix
        call obj_hits_of
        ld (hl),0
        call obj_ext_of
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        call block3_frame
        push de
        pop ix
        jp eagle_frame
eagle_heights:  db 0, 32, 16, 48

eagle_update:
        ld a,(freeze_t)
        or a
        jr nz,.hits
        ld a,(ix+9)
        or a
        jr nz,.s1
        ld (ix+4),48                    ; (its first frame: no move)
        ld (ix+9),1
        jr .hits
.s1:
        dec (ix+4)
        cp 1
        jr nz,.hover
        ld a,(ix+4)                     ; flying
        or a
        jr nz,.move
        ld (ix+4),16                    ; 47 frames flying, then hovering
        ld (ix+9),2
        jr .hits
.move:
        ld a,0xC0                       ; 1 3/4 px a frame
        call step_x_frac
        ld l,(ix+1)                     ; its middle leaves screen x 16..240:
        ld h,(ix+2)                     ; gone
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jp nz,obj_gone
        ld a,l
        cp 225
        jp nc,obj_gone
        jr .hits
.hover:
        ld a,(ix+4)
        or a
        jr nz,.hits
        ld (ix+4),48
        ld (ix+9),1
.hits:
        call eagle_frame
        call weapon_hits
        jr nc,.touch
        ld a,SCORE_EAGLE
        ld c,1                          ; (a big heart)
        jp enemy_killed
.touch:
        ld a,16
        ld bc,18*256+26
        jp b3_touch

; wings: 17 frames each (16 here)
eagle_frame:
        ld a,(frame_count)
        rrca
        rrca
        rrca
        rrca
        and 1
        bit 7,(ix+5)
        jr nz,.l
        add a,2
.l:
        add a,OBJF_EAGLE
        ld (ix+6),a
        ret

; --- the red skeleton (NES 6:$8A16, object $13 5:$91A4): a bone pile that
; gets up (60 frames, then 50), walks in legs of 48 frames at 5/8 px with 16
; still between them, facing Simon before the first leg and then every 4, 3,
; 5 or 4 legs; it turns at walls 12 px ahead and falls off floor ends. A hit
; (400 points, every time) collapses it: 32 frames, 84 lying, it gets up
; again. It never dies.
;   +4 timer  +5 facing  +9 state (0 lying, 1 getting up, 2 walking,
;   3 pausing, 4 collapsed, 5 falling)  +10 legs to the next turn
;   +11 collapse frames  obj_ext: x fraction, y fraction, fall speed (1/16)
rskel_spawn:
        ld (ix+0),OBJ_RSKEL
        ld (ix+7),KIND_BRAZIER          ; 16x32 box
        ld (ix+4),60
        ld (ix+9),0
        ld (ix+10),1
        ld (ix+11),0
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld (ix+5),-1
        jp rskel_frame

rskel_update:
        ld a,(freeze_t)                 ; the stopwatch: only a collapse
        or a                            ; goes on
        jr z,.go
        ld a,(ix+9)
        cp 4
        jp nz,.hits
.go:
        ld a,(ix+9)
        or a
        jr nz,.s1
        dec (ix+4)                      ; lying
        jp nz,.cull
        ld (ix+9),1
        ld (ix+4),50
        jp .cull
.s1:
        dec a
        jr nz,.s2
        dec (ix+4)                      ; getting up
        jp nz,.cull
.walk:
        dec (ix+10)                     ; a leg: face Simon every 4/3/5/4
        jr nz,.leg
        call knight_face
        call rng_and3
        ld hl,rskel_legs
        call table_a
        ld (ix+10),a
.leg:
        ld (ix+4),48
        ld (ix+9),2
        jp .cull
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; walking
        jr nz,.step
        ld (ix+4),16
        ld (ix+9),3
        jp .cull
.step:
        call obj_ext_of                 ; 5/8 px a frame
        ld a,(hl)
        add a,0xA0
        ld (hl),a
        jr nc,.probe
        ld a,(ix+5)
        call move_dir_a
.probe:
        ld de,8+12                      ; a wall 12 px ahead at its middle
        bit 7,(ix+5)
        jr z,.wr
        ld de,8-12
.wr:
        ld a,16
        call knight_probe
        jr nc,.no_wall
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jp .cull
.no_wall:
        call b3_offscreen               ; (on the screen) floor under it?
        jp c,.cull
        ld de,8
        ld a,32
        call knight_probe
        jp c,.cull
        ld (ix+9),5                     ; no: it falls
        call obj_ext_of
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        jp .cull
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; pausing
        jp nz,.cull
        jp .walk
.s4:
        dec a
        jr nz,.s5
        dec (ix+11)                     ; collapsed
        jp nz,.cull
        ld (ix+9),0
        ld (ix+4),84
        jp .cull
.s5:
        call obj_ext_of                 ; falling: 1/8 px faster a frame
        inc hl
        push hl
        inc hl
        ld a,(hl)
        add a,2
        ld (hl),a
        pop hl
        add a,(hl)
        ld c,a
        and 15
        ld (hl),a
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,(ix+3)
        cp MT_ROWS*16
        jp nc,b3_gone_dead
        ld (ix+3),a
        ld de,8
        ld a,32
        call knight_probe
        jr nc,.cull
        ld a,(ix+3)                     ; landed
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+9),2
.cull:
        ld l,(ix+1)                     ; gone 64 px beyond the screen (and
        ld h,(ix+2)                     ; made again when its place is near)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,64
        add hl,de
        bit 7,h
        jp nz,obj_release
        ld de,240+128+1
        or a
        sbc hl,de
        jp nc,obj_release
.hits:
        call rskel_frame
        ld a,(ix+9)                     ; hittable walking, pausing, falling
        cp 2
        ret c
        cp 4
        ret z
        call b3_offscreen
        ret c
        call weapon_hits
        jr nc,.touch
        ld a,SCORE_KNIGHT               ; 400 points, every hit
        call add_score
        ld a,SND_HIT
        call sfx_play
        ld (ix+9),4
        ld (ix+11),32
        jp rskel_frame
.touch:
        ld a,16
        ld bc,10*256+26
        jp b3_touch
rskel_legs:     db 4, 3, 5, 4

; its pictures: walking (17 frames each, held when it pauses), the pile, the
; half pile getting up and collapsing
rskel_frame:
        ld a,(ix+9)
        cp 2
        jr z,.walk
        cp 3
        ret z                           ; (pausing: as it was)
        cp 5
        ret z
        ld c,0                          ; C = 0 the pile, 1 the half pile
        or a
        jr z,.pile
        cp 1
        jr nz,.down
        ld a,(ix+4)                     ; getting up: the pile 25, half 25
        cp 25
        jr nc,.pile
        inc c
        jr .pile
.down:
        ld a,(ix+11)                    ; collapsing: half 25, then the pile
        cp 8
        jr c,.pile
        inc c
.pile:
        ld a,c
        bit 7,(ix+5)
        jr nz,.pl
        add a,2
.pl:
        add a,OBJF_RPILE
        ld (ix+6),a
        ret
.walk:
        ld a,(frame_count)
        rrca
        rrca
        rrca
        rrca
        and 1
        bit 7,(ix+5)
        jr nz,.wl
        add a,2
.wl:
        add a,OBJF_RSKEL
        ld (ix+6),a
        ret

; --- the bone dragon (NES 6:$8867, objects $14-$16 5:$8AAD-$8CC1): a root
; vertebra fixed in a right-hand wall (this object), 5 vertebrae and the head
; (drawn as parts, part_table 0-5). 8 frames after it appears the neck grows
; out to the left (the head to 52 px, the vertebrae to 40, 32, 24, 16, 8).
; The head moves up or down 1 3/4 px a frame: aimed at Simon's height every
; 32 frames, turned at the end of each leg (52/36/60/28 frames) and after
; each attack; 8 px from its neighbour it pushes it (1 3/4 px, slowing 1/8 a
; frame), and so on down the chain. Every 32 frames, 1 time in 2: the mouth
; opens 16 frames, it fires at Simon (if he is left of it and near its
; height), 16 more. Only the head can be hurt: damage adds up (hit_damage),
; 192 kills it (1000 points); a hit that doesn't freezes it 16 frames. Every
; part hurts Simon. One dragon at a time (the NES's fixed slots 4-10).
; drg_parts: 6 bytes each (head, vertebrae 1-5): x offset left of the root,
; y direction (0 still, 1 up, 2 down), y offset from the next part towards
; the root (8.8, -8..+8), its speed (8.8)
; ---------------------------------------------------------------------------
DP_SIZE         equ 6

dragon_spawn:
        push ix                         ; (one at a time: an old one goes)
        pop de
        push ix
        ld ix,obj_table
        ld b,OBJ_MAX
.old:
        ld a,(ix+0)
        cp OBJ_DRAGON
        jr nz,.on
        ld a,ixl
        cp e
        jr z,.on
        ld (ix+0),OBJ_NONE
.on:
        push de
        ld de,OBJ_SIZE
        add ix,de
        pop de
        djnz .old
        pop ix
        ld (ix+0),OBJ_DRAGON
        ld (ix+7),KIND_BAT
        ld (ix+9),0
        ld (ix+4),8
        ld (ix+6),OBJF_DHEAD+2
        ld hl,drg_state
        ld de,drg_state+1
        ld bc,4+6*DP_SIZE-1
        ld (hl),0
        ldir
        ld a,12                         ; the head starts 12 px out
        ld (drg_parts),a
        jp dragon_parts_clear

dragon_parts_clear:
        ld hl,part_table
        ld de,part_table+1
        ld bc,6*OBJ_SIZE-1
        ld (hl),0
        ldir
        ret

dragon_update:
        ld l,(ix+1)                     ; 112 px beyond the screen: gone (made
        ld h,(ix+2)                     ; again when its place is near)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,112+8
        add hl,de
        bit 7,h
        jr nz,.gone
        ld de,256+224+1
        or a
        sbc hl,de
        jr c,.here
.gone:
        call dragon_parts_clear
        jp obj_release
.here:
        ld a,(freeze_t)
        or a
        jp nz,.place
        ld a,(ix+9)
        or a
        jr nz,.awake
        dec (ix+4)                      ; 8 frames, then it grows out
        jp nz,.place
        ld (ix+9),1
        ld a,1
        ld (drg_state),a
        jp .place
.awake:
        ld a,(drg_frz)                  ; frozen by a hit: all of it
        or a
        jr z,.ai
        dec a
        ld (drg_frz),a
        jp .place
.ai:
        ld b,5                          ; the vertebrae, root side first
        ld hl,drg_parts+5*DP_SIZE
.vert:
        ld a,b                          ; its length: 48 - 8 * k
        add a,a
        add a,a
        add a,a
        neg
        add a,48
        cp (hl)
        jr z,.grown
        inc (hl)                        ; growing out
        jr .vnext
.grown:
        push hl                         ; slowing: vy -= 1/8 px, not below 0
        inc hl
        inc hl
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld de,-32
        add hl,de
        ex de,hl
        bit 7,d
        jr z,.vy
        ld de,0
        ld (hl),d
        dec hl
        ld (hl),e
        dec hl
        dec hl
        dec hl
        ld (hl),0                       ; (stopped)
        jr .vpop
.vy:
        ld (hl),d
        dec hl
        ld (hl),e
.vpop:
        pop hl
        push hl
        push bc
        call dragon_chain
        pop bc
        pop hl
.vnext:
        ld de,-DP_SIZE
        add hl,de
        djnz .vert
        call dragon_head                ; the head last
.place:
        call dragon_place
        jp dragon_hits

; the head's states (drg_state: 0 waiting, 1 growing, 2 a moment, 3 moving,
; 4 mouth open before firing, 5 after)
dragon_head:
        ld hl,drg_t
        ld a,(drg_state)
        or a
        ret z
        dec a
        jr nz,.s2
        ld a,(drg_parts)                ; growing: to 52 px
        inc a
        ld (drg_parts),a
        cp 52
        ret c
        ld (hl),8
        ld a,2
        ld (drg_state),a
        ret
.s2:
        dec a
        jr nz,.s3
        dec (hl)
        ret nz
        ld a,2                          ; then down, 1 3/4 px a frame
        ld (drg_parts+1),a
        ld de,0x01C0
        ld (drg_parts+4),de
        ld (hl),56
        ld a,3
        ld (drg_state),a
        ret
.s3:
        dec a
        jr nz,.s4
        dec (hl)
        jr z,.new_leg
        jr .move
.s4:
        dec a
        jr nz,.s5
        dec (hl)
        jr nz,.move
        call dragon_fire
        ld (hl),16
        ld a,5
        ld (drg_state),a
        jr .move
.s5:
        dec (hl)
        jr nz,.move
        ld a,3
        ld (drg_state),a
.new_leg:
        call rng_and3                   ; 52/36/60/28 frames, the other way
        ld hl,dragon_legs
        call table_a
        ld (drg_t),a
        ld a,(drg_parts+1)
        xor 3
        ld (drg_parts+1),a
        jr .chain
.move:
        ld a,(frame_count)
        and 31
        jr nz,.not0
        ld a,(drg_state)                ; 1 time in 2: an attack
        cp 3
        jr nz,.chain
        ld a,(rng)
        and 1
        jr nz,.chain
        ld a,4
        ld (drg_state),a
        ld a,16
        ld (drg_t),a
        jr .chain
.not0:
        cp 8
        jr nz,.chain
        ld a,(py)                       ; at Simon's height: his middle py+16,
        add a,8                         ; its middle y+8
        ld hl,part_table+3
        cp (hl)
        ld a,2
        jr nc,.yd
        dec a
.yd:
        ld (drg_parts+1),a
.chain:
        ld hl,drg_parts
        ld b,0
        jp dragon_chain
dragon_legs:    db 52, 36, 60, 28

; the chain step of part B (HL = its data): its y offset moves by its speed
; (up / down), held within -8..+8; at the limit it pushes the next part
dragon_chain:
        push hl
        pop iy
        ld a,(iy+1)
        or a
        ret z
        ld e,(iy+4)
        ld d,(iy+5)
        ld l,(iy+2)
        ld h,(iy+3)
        dec a
        jr nz,.down
        or a
        sbc hl,de                       ; up: the offset falls
        jr .clamp
.down:
        add hl,de
.clamp:
        ld (iy+2),l
        ld (iy+3),h
        ld a,h
        bit 7,a
        jr nz,.neg
        cp 8
        ret c
        ld (iy+3),8
        jr .push
.neg:
        cp -7
        ret nc
        ld (iy+3),-8
.push:
        ld a,b                          ; (the root isn't pushed)
        cp 5
        ret z
        ld a,(iy+1)
        ld (iy+DP_SIZE+1),a
        ld (iy+DP_SIZE+4),0xC0
        ld (iy+DP_SIZE+5),1
        ret

; the parts' places: x = the root's - its offset, y = the next part's + its
; y offset; into part_table
dragon_place:
        ld b,5
        ld c,(ix+3)                     ; C = the next part's y (the root's)
        ld iy,part_table+5*OBJ_SIZE
        ld hl,drg_parts+5*DP_SIZE
.lp:
        push hl
        ld a,(hl)                       ; x offset
        inc hl
        inc hl
        inc hl
        ld e,a
        ld a,c
        add a,(hl)                      ; + y offset
        ld c,a
        ld (iy+3),a
        ld l,(ix+1)
        ld h,(ix+2)
        ld d,0
        or a
        sbc hl,de
        ld (iy+1),l
        ld (iy+2),h
        ld (iy+0),OBJ_DRAGON
        ld (iy+7),KIND_BAT
        ld (iy+6),OBJF_DHEAD+2          ; a vertebra
        pop hl
        ld de,-DP_SIZE
        add hl,de
        ld de,-OBJ_SIZE
        add iy,de
        ld a,b
        dec b
        or a
        jr nz,.lp
        ld a,(drg_state)                ; the head: mouth open from 4
        cp 4
        ld a,OBJF_DHEAD
        jr c,.shut
        inc a
.shut:
        ld (part_table+6),a
        ret

; fire at Simon from the head, if it is on the screen, he is left of it and
; within -39..+40 px of its height (NES $8BE4): 1 1/2 px a frame, aimed
dragon_fire:
        push hl
        push ix
        call .try
        pop ix
        pop hl
        ret
.try:
        ld ix,part_table                ; IX = the head
        call b3_offscreen
        ret c
        ld hl,(px)                      ; Simon left of it
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret p
        call hl_abs
        ld a,h
        or a
        ld b,l
        jr z,.bx
        ld b,255
.bx:
        ld a,(py)                       ; his middle py+16, its y+8
        add a,8
        sub (ix+3)
        ld c,0
        jr nc,.dyp
        neg
        inc c
.dyp:
        cp 40
        ret nc
        ld hl,(part_table+1)
        ld a,(part_table+3)
        ld e,a
        jp fire_at_simon

; a fireball from a 16x16 shooter at (HL = x, E = top) at Simon's middle,
; 1 1/2 px a frame on the long axis (NES shoot_at_simon $EC94), at most 2
fire_at_simon:
        push hl
        push de
        ld a,OBJ_FIREBALL
        call count_type
        pop de
        pop hl
        cp 2
        ret nc
        push hl
        push de
        ex de,hl                        ; dx = Simon - the shooter
        ld hl,(px)
        or a
        sbc hl,de
        ld c,1                          ; C bit 7: left
        bit 7,h
        jr z,.r
        ld c,0x80
.r:
        call hl_abs
        ld a,h
        or a
        ld b,l
        jr z,.bx
        ld b,255
.bx:
        pop de
        push de
        ld a,(py)                       ; dy = Simon's middle - its middle
        add a,8
        sub e
        jr nc,.dyp
        neg
        inc c                           ; C bit 0: up
.dyp:
        ld d,a                          ; D = |dy|, B = |dx|
        push bc
        push de
        call obj_free_slot
        pop de
        pop bc
        pop hl                          ; (E)
        ld a,l
        pop hl
        ret c
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),a
        ld (ix+0),OBJ_FIREBALL
        ld (ix+4),0
        ld (ix+5),1
        bit 7,c
        jr z,.dir
        ld (ix+5),-1
.dir:
        ld (ix+6),OBJF_FIREBALL
        ld (ix+7),KIND_FIREBALL
        ld (ix+8),0xFF
        ld (ix+10),1                    ; (aimed: ball_step)
        push bc
        ld a,b
        or d
        jr nz,.aim
        ld b,1                          ; (on him: straight across)
.aim:
        ld a,d
        cp b
        jr nc,.ylong
        ld (ix+11),96                   ; x long: 1 1/2 px (1/64 units)
        ld l,b
        ld de,96
        call boss_muldiv
        ld a,l
        jr .vy
.ylong:
        ld l,a                          ; y long
        ld a,b
        ld de,96
        call boss_muldiv
        ld (ix+11),l
        ld a,96
.vy:
        pop bc
        bit 0,c
        jr z,.down
        neg
.down:
        ld (ix+9),a
        call obj_ext_of
        ld (hl),0
        inc hl
        ld (hl),0
        ret

; hits on the head, touches on every part
dragon_hits:
        push ix
        ld ix,part_table                ; the head
        call weapon_hits
        pop ix
        jr nc,.touch
        call hit_damage
        ld hl,drg_dmg
        add a,(hl)
        jr c,.dead
        cp PILLAR_HP
        jr nc,.dead
        ld (hl),a
        ld a,16
        ld (drg_frz),a
        ld a,SND_HIT
        call sfx_play
        jr .touch
.dead:
        ld b,5                          ; the vertebrae burst (and leave hearts)
        ld iy,part_table+5*OBJ_SIZE
.burst:
        push bc
        push ix
        ld l,(iy+1)
        ld h,(iy+2)
        ld c,(iy+3)
        call obj_free_slot
        jr c,.nb
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),c
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_SMALLHEART
        ld (ix+8),0xFF
.nb:
        pop ix
        ld de,-OBJ_SIZE
        add iy,de
        pop bc
        djnz .burst
        ld a,(part_table+1)             ; the head burns where it is
        ld (ix+1),a
        ld a,(part_table+2)
        ld (ix+2),a
        ld a,(part_table+3)
        ld (ix+3),a
        call dragon_parts_clear
        call mark_dead
        ld a,SCORE_DRAGON
        ld c,0
        jp enemy_killed
.touch:
        ld a,8                          ; the root
        ld bc,5*256+14
        call b3_touch
        ret c
        push ix
        ld ix,part_table
        ld a,8                          ; the head
        ld bc,10*256+18
        call b3_touch
        jr c,.tdone
        ld b,5
.tv:
        push bc
        ld de,OBJ_SIZE
        add ix,de
        ld a,8
        ld bc,5*256+14
        call b3_touch
        pop bc
        jr c,.tdone
        djnz .tv
.tdone:
        pop ix
        ret

; ---------------------------------------------------------------------------
; Frankenstein's monster and Igor (stage 12's boss), from the NES code
; (6:$88C5, Frank $1C 5:$8A0A, Igor $1F 5:$8967). When his place comes into
; view every other enemy goes; Igor sits on his shoulders. The camera at the
; room (the area's end) locks it, the boss music plays; 120 frames later
; Frank walks at Simon 3/4 px a frame for 60 frames carrying Igor, then lets
; him go, and walks in legs of 60/36/84/24 frames, at Simon from 80 px, else
; away, turning at the screen's edges (his picture always faces Simon). Igor
; spits a fireball when let go and at the top of every hop; he hops 3, 5, 4
; or 6 px up, 1 1/2 px across, lands on any floor, crouches 8 frames; he
; turns only at the screen's edges. A hit on Igor stops him 84 frames
; (flickering). Frank takes half the weapon's damage (3 / 4) from BOSS_HP and
; stops 8 frames; beaten (5000) he burns, Igor goes, the orb appears.
; Frank: +4 timer  +5 facing  +9 state (0 asleep, 1 waking, 2 carrying Igor,
;   3 walking, 4 burning)  +10 walk direction  +11 frames frozen by a hit
;   obj_ext: x fraction, picture counter, Igor (2)
; Igor: +4 timer  +5 facing  +9 state (0 riding, 1 rising, 2 falling,
;   3 crouching)  +10 frames stopped by a hit  obj_ext: x fraction,
;   y fraction, vy (8.8, + up)
; ---------------------------------------------------------------------------
frank_spawn:
        push ix                         ; every other enemy goes (NES $F47C)
        call enemies_burst
        push ix
        ld ix,obj_table
        ld b,OBJ_MAX
.gone:
        ld a,(ix+0)
        cp OBJ_BURST
        jr nz,.gn
        ld (ix+0),OBJ_NONE
.gn:
        ld de,OBJ_SIZE
        add ix,de
        djnz .gone
        pop ix
        pop ix
        ld (ix+0),OBJ_FRANK
        ld (ix+7),KIND_MUMMY            ; 16x44 box
        ld (ix+9),0
        ld (ix+11),0
        call knight_face
        ld a,BOSS_HP
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a                       ; (no Igor yet)
        inc hl
        ld (hl),a
        push hl
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,(ix+3)
        sub 8                           ; Igor: on his shoulders
        ld c,a
        ld b,(ix+5)
        call obj_free_slot
        jr c,.no_igor
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),c
        ld (ix+5),b
        ld (ix+0),OBJ_IGOR
        ld (ix+4),0
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),0
        ld (ix+6),OBJF_FLEA2
        push ix
        call obj_ext_of
        xor a
        ld b,4
.clr:
        ld (hl),a
        inc hl
        djnz .clr
        pop de                          ; DE = Igor
        pop ix
        pop hl
        ld (hl),d                       ; Frank's Igor
        dec hl
        ld (hl),e
        jp frank_frame
.no_igor:
        pop ix
        pop hl
        jp frank_frame

frank_update:
        ld a,(ix+9)
        cp 4
        jr nz,.alive
        inc (ix+4)
        jp boss_update.burning
.alive:
        ld a,(ix+11)                    ; frozen by a hit
        or a
        jr z,.nf
        dec (ix+11)
        jp .hits
.nf:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        call obj_ext_of                 ; his walk picture: the counter
        inc hl
        inc (hl)
        call knight_face
        ld a,(ix+9)
        or a
        jr nz,.s1
        ld hl,(cam_x)                   ; asleep until the screen is at his
        ld de,(area_hdr+AH_MAXCAM)      ; room (the area's end)
        or a
        sbc hl,de
        jp nz,.hits
        ld a,SND_BOSS
        call music_restart
        ld hl,(cam_x)                   ; the screen locks
        ld (cam_min),hl
        ld a,1
        ld (cam_lock),a
        ld (ix+9),1
        ld (ix+4),120
        jp .hits
.s1:
        dec a
        jr nz,.s2
        dec (ix+4)                      ; waking
        jp nz,.hits
        ld (ix+9),2
        ld (ix+4),60
        jp .hits
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; carrying Igor
        jr z,.let_go
        call frank_igor                 ; Igor's x = his (before his move)
        jr z,.carry
        ld (iy+1),e
        ld (iy+2),d
.carry:
        ld a,(ix+5)
        call frank_step
        jp .hits
.let_go:
        call frank_igor
        jr z,.pick
        ld a,(iy+9)
        or a
        jr nz,.pick
        ld (iy+9),1
        jr .pick
.s3:
        dec (ix+4)                      ; walking
        jr z,.pick
        ld a,(ix+10)
        call frank_step
        ld l,(ix+1)                     ; turning at screen x 16 / 240 (his
        ld h,(ix+2)                     ; middle)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.turn
        ld a,l
        cp 8
        jr c,.turn
        cp 232
        jr c,.hits
.turn:
        ld a,(ix+10)
        neg
        ld (ix+10),a
        jr .hits
.pick:
        ld a,(ix+5)                     ; at Simon from 80 px, else away
        ld (ix+10),a
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.leg
        ld a,l
        cp 80
        jr nc,.leg
        ld a,(ix+10)
        neg
        ld (ix+10),a
.leg:
        call rng_and3
        ld hl,frank_legs
        call table_a
        ld (ix+4),a
        ld (ix+9),3
.hits:
        call frank_frame
        ld a,(ix+9)                     ; asleep or waking: no hits, no harm
        cp 2
        ret c
        call weapon_hits
        jr nc,.touch
        ld a,SND_HIT
        call sfx_play
        call hit_damage                 ; half the weapon's damage; holy
        rrca                            ; water's fire 1 every 8 frames
        rrca
        rrca
        and 31
        ld b,a
        ld a,(hit_src)
        cp 3
        jr nz,.dmg
        ld b,0
        ld a,(frame_count)
        and 7
        jr nz,.dmg
        inc b
.dmg:
        ld a,1
        ld (hud_dirty),a
        ld a,(boss_hp)
        sub b
        jr z,.dead
        jr c,.dead
        ld (boss_hp),a
        ld (ix+11),BOSS_FREEZE
        ret
.dead:
        xor a
        ld (boss_hp),a
        ld a,SCORE_FRANK
        call add_score
        call frank_igor                 ; Igor: a flame
        jr z,.burn
        ld (iy+0),OBJ_BURST
        ld (iy+4),0
        ld (iy+6),OBJF_BURST
        ld (iy+5),ITEM_NONE
.burn:
        ld (ix+9),4                     ; Frank burns at his middle, then the
        ld (ix+4),0                     ; orb
        ld a,(ix+3)
        add a,16
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret
.touch:
        ld a,24
        ld bc,12*256+34
        jp b3_touch
frank_legs:     db 60, 36, 84, 24

; IY = his Igor, DE = Frank's x; Z if Igor is gone
frank_igor:
        call obj_ext_of
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        pop iy
        ld e,(ix+1)
        ld d,(ix+2)
        ld a,iyh
        or iyl
        ret z
        ld a,(iy+0)
        cp OBJ_IGOR
        ret

; x += 3/4 px along A (+1 / -1)
frank_step:
        ld c,a
        call obj_ext_of
        ld a,(hl)
        add a,0xC0
        ld (hl),a
        ret nc
        ld a,c
        jp move_dir_a

; his walk: $8F $90 $91 $90, 25 frames each (24 here)
frank_frame:
        call obj_ext_of
        inc hl
        ld a,(hl)
        cp 96
        jr c,.c
        xor a
        ld (hl),a
.c:
        ld c,0
.d24:
        sub 24
        jr c,.p
        inc c
        jr .d24
.p:
        ld a,c
        cp 3
        jr nz,.q
        ld a,1
.q:
        bit 7,(ix+5)
        jr nz,.l
        add a,3
.l:
        add a,OBJF_FRANK
        ld (ix+6),a
        ret

igor_update:
        ld a,(ix+10)                    ; stopped by a hit: flickering, no
        or a                            ; AI, no collision
        jr z,.go
        dec (ix+10)
        ld a,(frame_count)              ; (shown every other frame)
        and 1
        ld a,OBJF_FLEA
        jr z,.fl
        ld a,OBJF_BURST+3
.fl:
        ld (ix+6),a
        ret
.go:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+9)
        or a
        jr nz,.s1
        call knight_face                ; riding: faces Simon, 82 / 83 in
        call obj_ext_of                 ; turn
        inc hl
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,(frame_count)
        ld c,0
.d9:
        sub 9
        jr c,.d9e
        inc c
        jr .d9
.d9e:
        bit 0,c
        ld a,OBJF_FLEA2
        jr z,.f0
        ld a,OBJF_FLEA
.f0:
        call igor_pic
        jp .hits
.s1:
        cp 3
        jr nz,.air
        dec (ix+4)                      ; crouching
        jp nz,.hits
        call rng_and3                   ; a hop: 3, 5, 4 or 6 px up
        ld hl,igor_hops
        call table_a
        ld c,a
        call obj_ext_of
        inc hl
        inc hl
        ld (hl),0
        inc hl
        ld (hl),c
        ld (ix+9),1
        ld a,OBJF_FLEA
        call igor_pic
        jp .hits
.air:
        call obj_ext_of                 ; 1 1/2 px across
        ld a,(hl)
        add a,0x80
        ld (hl),a
        ld a,1
        adc a,0
        bit 7,(ix+5)
        jr z,.xr
        neg
.xr:
        call move_dir_a
        call obj_ext_of                 ; gravity: vy -= 1/8 px, y -= vy
        inc hl
        push hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,-32
        add hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        pop hl
        ld a,(hl)
        sub e
        ld (hl),a
        ld a,(ix+3)
        sbc a,d
        ld (ix+3),a
        call snake_ground               ; any floor (also rising)
        jr nc,.clamps
        ld a,(ix+3)
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld a,OBJF_FLEA2
        call igor_pic
        ld (ix+4),8
        ld a,(ix+9)
        inc a
        ld (ix+9),a
.clamps:
        ld l,(ix+1)                     ; the screen's edges: turn
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.edge
        ld a,l
        cp 1
        jr c,.edge
        cp 239
        jr c,.top
.edge:
        ld a,(ix+5)
        neg
        ld (ix+5),a
        call move_dir_a
.top:
        ld a,(ix+3)                     ; not above the playfield's top
        cp 0xC0
        jr c,.shot
        ld (ix+3),0
        call obj_ext_of
        inc hl
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
.shot:
        ld a,(ix+9)                     ; rising, past the top: a fireball
        cp 1
        jr nz,.hits
        call obj_ext_of
        inc hl
        inc hl
        inc hl
        bit 7,(hl)
        jr z,.hits
        ld (ix+9),2
        ld a,OBJF_FLEA2                 ; (spitting)
        call igor_pic
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld e,(ix+3)
        call fire_at_simon
        pop ix
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,SND_HIT                    ; no damage: he stops 84 frames
        call sfx_play
        ld (ix+10),84
        ret
.touch:
        ld a,8
        ld bc,10*256+18
        jp b3_touch
igor_hops:      db 3, 5, 4, 6

; A = a fleaman picture facing left -> by his facing
igor_pic:
        bit 7,(ix+5)
        jr nz,.l
        inc a
.l:
        ld (ix+6),a
        ret

; ---------------------------------------------------------------------------
; The mummies (stage 9 boss), from the NES code (bank 5 $866C, $8666). Two,
; placed in the tower room, asleep until the screen reaches the room (the
; area's last screen): then the screen locks, the boss music plays, the
; bridge's enemies go and their sprite patterns make way for the mummies'
; (swap window, set 1). Each gets up for 120 frames (it can't be hit and
; doesn't hurt), then: walks 3/4 px a frame for 123, 65, 180 or 32 frames
; (in turn, from a random start), facing Simon every 32 frames - and walking
; away if he faces it within 56 px; at the screen's edges it stands; then it
; faces Simon, stands 40 frames, throws a bandage, stands 8 and walks on.
; Each has 32 health (the HUD's bar shows both together); a hit takes the
; weapon's damage / 4 (1 1/2 leather, 2 chain/morning star) and stops it 8
; frames. Beaten, each burns 60 frames (3000 points); the last leaves the orb.
;   +4 timer  +5 direction  +9 state (0 asleep, 1 getting up, 2 walking,
;   3 winding up, 4 after the throw, 5 burning)  +10 health (1/4s)
;   +11 frames frozen  obj_ext: walk index, x fraction
; ---------------------------------------------------------------------------
mummy_spawn:
        ld (ix+7),KIND_MUMMY            ; 16x44 box
        ld (ix+10),MUMMY_HP*4
        ld (ix+11),0
        ld (ix+6),OBJF_MUMMY
        ld a,MUMMY_HP*2
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        ret

mummy_walks:    db 123, 65, 180, 32

mummy_update:
        ld a,(ix+9)
        cp 5
        jp z,.burning
        or a
        jp nz,.awake
        ld hl,(cam_x)                   ; asleep until the screen is at the room
        ld de,(area_hdr+AH_MAXCAM)
        or a
        sbc hl,de
        jp nz,.frame
        ld (ix+9),1                     ; getting up
        ld (ix+4),120
        call obj_slot                   ; walk index: (slot + random) & 3
        ld hl,rng
        add a,(hl)
        and 3
        push af
        call obj_ext_of
        pop af
        ld (hl),a
        ld a,(swap_boss)                ; the first to wake sets the scene
        or a
        jp nz,.frame
        ld a,SND_BOSS
        call music_restart
        ld hl,(cam_x)                   ; the screen locks
        ld (cam_min),hl
        ld a,1
        ld (cam_lock),a
        push ix                         ; the bridge's enemies go
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
.clear:
        ld a,(ix+0)
        cp OBJ_FIREBALL
        jr z,.gone
        cp OBJ_MHEAD
        jr z,.gone
        cp OBJ_ZOMBIE
        jr z,.gone
        cp OBJ_FLEA
        jr c,.keep
        cp OBJ_MUMMY
        jr nc,.keep
.gone:
        ld (ix+0),OBJ_NONE
.keep:
        add ix,de
        djnz .clear
        ld a,1                          ; their patterns: the mummies' now
        call load_swap_patterns
        pop ix
        jp .frame
.awake:
        ld a,(freeze_t)
        or a
        jp nz,.frame
        ld a,(ix+11)                    ; frozen by a hit
        or a
        jr z,.ai
        dec (ix+11)
        jp .frame
.ai:
        ld a,(ix+9)
        cp 2
        jr z,.walk
        jr nc,.standing
        dec (ix+4)                      ; 1: getting up
        jp nz,.frame
.next_walk:
        call knight_face
        call obj_ext_of
        inc (hl)
        ld a,(hl)
        and 3
        ld hl,mummy_walks
        call table_a
        ld (ix+4),a
        ld (ix+9),2
        jp .frame
.standing:
        cp 4
        jr z,.after
        dec (ix+4)                      ; 3: winding up
        jp nz,.frame
        call mummy_throw
        ld (ix+9),4
        ld (ix+4),8
        jp .frame
.after:
        dec (ix+4)                      ; 4: after the throw
        jp nz,.frame
        jr .next_walk
.walk:
        dec (ix+4)
        jr nz,.step
        call knight_face                ; the walk ends: face Simon, wind up
        ld (ix+9),3
        ld (ix+4),40
        jp .frame
.step:
        ld a,(frame_count)              ; every 32 frames: face Simon, and
        and 31                          ; walk away if he faces it near
        jr nz,.move
        call knight_face
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.move
        ld a,l
        cp 56
        jr nc,.move
        ld c,0
        bit 7,(ix+5)
        jr z,.mf
        inc c
.mf:
        ld a,(facing)
        cp c
        jr z,.move
        ld a,(ix+5)
        neg
        ld (ix+5),a
.move:
        call obj_ext_of                 ; 3/4 px a frame
        inc hl
        ld a,(hl)
        add a,0xC0
        ld (hl),a
        jr nc,.clamp
        ld a,(ix+5)
        call move_dir_a
.clamp:
        ld l,(ix+1)                     ; its middle stays on the screen
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        bit 7,h
        jr nz,.to_left
        ld a,h
        or a
        jr nz,.to_right
        ld a,l
        cp 241
        jr c,.frame
.to_right:
        ld hl,(cam_x)
        ld de,240
        add hl,de
        jr .put
.to_left:
        ld hl,(cam_x)
.put:
        ld (ix+1),l
        ld (ix+2),h
.frame:
        call mummy_frame
        ld a,(ix+9)                     ; asleep or getting up: no harm, no hits
        cp 2
        ret c
        call weapon_hits
        jr nc,.touch
        ld a,SND_HIT
        call sfx_play
        call hit_damage                 ; the weapon's damage / 4 (in 1/4s)
        rrca
        rrca
        and 0x3F
        ld b,a
        ld a,(ix+10)
        sub b
        jr nc,.hp
        xor a
.hp:
        ld (ix+10),a
        call mummy_bar
        ld a,(ix+10)
        or a
        jr z,.dead
        ld (ix+11),MUMMY_FREEZE
.touch:
        ld a,24
        ld bc,12*256+34
        jp b3_touch
.dead:
        ld a,SCORE_BOSS
        call add_score
        call mummy_partner              ; the last: the orb after its burn
        ld a,0
        jr nc,.first
        inc a
.first:
        ld (ix+10),a
        ld (ix+9),5
        ld (ix+4),0
        ld a,(ix+3)                     ; burn at its middle
        add a,16
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret
.burning:
        inc (ix+4)
        ld a,(ix+10)
        or a
        jp nz,boss_update.burning
        ld a,(ix+4)                     ; the first: gone after its burn
        cp 60
        jp c,boss_update.burning
        ld (ix+0),OBJ_NONE
        ret

; its walk (NES $67, $68, $69, $68, 17 frames each: 16 here); one picture
; while asleep and getting up, none moving while frozen by a hit
mummy_frame:
        ld a,(ix+9)
        cp 3                            ; winding up: it flickers
        jr nz,.not_wind
        ld a,(frame_count)
        and 2
        jr z,.first
        ld a,OBJF_MUMMY_F
        bit 7,(ix+5)
        jr nz,.fl
        inc a
.fl:
        ld (ix+6),a
        ret
.not_wind:
        ld a,(ix+9)
        cp 2
        jr c,.first
        ld a,(ix+11)
        or a
        ret nz
        ld a,(frame_count)
        rrca
        rrca
        rrca
        rrca
        and 3
        jr z,.first
        cp 3
        jr nz,.other
        ld a,1
.other:
        dec a                           ; 0: picture 2, 1: picture 3
        bit 7,(ix+5)
        jr nz,.l2
        add a,2
.l2:
        add a,OBJF_MUMMY2
        ld (ix+6),a
        ret
.first:
        ld a,OBJF_MUMMY
        bit 7,(ix+5)
        jr nz,.l1
        inc a
.l1:
        ld (ix+6),a
        ret

; Carry if IX's partner is no longer a mummy (not there or burning)
        ASSERT (obj_table & 0xFF) + OBJ_MAX*OBJ_SIZE <= 256
mummy_partner:
        ld c,ixl                        ; (the slots share one 256-byte page)
        push ix
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
.lp:
        ld a,ixl
        cp c
        jr z,.next                      ; (itself)
        ld a,(ix+0)
        cp OBJ_MUMMY
        jr nz,.next
        ld a,(ix+9)
        cp 5
        jr z,.next
        pop ix
        or a                            ; a partner
        ret
.next:
        add ix,de
        djnz .lp
        pop ix
        scf
        ret

; the HUD's bar: both mummies' health (NES $E2D8)
mummy_bar:
        push ix
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
        ld c,0
.lp:
        ld a,(ix+0)
        cp OBJ_MUMMY
        jr nz,.next
        ld a,(ix+9)
        cp 5
        jr z,.next
        ld a,(ix+10)
        rrca
        rrca
        and 0x3F
        add a,c
        ld c,a
.next:
        add ix,de
        djnz .lp
        pop ix
        ld a,c
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        ret

; a bandage from the mummy at IX, at its middle y + 8 (even frames) or - 8,
; towards Simon
mummy_throw:
        push ix
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,(frame_count)
        and 1
        ld a,(ix+3)
        jr nz,.up
        add a,16                        ; (top + 24 + 8 - 8)
.up:
        ld b,a
        call obj_free_slot
        jr c,.none
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+10),b                    ; the wave's centre
        ld (ix+5),c
        ld (ix+0),OBJ_BANDAGE
        ld (ix+4),0
        ld (ix+6),OBJF_BANDAGE
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+11),0
        call obj_ext_of                 ; y fraction 0, vy 1 1/2 px down
        ld (hl),0
        inc hl
        ld (hl),0x80
        inc hl
        ld (hl),1
.none:
        pop ix
        ret

; --- a bandage: 1 1/2 px a frame across, on a spring around its start y
; (wave_y: vy -= (y - centre)/256, y += vy; from 1 1/2 px down: 24 px up and
; down, ~100 frames). Whipped: 100 points; touching Simon it flies on. ---
bandage_update:
        ld a,(freeze_t)
        or a
        jr nz,.hits
        inc (ix+4)
        ld a,0x80
        call step_x_frac
        ld a,(ix+3)                     ; the spring, as Medusa's
        sub (ix+10)
        ld c,a
        sbc a,a
        ld b,a
        call obj_ext_of
        push hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        or a
        sbc hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        pop hl
        ccf
        ld a,(hl)
        adc a,e
        ld (hl),a
        ld a,(ix+3)
        adc a,d
        ld (ix+3),a
        ld a,(ix+4)                     ; frame: 9 frames each
        ld c,0
.div9:
        sub 9
        jr c,.d9
        inc c
        jr .div9
.d9:
        ld a,c
        and 1
        add a,OBJF_BANDAGE
        ld (ix+6),a
        call b3_offscreen
        jp c,obj_gone
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,SCORE_SNAKE
        ld c,2
        jp enemy_killed
.touch:
        ld a,8
        ld bc,6*256+16
        jp b3_touch
