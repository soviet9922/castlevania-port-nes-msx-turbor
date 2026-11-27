; ---------------------------------------------------------------------------
; RAM overlay B: the enemies only blocks 5-7 have (stages 13-18). Copied to
; OVL_BASE by load_area (src/overlays.asm); it calls the resident code in
; src/enemies2.asm and src/objects.asm.
; ---------------------------------------------------------------------------

; --- the axe knight (NES record $4A 6:$89F5, object $0A 5:$90D2, hits $E214).
; At most two. It appears when its place's middle is on the screen (NES
; screen x 8..248), always faces Simon, and walks in cycles of 9/11/10/12
; legs (random): a leg is 16 frames at 5/8 px (15 moving), then 4 still; each
; leg goes towards Simon if he is 80 px or more away, else away from him. A
; wall 12 px ahead at its waist or no floor 4 px ahead turns it at once. After
; the last leg it stands 16 frames and throws an axe (high or low, random).
; A page away from the camera it stands. Its guard: a whip hit face to face, or
; a sub-weapon from the front, only adds to the guard (a clink) until 224;
; then hits count, and 64 kill it (500, always a big heart; a hit freezes it
; 16 frames, a sub-weapon hit 8 first).
;   +4 timer  +5 facing (+1/-1)  +9 state (0 not out, 1 new cycle, 2 walking,
;   3 pausing, 4 before the throw; bit 7: walking left)  +10 legs left
;   +11 frozen frames  obj_ext: x fraction, guard ($FF broken), picture
;   timer, picture  obj_hits: damage taken
; ---------------------------------------------------------------------------
AKNIGHT_GUARD   equ 224
AKNIGHT_HP      equ 64

; IX = new object (spawn_candle)
aknight_spawn:
        push ix
        ld a,OBJ_AKNIGHT
        call count_type
        pop ix
        cp 2
        jp nc,obj_release               ; (NES slots 7-8: try again later)
        ld (ix+0),OBJ_AKNIGHT
        ld (ix+7),KIND_AKNIGHT          ; 12x28 box at +2, +2
        ld (ix+6),OBJF_AKNIGHT
        xor a
        ld (ix+9),a
        ld (ix+11),a
        ld (ix+5),-1
        call obj_hits_of
        ld (hl),0
        jp b5_ext_clear

; obj_ext of IX = 0, 0, 0, 0
b5_ext_clear:
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ret

aknight_update:
        ld a,(ix+9)
        or a
        jr nz,.out
        call b3_offscreen               ; out when its middle is on the screen
        ret c
        ld (ix+9),1
.out:
        ld a,(freeze_t)                 ; the stopwatch
        or a
        jp nz,.hits
        ld a,(ix+11)
        or a
        jr z,.go
        dec (ix+11)
        jp .hits
.go:
        call knight_face
        call aknight_anim
        ld a,(ix+9)
        and 7
        dec a
        jr nz,.s2
        call rng_and3                   ; a new cycle: 9-12 legs
        ld hl,aknight_legs
        call table_a
        ld (ix+10),a
.pick:
        ld hl,(px)                      ; 80 px or more away: towards Simon
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld b,(ix+5)
        ld a,h
        or a
        jr nz,.dir
        ld a,l
        cp 80
        jr nc,.dir
        ld a,b                          ; nearer: away from him
        neg
        ld b,a
.dir:
        ld a,2
        bit 7,b
        jr z,.dset
        or 0x80
.dset:
        ld (ix+9),a
        ld (ix+4),16
        jp .cull
.s2:
        dec a
        jr nz,.s3
        call b5_far_page                ; a page away: it stands
        jr nc,.near
        ld b,3
        ld c,4
        jp .state
.near:
        dec (ix+4)
        jr nz,.walk
        dec (ix+10)
        ld b,3                          ; legs left: a pause
        ld c,4
        jr nz,.state
        ld b,4                          ; none: stand, then throw
        ld c,16
        jr .state
.walk:
        ld de,8+12                      ; a wall 12 px ahead at its waist
        bit 7,(ix+9)
        jr z,.wr
        ld de,8-12
.wr:
        ld a,16
        call knight_probe
        jr c,.turn
        ld de,8+4                       ; floor 4 px ahead of its feet
        bit 7,(ix+9)
        jr z,.fr
        ld de,8-4
.fr:
        ld a,32
        call knight_probe
        jr c,.move
.turn:
        ld a,(ix+9)
        xor 0x80
        ld (ix+9),a
.move:
        call obj_ext_of                 ; 5/8 px a frame
        ld a,(hl)
        add a,0xA0
        ld (hl),a
        jr nc,.cull
        ld a,1
        bit 7,(ix+9)
        jr z,.mv
        ld a,-1
.mv:
        call move_dir_a
        jr .cull
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; pausing
        jr nz,.cull
        jp .pick
.s4:
        dec (ix+4)                      ; standing before the throw
        jr nz,.cull
        call aknight_throw
        ld b,1
        ld c,0
.state:                                 ; state B (keeps the direction), timer C
        ld a,(ix+9)
        and 0x80
        or b
        ld (ix+9),a
        ld (ix+4),c
.cull:
        call b5_cull64
        ret c
.hits:
        call b3_offscreen               ; (off the screen: no collision)
        ret c
        call weapon_hits
        jp nc,.touch
        ld a,(hit_src)
        or a
        jr nz,.sub
        ld a,(facing)                   ; the whip: face to face, guarded
        or a
        ld a,-1
        jr z,.wf
        ld a,1
.wf:
        cp (ix+5)
        jr z,.guard
        jr .damage
.sub:
        ld (ix+11),8                    ; a sub-weapon: 8 frames first
        cp 3
        jr z,.damage                    ; (the holy water's fire)
        ld hl,(hit_x1)                  ; from behind: damage
        ld de,(hit_x2)
        add hl,de
        srl h
        rr l                            ; HL = the weapon's middle
        ld e,(ix+1)
        ld d,(ix+2)
        inc de
        inc de
        inc de
        inc de
        inc de
        inc de
        inc de
        inc de                          ; DE = the knight's middle
        or a
        sbc hl,de                       ; weapon - knight
        bit 7,(ix+5)
        jr nz,.fl
        bit 7,h                         ; facing right: weapon <= knight: behind
        jr nz,.damage
        ld a,h
        or l
        jr z,.damage
        jr .front
.fl:
        bit 7,h                         ; facing left: weapon > knight: behind
        jr nz,.front
        ld a,h
        or l
        jr nz,.damage
.front:
        ld a,(hit_src)                  ; the axe drops straight down
        cp 2
        call z,b5_axe_drop
.guard:
        call obj_ext_of
        inc hl
        ld a,(hl)
        cp 0xFF
        jr z,.damage                    ; broken
        push hl
        call hit_damage
        pop hl
        add a,(hl)
        jr c,.broken
        cp AKNIGHT_GUARD
        jr c,.gset
.broken:
        ld a,0xFF
.gset:
        ld (hl),a
        ld a,SND_HIT                    ; (the NES's clink)
        jp sfx_play
.damage:
        call hit_damage
        ld b,a
        call obj_hits_of
        ld a,(hl)
        add a,b
        jr c,.dead
        cp AKNIGHT_HP
        jr nc,.dead
        ld (hl),a
        ld (ix+11),16
        ld a,SND_HIT
        jp sfx_play
.dead:
        call mark_dead
        ld a,SCORE_AKNIGHT
        ld c,3                          ; always a big heart
        jp enemy_killed
.touch:
        ld a,16
        ld bc,10*256+26
        jp b3_touch
aknight_legs:   db 9, 11, 10, 12

; its two pictures, 17 frames each (stopped while it is frozen)
aknight_anim:
        call obj_ext_of
        inc hl
        inc hl
        inc (hl)
        ld a,(hl)
        cp 17
        jr c,.pic
        ld (hl),0
        inc hl
        ld a,(hl)
        xor 1
        ld (hl),a
        dec hl
.pic:
        inc hl
        ld a,(hl)
        bit 7,(ix+5)
        jr nz,.l
        add a,2
.l:
        add a,OBJF_AKNIGHT
        ld (ix+6),a
        ret

; Carry if the middle of IX is a page away from the camera (screen x outside
; 0..255)
b5_far_page:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        ret z
        scf
        ret

; Gone (and made again when its place is near) if its middle is more than 64
; px beyond either screen edge: carry if so
b5_cull64:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,8+64
        add hl,de
        bit 7,h
        jr nz,.gone
        ld de,256+128
        or a
        sbc hl,de
        ccf
        ret nc
.gone:
        call obj_release
        scf
        ret

; Simon's flying axe stops going across (it drops straight down)
b5_axe_drop:
        push ix
        ld ix,obj_table
        ld b,OBJ_MAX
        ld de,OBJ_SIZE
.lp:
        ld a,(ix+0)
        cp OBJ_AXE
        jr nz,.nx
        ld (ix+5),0
.nx:
        add ix,de
        djnz .lp
        pop ix
        ret

; the knight at IX throws an axe: from its middle, at its head (top - 5) or
; its knees (top + 15) at random, towards Simon, 1 1/4 px a frame
aknight_throw:
        call obj_slot
        ld d,a                          ; D = the thrower's slot
        ld a,(rng)
        rrca
        ld a,(ix+3)
        jr c,.low
        sub 5
        jr .y
.low:
        add a,15
.y:
        ld b,a
        ld c,(ix+5)
        ld l,(ix+1)
        ld h,(ix+2)
        push ix
        call obj_free_slot
        jr c,.none
        ld (ix+0),OBJ_KAXE
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+4),88
        ld (ix+5),c
        ld (ix+6),OBJF_AXE
        ld (ix+7),KIND_FIREBALL         ; 8x8 box at +4, +4
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),10                   ; 1 1/4 px (in 1/8)
        ld (ix+11),d
        call b5_ext_clear
.none:
        pop ix
        ret

; --- its axe (NES object $27 5:$8DEE): 87 frames out at 1 1/4 px, slows by
; 1/8 px a frame, turns, speeds up again and flies back at the same height;
; the thrower's slot catches it within 16 px. Whippable (100).
;   +4 timer  +5 direction  +9 state (0 out, 1 slowing, 2 speeding up,
;   3 back)  +10 speed (1/8 px)  +11 the thrower's slot
;   obj_ext: x fraction, picture timer
kaxe_update:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+9)
        or a
        jr nz,.k1
        dec (ix+4)                      ; out
        jr z,.to1
        call kaxe_move
        jp .after
.to1:
        ld (ix+9),1
        jp .after
.k1:
        dec a
        jr nz,.k2
        ld a,(ix+10)                    ; slowing
        sub 1
        jr nc,.slow
        ld a,(ix+5)                     ; turns round
        neg
        ld (ix+5),a
        ld (ix+10),0
        ld (ix+9),2
        jr .after
.slow:
        ld (ix+10),a
        call kaxe_move
        jr .after
.k2:
        dec a
        jr nz,.k3
        inc (ix+10)                     ; speeding up again
        call kaxe_move
        ld a,(ix+10)
        cp 10
        jr c,.after
        ld (ix+9),3
        jr .after
.k3:
        call kaxe_move                  ; back: caught?
        ld a,(ix+11)
        ld b,a
        add a,a
        add a,b
        add a,a
        add a,a                         ; * 12
        ld e,a
        ld d,0
        ld iy,obj_table
        add iy,de
        ld a,(iy+0)
        or a
        jr z,.after
        ld a,(iy+3)                     ; |axe middle - its middle| < 16
        add a,16-8
        sub (ix+3)
        jp p,.dy
        neg
.dy:
        cp 16
        jr nc,.after
        ld l,(ix+1)
        ld h,(ix+2)
        ld e,(iy+1)
        ld d,(iy+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.after
        ld a,l
        cp 16
        jp c,obj_gone
.after:
        call obj_ext_of                 ; turning: 4 frames a picture
        inc hl
        inc (hl)
        ld a,(hl)
        rrca
        rrca
        and 3
        bit 7,(ix+5)
        jr z,.pr
        ld e,a
        ld d,0
        ld hl,kaxe_left
        add hl,de
        ld a,(hl)
.pr:
        add a,OBJF_AXE
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
        ld bc,8*256+16
        jp b3_touch
kaxe_left:      db 1, 0, 3, 2

; x += direction * speed / 8 (fraction in obj_ext[0])
kaxe_move:
        call obj_ext_of
        ld a,(ix+10)
        ld b,a
        and 7
        rrca
        rrca
        rrca                            ; * 32
        add a,(hl)
        ld (hl),a
        sbc a,a
        neg
        ld c,a                          ; the carry
        ld a,b
        rrca
        rrca
        rrca
        and 31
        add a,c
        ret z
        ld b,a
.lp:
        push bc
        ld a,(ix+5)
        call move_dir_a
        pop bc
        djnz .lp
        ret

; --- the giant bat (NES record $5E 6:$8AED, object $1E 5:$9386, hits $E1AE).
; At most three. Once out it waits 60 frames, then flies straight at a point
; 48 px right of and 16 px above Simon (screen x wrapping) for 61/37/32/69
; frames, hovers 123/32/61/199 (jumping 17 px up if Simon swings near it),
; then shoots a fireball (Simon above it, far below or 72 px across: then 16
; frames still) or swoops at his feet (77/32/40/63 frames, curving back up).
; Off the screen it flies straight across. 192 damage (3000).
;   +4 timer  +5 facing (+1/-1)  +9 state (0 not out, 1 wait, 2 fly, 3 hover,
;   4 dodge, 5 swoop)  +10 speed across (1/64 px)  +11 frozen frames
;   obj_ext: x fraction, y fraction, vy (8.8, + = down)  obj_hits: damage
;   (ix+3): its top, 0xC0-0xFF = -64..-1 (it can fly 49 px above the
;   playfield; its lowest top is 190)
; ---------------------------------------------------------------------------
GBAT_HP         equ 192

gbat_spawn:
        push ix
        ld a,OBJ_GBAT
        call count_type
        pop ix
        cp 3
        jp nc,obj_release
        ld (ix+0),OBJ_GBAT
        ld (ix+7),KIND_GBAT             ; 40x20 around its middle
        ld (ix+6),OBJF_GBAT
        xor a
        ld (ix+9),a
        ld (ix+11),a
        ld (ix+10),a
        ld (ix+5),-1
        call obj_hits_of
        ld (hl),0
        jp b5_ext_clear

gbat_update:
        ld a,(ix+9)
        or a
        jr nz,.out
        call b3_offscreen
        ret c
        ld (ix+9),1
        ld (ix+4),60
.out:
        ld a,(frame_count)              ; two pictures, 9 frames each
        ld b,0
.m18:
        sub 18
        jr nc,.m18
        add a,18
        cp 9
        jr c,.pic
        inc b
.pic:
        ld a,(ix+11)
        or a
        jr nz,.frozen_pic
        ld a,b
        add a,OBJF_GBAT
        ld (ix+6),a
.frozen_pic:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        ld a,(ix+11)
        or a
        jr z,.go
        dec (ix+11)
        jp .hits
.go:
        ld a,(ix+9)
        dec a
        jr nz,.s2
        dec (ix+4)                      ; waiting
        jp nz,.cull
        call gbat_aim
        jp .cull
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; flying
        jr nz,.fly
        ld (ix+9),3
        call rng_and3
        ld hl,gbat_hovers
        call table_a
        ld (ix+4),a
        jp .cull
.fly:
        call gbat_move
        jp .cull
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; hovering
        jr z,.decide
        ld a,(frame_count)
        and 7
        jp z,.cull
        ld a,(whip_prev)                ; Simon swings near it: it jumps up
        or a
        jp z,.cull
        ld a,16-8
        call gbat_dy
        bit 7,a
        jr z,.ady
        neg
.ady:
        cp 20
        jp nc,.cull
        call gbat_dx
        jp nz,.cull
        ld a,l
        cp 88
        jp nc,.cull
        call obj_ext_of                 ; 2 1/2 px up for 7 frames
        inc hl
        inc hl
        ld (hl),0x80
        inc hl
        ld (hl),-3
        ld (ix+10),0
        ld (ix+9),4
        ld (ix+4),8
        jp .cull
.s4:
        dec a
        jr nz,.s5
        dec (ix+4)                      ; the jump up
        jr z,.decide
        call gbat_move
        jp .cull
.s5:
        dec (ix+4)                      ; swooping
        jr nz,.swoop
        call gbat_aim
        jp .cull
.swoop:
        call obj_ext_of                 ; vy -= 6/256
        inc hl
        inc hl
        ld a,(hl)
        sub 6
        ld (hl),a
        jr nc,.sw
        inc hl
        dec (hl)
.sw:
        call gbat_move
        jp .cull
.decide:
        call gbat_onscreen
        jr nc,.near
        call gbat_vy0                   ; off the screen: straight across
        ld (ix+10),48
        call gbat_flytime
        jp .cull
.near:
        ld a,16-8                       ; Simon above it, 56+ below or 72+
        call gbat_dy                    ; across: a fireball
        bit 7,a
        jr nz,.shoot
        cp 56
        jr nc,.shoot
        call gbat_dx
        jr nz,.shoot
        ld a,l
        cp 72
        jr nc,.shoot
        call gbat_swoop
        jp .cull
.shoot:
        ld l,(ix+1)
        ld h,(ix+2)
        ld e,(ix+3)
        push ix
        call fire_at_simon              ; (it moves IX)
        pop ix
        ld (ix+9),1
        ld (ix+4),16
.cull:
        ld a,(ix+3)                     ; NES y outside 8..247: gone
        add a,49
        cp 240
        jp nc,obj_release
        call b5_cull64
        ret c
.hits:
        call gbat_onscreen              ; (collision only on the screen)
        ret c
        call weapon_hits
        jr nc,.touch
        call hit_damage
        ld b,a
        call obj_hits_of
        ld a,(hl)
        add a,b
        jr c,.dead
        cp GBAT_HP
        jr nc,.dead
        ld (hl),a
        ld (ix+11),16
        ld a,SND_HIT
        jp sfx_play
.dead:
        call mark_dead
        ld a,SCORE_GBAT
        ld c,0
        jp enemy_killed
.touch:
        ld a,(ix+3)                     ; (above the playfield: b3_touch
        cp 0xC0                         ; reads the top unsigned)
        ret nc
        ld a,8
        ld bc,24*256+22
        jp b3_touch
gbat_hovers:    db 123, 32, 61, 199
gbat_flights:   db 61, 37, 32, 69
gbat_swoops:    db 77, 32, 40, 63

; Carry if its middle is off the screen (NES: screen x outside 16..240)
gbat_onscreen:
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
        cp 8
        ret c
        cp 233
        ccf
        ret

; A = py + A - its signed top, clamped to -127..127 (HL kept)
gbat_dy:
        push hl
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(py)
        add hl,de
        call gbat_top
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.hi
        ld a,l
        bit 7,a
        jr z,.ok
        ld a,127
        jr .ok
.hi:
        inc a
        jr nz,.minus
        ld a,l
        bit 7,a
        jr nz,.ok
.minus:
        bit 7,h
        ld a,127
        jr z,.ok
        ld a,-127
.ok:
        pop hl
        ret

; DE = its top as a 16-bit number (0xC0-0xFF: above the playfield)
gbat_top:
        ld a,(ix+3)
        ld e,a
        ld d,0
        cp 0xC0
        ret c
        dec d
        ret

; HL = |Simon x - its x|, NZ if 256 or more
gbat_dx:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        ret

gbat_vy0:
        call obj_ext_of
        inc hl
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        ret

gbat_flytime:
        call rng_and3
        ld hl,gbat_flights
        call table_a
        ld (ix+4),a
        ld (ix+9),2
        ret

; obj_ext vy = HL (+ = down), by the sign in B (bit 7 set: up)
gbat_set_vy:
        bit 7,b
        jr z,.down
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.down:
        push hl
        call obj_ext_of
        inc hl
        inc hl
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; D = |dx|, E = |dy| (at least 1, at most 255); facing from dx; B bit 7 set
; if the target is above (dy < 0). In: HL = target x - its middle x
; (16-bit), A = target y - its middle y (signed)
gbat_dirs:
        ld b,a
        ld (ix+5),1
        bit 7,h
        jr z,.xp
        ld (ix+5),-1
.xp:
        call hl_abs
        ld a,h
        or a
        ld a,l
        jr z,.xok
        ld a,255
.xok:
        or a
        jr nz,.x1
        inc a
.x1:
        ld d,a
        ld a,b
        bit 7,a
        jr z,.yp
        neg
.yp:
        or a
        jr nz,.y1
        inc a
.y1:
        ld e,a
        ret

; aim A: at (Simon's screen middle + 48 (wrapping), his middle - 16)
gbat_aim:
        ld hl,(px)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,l
        add a,8+48
        ld l,a
        ld h,0                          ; target screen x (wrapped)
        push hl
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        ex de,hl
        pop hl
        or a
        sbc hl,de                       ; target - its middle
        ld a,-8                         ; (py + 16 - 16) - (top + 8)
        call gbat_dy
        call gbat_dirs
        ld a,d
        cp e
        jr c,.ylong
        push bc                         ; x long: 3/4 px across, 1 1/2 r
        ld (ix+10),48
        ld a,e
        ld l,d
        ld de,384
        call boss_muldiv
        pop bc
        call gbat_set_vy
        jr .time
.ylong:
        ld l,d                          ; y long: 3/4 px down/up, 1 px
        ld h,0                          ; across if 3 dx >= 2 dy
        push de
        ld e,l
        ld d,h
        add hl,hl
        add hl,de                       ; 3 dx
        pop de
        push hl
        ld l,e
        ld h,0
        add hl,hl                       ; 2 dy
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ld a,64
        jr nc,.vx
        xor a
.vx:
        ld (ix+10),a
        ld hl,0xC0
        call gbat_set_vy
.time:
        call gbat_flytime
        ret

; the swoop: at (Simon's middle x, his middle + 24)
gbat_swoop:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        push hl
        ld a,16+24-8
        call gbat_dy
        pop hl
        call gbat_dirs
        ld b,0                          ; (always down)
        ld a,d
        cp e
        jr c,.ylong
        ld (ix+10),112                  ; x long: 1 3/4 px, 2 r down
        ld a,e
        ld l,d
        ld de,512
        call boss_muldiv
        ld b,0
        call gbat_set_vy
        jr .time
.ylong:
        ld a,d                          ; y long: 2 px down, 3 r across
        ld l,e
        ld de,192
        call boss_muldiv
        ld (ix+10),l
        ld hl,0x200
        ld b,0
        call gbat_set_vy
.time:
        call rng_and3
        ld hl,gbat_swoops
        call table_a
        ld (ix+4),a
        ld (ix+9),5
        ret

; x += facing * speed / 64, y += vy (8.8, signed; the top is signed)
gbat_move:
        call obj_ext_of
        ld a,(ix+10)
        ld b,a
        add a,a
        add a,a                         ; fraction: (speed & 63) * 4
        add a,(hl)
        ld (hl),a
        sbc a,a
        neg
        ld c,a                          ; the carry
        ld a,b
        rlca
        rlca
        and 3
        add a,c
        jr z,.y
        push hl
        ld b,a
.lp:
        push bc
        ld a,(ix+5)
        call move_dir_a
        pop bc
        djnz .lp
        pop hl
.y:
        inc hl                          ; y fraction
        ld a,(hl)
        inc hl
        add a,(hl)                      ; + vy low
        dec hl
        ld (hl),a
        inc hl
        inc hl
        ld a,(ix+3)
        adc a,(hl)                      ; + vy high
        ld (ix+3),a
        ret

; --- Death (stage 15's boss; NES record $58 6:$8AA9, object $18 5:$8EE0,
; hits $E282 as Medusa's). Made when the screen comes within 216 px of his
; room (every other enemy vanishes); 120 frames after the screen locks at his
; room he appears at the top right and floats down (2 1/2 px, slowing 5/256
; a frame) to the first floor under him. At every landing he throws 3
; sickles, then stands 144/95/185/84 frames: every 32 frames, with Simon
; within 72 px, he leaps at him (1 1/4 px across, 2 px up); else when the
; time is up he hops 1 or 2 px up, 3/4 px across to a random side. In the air
; gravity is 6/256; he bounces off screen x 16 and 240; his feet probe the
; floor (rising too, as the NES's). Half the weapon's damage off the boss bar
; (64), 8 frames frozen a hit; 7000, then the orb.
;   +4 timer  +5 facing  +9 state (0 placed, 1 waiting for the lock,
;   2 appearing, 3 floating down, 4 standing, 5 in the air, 6 burning)
;   +10 bit 0: moving left, bit 1: fast  +11 frozen frames
;   obj_ext: x fraction, y fraction, vy (8.8, + = down)
;   his NES y (middle) = (ix+3) + 72 (the top of his 40x48 picture: -72)
; ---------------------------------------------------------------------------
DEATH_Y0        equ 48                  ; his NES y when he appears
death_spawn:
        ld (ix+0),OBJ_DEATH
        ld (ix+7),KIND_DEATH            ; 24x44 around his middle
        ld (ix+6),OBJF_DEATH
        ld (ix+3),DEATH_Y0-72
        xor a
        ld (ix+9),a
        ld (ix+10),a
        ld (ix+11),a
        ld (ix+5),1
        jp b5_ext_clear

death_update:
        ld a,(ix+9)
        cp 6
        jr nz,.alive
        inc (ix+4)
        jp boss_update.burning
.alive:
        or a
        jr nz,.made
        ld hl,(cam_x)                   ; the record at screen x 8: camera
        ld de,216+1                     ; 216 (Simon comes from the right)
        or a
        sbc hl,de
        ret nc
        push ix                         ; every other enemy goes (NES $F47C)
        call enemies_burst
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
        ld a,1                          ; his patterns in the corridor
        call load_swap_patterns         ; enemies' place (swap window)
        pop ix
        ld a,BOSS_HP
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        ld (ix+9),a
        ret
.made:
        ld a,(ix+11)                    ; frozen by a hit
        or a
        jr z,.nf
        dec (ix+11)
        jp .hits
.nf:
        ld a,(freeze_t)
        or a
        jp nz,.hits
        call knight_face
        ld a,(ix+9)
        dec a
        jr nz,.s2
        ld hl,(cam_x)                   ; until the screen is at his room
        ld de,(area_hdr+AH_MINCAM)
        or a
        sbc hl,de
        ret nz
        ld a,SND_BOSS
        call music_restart
        ld hl,(cam_x)                   ; the screen locks, both ways
        ld (cam_min),hl
        ld (area_hdr+AH_MAXCAM),hl
        ld a,1
        ld (cam_lock),a
        ld (ix+9),2
        ld (ix+4),120
        ret
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; appearing
        ret nz
        ld (ix+9),3
        ld hl,0x0280                    ; 2 1/2 px down
        jp death_set_vy
.s3:
        dec a
        jr nz,.s4
        call death_vy                   ; floating down: vy -= 5/256
        ld de,-5
        add hl,de
        call death_set_vy
        call death_y_move
        ld a,24
        call death_probe
        jp nc,.hits
        jp .land
.s4:
        dec a
        jr nz,.s5
        ld a,(frame_count)              ; standing: every 32 frames, with
        and 31                          ; Simon near, the leap
        jr nz,.tick
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.tick
        ld a,l
        cp 72
        jr nc,.tick
        ld a,2                          ; towards him, fast
        bit 7,(ix+5)
        jr z,.lr
        inc a
.lr:
        ld (ix+10),a
        ld hl,-0x0200                   ; 2 px up
        jr .jump
.tick:
        dec (ix+4)
        jp nz,.hits
        ld a,(frame_count)              ; the hop: a random side, 3/4 px
        and 1
        ld (ix+10),a
        ld a,(rng)
        rrca
        ld hl,-0x0100                   ; 1 or 2 px up
        jr nc,.jump
        ld hl,-0x0200
.jump:
        call death_set_vy
        ld (ix+9),5
        jp .hits
.s5:
        call death_x_move               ; in the air
        call death_vy
        ld de,6                         ; gravity 6/256
        add hl,de
        call death_set_vy
        call death_y_move
        ld a,(ix+3)                     ; the ceiling: NES y 32
        add a,72
        cp 32
        jr nc,.probe
        ld (ix+3),33-72
        ld hl,0
        call death_set_vy
        jp .hits
.probe:
        ld a,25
        call death_probe
        jp nc,.hits
.land:
        ld a,(ix+3)                     ; on the tile: y &= $F8
        add a,72
        and 0xF8
        sub 72
        ld (ix+3),a
        call sickles_throw
        call rng_and3
        ld hl,death_waits
        call table_a
        ld (ix+4),a
        ld (ix+9),4
.hits:
        ld a,(ix+9)                     ; (placed, waiting, appearing: no
        cp 3                            ; hits, no harm)
        ret c
        ld a,OBJF_DEATH
        bit 7,(ix+5)
        jr nz,.pic
        inc a
.pic:
        ld (ix+6),a
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
        ld a,SCORE_DEATH
        call add_score
        ld (ix+9),6                     ; he burns at his middle, then the
        ld (ix+4),0                     ; orb (the sickles fly on)
        ld a,(ix+3)
        add a,16
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret
.touch:
        ld a,24
        ld bc,16*256+34
        jp b3_touch
death_waits:    db 144, 95, 185, 84

; HL = his vy (obj_ext 2-3)
death_vy:
        call obj_ext_of
        inc hl
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; his vy = HL
death_set_vy:
        push hl
        call obj_ext_of
        inc hl
        inc hl
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; y += vy (8.8, the fraction in obj_ext 1)
death_y_move:
        call obj_ext_of
        inc hl
        ld a,(hl)
        inc hl
        add a,(hl)
        dec hl
        ld (hl),a
        inc hl
        inc hl
        ld a,(ix+3)
        adc a,(hl)
        ld (ix+3),a
        ret

; x += 3/4 or 1 1/4 px along +10; bounces off screen x 16 and 240 (middle)
death_x_move:
        call obj_ext_of
        ld b,0xC0                       ; 3/4 px
        ld c,0
        bit 1,(ix+10)
        jr z,.sp
        ld b,0x40                       ; fast: 1 1/4 px
        inc c
.sp:
        ld a,(hl)
        add a,b
        ld (hl),a
        ld a,c
        adc a,0
        or a
        jr z,.clamp
        bit 0,(ix+10)
        jr z,.r
        neg
.r:
        call move_dir_a
.clamp:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de                       ; screen x of his middle
        ld a,h
        or a
        jr nz,.left
        ld a,l
        cp 240
        jr nc,.right
        cp 16
        ret nc
.left:
        ld a,16
        jr .set
.right:
        ld a,240
.set:
        sub 8
        ld l,a
        ld h,0
        ld de,(cam_x)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+10)
        xor 1
        ld (ix+10),a
        ret

; Carry if the tile under his middle at NES y + A is solid
death_probe:
        add a,(ix+3)
        add a,72-48
        ld e,a
        ld d,0
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,8
        add hl,bc
        jp solid_at

; --- the sickles (NES $9083, object $0B 5:$8FF8): 3 at each of Death's
; landings, at most 4 out, placed from SIMON (screen x, y wrapping): (+160,
; -80), (+48, +24), (+4, -48). Each flickers 40 frames (shown and hittable
; on even frames), then aims at Simon: 7/8 px on the long axis, short/long
; on the other; flies 119 frames, stops 32, aims again. Gone off the screen
; (NES x outside 8..248, y outside 8..247) or by any hit (100).
;   +4 timer  +5 x direction  +9 state (0 appearing, 1 aim, 2 flying,
;   3 stopped)  +10 y direction (0 down, 1 up)  +11 bit 0 vx 1 px, bit 1 vy
;   1 px  obj_ext: x fraction, y fraction, vx fraction, vy fraction
;   (ix+3): the 16x16 top, NES y - 56 (0xC0-0xFF: above the playfield)
sickles_throw:
        push ix
        ld hl,sickle_offsets
        ld b,3
.lp:
        push bc
        push hl
        ld a,OBJ_SICKLE
        call count_type
        cp 4
        jr nc,.skip
        call obj_free_slot
        jr c,.skip
        pop hl
        push hl
        ld a,(px)                       ; Simon's NES middle: screen x, y
        ld de,(cam_x)
        sub e
        add a,8
        add a,(hl)
        ld e,a                          ; its screen x (wrapping)
        ld a,(py)
        add a,64
        inc hl
        add a,(hl)                      ; its NES y (wrapping)
        sub 56
        ld (ix+3),a
        ld d,0
        ld hl,(cam_x)
        add hl,de
        ld de,-8
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+0),OBJ_SICKLE
        ld (ix+4),40
        ld (ix+5),-1
        ld (ix+6),OBJF_SICKLE
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        xor a
        ld (ix+9),a
        ld (ix+10),a
        ld (ix+11),a
        call b5_ext_clear
.skip:
        pop hl
        inc hl
        inc hl
        pop bc
        djnz .lp
        pop ix
        ret
sickle_offsets: db 160, -80, 48, 24, 4, -48

sickle_update:
        ld a,(freeze_t)
        or a
        jp nz,.cull
        ld a,(ix+9)
        or a
        jr nz,.s1
        dec (ix+4)                      ; appearing
        jp nz,.cull
        inc (ix+9)
.s1:
        ld a,(ix+9)
        cp 1
        jr nz,.s2
.aim:
        call sickle_aim
        ld (ix+4),120
        ld (ix+9),2
        jp .cull
.s2:
        cp 2
        jr nz,.s3
        dec (ix+4)                      ; flying
        jr nz,.fly
        ld (ix+4),32
        ld (ix+9),3
        jp .cull
.fly:
        call sickle_move
        jp .cull
.s3:
        dec (ix+4)                      ; stopped
        jr z,.aim
.cull:
        ld l,(ix+1)                     ; NES screen x outside 8..248
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jp nz,obj_gone
        ld a,l
        cp 241
        jp nc,obj_gone
        ld a,(ix+3)                     ; NES y outside 8..247
        add a,56
        sub 8
        cp 240
        jp nc,obj_gone
        ld a,(frame_count)              ; its picture: 3 frames each
        ld b,0
.d3:
        sub 3
        jr c,.p
        inc b
        jr .d3
.p:
        ld a,b
        and 3
        bit 7,(ix+5)
        jr nz,.l
        add a,4
.l:
        add a,OBJF_SICKLE
        ld (ix+6),a
        ld a,(ix+9)                     ; appearing: only on even frames
        or a
        jr nz,.hits
        ld a,(frame_count)
        rrca
        ret c
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,SCORE_SNAKE
        ld c,2
        jp enemy_killed
.touch:
        ld a,(ix+3)
        cp 0xC0
        ret nc
        ld a,8
        ld bc,10*256+18
        jp b3_touch

; aim at Simon's middle: 7/8 px on the long axis, short/long on the other
sickle_aim:
        ld hl,(px)                      ; dx = (px + 8) - (x + 8)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld (ix+5),1
        bit 7,h
        jr z,.xp
        ld (ix+5),-1
.xp:
        call hl_abs
        ld a,h
        or a
        ld a,l
        jr z,.x1
        ld a,255
.x1:
        or a
        jr nz,.x2
        inc a
.x2:
        ld c,a                          ; C = |dx|
        push bc
        ld a,8                          ; dy = (py + 16) - (top + 8)
        call gbat_dy
        pop bc
        ld (ix+10),0
        bit 7,a
        jr z,.yp
        ld (ix+10),1
        neg
.yp:
        or a
        jr nz,.y1
        inc a
.y1:
        ld b,a                          ; B = |dy|
        call obj_ext_of
        inc hl
        inc hl
        push hl
        ld a,c
        cp b
        jr c,.ylong
        ld a,b                          ; x long: vx 7/8, vy = dy / dx
        ld l,c
        ld de,256
        call boss_muldiv
        ex de,hl
        pop hl
        ld (hl),0xE0
        inc hl
        ld (hl),e
        ld a,d
        add a,a
        ld (ix+11),a
        ret
.ylong:
        ld a,c                          ; y long: vy 7/8, vx = dx / dy
        ld l,b
        ld de,256
        call boss_muldiv
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),0xE0
        ld (ix+11),d
        ret

; x, y += the speeds (fractions in obj_ext 0, 1)
sickle_move:
        call obj_ext_of
        ld a,(ix+11)
        and 1
        ld c,a                          ; vx whole
        ld a,(hl)
        inc hl
        inc hl
        add a,(hl)                      ; x fraction + vx fraction
        dec hl
        dec hl
        ld (hl),a
        ld a,c
        adc a,0
        push hl
        or a
        jr z,.y
        ld b,a
.xl:
        push bc
        ld a,(ix+5)
        call move_dir_a
        pop bc
        djnz .xl
.y:
        pop hl
        ld a,(ix+11)
        rrca
        and 1
        ld c,a                          ; vy whole
        inc hl
        ld a,(hl)
        inc hl
        inc hl
        add a,(hl)                      ; y fraction + vy fraction
        dec hl
        dec hl
        ld (hl),a
        ld a,c
        adc a,0
        ret z
        bit 0,(ix+10)
        jr z,.down
        neg
.down:
        add a,(ix+3)
        ld (ix+3),a
        ret
