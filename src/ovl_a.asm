; ---------------------------------------------------------------------------
; RAM overlay A: the enemies only blocks 2-4 have (hanging bat, spear knight,
; Medusa and her snakes, raven, ghost, bone dragon, Frankenstein and Igor, the
; mummies). Copied to OVL_BASE by load_area for stages 4-12 (src/overlays.asm);
; it calls the resident code in src/enemies2.asm and src/objects.asm.
; ---------------------------------------------------------------------------
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
        call weapon_hits                ; (frozen too: every hit counts, NES
        jr nc,.touch                    ; $E1B6)
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
        call hit_damage                 ; half the weapon's damage; holy
        rrca                            ; water's fire 1 every 8 frames
        rrca
        rrca
        and 31
        ld b,a
        ld a,(hit_src)
        cp 3
        jr nz,.sound                    ; (the hit sound: not for the fire)
        ld b,0
        ld a,(frame_count)
        and 7
        jr nz,.dmg
        inc b
        jr .dmg
.sound:
        ld a,SND_HIT
        call sfx_play
.dmg:
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
        ld a,1                          ; his patterns in the corridor
        call load_swap_patterns         ; enemies' place (swap window)
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
        jr z,.there
        xor a                           ; (gone: Z)
        ret
.there:
        or a                            ; (NZ)
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
        call hit_damage                 ; the weapon's damage / 4 (in 1/4s);
        rrca                            ; holy water's fire 1/4 every 4 frames
        rrca
        and 0x3F
        ld b,a
        ld a,(hit_src)
        cp 3
        jr nz,.sub
        ld b,0
        ld a,(frame_count)
        and 3
        jr nz,.sub
        inc b
.sub:
        ld a,(ix+10)
        sub b
        jr nc,.hp
        xor a
.hp:
        ld (ix+10),a
        call mummy_bar
        ld a,(ix+10)                    ; dead when the whole part is 0 (NES
        cp 4                            ; $E2FD)
        jr c,.dead
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
