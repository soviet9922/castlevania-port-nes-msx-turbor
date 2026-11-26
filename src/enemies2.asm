; ---------------------------------------------------------------------------
; Enemies of blocks 2 and 3 and Medusa. This code runs from RAM: it is stored
; in Simon's ROM bank (src/ramcode.asm) and copied to RAMCODE at start-up,
; because bank 0 (the code page) is full. It calls the engine in bank 0 and
; reads the current area's bank at 0x8000 like the rest of the object code.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Block 2's enemies (measured on the NES in stages 4 and 5)
;
; Medusa heads: while a Medusa head spawner is near, every MEDUSA_EVERY frames
; one starts at the screen edge Simon faces (as the NES: x $F8 or $08) and flies
; at him 5 px every 4 frames, in a wave around his height: 34 px up and down,
; every 100 frames, starting at the top. One whip hit, 300 points; touching
; Simon hurts him (8) and the head is gone.
;   +4 timer   +5 direction   +9 centre y   +10 x fraction
; ---------------------------------------------------------------------------
medusa_spawner:
        ld hl,medusa_t
        inc (hl)
        ld a,(hl)
        cp MEDUSA_EVERY
        ret c
        ld (hl),0
        ld a,(stair_state)              ; (NES: not while Simon is on the stairs)
        ld hl,hurt_state
        or (hl)
        ret nz
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
        ld a,c
        cp MEDUSA_MAX
        ret nc
        call obj_free_slot
        ret c
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
        ld a,(py)                       ; wave centre: Simon's head
        add a,7
        ld (ix+9),a
        ld (ix+0),OBJ_MHEAD
        ld (ix+4),0
        ld (ix+7),KIND_BAT              ; 16x16 box
        ld (ix+8),0xFF
        ld (ix+10),0
        jr mhead_place

mhead_update:
        ld a,(freeze_t)                 ; the stopwatch holds it
        or a
        jp nz,bat_update.checks
        inc (ix+4)
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
        ld a,(ix+4)                     ; y: centre - 34 cos(2 pi t / 100)
.mod100:
        sub 100
        jr nc,.mod100
        add a,100
        ld e,a
        ld d,0
        ld hl,mhead_wave
        add hl,de
        ld a,(ix+9)
        add a,(hl)
        ld (ix+3),a
        ld a,(ix+4)                     ; frame: 8 frames each
        rrca
        rrca
        rrca
        and 1
        bit 7,(ix+5)
        jr nz,.left
        add a,2
.left:
        add a,OBJF_MHEAD
        ld (ix+6),a
        jp bat_update.checks

; -34 cos(2 pi t / 100)
mhead_wave:
        db -34, -34, -34, -33, -33, -32, -32, -31, -29, -28
        db -27, -26, -24, -22, -21, -19, -17, -15, -13, -11
        db -9, -7, -4, -2, 0, 0, 2, 4, 7, 9
        db 11, 13, 15, 17, 19, 21, 22, 24, 26, 27
        db 28, 29, 31, 32, 32, 33, 33, 34, 34, 34
        db 34, 34, 34, 33, 33, 32, 32, 31, 29, 28
        db 27, 26, 24, 22, 21, 19, 17, 15, 13, 11
        db 9, 7, 4, 2, 0, 0, -2, -4, -7, -9
        db -11, -13, -15, -17, -19, -21, -22, -24, -26, -27
        db -28, -29, -31, -32, -32, -33, -33, -34, -34, -34

; ---------------------------------------------------------------------------
; Hanging bat (object $07): hangs under the ceiling until Simon is within
; HBAT_WAKE px across and HBAT_WAKE_DY px of its height, then flies at him 3 px every 2 frames across, dropping about
; 30 px to his height (the recorded steps, hbat_drop), and on. Like the stage 2
; bat, touching Simon hurts him and the bat is gone; once awake it never comes
; back. +9 = state (0 hanging, 1 flying), +10 = x fraction, +11 = drop step.
; ---------------------------------------------------------------------------
hbat_update:
        ld a,(ix+9)
        or a
        jr nz,.flying
        call simon_dx                   ; HL = Simon centre - bat centre
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
        jr nz,.hang
        ld a,l
        cp HBAT_WAKE
        jr nc,.hang
        ld a,(freeze_t)
        or a
        jr nz,.hang
        ld a,(py+1)                     ; and near its height (NES: it stays
        or a                            ; put while Simon is on the floor below)
        jr nz,.hang
        ld a,(py)
        sub (ix+3)
        jr nc,.dy
        neg
.dy:
        cp HBAT_WAKE_DY
        jr nc,.hang
        ld (ix+9),1                     ; awake: it never comes back
        ld (ix+4),0
        ld (ix+11),0
        ld a,(ix+8)
        cp 0xFF
        jr z,.flying
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
        jr .flying
.hang:
        ld (ix+6),OBJF_HBAT_HANG
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

hbat_drop:
        db 1, 1, 2, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1
        db 0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1
hbat_drop_end:

; ---------------------------------------------------------------------------
; Spear knight (object $08): paces its floor at 1/2 px per frame and turns to
; face Simon every 192-255 frames (NES: 200-260), and at the edge of its floor
; or a wall. KNIGHT_HP whip hits kill it (400 points); after a hit it can't be
; hit again for KNIGHT_FLASH frames. Touching it hurts Simon (8).
;   +4 timer  +5 direction  +9 hits taken  +10 frames to the next turn
;   +11 frames it can't be hit
; ---------------------------------------------------------------------------
knight_update:
        ld a,(freeze_t)
        or a
        jr nz,.hits
        inc (ix+4)
        dec (ix+10)
        jr nz,.no_turn
        ld a,(frame_count)
        and 63
        add a,KNIGHT_TURN
        ld (ix+10),a
        call simon_dx                   ; face Simon
        ld (ix+5),1
        bit 7,h
        jr z,.no_turn
        ld (ix+5),-1
.no_turn:
        ld a,(ix+4)                     ; a step every other frame
        and 1
        jr z,.frame
        call knight_blocked             ; floor ends or a wall: turn round
        jr nc,.step
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jr .frame
.step:
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
.frame:
        call knight_frame
.hits:
        ld a,(ix+11)
        or a
        jr z,.can_hit
        dec (ix+11)
        jr .touch
.can_hit:
        call weapon_hits
        jr nc,.touch
        ld a,SND_HIT
        call sfx_play
        inc (ix+9)
        ld a,(ix+9)
        cp KNIGHT_HP
        jr nc,.dead
        ld (ix+11),KNIGHT_FLASH
        jr .touch
.dead:
        ld a,(ix+8)                     ; it stays dead
        cp 0xFF
        jr z,.burst
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
.burst:
        ld a,SCORE_KNIGHT
        call add_score
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ret
.touch:
        jp zombie_update.touch

; Carry if the knight at IX can't step on: no floor ahead of its feet, or a
; wall ahead at its waist
knight_blocked:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8+4                       ; 4 px ahead of its middle
        bit 7,(ix+5)
        jr z,.ahead
        ld de,8-4
.ahead:
        add hl,de
        push hl
        ld a,(ix+3)
        add a,32
        ld e,a
        ld d,0
        call solid_at
        pop hl
        ccf
        ret c                           ; no floor there
        ld de,4                         ; a wall: 8 px ahead at its waist
        bit 7,(ix+5)
        jr z,.wall
        ld de,-4
.wall:
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        jp solid_at

; the zombie's frames (block 2's graphics have the knight there): legs every
; 16 frames, +2 facing right
knight_frame:
        ld a,(ix+4)
        rrca
        rrca
        rrca
        rrca
        and 1
        bit 7,(ix+5)
        jr nz,.left
        add a,2
.left:
        add a,OBJF_ZOMBIE
        ld (ix+6),a
        ret

; ---------------------------------------------------------------------------
; Medusa (stage 6 boss, recorded on the NES). Asleep she is the statue in the
; map. When Simon comes within MEDUSA_WAKE px and the screen has reached her
; room at the area's left end, she wakes: the statue's tiles go
; blank, the screen locks, the boss music starts and her first snake drops.
; She drifts 7 px every 8 frames, bobbing along the bat's 96-frame wave, turns
; at the room's edges and follows Simon's height; every 150-277 frames she
; stops for MEDUSA_PAUSE frames and drops a snake. Health in the HUD's enemy bar
; (MEDUSA_DAMAGE a whip hit); beaten, she burns and leaves the orb (as the
; stage 3 boss: boss_update's hit, burn and orb code).
;   +4 timer  +9 state (0 asleep, 1 flying, 2 stopped, 4 burning)
;   +10 the wave's top y  +5 direction
; ---------------------------------------------------------------------------
medusa_update:
        inc (ix+4)
        ld a,(boss_inv)
        or a
        jr z,.no_inv
        dec a
        ld (boss_inv),a
.no_inv:
        ld a,(ix+9)
        cp 4
        jp z,boss_update.burning
        ld a,(ix+4)                     ; her two pictures, 8 frames each
        rrca
        rrca
        rrca
        and 1
        add a,OBJF_MEDUSA
        ld (ix+6),a
        ld a,(ix+9)
        or a
        jr nz,.awake
        call boss_simon_dx              ; asleep: Simon near?
        bit 7,h
        jr z,.pos
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
        cp MEDUSA_WAKE
        ret nc
        ld hl,(cam_x)                   ; and the screen is at her room (the
        ld de,(area_hdr+AH_MINCAM)      ; area's left end)
        or a
        sbc hl,de
        ret nz
        ld a,SND_BOSS                   ; awake
        call music_restart
        ld hl,(cam_x)                   ; the screen locks
        ld (cam_min),hl
        ld (area_hdr+AH_MAXCAM),hl
        ld a,1
        ld (cam_lock),a
        ld l,(ix+1)                     ; the statue's tiles: 4 x 3 from
        ld h,(ix+2)                     ; box x + 8, y + 9
        ld de,8
        add hl,de
        call hl_shr3
        ld (med_col),hl
        ld a,(ix+3)
        add a,9
        rrca
        rrca
        rrca
        and 31
        ld (med_row),a
        ld a,1
        ld (med_erase),a
        ld a,(ix+3)
        ld (ix+10),a
        call boss_simon_dx              ; first towards Simon
        ld (ix+5),1
        bit 7,h
        jr z,.dir
        ld (ix+5),-1
.dir:
        ld (ix+9),1
        ld (ix+4),0
        call medusa_next_pause
        call snake_drop
        jp boss_update.hits

.awake:
        cp 2
        jr z,.stopped
        ld hl,med_t                     ; flying
        dec (hl)
        jr nz,.fly
        ld (ix+9),2
        ld (hl),MEDUSA_PAUSE
        jr .wave
.fly:
        ld a,(ix+4)                     ; x: 7 px every 8 frames
        and 7
        cp 7
        jr z,.edges
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
        ld l,(ix+1)                     ; turn at the room's edges
        ld h,(ix+2)
        ld de,24
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de                       ; HL = her centre on the screen
        ld a,h
        or a
        jr nz,.go_left
        ld a,l
        cp MEDUSA_LEFT
        jr nc,.not_left
        ld (ix+5),1
        jr .wave
.not_left:
        cp MEDUSA_RIGHT
        jr c,.wave
.go_left:
        ld (ix+5),-1
        jr .wave

.stopped:
        ld hl,med_t
        dec (hl)
        ld a,(hl)
        cp MEDUSA_PAUSE/2
        call z,snake_drop
        ld a,(med_t)
        or a
        jr nz,.wave
        ld (ix+9),1
        call medusa_next_pause

.wave:
        ld a,(ix+4)                     ; follow Simon's height, 1 px every
        and 7                           ; 8 frames
        jr nz,.no_follow
        ld a,(py)
        sub 4
        cp (ix+10)
        jr z,.no_follow
        jr c,.up
        inc (ix+10)
        jr .no_follow
.up:
        dec (ix+10)
.no_follow:
        ld a,(ix+4)                     ; y: the wave's top + bat wave
.mod96:
        sub 96
        jr nc,.mod96
        add a,96
        ld e,a
        ld d,0
        ld hl,bat_wave
        add hl,de
        ld a,(ix+10)
        add a,(hl)
        ld (ix+3),a
        jp boss_update.hits

medusa_next_pause:
        ld a,(frame_count)
        and 127
        add a,150
        ld (med_t),a
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
; Snake (Medusa's): falls to the floor, then slides at Simon 3 px every 2
; frames. One whip hit; touching Simon hurts him.
;   +9 state (0 falling, 1 sliding)  +10 fall speed / x fraction  +11 fraction
; ---------------------------------------------------------------------------
snake_update:
        inc (ix+4)
        ld a,(ix+9)
        or a
        jr nz,.slide
        ld a,(ix+10)                    ; falling: vy += 2/16, y += vy / 16
        add a,2
        cp 64
        jr c,.vy
        ld a,64
.vy:
        ld (ix+10),a
        add a,(ix+11)
        ld c,a
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,(ix+3)
        ld (ix+3),a
        ld a,c
        and 15
        ld (ix+11),a
        ld a,(ix+3)
        cp MT_ROWS*16
        jp nc,.gone
        call snake_ground
        jr nc,.frame
        ld a,(ix+3)                     ; on the floor: slide at Simon
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+9),1
        ld (ix+10),0
        call simon_dx
        ld de,8                         ; (simon_dx is for a 32-wide box)
        add hl,de
        ld (ix+5),1
        bit 7,h
        jr z,.frame
        ld (ix+5),-1
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

; VBLANK: Medusa woke: her statue's 4 x 3 tiles go blank
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
        ld c,3
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
        ld a,(ix+0)                     ; the mummies and their bandages
        cp OBJ_MUMMY
        jp z,mummy_update
        cp OBJ_BANDAGE
        jp z,bandage_update
        ld a,(freeze_t)                 ; the stopwatch holds them
        or a
        jp nz,block3_hits
        inc (ix+4)
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

; --- fleaman ---
flea_update:
        ld a,(ix+9)
        or a
        jr nz,.awake
        call wake_near
        jr nz,.done
        ld (ix+9),2                     ; hop at once
        ld (ix+4),FLEA_REST-1
.awake:
        cp 1
        jr z,.air
        ld a,(ix+4)                     ; 2: on the floor, then a hop at him
        cp FLEA_REST
        jr c,.done
        call wake_near                  ; (sets the direction)
        ld (ix+9),1
        ld (ix+10),FLEA_VY0
        ld (ix+11),0
.air:
        ld a,(ix+5)                     ; 1 px across
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,FLEA_GRAVITY
        call fall_step
        jp c,obj_gone
        bit 7,(ix+10)
        jr nz,.done                     ; going up
        call snake_ground               ; landed?
        jr nc,.done
        ld a,(ix+3)
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+9),2
        ld (ix+4),0
.done:
        call block3_frame
        jp block3_hits

; --- raven ---
raven_update:
        ld a,(ix+9)
        or a
        jr nz,.awake
        call wake_near
        jp nz,.done
        ld (ix+9),1
        ld a,(py)                       ; swoop to his head's height
        sub 12
        ld (ix+10),a
.awake:
        cp 1
        jr nz,.not_swoop
        ld a,0xC0                       ; 3/4 px across and down a frame
        call .frac_step
        ld a,(ix+4)
        and 3
        jr z,.down2
        inc (ix+3)
.down2:
        ld a,(ix+3)
        cp (ix+10)
        jr c,.done
        ld (ix+9),2
        ld (ix+4),0
        jr .done
.not_swoop:
        cp 2
        jr nz,.chase
        ld a,(ix+4)                     ; 2: hovering
        cp RAVEN_HOVER
        jr c,.done
        ld (ix+9),3
        ld (ix+10),0                    ; speed, 1/16 px per frame (signed)
.chase:
        call simon_dx                   ; 3: speeds up towards Simon
        ld de,8
        add hl,de
        ld a,(ix+10)
        bit 7,h
        jr nz,.left
        cp 48
        jr z,.move
        inc a
        jr .set
.left:
        cp -48
        jr z,.move
        dec a
.set:
        ld (ix+10),a
.move:
        ld a,(ix+10)                    ; x += speed / 16
        ld (ix+5),1
        or a
        jp p,.right
        ld (ix+5),-1
.right:
        sra a
        sra a
        sra a
        sra a
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
.done:
        call block3_frame
        jp block3_hits
.frac_step:
        ld c,a
        ld a,(ix+11)
        add a,c
        ld (ix+11),a
        ret nc
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
        ret

; --- ghost ---
ghost_update:
        ld a,(ix+9)
        or a
        jr nz,.awake
        call wake_near
        jr nz,.hide
        ld (ix+9),1
        call mark_dead                  ; one ghost, once
.awake:
        ld a,(ix+4)                     ; 3 px every 4 frames on both axes
        and 3
        jr z,.done
        call wake_near                  ; (direction to him)
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
        ld a,(py)
        add a,8
        cp (ix+3)
        jr z,.done
        jr c,.up
        inc (ix+3)
        jr .done
.up:
        dec (ix+3)
.done:
        call block3_frame
        jp block3_hits
.hide:
        ret                             ; (not drawn until it appears: see block3_frame)

; --- skeleton ---
skel_update:
        dec (ix+10)                     ; face Simon now and then
        jr nz,.no_turn
        ld a,(frame_count)
        and 63
        add a,96
        ld (ix+10),a
        call wake_near
.no_turn:
        ld a,(ix+4)                     ; 3 px every 4 frames
        and 3
        jr z,.throw
        call knight_blocked
        jr nc,.step
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jr .throw
.step:
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
.throw:
        ld a,(ix+4)
        cp SKEL_THROW
        jr c,.done
        ld (ix+4),0
        push ix                         ; a bone, up and towards Simon
        call wake_near
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        ld b,(ix+3)
        call obj_free_slot
        jr c,.no_bone
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+5),c
        ld (ix+0),OBJ_BONE
        ld (ix+4),0
        ld (ix+6),OBJF_BONE
        ld (ix+7),KIND_FIREBALL         ; small box
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),BONE_VY0
        ld (ix+11),0
.no_bone:
        pop ix
.done:
        call knight_frame               ; (the zombie's frames, as the knight)
        jp block3_hits

; --- bone: up and across under gravity; hurts Simon, can't be whipped ---
bone_update:
        ld a,(ix+4)                     ; 3 px every 4 frames across
        and 3
        jr z,.no_dx
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
.no_dx:
        ld a,2
        call fall_step
        jp c,obj_gone
        ld l,(ix+1)                     ; off the screen: gone
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        bit 7,h
        jp nz,obj_gone
        ld de,256+16+1
        or a
        sbc hl,de
        jp nc,obj_gone
        jp bat_update.touch

; --- bone pillar ---
pillar_update:
        ld a,(ix+4)                     ; fireballs at 0 and 40 of each cycle
        or a
        jr z,.fire
        cp 40
        jr z,.fire
        cp PILLAR_EVERY
        jr c,.done
        ld (ix+4),0
.fire:
        call wake_near                  ; (Simon's side)
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
        add a,4
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
.done:
        ld (ix+6),OBJF_PILLAR
        jp block3_hits

; frame by kind and direction
block3_frame:
        ld a,(ix+0)
        ld c,OBJF_FLEA
        cp OBJ_FLEA
        jr z,.lr
        ld c,OBJF_GHOST
        cp OBJ_GHOST
        jr z,.lr
        cp OBJ_SKEL
        jp z,knight_frame
        cp OBJ_RAVEN
        jr nz,.pillar
        ld a,(ix+9)
        or a
        ld a,OBJF_RAVEN_PERCH
        jr z,.set
        ld a,(ix+4)                     ; wings: 3 pictures, 8 frames each
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
        ld a,OBJF_PILLAR
        jr .set
.lr:
        ld a,c
        bit 7,(ix+5)
        jr nz,.set
        inc a
.set:
        ld (ix+6),a
        ret

; whip hits (HP in +11 for the ghost and the pillar: hits taken, with the
; stage 2 bat's... no: their own flash in the high bits of +9), touching Simon
block3_hits:
        ld a,(ix+0)
        cp OBJ_GHOST
        jr nz,.not_ghost
        ld a,(ix+9)                     ; a ghost not out yet: nothing
        or a
        ret z
        ld b,GHOST_HP
        jr .tough
.not_ghost:
        cp OBJ_PILLAR
        jr nz,.one_hit
        ld b,PILLAR_HP
.tough:
        call obj_hits_of                ; HL = this slot's hit counter
        ld a,(hl)
        and 0x1F
        jr z,.can_hit
        dec (hl)                        ; flash running
        jp .touch
.can_hit:
        push hl
        push bc
        call weapon_hits
        pop bc
        pop hl
        jp nc,.touch
        ld a,SND_HIT
        call sfx_play
        ld a,(hl)
        add a,0x20                      ; one more hit taken
        ld c,a
        rlca
        rlca
        rlca
        and 7
        cp b
        jr nc,.dead
        ld a,c
        or 16                           ; 16 frames before the next can count
        ld (hl),a
        jp .touch
.one_hit:
        call weapon_hits
        jp nc,.touch
.dead:
        call mark_dead
        ld a,(ix+0)
        sub OBJ_FLEA
        ld e,a
        ld d,0
        ld hl,block3_scores
        add hl,de
        ld a,(hl)
        call add_score
        ld a,SND_HIT
        call sfx_play
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ret
.touch:
        ld l,(ix+1)                     ; off the screen far: gone (fleaman,
        ld h,(ix+2)                     ; raven; placed ones come back later)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,48
        add hl,de
        bit 7,h
        jp nz,obj_gone
        ld de,256+96+1
        or a
        sbc hl,de
        jp nc,obj_gone
        ld a,(ix+7)
        cp KIND_BAT
        jp nz,zombie_update.touch       ; 16x32: as the zombie
        jp zombie_update.touch          ; (16x16 boxes: close enough)
; HL = obj_hits + the slot index of IX (B kept)
obj_hits_of:
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
        ld e,c
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
; The mummies (stage 9 boss, recorded on the NES). Two, placed in the tower
; room, asleep until the screen reaches the room (the area's last screen):
; then the screen locks, the boss music plays, the bridge's enemies go and
; their sprite patterns make way for the mummies' (swap window, set 1). Each
; walks 3 px every 4 frames, faces Simon every MUMMY_TURN frames and at the
; screen's edges, and throws a bandage at him every 128 frames. Each has
; MUMMY_HP; the HUD's enemy bar shows both together. Beaten, a mummy bursts
; (3000 points); the last one burns and leaves the orb (boss_update.burning).
;   +4 timer  +5 direction  +9 state (0 asleep, 1 awake, 4 burning)
;   +10 health  +11 frames it can't be hit
; ---------------------------------------------------------------------------
mummy_spawn:
        ld (ix+7),KIND_BRAZIER          ; 16x32 box from its top (its body)
        ld (ix+10),MUMMY_HP
        ld (ix+11),0
        ld (ix+6),OBJF_MUMMY
        ld a,MUMMY_HP*2
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        ret

mummy_update:
        inc (ix+4)
        ld a,(ix+9)
        cp 4
        jp z,boss_update.burning
        or a
        jr nz,.awake
        ld hl,(cam_x)                   ; asleep until the screen is at the room
        ld de,(area_hdr+AH_MAXCAM)
        or a
        sbc hl,de
        jp nz,.frame
        ld (ix+9),1
        ld (ix+4),0
        ld a,(swap_boss)                ; the first to wake sets the scene
        or a
        jr nz,.awake
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
.awake:
        ld a,(freeze_t)
        or a
        jp nz,.frame
        ld a,(ix+4)                     ; face Simon now and then
        and MUMMY_TURN-1
        call z,wake_near
        ld a,(ix+4)                     ; 3 px every 4 frames
        and 3
        jr z,.throw
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
        ld de,(cam_x)                   ; turn at the screen's edges
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.throw
        ld a,l
        cp 16
        jr nc,.not_left
        ld (ix+5),1
        jr .throw
.not_left:
        cp 256-32
        jr c,.throw
        ld (ix+5),-1
.throw:
        ld a,(ix+8)                     ; a bandage at Simon every 128 frames
        rrca                            ; (the two mummies, by their place in
        rrca                            ; the list, half a cycle apart)
        and 0x40
        add a,(ix+4)
        and 127
        cp 64
        jr nz,.frame
        call wake_near
        push ix
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,(ix+3)
        add a,16
        ld b,a
        call obj_free_slot
        jr c,.no_bandage
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+10),b                    ; (the wave's top)
        ld (ix+5),c
        ld (ix+0),OBJ_BANDAGE
        ld (ix+4),0
        ld (ix+6),OBJF_BANDAGE
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+11),0
.no_bandage:
        pop ix
.frame:
        ld a,OBJF_MUMMY
        bit 7,(ix+5)
        jr nz,.left
        inc a
.left:
        ld (ix+6),a
        ld a,(ix+9)                     ; asleep: no harm, no hits
        or a
        ret z
        ld a,(ix+11)                    ; hit
        or a
        jr z,.can_hit
        dec (ix+11)
        jp zombie_update.touch
.can_hit:
        call weapon_hits
        jp nc,zombie_update.touch
        ld a,SND_HIT
        call sfx_play
        ld (ix+11),16
        ld a,1
        ld (hud_dirty),a
        ld a,(boss_hp)                  ; the bar: both together
        sub MUMMY_DAMAGE
        jr nc,.bar
        xor a
.bar:
        ld (boss_hp),a
        ld a,(ix+10)
        sub MUMMY_DAMAGE
        jr z,.dead
        jr c,.dead
        ld (ix+10),a
        ret
.dead:
        ld a,SCORE_BOSS
        call add_score
        ld a,(boss_hp)                  ; the last one: it burns, leaves the orb
        or a
        jr z,.last
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ret
.last:
        ld (ix+9),4
        ld (ix+4),0
        ld a,(ix+3)                     ; burn at its middle
        add a,16
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret

; --- a bandage: across at 1 1/2 px a frame, in an 18-px wave ---
bandage_update:
        inc (ix+4)
        ld a,0x80
        call step_x_frac
        ld a,(ix+4)
.mod96:
        sub 96
        jr nc,.mod96
        add a,96
        ld e,a
        ld d,0
        ld hl,bat_wave
        add hl,de
        ld a,(ix+10)
        add a,(hl)
        sub 9
        ld (ix+3),a
        ld a,(ix+4)
        rrca
        rrca
        rrca
        and 1
        add a,OBJF_BANDAGE
        ld (ix+6),a
        jp bat_update.checks

