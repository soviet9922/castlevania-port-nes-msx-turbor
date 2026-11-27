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
        jr nc,.late
        cp OBJ_DRAGON
        jr nz,.burst
        push bc
        call dragon_parts_clear         ; (and its parts)
        pop bc
        jr .burst
.late:
        cp OBJ_DEATH                    ; (not Death, his sickles, Dracula)
        jr nc,.next
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
        cp KIND_DRACULA
        jp z,dracula_spawn
        cp KIND_DEATH
        jp z,death_spawn
        cp KIND_AKNIGHT
        jp z,aknight_spawn
        cp KIND_GBAT
        jp z,gbat_spawn
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
        ld a,(ix+0)                     ; blocks 5-7's
        cp OBJ_AKNIGHT
        jp z,aknight_update
        cp OBJ_KAXE
        jp z,kaxe_update
        cp OBJ_GBAT
        jp z,gbat_update
        cp OBJ_DEATH
        jp z,death_update
        cp OBJ_SICKLE
        jp z,sickle_update
        cp OBJ_DRAC
        jp z,dracula_update
        cp OBJ_DEBRIS
        jp z,debris_update
        cp OBJ_EAGLE                    ; block 4's
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
        ld hl,drops_lists               ; by the stage (BCD): 1-3, 4-6, 7-9,
        ld a,(area_hdr+AH_STAGE)        ; 10-12, 13-15, 16-18
        ld b,a
.list:
        ld a,(hl)
        inc hl
        cp b
        jr z,.found
        jr c,.next
.found:
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jr .pick
.next:
        inc hl
        inc hl
        jr .list
.pick:
        add hl,de
        ld a,(hl)
        jr .set
.no_sub:
        ld a,c
        cp 3
        ld a,ITEM_HEART                 ; (the axe knight's: always)
        jr z,.set
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
drops_1012:     db ITEM_SMALLHEART, ITEM_STOPWATCH, ITEM_AXE, ITEM_SMALLHEART
drops_1315:     db ITEM_SMALLHEART, ITEM_STOPWATCH, ITEM_STOPWATCH, ITEM_DAGGER
drops_1618:     db ITEM_SMALLHEART, ITEM_STOPWATCH, ITEM_SMALLHEART, ITEM_SMALLHEART
; the last stage (BCD) of each list
drops_lists:    db 0x03
                dw drops_13
                db 0x06
                dw drops_46
                db 0x09
                dw drops_79
                db 0x12
                dw drops_1012
                db 0x15
                dw drops_1315
                db 0xFF
                dw drops_1618

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


dragon_parts_clear:
        ld hl,part_table
        ld de,part_table+1
        ld bc,6*OBJ_SIZE-1
        ld (hl),0
        ldir
        ret

; a fireball from a 16x16 shooter at (HL = x, E = top) at Simon's middle,
; 1 1/2 px a frame on the long axis (NES shoot_at_simon $EC94), at most 2
fire_at_simon:
        ld a,96                         ; 1 1/2 px, at Simon's middle, at most 2
        ld (fire_speed),a
        ld a,8
        ld (fire_dy),a
        ld a,2
        ld (fire_max),a
; the same with (fire_speed) in 1/64 px (at most 127), the target (fire_dy)
; px below the middle of a 16x16 shooter at Simon's (+ 8), at most
; (fire_max) fireballs out
fire_aimed:
        push hl
        push de
        ld a,OBJ_FIREBALL
        call count_type
        pop de
        pop hl
        push hl
        ld hl,fire_max
        cp (hl)
        pop hl
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
        ld a,(fire_dy)                  ; dy = Simon's middle - its middle
        ld l,a
        ld a,(py)
        add a,l
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
        push af
        ld a,(fire_speed)               ; x long: the speed (1/64 units)
        ld (ix+11),a
        ld e,a
        ld d,0
        pop af
        ld l,b
        call boss_muldiv
        ld a,l
        jr .vy
.ylong:
        ld l,a                          ; y long
        ld a,(fire_speed)
        ld e,a
        ld d,0
        ld a,b
        call boss_muldiv
        ld (ix+11),l
        ld a,(fire_speed)
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

