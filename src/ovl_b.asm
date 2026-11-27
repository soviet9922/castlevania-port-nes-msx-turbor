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

; --- Dracula (stage 18's boss; NES record $5D 6:$8B3B, object $1D 5:$950E,
; hits $E327 on his body and $E34B on his head's box). Made when the screen
; comes within 216 px of his room (every other enemy goes). 120 frames after
; the screen locks his head shows at the floor, rises 56 px (1/2 px a frame),
; and he flickers in. First form, a loop: stand 36/16/50/24 frames, open the
; cape 16, 3 fireballs (at Simon's middle and 16 px below and above it, 2 px
; a frame), 32, vanish 32, away 79, reappear by Simon (+16, -8, +128, +96,
; +48, -40, +96, -88 px, kept on the screen), flicker in 32. Only the head
; takes damage (half the weapon's), and only while he stands, opens the cape
; or fires; the body clinks. At 0 the head flies off, the body stands 120
; frames headless, crumbles (6 pieces), and the monster appears with a full
; bar: it stands 33, waits 85/123 (crouching at once if Simon faces it
; swinging), crouches 16 and jumps at Simon (6 or 4 1/2 px up, gravity 3/16,
; 3/4 px across), lands, and (48 px or more away, 3 times in 4) opens its
; mouth and fires 3. Its head takes a quarter of the weapon's damage, a hit
; freezes it 8 frames; holy water also burns its body. 50000, then the orb.
;   +4 timer  +5 facing  +9 state (0 placed; first form 1-14; the monster
;   20-30; 31-32 burning)  +10 bit 0: moving left (jumps); burning: frames
;   +11 frozen frames (the monster)  obj_ext: y fraction, vy (8.8, + = up),
;   x fraction   his NES y (middle) = (ix+3) + 72
; ---------------------------------------------------------------------------
DRAC_Y0         equ 224                 ; NES y: his place (the head at the floor)
DRAC_Y          equ 168                 ; standing (frame bottom on the floor, 192)

dracula_spawn:
        ld (ix+0),OBJ_DRAC
        ld (ix+7),KIND_DRAC1
        ld (ix+6),OBJF_DRAC
        ld (ix+3),DRAC_Y0-72
        xor a
        ld (ix+9),a
        ld (ix+10),a
        ld (ix+11),a
        ld (ix+5),-1
        ld (drac_form),a
        ld (drac_vis),a
        ld (drac_head),a
        ld (drac_frac),a
        jp b5_ext_clear

dracula_update:
        ld a,(ix+9)
        or a
        jr nz,.made
        ld hl,(cam_x)                   ; the record at screen x 8
        ld de,216+1
        or a
        sbc hl,de
        ret nc
        push ix                         ; every other enemy goes
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
        pop ix
        ld a,BOSS_HP
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
        ld (ix+9),a
        ret
.made:
        cp 31
        jp nc,drac_burning
        ld a,(freeze_t)                 ; the stopwatch: no AI
        or a
        jp nz,drac_hits
        call knight_face
        ld a,(ix+11)                    ; (the monster) frozen by a hit
        or a
        jr z,.nf
        dec (ix+11)
        jp drac_hits
.nf:
        ld a,(ix+9)
        cp 20
        jp nc,drac_form2
        dec a
        jr nz,.s2
        ld hl,(cam_x)                   ; waiting for the lock (the stage's
        ld de,(area_hdr+AH_MINCAM)      ; music goes on: NES 6:$998B)
        or a
        sbc hl,de
        ret nz
        ld hl,(cam_x)
        ld (cam_min),hl
        ld (area_hdr+AH_MAXCAM),hl
        ld a,1
        ld (cam_lock),a
        ld (ix+4),120
        ld (ix+9),2
        ret
.s2:
        dec a
        jr nz,.s3
        dec (ix+4)                      ; 120 frames
        ret nz
        ld a,1                          ; his head shows at the floor
        ld (drac_head),a
        ld (ix+4),60
        ld (ix+9),3
        jp drac_hits
.s3:
        dec a
        jr nz,.s4
        dec (ix+4)                      ; 60 frames
        jp nz,drac_hits
        ld hl,0x0080                    ; rising 1/2 px a frame
        call drac_set_vy
        ld (ix+9),4
        jp drac_hits
.s4:
        dec a
        jr nz,.s5
        call drac_y_move
        ld a,(ix+3)
        add a,72
        cp DRAC_Y
        jp nc,drac_hits
        ld (ix+3),DRAC_Y-72
        ld (ix+4),60
        ld (ix+9),5
        jp drac_hits
.s5:
        dec a
        jr nz,.s6
        dec (ix+4)                      ; 60 frames
        jp nz,drac_hits
        ld (ix+4),69
        ld (ix+9),6
        jp drac_hits
.s6:
        dec a
        jr nz,.s7
        ld a,(frame_count)              ; flickering in: the body on odd frames
        and 1
        ld (drac_vis),a
        xor a
        call drac_show
        dec (ix+4)
        jp nz,drac_hits
.pick:
        ld a,1
        ld (drac_vis),a
        xor a
        call drac_show
        call rng_and3
        ld hl,drac_stands
        call table_a
        ld (ix+4),a
        ld (ix+9),7
        jp drac_hits
.s7:
        dec a
        jr nz,.s8
        xor a                           ; standing
        call drac_show
        dec (ix+4)
        jp nz,drac_hits
        ld (ix+4),16
        ld (ix+9),8
        jp drac_hits
.s8:
        dec a
        jr nz,.s9
        ld a,1                          ; the cape open
        call drac_show
        dec (ix+4)
        jp nz,drac_hits
        ld l,(ix+1)                     ; 3 fireballs from his middle
        ld h,(ix+2)
        ld a,(ix+3)
        add a,72-56
        ld e,a
        call drac_volley
        ld (ix+4),32
        ld (ix+9),9
        jp drac_hits
.s9:
        dec a
        jr nz,.s10
        ld a,1
        call drac_show
        dec (ix+4)
        jp nz,drac_hits
        ld (ix+4),32
        ld (ix+9),10
        jp drac_hits
.s10:
        dec a
        jr nz,.s11
        ld a,1                          ; vanishing (the head flickers; the
        call drac_show                  ; body stays, as the NES draws it)
        ld a,(frame_count)
        and 1
        inc a
        ld (drac_head),a                ; (2 = hidden here)
        dec (ix+4)
        jp nz,drac_hits
        xor a
        ld (drac_vis),a
        ld a,2
        ld (drac_head),a
        ld (ix+4),79
        ld (ix+9),11
        jp drac_hits
.s11:
        dec a
        jr nz,.s12
        dec (ix+4)                      ; away
        jp nz,drac_hits
        call drac_teleport
        ld (ix+4),32
        ld (ix+9),12
        jp drac_hits
.s12:
        dec a
        jr nz,.s14
        xor a                           ; flickering in by Simon
        call drac_show
        ld a,(frame_count)
        and 1
        ld (drac_vis),a
        xor 1
        inc a
        ld (drac_head),a                ; (shown with the body)
        dec (ix+4)
        jp nz,drac_hits
        ld a,1
        ld (drac_head),a
        jp .pick
.s14:
        dec (ix+4)                      ; headless, 120 frames
        jp nz,drac_hits
        ld a,1                          ; the monster
        ld (drac_form),a
        ld (ix+4),32
        ld (ix+9),20
        jp drac_hits
drac_stands:    db 36, 16, 50, 24

; the second form (states 20-30)
drac_form2:
        sub 20
        jr nz,.t21
        dec (ix+4)                      ; the old body, 32 frames
        jp nz,drac_hits
        xor a                           ; it crumbles
        ld (drac_vis),a
        call drac_debris
        ld a,SND_KILL
        call sfx_play
        ld (ix+4),16
        ld (ix+9),21
        jp drac_hits
.t21:
        dec a
        jr nz,.t22
        dec (ix+4)                      ; 16 frames
        jp nz,drac_hits
        ld a,BOSS_HP                    ; the bar fills again
        ld (boss_hp),a
        ld a,1
        ld (hud_dirty),a
.new:
        ld a,1                          ; standing at y 168, the head live
        ld (drac_vis),a
        ld (drac_head),a
        ld (ix+7),KIND_DRAC2
        ld (ix+3),DRAC_Y-72
        ld (ix+4),33
        ld (ix+9),22
        call drac_stand_pic
        jp drac_hits
.t22:
        dec a
        jr nz,.t23
        call drac_stand_pic             ; standing 33
        dec (ix+4)
        jp nz,drac_hits
.wait:
        ld a,(frame_count)              ; 85 or 123
        and 1
        ld a,85
        jr z,.w
        ld a,123
.w:
        ld (ix+4),a
        ld (ix+9),23
        jp drac_hits
.t23:
        dec a
        jr nz,.t24
        call drac_stand_pic
        ld a,(frame_count)              ; Simon faces it swinging: crouch now
        and 15
        jr nz,.wt
        ld a,(whip_prev)
        or a
        jr z,.wt
        ld a,(facing)                   ; (Simon's 0 right, 1 left; it faces
        or a                            ; him: +1 = he is to its right)
        ld a,1
        jr z,.sf
        ld a,-1
.sf:
        cp (ix+5)
        jr nz,.crouch
.wt:
        dec (ix+4)
        jp nz,drac_hits
.crouch:
        ld a,2
        call drac_show
        ld (ix+4),16
        ld (ix+9),24
        jp drac_hits
.t24:
        dec a
        jr nz,.t25
        dec (ix+4)                      ; crouching
        jp nz,drac_hits
        ld a,0                          ; the jump: at Simon
        bit 7,(ix+5)
        jr z,.jd
        inc a
.jd:
        ld (ix+10),a
        ld a,(frame_count)
        rrca
        ld hl,0x0600                    ; 6 or 4 1/2 px up
        jr c,.jv
        ld hl,0x0480
.jv:
        call drac_set_vy
        ld (ix+9),25
        jp drac_hits
.t25:
        dec a
        jr nz,.t26
        call drac_vy                    ; jumping: gravity 3/16
        ld de,-0x30
        add hl,de
        call drac_set_vy
        call drac_y_move
        ld a,(ix+3)                     ; above NES y 32: no more rising
        add a,72
        cp 32
        jr nc,.jp
        ld hl,0
        call drac_set_vy
.jp:
        ld a,(ix+3)
        add a,72
        cp 96
        ld a,3                          ; low: the jump picture, high: the other
        jr nc,.jpic
        inc a
.jpic:
        call drac_show
        call drac_x_move
        ld a,8                          ; the floor at y + 8
        call drac_probe
        jp nc,drac_hits
        ld a,(ix+3)
        add a,72
        and 0xF8
        sub 72
        ld (ix+3),a
        ld a,5
        call drac_show
        ld a,SND_DOOR                   ; (the thud)
        call sfx_play
        ld (ix+4),24
        ld (ix+9),26
        jp drac_hits
.t26:
        dec a
        jr nz,.t27
        dec (ix+4)                      ; landed, 24
        jp nz,drac_hits
        ld a,(ix+3)
        sub 16
        ld (ix+3),a
        ld (ix+4),16
        ld (ix+9),27
        call drac_stand_pic
        jp drac_hits
.t27:
        dec a
        jr nz,.t28
        call drac_stand_pic
        dec (ix+4)
        jp nz,drac_hits
        ld hl,(px)                      ; |dx| < 48 or a multiple of 4: wait
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        call hl_abs
        ld a,h
        or a
        jr nz,.far
        ld a,l
        cp 48
        jp c,.wait
        and 3
        jp z,.wait
.far:
        ld a,(frame_count)
        rrca
        ld a,16
        jr nc,.ft
        ld a,40
.ft:
        ld (ix+4),a
        ld (ix+9),28
        jp drac_hits
.t28:
        dec a
        jr nz,.t29
        call drac_stand_pic
        dec (ix+4)
        jp nz,drac_hits
        ld a,6                          ; the mouth open
        call drac_show
        ld (ix+4),16
        ld (ix+9),29
        jp drac_hits
.t29:
        dec a
        jr nz,.t30
        dec (ix+4)
        jp nz,drac_hits
        call drac_box_place             ; 3 fireballs from its head
        ld hl,(drac_box+1)
        ld a,(drac_box+3)
        ld e,a
        call drac_volley
        ld (ix+4),16
        ld (ix+9),30
        jp drac_hits
.t30:
        dec (ix+4)
        jp nz,drac_hits
        jp .new

; the monster's standing pictures, 32 frames each
drac_stand_pic:
        ld a,(frame_count)
        rlca
        rlca
        rlca
        and 1
; show picture A (first form: 0 standing, 1 the cape; the monster: 0-1
; standing, 2 crouching, 3 jumping, 4 jumping high, 5 landed, 6 the mouth
; open) facing its way: loads that picture's patterns when they change
drac_show:
        ld c,a
        ld a,(drac_form)
        or a
        ld a,c
        jr nz,.mon
        bit 7,(ix+5)                    ; first form: sets 0-1 left, 2-3 right
        jr nz,.f1
        add a,2
.f1:
        push af
        ld e,a
        ld d,0
        ld hl,drac_frames1
        add hl,de
        ld a,(hl)
        jr .set
.mon:
        bit 7,(ix+5)                    ; the monster: sets 4-10 left, 11-17
        jr nz,.m1                       ; right
        add a,7
.m1:
        add a,4
        push af
        add a,OBJF_MON-4
.set:
        ld (ix+6),a
        pop af
        ld hl,drac_set
        cp (hl)
        ret z
        ld (hl),a
        push ix
        call load_swap_patterns
        pop ix
        ret
drac_frames1:   db OBJF_DRAC, OBJF_DRAC+1, OBJF_DRAC+3, OBJF_DRAC+4

; HL = vy, vy = HL (obj_ext 1-2; + = up)
drac_vy:
        call obj_ext_of
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
drac_set_vy:
        push hl
        call obj_ext_of
        inc hl
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; y -= vy (the fraction in obj_ext 0)
drac_y_move:
        call obj_ext_of
        ld a,(hl)
        inc hl
        sub (hl)
        dec hl
        ld (hl),a
        inc hl
        inc hl
        ld a,(ix+3)
        sbc a,(hl)
        ld (ix+3),a
        ret

; 3/4 px along +10 bit 0; turns at screen x 24 (going left) and 232
drac_x_move:
        call obj_ext_of
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        add a,0xC0
        ld (hl),a
        jr nc,.edge
        ld a,1
        bit 0,(ix+10)
        jr z,.r
        ld a,-1
.r:
        call move_dir_a
.edge:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,l
        bit 0,(ix+10)
        jr z,.right
        cp 24
        ret nc
        jr .turn
.right:
        cp 232
        ret c
.turn:
        ld a,(ix+10)
        xor 1
        ld (ix+10),a
        ret

; Carry if the tile under his middle at NES y + A is solid
drac_probe:
        add a,(ix+3)
        add a,72-48
        ld e,a
        ld d,0
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,8
        add hl,bc
        jp solid_at

; 3 fireballs from (HL = x, E = top of a 16x16 shooter) at Simon's middle
; and 16 px below and above it, 2 px a frame (NES $99EB)
drac_volley:
        ld a,127
        ld (fire_speed),a
        ld a,6
        ld (fire_max),a
        ld b,3
        ld c,8+16
.lp:
        push bc
        push hl
        push de
        ld a,c
        ld (fire_dy),a
        push ix
        call fire_aimed
        pop ix
        pop de
        pop hl
        pop bc
        ld a,c
        sub 16
        ld c,a
        djnz .lp
        ret

; he reappears by Simon (NES $96F1): his screen x + the table, kept in 20..235
drac_teleport:
        ld a,(frame_count)
        ld c,a
.try:
        ld a,c
        and 7
        ld e,a
        ld d,0
        ld hl,drac_jumps
        add hl,de
        ld a,(px)
        ld de,(cam_x)
        sub e
        add a,8
        add a,(hl)
        inc c
        cp 20
        jr c,.try
        cp 236
        jr nc,.try
        sub 8
        ld l,a
        ld h,0
        ld de,(cam_x)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ret
drac_jumps:     db 16, -8, 128, 96, 48, -40, 96, -88

; his head's box (drac_box): first form 16x16 at (x -/+ 6, y - 27), the
; monster's at (x -/+ 8, y - 32), on the side he faces
drac_box_place:
        ld a,(drac_form)
        or a
        ld b,6
        ld c,11
        jr z,.f
        ld b,8
        ld c,16
.f:
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,b
        bit 7,(ix+5)
        jr z,.r
        neg
.r:
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
        ld (drac_box+1),hl
        ld a,(ix+3)
        sub c
        ld (drac_box+3),a
        ld a,KIND_BAT
        ld (drac_box+7),a
        ret

; his collision, his head's picture (part 0), each frame
drac_hits:
        call drac_head_pic
        ld a,(ix+9)                     ; the head's box: first form while he
        ld b,a                          ; stands, opens the cape, fires; the
        cp 7                            ; monster from state 22 on
        jr c,.nohead
        cp 10
        jr c,.head
        cp 22
        jr c,.nohead
.head:
        call drac_box_place
        push ix
        ld ix,drac_box
        call weapon_hits
        pop ix
        jr nc,.htouch
        ld a,SND_HIT
        call sfx_play
        call drac_damage
        ret
.htouch:
        push ix
        ld ix,drac_box
        ld a,8
        ld bc,12*256+20
        call b3_touch
        pop ix
        ret c
.nohead:
        ld a,(ix+9)                     ; the body: first form 7-9, the
        cp 7                            ; monster 23-30
        ret c
        cp 10
        jr c,.body
        cp 23
        ret c
.body:
        ld a,1                          ; (the axe / cross keep the head's mark)
        ld (hit_nomark),a
        call weapon_hits
        ld a,0
        ld (hit_nomark),a
        jr nc,.btouch
        ld a,(drac_form)                ; holy water burns the monster's
        or a                            ; body (1 every 32 frames)
        jr z,.clink
        ld a,(hit_src)
        cp 3
        jr nz,.clink
        ld a,(frame_count)
        and 31
        ret nz
        ld b,1
        jp drac_sub_hp
.clink:
        ld a,SND_HIT                    ; (the NES's clink)
        jp sfx_play
.btouch:
        ld a,(drac_form)
        or a
        ld bc,20*256+36
        jr z,.bt
        ld bc,28*256+36
.bt:
        ld a,24
        jp b3_touch

; a hit on his head
drac_damage:
        ld a,(drac_form)
        or a
        jr nz,.mon
        ld a,(hit_src)                  ; first form: half the weapon's, holy
        cp 3                            ; water 1 every 8 frames
        jr nz,.half
        ld a,(frame_count)
        and 7
        ret nz
        ld b,1
        jr .first
.half:
        call hit_damage
        rrca
        rrca
        rrca
        and 31
        ld b,a
.first:
        ld a,1
        ld (hud_dirty),a
        ld a,(boss_hp)
        sub b
        jr z,.head_off
        jr c,.head_off
        ld (boss_hp),a
        ret
.head_off:
        xor a                           ; the head flies off (no score)
        ld (boss_hp),a
        ld a,3
        ld (drac_head),a
        ld hl,0x0500                    ; 5 px up, 2 px a frame away
        ld (drac_hvy),hl
        xor a
        ld (drac_hyf),a
        ld a,(ix+5)
        neg
        ld (part_table+5),a
        ld (ix+4),120
        ld (ix+9),14
        ret
.mon:
        ld a,(hit_src)                  ; the monster: a quarter (fractions
        cp 3                            ; kept), holy water 1 every 16 frames
        jr nz,.quarter
        ld a,(frame_count)
        and 15
        ret nz
        ld b,1
        jr .freeze
.quarter:
        call hit_damage
        ld b,a
        ld a,(drac_frac)
        add a,b
        ld b,a
        and 15
        ld (drac_frac),a
        ld a,b
        rrca
        rrca
        rrca
        rrca
        and 15
        ld b,a
.freeze:
        ld (ix+11),BOSS_FREEZE
; boss_hp -= B; the monster beaten at 0
drac_sub_hp:
        ld a,1
        ld (hud_dirty),a
        ld a,(boss_hp)
        sub b
        jr z,.dead
        jr c,.dead
        ld (boss_hp),a
        ret
.dead:
        xor a
        ld (boss_hp),a
        ld (drac_head),a
        ld (part_table),a
        ld b,10                         ; 50000
.sc:
        push bc
        ld a,0x50
        call add_score
        pop bc
        djnz .sc
        ld a,1                          ; it burns 90 frames, then the orb
        ld (drac_vis),a
        ld (ix+9),31
        ld (ix+10),0
        ld (ix+4),0
        ld a,(ix+3)                     ; (a burst at its middle, y + 8)
        add a,72+8-56
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret

drac_burning:
        cp 32
        jr z,.orb
        inc (ix+10)                     ; the first 30 of the 90 frames
        ld a,(ix+10)
        rrca
        rrca
        rrca
        and 3
        add a,OBJF_BURST
        ld (ix+6),a
        ld a,(ix+10)
        cp 30
        ret c
        ld (ix+9),32
        ret
.orb:
        inc (ix+4)                      ; then the usual 60 and the orb
        jp boss_update.burning

; his head's picture (part 0): first form; flying off after the last hit
drac_head_pic:
        ld a,(drac_head)                ; (the flying head keeps its course
        cp 3                            ; whatever the form)
        jr z,.fly
        ld a,(drac_form)
        or a
        jr nz,.none
        ld a,(drac_head)
        dec a
        jr z,.show
        dec a
        jr z,.none
        dec a
        jr z,.fly
.none:
        ld a,(drac_head)                ; (the flying head stays its course)
        cp 3
        ret z
        xor a
        ld (part_table),a
        ret
.show:
        ld a,OBJ_BRAZIER                ; (any id: parts are only drawn)
        ld (part_table),a
        ld a,(ix+1)
        ld (part_table+1),a
        ld a,(ix+2)
        ld (part_table+2),a
        ld a,(ix+3)
        ld (part_table+3),a
        ld a,OBJF_DRAC+2
        bit 7,(ix+5)
        jr nz,.hp
        ld a,OBJF_DRAC+5
.hp:
        ld (part_table+6),a
        ret
.fly:
        ld a,(part_table)
        or a
        ret z
        ld hl,(part_table+1)            ; 2 px a frame away from Simon
        ld a,(part_table+5)
        add a,a
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
        ld (part_table+1),hl
        ld hl,(drac_hvy)                ; gravity 1/8, y -= vy
        ld de,-0x20
        add hl,de
        ld (drac_hvy),hl
        ld a,(drac_hyf)
        sub l
        ld (drac_hyf),a
        ld a,(part_table+3)
        sbc a,h
        ld (part_table+3),a
        add a,49+11                     ; gone below NES y 247 or above 8
        cp 240
        jr nc,.off
        ld hl,(part_table+1)            ; or off the screen
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        ret z
.off:
        xor a
        ld (part_table),a
        ret

; 6 pieces fly out of the crumbling body (NES $996D): at 0 and 45 degrees,
; 4 px a frame across, or 2.81 px on both axes; harmless, straight
drac_debris:
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,(ix+3)
        add a,72-56
        ld c,a
        ld de,drac_pieces
        ld b,6
.lp:
        push bc
        push de
        push hl
        call obj_free_slot
        pop hl
        pop de
        pop bc
        jr c,.done
        ld (ix+0),OBJ_DEBRIS
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),c
        ld (ix+6),OBJF_DEBRIS
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld a,(de)
        ld (ix+5),a                     ; x direction
        inc de
        ld a,(de)
        ld (ix+10),a                    ; y direction
        inc de
        ld a,(de)
        ld (ix+11),a                    ; speed (1/64 px)
        inc de
        push hl
        call b5_ext_clear
        pop hl
        djnz .lp
.done:
        pop ix
        ret
drac_pieces:    db 1, 1, 180,  1, 0, 255,  1, -1, 180
                db -1, 1, 180,  -1, 0, 255,  -1, -1, 180

; a piece: x, y += its directions * speed (1/64 px; fractions in obj_ext)
debris_update:
        call obj_ext_of                 ; across
        call frac64_step
        or a
        jr z,.y
        ld b,a
.mx:
        push bc
        ld a,(ix+5)
        call move_dir_a
        pop bc
        djnz .mx
.y:
        ld a,(ix+10)                    ; up or down
        or a
        jr z,.cull
        call obj_ext_of
        inc hl
        call frac64_step
        bit 7,(ix+10)
        jr z,.dn
        neg
.dn:
        add a,(ix+3)
        ld (ix+3),a
.cull:
        call b3_offscreen
        jp c,obj_gone
        ld a,(ix+3)
        cp MT_ROWS*16
        jp nc,obj_gone
        ret

; the fraction at HL += (ix+11) (1/64 px): A = the whole px this frame
frac64_step:
        ld a,(ix+11)
        ld c,a
        rlca
        rlca
        and 3
        ld b,a
        ld a,c
        add a,a
        add a,a
        add a,(hl)
        ld (hl),a
        ld a,b
        adc a,0
        ret
