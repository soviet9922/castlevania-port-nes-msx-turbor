; ---------------------------------------------------------------------------
; Objects: candles (braziers and wall candles), their burst when whipped,
; and the items they drop.
;
; OBJ_MAX slots of OBJ_SIZE bytes:
;   +0 type   +1/+2 world x (left of a 16-wide box)   +3 y (playfield)
;   +4 timer  +5 item id  +6 frame  +7 kind (0 brazier, 1 wall candle)
;   +8 candle index (0xFF: none)   +9 small heart sway offset / panther state
;   +10 panther vertical speed (1/16 px)   +11 its fraction
;
; Boxes: brazier y..y+31, wall candle y+8..y+23, items y+8..y+23.
;
; Candles come from the area's candle list (tools/convert_objects.py). Like
; on the NES, they get an object only while they are near the screen
; (objects_spawn), and one that has been destroyed stays destroyed until
; the area is loaded again (candle_dead bits).
;
; Behaviour follows the NES game (recorded with tools/nes_probe/):
;   brazier  flame alternates every 8 frames; wall candle every 9 frames
;   burst    20 frames: 9 + 7 + 2 + 2
;   items    appear where the candle was; big items hang 4 frames, then fall
;            1 px per frame (2 from the 8th); the small heart drifts down
;            at 1/2 px per frame, swaying sideways; touching one collects it
; ---------------------------------------------------------------------------

OBJ_NONE        equ 0
OBJ_BRAZIER     equ 1
OBJ_BURST       equ 2
OBJ_ITEM        equ 3
OBJ_CANDLE      equ 4
OBJ_ZOMBIE      equ 5
OBJ_PANTHER     equ 6
OBJ_BAT         equ 7

KIND_BRAZIER    equ 0
KIND_CANDLE     equ 1
KIND_PANTHER    equ 2                   ; 32x16 box
KIND_BAT        equ 3                   ; 16x16 box

; object frame numbers (OBJ_FRAMES in tools/convert_objects.py)
OBJF_BRAZIER    equ 0
OBJF_BURST      equ 2
OBJF_HEART      equ 6
OBJF_WHIPUP     equ 7
OBJF_DAGGER     equ 8
OBJF_CANDLE     equ 9
OBJF_SMALLHEART equ 11
OBJF_ZOMBIE     equ 12                  ; left 1/2, right 1/2
OBJF_PANTHER    equ 16                  ; sit, run1-3 facing left, then facing right
OBJF_BAT        equ 24                  ; wings 1-3 flying left, then flying right

ITEM_WHIPUP     equ 0
ITEM_HEART      equ 1
ITEM_DAGGER     equ 2
ITEM_SMALLHEART equ 3
ITEM_NONE       equ 0xFF                ; burst of an enemy: nothing drops

SPAWN_LEFT      equ 16                  ; spawn when -16 <= box x - camera <= 272
SPAWN_RIGHT     equ 272
KEEP_LEFT       equ 48                  ; free the slot when < -48 or > 304
KEEP_RIGHT      equ 304

; Clear all objects and candle flags (area load / respawn).
objects_reset:
        ld hl,obj_table
        ld de,obj_table+1
        ld bc,OBJ_MAX*OBJ_SIZE-1
        ld (hl),0
        ldir
        ld hl,candle_dead
        ld de,candle_dead+1
        ld bc,MAX_CANDLES/4-1           ; candle_dead + candle_live
        ld (hl),0
        ldir
        ld hl,0xFFFF
        ld (spawn_last),hl
        xor a
        ld (zombie_wave),a
        ld (zombie_spawn_t),a
        ret

; A = candle index -> HL = byte in candle_dead, B = bit mask (DE, C clobbered)
candle_bit:
        ld c,a
        and 7
        ld b,1
        jr z,.mask_done
.mask:
        sla b
        dec a
        jr nz,.mask
.mask_done:
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        ld e,a
        ld d,0
        ld hl,candle_dead
        add hl,de
        ret

; ---------------------------------------------------------------------------
; Spawn candles that come near the screen; free objects that left it.
; Runs when the camera has moved to another 16-px column.
; ---------------------------------------------------------------------------
objects_spawn:
        ld hl,(cam_x)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld de,(spawn_last)
        or a
        sbc hl,de
        ret z
        add hl,de
        ld (spawn_last),hl

        ; --- free objects that are far outside the screen ---
        ld ix,obj_table
        ld b,OBJ_MAX
.free_lp:
        push bc
        ld a,(ix+0)
        or a
        jr z,.free_next
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de                       ; HL = box x - camera
        ld de,KEEP_LEFT
        add hl,de
        bit 7,h
        jr nz,.free_it                  ; < -KEEP_LEFT
        ld de,KEEP_RIGHT+KEEP_LEFT+1
        or a
        sbc hl,de
        jr c,.free_next                 ; <= KEEP_RIGHT
.free_it:
        ld (ix+0),OBJ_NONE
        ld a,(ix+8)
        cp 0xFF
        jr z,.free_next
        call candle_bit                 ; no longer has an object
        ld de,MAX_CANDLES/8
        add hl,de                       ; -> candle_live
        ld a,b
        cpl
        and (hl)
        ld (hl),a
.free_next:
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        djnz .free_lp

        ; --- spawn candles in range that are neither dead nor live ---
        ld hl,(area_hdr+AH_CANDLES)
        ld a,(hl)
        inc hl
        or a
        ret z
        ld b,a
        ld c,0                          ; candle index
.spawn_lp:
        push bc
        push hl
        call spawn_candle
        pop hl
        ld de,5
        add hl,de
        pop bc
        inc c
        djnz .spawn_lp
        ret

; HL = candle record (x lo, x hi, y, item, kind), C = candle index
spawn_candle:
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                        ; HL = box x
        ld de,(cam_x)
        or a
        sbc hl,de                       ; HL = box x - camera
        ld de,SPAWN_LEFT
        add hl,de
        pop de                          ; DE = record
        bit 7,h
        ret nz                          ; left of the spawn range
        push de
        ld de,SPAWN_RIGHT+SPAWN_LEFT+1
        or a
        sbc hl,de
        pop de
        ret nc                          ; right of the spawn range
        push de
        ld a,c
        push bc
        call candle_bit
        ld a,(hl)
        and b
        jr nz,.no                       ; destroyed
        ld de,MAX_CANDLES/8
        add hl,de
        ld a,(hl)
        and b
        jr nz,.no                       ; already has an object
        push hl                         ; panthers can be switched off (tests)
        ld hl,4                         ; stack: live byte, BC, record
        add hl,sp
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = record
        ld hl,4
        add hl,de
        ld a,(hl)                       ; kind
        pop hl
        cp KIND_PANTHER
        jr nz,.allowed
        ld a,(enemies_off)
        and 2
        jr nz,.no
.allowed:
        call obj_free_slot
        jr c,.no                        ; all slots in use: try again later
        ld a,(hl)
        or b
        ld (hl),a                       ; live
        pop bc
        pop de
        ld (ix+8),c
        ld a,(de)
        ld (ix+1),a
        inc de
        ld a,(de)
        ld (ix+2),a
        inc de
        ld a,(de)
        ld (ix+3),a
        inc de
        ld a,(de)
        ld (ix+5),a
        inc de
        ld a,(de)
        ld (ix+7),a
        ld (ix+4),0
        ld (ix+9),0
        ld (ix+10),0
        ld (ix+11),0
        or a
        ld (ix+0),OBJ_BRAZIER
        ld (ix+6),OBJF_BRAZIER
        ret z
        cp KIND_PANTHER
        jr z,.panther
        ld (ix+0),OBJ_CANDLE
        ld (ix+6),OBJF_CANDLE
        ret
.panther:
        ld (ix+0),OBJ_PANTHER
        ld (ix+6),OBJF_PANTHER
        ld (ix+5),-1
        ret
.no:
        pop bc
        pop de
        ret

; -> IX = first free slot (carry clear), or carry set if all are in use
obj_free_slot:
        push bc
        push de
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
.lp:
        ld a,(ix+0)
        or a
        jr z,.found
        add ix,de
        djnz .lp
        pop de
        pop bc
        scf
        ret
.found:
        pop de
        pop bc
        or a
        ret

objects_update:
        ld ix,obj_table
        ld b,OBJ_MAX
.lp:
        push bc
        ld a,(ix+0)
        cp OBJ_BRAZIER
        jr nz,.not_brazier
        call brazier_update
        jr .next
.not_brazier:
        cp OBJ_CANDLE
        jr nz,.not_candle
        call candle_update
        jr .next
.not_candle:
        cp OBJ_BURST
        jr nz,.not_burst
        call burst_update
        jr .next
.not_burst:
        cp OBJ_ZOMBIE
        jr nz,.not_zombie
        call zombie_update
        jr .next
.not_zombie:
        cp OBJ_PANTHER
        jr nz,.not_panther
        call panther_update
        jr .next
.not_panther:
        cp OBJ_BAT
        jr nz,.not_bat
        call bat_update
        jr .next
.not_bat:
        cp OBJ_ITEM
        call z,item_update
.next:
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        djnz .lp
        ret

brazier_update:
        inc (ix+4)
        ld a,(ix+4)
        and 8
        rrca
        rrca
        rrca
        ld (ix+6),a                     ; OBJF_BRAZIER + 0/1
        jr candle_whipped

candle_update:
        ld a,(ix+4)
        inc a
        cp 18
        jr c,.t
        xor a
.t:
        ld (ix+4),a
        cp 9
        ld a,OBJF_CANDLE
        jr c,.f
        inc a
.f:
        ld (ix+6),a

candle_whipped:
        ld a,(whip_active)
        or a
        ret z
        call whip_hits_object
        ret nc
        ld a,(ix+8)                     ; destroyed for good
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ret

burst_update:
        inc (ix+4)
        ld a,(ix+4)
        ld c,OBJF_BURST
        cp 10
        jr c,.frame                     ; frames 1-9
        inc c
        cp 17
        jr c,.frame                     ; 10-16
        inc c
        cp 19
        jr c,.frame                     ; 17-18
        inc c
        cp 21
        jr c,.frame                     ; 19-20
        ld a,(ix+5)
        cp ITEM_NONE
        jr nz,.item
        ld (ix+0),OBJ_NONE              ; an enemy's burst: gone
        ret
.item:
        ld (ix+0),OBJ_ITEM              ; the item appears
        ld (ix+4),0
        ld (ix+9),0
        ld e,(ix+5)
        ld d,0
        ld hl,item_frames
        add hl,de
        ld c,(hl)
.frame:
        ld (ix+6),c
        ret

item_frames:
        db OBJF_WHIPUP, OBJF_HEART, OBJF_DAGGER, OBJF_SMALLHEART

item_update:
        inc (ix+4)
        ld a,(ix+5)
        cp ITEM_SMALLHEART
        jr z,.small_heart
        ld a,(ix+4)
        cp 5
        jr c,.pickup                    ; hangs in the air for 4 frames
        ld b,1
        cp 8
        jr c,.fall
        inc b
        jr .fall

.small_heart:                           ; 1/2 px per frame, swaying
        call item_on_ground
        jr c,.pickup
        ld a,(ix+4)
        and 0x7C
        rrca
        rrca
        ld e,a
        ld d,0
        ld hl,sway_table
        add hl,de
        ld a,(hl)                       ; wanted offset
        ld c,a
        sub (ix+9)                      ; move by the difference
        ld (ix+9),c
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+4)
        and 1
        jr z,.pickup
        ld b,1

.fall:                                  ; fall B pixels, one at a time
        push bc
        call item_on_ground
        pop bc
        jr c,.pickup                    ; resting on the ground
        inc (ix+3)
        ld a,(ix+3)
        cp MT_ROWS*16
        jp nc,.gone                     ; fell into a pit
        djnz .fall

.pickup:                                ; Simon's box (px+3..px+12, py..py+31)
        ld hl,(px)                      ; vs item (x..x+15, y+8..y+23)
        ld de,3
        add hl,de
        ex de,hl                        ; DE = Simon left
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,15
        add hl,bc                       ; HL = item right
        or a
        sbc hl,de
        ret c
        ld hl,(px)
        ld de,12
        add hl,de                       ; HL = Simon right
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret c
        ld l,(ix+3)
        ld h,0
        ld de,23
        add hl,de                       ; HL = item bottom
        ld de,(py)
        or a
        sbc hl,de
        bit 7,h
        ret nz
        ld hl,(py)
        ld de,31
        add hl,de                       ; HL = Simon bottom
        ld e,(ix+3)
        ld d,0
        ld a,8
        add a,e
        ld e,a
        ld a,d
        adc a,0
        ld d,a                          ; DE = item top
        or a
        sbc hl,de
        bit 7,h
        ret nz

        ld a,(ix+5)                     ; collected
        ld c,5
        cp ITEM_HEART
        jr z,.add_hearts
        ld c,1
        cp ITEM_SMALLHEART
        jr z,.add_hearts
        cp ITEM_WHIPUP
        jr nz,.not_whip
        ld a,(whip_level)
        cp 2
        jr nc,.gone
        inc a
        ld (whip_level),a
        jr .gone
.not_whip:
        cp ITEM_DAGGER
        jr nz,.gone
        ld a,1
        ld (subweapon),a
        jr .gone
.add_hearts:
        ld a,(hearts)
        add a,c
        cp 100
        jr c,.hearts_ok
        ld a,99
.hearts_ok:
        ld (hearts),a
        ld a,1
        ld (hud_dirty),a
.gone:
        ld (ix+0),OBJ_NONE
        ret

; ---------------------------------------------------------------------------
; Zombie (measured in the NES entrance hall): walks straight across at
; 7 px every 8 frames, legs alternate every 8 frames, one whip hit kills
; it, touching it hurts Simon (ZOMBIE_DAMAGE). +5 = direction (+1 / -1).
; ---------------------------------------------------------------------------
zombie_update:
        inc (ix+4)
        ld a,(ix+4)
        and 7
        jr z,.no_step                   ; rests 1 frame in 8
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
.no_step:
        ld a,(ix+4)
        rrca
        rrca
        rrca
        and 1
        ld c,a
        ld a,(ix+5)
        or a
        ld a,OBJF_ZOMBIE
        jp m,.left
        add a,2
.left:
        add a,c
        ld (ix+6),a

        ld l,(ix+1)                     ; walked off the screen: gone
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        bit 7,h
        jp nz,.gone
        ld de,256+16+1
        or a
        sbc hl,de
        jr nc,.gone

        ld a,(whip_active)              ; whipped
        or a
        jr z,.touch
        call whip_hits_object
        jr nc,.touch
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ld hl,kills
        inc (hl)
        ret

.touch:                                 ; zombie x+2..x+13 vs Simon px+3..px+12
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld hl,(px)
        ld de,3
        add hl,de
        ex de,hl                        ; DE = Simon left
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,13
        add hl,bc                       ; zombie right
        or a
        sbc hl,de
        ret c
        ld hl,(px)
        ld de,12
        add hl,de                       ; Simon right
        ld e,(ix+1)
        ld d,(ix+2)
        inc de
        inc de                          ; zombie left
        or a
        sbc hl,de
        ret c
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)                       ; vertical overlap
        sub (ix+3)
        jr nc,.dy
        neg
.dy:
        cp 28
        ret nc
        ld hl,(px)                      ; knocked away from the zombie
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld b,1
        jp nc,simon_hurt
        ld b,-1
        jp simon_hurt
.gone:
        ld (ix+0),OBJ_NONE
        ret

; ---------------------------------------------------------------------------
; Black panther (measured in the NES entrance hall). +9 = state:
;   0 waits on its platform until Simon is within PANTHER_WAKE pixels
;   1 runs towards him along the platform (2 px per frame)
;   2 leaps off the edge: 2 px across, falls under gravity until it lands
;   3 runs along the floor towards the side Simon was on, off the screen
; Run cycle: 3 frames of 7. One whip hit kills it; touching it hurts Simon.
; ---------------------------------------------------------------------------
panther_update:
        ld a,(ix+9)
        or a
        jr nz,.awake
        call simon_dx                   ; HL = Simon centre - panther centre
        bit 7,h                         ; |HL| < PANTHER_WAKE ?
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
        jp nz,.check_hits
        ld a,l
        cp PANTHER_WAKE
        jp nc,.check_hits
        call simon_dx                   ; run towards him
        ld (ix+5),1
        bit 7,h
        jr z,.dir_set
        ld (ix+5),-1
.dir_set:
        ld (ix+9),1
        ld (ix+4),0
        ld a,(ix+8)                     ; once awake it never comes back,
        cp 0xFF                         ; even if it leaves the screen
        jr z,.awake
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a

.awake:
        inc (ix+4)                      ; move 2 px in the running direction
        ld a,(ix+5)
        add a,a
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h

        ld a,(ix+9)
        cp 2
        jr z,.leaping
        ld l,(ix+1)                     ; 1, 3: ground under it? If not, leap
        ld h,(ix+2)                     ; (off a platform, or again at the
                                        ; next edge, so it never runs on air)
        ld de,16
        add hl,de
        ld e,(ix+3)
        ld d,0
        push hl
        ld hl,16
        add hl,de
        ex de,hl
        pop hl
        call solid_at
        jp c,.check_hits
        ld (ix+9),2                     ; off the edge: leap
        ld (ix+10),PANTHER_VY0
        ld (ix+11),0
        jr .check_hits

.leaping:                               ; vy += g (capped), y += vy / 16
        ld a,(ix+10)
        add a,PANTHER_GRAVITY
        cp PANTHER_VMAX+1
        jp m,.vy_ok
        ld a,PANTHER_VMAX
.vy_ok:
        ld (ix+10),a
        ld c,a                          ; 16 * y + fraction += vy
        ld a,(ix+11)
        add a,c
        ld c,a
        sra a
        sra a
        sra a
        sra a                           ; whole pixels (signed)
        add a,(ix+3)
        ld (ix+3),a
        ld a,c
        and 15
        ld (ix+11),a
        ld a,(ix+10)
        or a
        jp m,.check_hits                ; still rising
        ld l,(ix+1)                     ; landed? (feet at y+16)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld e,(ix+3)
        ld d,0
        push hl
        ld hl,16
        add hl,de
        ex de,hl
        pop hl
        call solid_at
        jr nc,.not_landed
        ld a,(ix+3)                     ; stand on the tile
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
        ld (ix+9),3
        call simon_dx                   ; run towards the side Simon is on
        ld (ix+5),1
        bit 7,h
        jr z,.check_hits
        ld (ix+5),-1
        jr .check_hits
.not_landed:
        ld a,(ix+3)
        cp MT_ROWS*16
        jr c,.check_hits
        ld (ix+0),OBJ_NONE              ; fell out of the playfield
        ret

.check_hits:
        ; animation frame: sit, or run cycle (leap: run2), +4 facing right
        ld a,(ix+9)
        or a
        ld c,0
        jr z,.frame
        ld c,2
        cp 2
        jr z,.frame
        ld a,(ix+4)                     ; run: (timer / 7) mod 3
        ld c,0
.div7:
        sub 7
        jr c,.cycle
        inc c
        jr .div7
.cycle:
        ld a,c
.mod3:
        sub 3
        jr nc,.mod3
        add a,3+1
        ld c,a
.frame:
        ld a,(ix+5)
        or a
        ld a,OBJF_PANTHER
        jp m,.left
        add a,4
.left:
        add a,c
        ld (ix+6),a

        ld a,(whip_active)              ; whipped
        or a
        jr z,.touch
        call whip_hits_object
        jr nc,.touch
        ld a,(ix+8)                     ; dead for good
        cp 0xFF
        jr z,.no_flag
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
.no_flag:
        ld a,(ix+3)                     ; burst centred on its 16-px body
        sub 8
        ld (ix+3),a
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ld (ix+7),KIND_BRAZIER
        ld hl,kills
        inc (hl)
        ret

.touch:                                 ; panther x+4..x+27, y..y+15
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld hl,(px)
        ld de,3
        add hl,de
        ex de,hl                        ; DE = Simon left
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,27
        add hl,bc
        or a
        sbc hl,de
        ret c
        ld hl,(px)
        ld de,12-4
        add hl,de                       ; Simon right - 4
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret c
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)                     ; panther y..y+15 vs Simon py..py+31
        add a,15
        ld hl,py
        sub (hl)
        ret c
        ld a,(py)
        add a,31
        sub (ix+3)
        ret c
        call simon_dx
        ld b,1
        bit 7,h
        jp z,simon_hurt
        ld b,-1
        jp simon_hurt

; HL = (Simon centre x) - (object centre x), for a 32-px-wide object
simon_dx:
        ld hl,(px)
        ld de,8
        add hl,de
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld de,-16
        add hl,de
        ret

; ---------------------------------------------------------------------------
; Zombie spawners: while one is near the camera, a zombie appears every
; ZOMBIE_INTERVAL frames at alternating screen edges, in waves of ZOMBIE_MAX.
; Like the NES, the next wave starts only after the last one is gone
; (killed or walked off screen) plus a pause.
; ---------------------------------------------------------------------------
enemies_update:
        ld a,(enemies_off)
        and 1
        ret nz
        ld hl,(area_hdr+AH_ENEMIES)
        ld a,(hl)
        inc hl
        or a
        ret z
        ld b,a
.lp:
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = spawner x
        inc hl
        ld c,(hl)                       ; C = y
        inc hl
        ld a,(hl)                       ; spawner type
        ld (spawner_type),a
        inc hl
        push hl
        push bc
        ex de,hl
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,SPAWNER_LEFT
        add hl,de
        bit 7,h
        jr nz,.next
        ld de,SPAWNER_RIGHT+SPAWNER_LEFT+1
        or a
        sbc hl,de
        jr c,.active
.next:
        pop bc
        pop hl
        djnz .lp
        ret
.active:
        pop bc
        pop hl
        ld a,(spawner_type)
        cp ENEMY_BAT
        jp z,bat_spawner
        ld hl,zombie_spawn_t
        inc (hl)
        ld a,(zombie_wave)
        cp ZOMBIE_MAX
        jr c,.in_wave
        push bc                         ; wave complete: wait until its
        call count_zombies              ; zombies are all gone, then pause
        pop bc
        ld hl,zombie_spawn_t
        jr z,.all_gone
        ld (hl),0
        ret
.all_gone:
        ld a,(hl)
        cp ZOMBIE_PAUSE
        ret c
        xor a
        ld (hl),a
        ld (zombie_wave),a
        ret
.in_wave:
        ld a,(hl)
        cp ZOMBIE_INTERVAL
        ret c
        ld (hl),0
        push bc
        call count_zombies
        pop bc
        cp ZOMBIE_MAX
        ret nc
        call obj_free_slot
        ret c
        ld hl,zombie_wave
        inc (hl)
        ld hl,(cam_x)
        ld a,(zombie_side)
        xor 1
        ld (zombie_side),a
        jr z,.left_edge
        ld de,240                       ; right edge, walking left
        add hl,de
        ld (ix+5),-1
        jr .place
.left_edge:
        ld (ix+5),1                     ; left edge, walking right
.place:
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),c
        ld (ix+0),OBJ_ZOMBIE
        ld (ix+4),0
        ld (ix+7),KIND_BRAZIER          ; 16x32 box for the whip
        ld (ix+8),0xFF
        ld (ix+9),0
        ret

; ---------------------------------------------------------------------------
; Bat (measured in NES stage 2): while a bat spawner is near and no bat is
; flying, one appears after BAT_DELAY frames at the screen edge Simon faces,
; at his height, and flies at him: 9 px every 8 frames across, dipping 18 px
; and back every 96 frames. Wings: 3 frames of 9 (1 2 3 2). Touching Simon
; hurts him and kills the bat; the whip kills it.
;   +4 timer   +5 direction   +9 start y   +10 x fraction
; ---------------------------------------------------------------------------
bat_spawner:
        ld ix,obj_table                 ; a bat flying already?
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
.find:
        ld a,(ix+0)
        cp OBJ_BAT
        jr z,.flying
        add ix,de
        djnz .find
        ld hl,bat_spawn_t
        inc (hl)
        ld a,(hl)
        cp BAT_DELAY
        ret c
        ld (hl),0
        ld a,(hurt_state)               ; not while Simon is knocked back
        or a
        ret nz
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
        ld a,(py)
        add a,8
        ld (ix+3),a
        ld (ix+9),a
        ld (ix+0),OBJ_BAT
        ld (ix+4),0
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+10),0
        jp bat_frame
.flying:
        xor a
        ld (bat_spawn_t),a
        ret

bat_update:
        inc (ix+4)
        ld a,(ix+10)                    ; x: 1 + 1/8 px per frame
        add a,0x20
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
        ld a,(ix+4)                     ; y: start y + wave(timer mod 96)
.mod96:
        sub 96
        jr nc,.mod96
        add a,96
        ld e,a
        ld d,0
        ld hl,bat_wave
        add hl,de
        ld a,(ix+9)
        add a,(hl)
        ld (ix+3),a
        call bat_frame

        ld l,(ix+1)                     ; flew off the screen: gone
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        bit 7,h
        jr nz,.gone
        ld de,256+16+1
        or a
        sbc hl,de
        jr nc,.gone

        ld a,(whip_active)
        or a
        jr z,.touch
        call whip_hits_object
        jr nc,.touch
        ld hl,kills
        inc (hl)
        jr .burst
.touch:                                 ; bat x+2..x+13 vs Simon px+3..px+12
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld hl,(px)
        ld de,3
        add hl,de
        ex de,hl
        ld l,(ix+1)
        ld h,(ix+2)
        ld bc,13
        add hl,bc
        or a
        sbc hl,de
        ret c
        ld hl,(px)
        ld de,12
        add hl,de
        ld e,(ix+1)
        ld d,(ix+2)
        inc de
        inc de
        or a
        sbc hl,de
        ret c
        ld a,(py+1)                     ; bat y+2..y+13 vs Simon py..py+31
        or a
        ret nz
        ld a,(ix+3)
        add a,13
        ld hl,py
        sub (hl)
        ret c                           ; above him
        cp 32+11
        ret nc                          ; below him
        ld b,(ix+5)                     ; knocked the way the bat flies
        call simon_hurt
.burst:
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ret
.gone:
        ld (ix+0),OBJ_NONE
        ret

; wing frame: (timer / 9) mod 4 -> 0 1 2 1, +3 flying right
bat_frame:
        ld a,(ix+4)
        ld c,0
.div9:
        sub 9
        jr c,.d9
        inc c
        jr .div9
.d9:
        ld a,c
        and 3
        cp 3
        jr nz,.f
        ld a,1
.f:
        bit 7,(ix+5)
        jr nz,.left
        add a,3
.left:
        add a,OBJF_BAT
        ld (ix+6),a
        ret

; 9 - 9 cos(2 pi t / 96)
bat_wave:
        db 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4
        db 4, 5, 6, 6, 7, 7, 8, 8, 9, 10, 10, 11, 11, 12, 12, 13
        db 13, 14, 14, 15, 15, 16, 16, 16, 17, 17, 17, 18, 18, 18, 18, 18
        db 18, 18, 18, 18, 18, 18, 17, 17, 17, 16, 16, 16, 15, 15, 14, 14
        db 14, 13, 12, 12, 11, 11, 10, 10, 9, 8, 8, 7, 7, 6, 6, 5
        db 4, 4, 4, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0

; -> A = number of zombies alive, Z if none (BC, DE, IX clobbered)
count_zombies:
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
        ld c,0
.lp:
        ld a,(ix+0)
        cp OBJ_ZOMBIE
        jr nz,.not_one
        inc c
.not_one:
        add ix,de
        djnz .lp
        ld a,c
        or a
        ret

; Carry set if the item (sprite y+8..y+23) rests on solid ground.
item_on_ground:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld e,(ix+3)
        ld d,0
        push hl
        ld hl,24
        add hl,de
        ex de,hl
        pop hl
        jp solid_at

; Small heart sideways drift (pixels), 32 steps of 4 frames
sway_table:
        db 0, 3, 6, 8, 11, 12, 14, 15, 15, 15, 14, 12, 11, 8, 6, 3
        db 0, -3, -6, -8, -11, -12, -14, -15, -15, -15, -14, -12, -11, -8, -6, -3

; Carry set if the whip's strike box overlaps the object's box.
; Boxes by kind: brazier/zombie 16x32 at y, wall candle 16x16 at y+8,
; panther 32x16 at y. (signed 16-bit compares: the whip can be left of x = 0)
whip_hits_object:
        ld a,(ix+7)
        ld de,15                        ; DE = box width - 1
        ld bc,31*256 + 0                ; B = height - 1, C = top offset
        cp KIND_PANTHER
        jr nz,.not_wide
        ld de,31
        ld b,15
        jr .box_ready
.not_wide:
        cp KIND_BAT
        jr nz,.not_bat
        ld b,15
        jr .box_ready
.not_bat:
        cp KIND_CANDLE
        jr nz,.box_ready
        ld bc,15*256 + 8
.box_ready:
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld de,(whip_x1)
        or a
        sbc hl,de                       ; box right - whip left
        bit 7,h
        jr nz,.no
        ld hl,(whip_x2)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de                       ; whip right - box left
        bit 7,h
        jr nz,.no
        ld a,(ix+3)
        add a,c
        ld l,a
        ld h,0
        push hl                         ; box top
        ld e,b
        ld d,0
        add hl,de                       ; box bottom
        ld de,(whip_y1)
        or a
        sbc hl,de                       ; box bottom - whip top
        pop de
        bit 7,h
        jr nz,.no
        ld hl,(whip_y2)
        or a
        sbc hl,de                       ; whip bottom - box top
        bit 7,h
        jr nz,.no
        scf
        ret
.no:
        or a
        ret

; ---------------------------------------------------------------------------
; Append the objects' sprites to sat_buf (called by build_sat with IY at the
; next free entry). Each sprite's colour column is listed in obj_sct_list;
; write_player_sprites copies those into the hidden page's colour table.
; ---------------------------------------------------------------------------
objects_draw:
        ld (spr_sat_ptr),iy
        ld a,(spr_total)                ; alternate HL: next obj_sct_list entry
        ld e,a
        ld d,0
        ld hl,obj_sct_list
        add hl,de
        push hl
        exx
        pop hl
        exx
        ; Rotate which object comes first every frame: with more than 8
        ; sprites on a line, the hardware drops the last ones, so rotating
        ; turns a permanently missing sprite into flicker (as on the NES).
        ld a,(frame_count)
        and OBJ_MAX-1
        add a,a
        add a,a                         ; * 4
        ld e,a
        add a,a                         ; * 8
        add a,e                         ; * 12 = OBJ_SIZE
        ASSERT OBJ_SIZE == 12 && OBJ_MAX == 8
        ld e,a
        ld d,0
        ld ix,obj_table
        add ix,de
        ld b,OBJ_MAX
.obj:
        push bc
        ld a,(ix+0)
        or a
        jp z,.next_obj
        ld l,(ix+1)                     ; screen x of the box
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h                          ; visible if -32 <= box x <= 255
        or a
        jr z,.on_screen
        inc a
        jp nz,.next_obj
        ld a,l
        cp 0xE0
        jp c,.next_obj
.on_screen:
        ld (spr_bx),hl
        ld a,(ix+3)
        add a,PF_TOP_PX-1
        ld c,a                          ; C = sprite y of the box
        ld a,(ix+6)
        push ix
        call obj_frame_address
        push ix
        pop de                          ; DE = frame data
        ld a,(de)
        inc de
        ld b,a                          ; B = sprites in the frame
        ld hl,(spr_sat_ptr)
.spr:
        ld a,(spr_total)
        cp MAX_SPRITES
        jr nc,.frame_done               ; hardware limit: 32 sprites
        ld a,(de)                       ; y = box y + dy
        add a,c
        cp 192
        jr nc,.skip_dy                  ; below the screen (and never Y = 216)
        ld (hl),a
        inc de
        ld a,(de)                       ; x = box x + dx (16-bit)
        push hl
        push de
        ld l,a
        rla
        sbc a,a
        ld h,a
        ld de,(spr_bx)
        add hl,de
        ld a,h
        or a
        ld a,l
        pop de
        pop hl
        jr nz,.skip_dx                  ; off the left or right edge
        inc hl
        ld (hl),a
        inc hl
        inc de
        ld a,(de)                       ; pattern: after Simon's slots
        add a,PLAYER_SPRITES
        add a,a
        add a,a
        ld (hl),a
        inc hl
        inc hl
        inc de
        ld a,(de)                       ; colour column
        inc de
        exx
        ld (hl),a
        inc hl
        exx
        ld a,(spr_total)
        inc a
        ld (spr_total),a
        djnz .spr
        jr .frame_done
.skip_dy:
        inc de
.skip_dx:
        inc de
        inc de
        inc de
        djnz .spr
.frame_done:
        ld (spr_sat_ptr),hl
        pop ix
.next_obj:
        ld de,OBJ_SIZE
        add ix,de
        push ix                         ; wrap around the table
        pop hl
        ld de,obj_table+OBJ_MAX*OBJ_SIZE
        or a
        sbc hl,de
        jr c,.no_wrap
        ld ix,obj_table
.no_wrap:
        pop bc
        dec b
        jp nz,.obj
        ld iy,(spr_sat_ptr)
        ret

; A = object frame -> IX = frame data (the area's object frame table)
obj_frame_address:
        ld l,a
        ld h,0
        add hl,hl
        ld de,(area_hdr+AH_OBJFRAMES)
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        pop ix
        ret

; Copy the area's object sprite patterns into pattern slots
; PLAYER_SPRITES.. of both sprite pages (they stay resident).
objects_load_patterns:
        xor a
        call .page
        ld a,1
.page:
        di
        ld hl,VRAM_SPT + PLAYER_SPRITES*32
        call vram_set_write_far
        ld hl,(area_hdr+AH_OBJSPT)
        ld bc,(area_hdr+AH_OBJSPTSZ)
.lp:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.lp
        jp vram_r14_zero                ; (enables interrupts)

; ---------------------------------------------------------------------------
; HUD: hearts counter (row 1, columns 25-26), written during VBLANK
; ---------------------------------------------------------------------------
HUD_HEARTS_ADDR equ VRAM_PNT + 32 + 25
HUD_HP_ADDR     equ VRAM_PNT + 32 + 3

hud_update:
        ld a,(hud_dirty)
        or a
        ret z
        xor a
        ld (hud_dirty),a
        ld hl,HUD_HP_ADDR               ; health bar: one tile per 8 HP
        call vram_set_write
        ld a,(hp)
        ld c,a
        ld b,8
.bar:
        ld a,c
        sub 8
        ld c,a
        ld a,HUDT_BAR_PLAYER
        jr nc,.full
        ld a,HUDT_BAR_EMPTY
        ld c,0
.full:
        out (VDP_DATA),a
        djnz .bar
        ld hl,HUD_HEARTS_ADDR
        call vram_set_write
        ld a,(hearts)
        ld b,"0"-1
.tens:
        inc b
        sub 10
        jr nc,.tens
        add a,10+"0"
        ld c,a
        ld a,b
        out (VDP_DATA),a
        ld a,c
        out (VDP_DATA),a
        ret
