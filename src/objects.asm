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
OBJ_FISH        equ 8
OBJ_FIREBALL    equ 9
OBJ_BOSS        equ 10
OBJ_ORB         equ 11
OBJ_DAGGER      equ 12
OBJ_AXE         equ 13
OBJ_HOLY        equ 14                  ; holy water: bottle, then fire
OBJ_KNIGHT      equ 15                  ; block 2: spear knight
OBJ_MHEAD       equ 16                  ; block 2: Medusa head
OBJ_HBAT        equ 17                  ; block 2: a bat hanging until Simon comes
OBJ_MEDUSA      equ 18                  ; the stage 6 boss
OBJ_SNAKE       equ 19                  ; her snakes
OBJ_FLEA        equ 20                  ; block 3: fleaman
OBJ_SKEL        equ 21                  ; skeleton
OBJ_BONE        equ 22                  ; its bones
OBJ_PILLAR      equ 23                  ; bone pillar
OBJ_RAVEN       equ 24                  ; raven
OBJ_GHOST       equ 25                  ; ghost

KIND_BRAZIER    equ 0
KIND_CANDLE     equ 1
KIND_PANTHER    equ 2                   ; 32x16 box
KIND_BAT        equ 3                   ; 16x16 box
KIND_FIREBALL   equ 4                   ; 8x8 box at +4,+4
KIND_BOSS       equ 5                   ; 48x32 sprite, 32x24 box at +8
KIND_KNIGHT     equ 6                   ; candle list only: a spear knight
KIND_HBAT       equ 7                   ; candle list only: a hanging bat
KIND_MEDUSA     equ 8                   ; candle list only: Medusa
KIND_FLEA       equ 9                   ; candle list only: block 3's enemies
KIND_SKEL       equ 10
KIND_PILLAR     equ 11
KIND_RAVEN      equ 12
KIND_GHOST      equ 13

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
OBJF_FISH       equ 30                  ; walk 1, walk 2, shoot facing left, then right
OBJF_FIREBALL   equ 36
OBJF_BOSS       equ 37                  ; wings open, wings up
OBJF_ORB        equ 39
OBJF_BOSS_SLEEP equ 55                  ; asleep: a small bat
OBJF_DAGGER_FLY equ 40                  ; flying right, flying left
OBJF_AXE        equ 42                  ; turning: 4 frames (also its pickup)
OBJF_BOTTLE     equ 46                  ; holy water (also its pickup)
OBJF_FLAME      equ 47                  ; holy water's fire: 3 small flames
OBJF_HOLY_ITEM  equ 50
OBJF_WATCH_ITEM equ 51
OBJF_FLAME4     equ 52                  ; the fire's wide flames
OBJF_AXE_ITEM   equ 54
OBJF_MHEAD      equ 56                  ; Medusa head 1/2 flying left, then right
OBJF_HBAT_HANG  equ 60
OBJF_HBAT       equ 61                  ; wings 1-3 flying left, then right
OBJF_MEDUSA     equ 67                  ; her two pictures
OBJF_SNAKE      equ 69                  ; left, right
OBJF_FLEA       equ 71                  ; left, right
OBJF_GHOST      equ 73                  ; left, right
OBJF_BONE       equ 75
OBJF_PILLAR     equ 76
OBJF_RAVEN_PERCH equ 77
OBJF_RAVEN      equ 78                  ; wings 1-3 left, then right

ITEM_WHIPUP     equ 0
ITEM_HEART      equ 1
ITEM_DAGGER     equ 2
ITEM_SMALLHEART equ 3
ITEM_AXE        equ 4
ITEM_HOLYWATER  equ 5
ITEM_STOPWATCH  equ 6
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
        jp nz,.no                       ; destroyed
        ld de,MAX_CANDLES/8
        add hl,de
        ld a,(hl)
        and b
        jp nz,.no                       ; already has an object
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
        cp KIND_PANTHER                 ; (placed enemies: panthers, knights,
        jr z,.placed                    ; hanging bats)
        cp KIND_KNIGHT
        jr c,.allowed
        cp KIND_MEDUSA                  ; (not the boss)
        jr z,.allowed
.placed:
        ld a,(enemies_off)
        and 2
        jp nz,.no
.allowed:
        call obj_free_slot
        jp c,.no                        ; all slots in use: try again later
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
        cp KIND_BOSS
        jr z,.boss
        cp KIND_KNIGHT
        jr z,.knight
        cp KIND_HBAT
        jr z,.hbat
        cp KIND_MEDUSA
        jr z,.medusa
        cp KIND_FLEA
        jp nc,block3_spawn
        ld (ix+0),OBJ_CANDLE
        ld (ix+6),OBJF_CANDLE
        ret
.panther:
        ld (ix+0),OBJ_PANTHER
        ld (ix+6),OBJF_PANTHER
        ld (ix+5),-1
        ret
.knight:
        ld (ix+0),OBJ_KNIGHT
        ld (ix+7),KIND_BRAZIER          ; 16x32 box
        ld (ix+5),-1
        ld a,(frame_count)              ; when it next faces Simon
        and 63
        add a,KNIGHT_TURN
        ld (ix+10),a
        jp knight_frame
.medusa:
        ld (ix+0),OBJ_MEDUSA
        ld (ix+6),OBJF_MEDUSA
        jr .boss_common
.hbat:
        ld (ix+0),OBJ_HBAT
        ld (ix+7),KIND_BAT              ; 16x16 box
        ld (ix+6),OBJF_HBAT_HANG
        ret
.boss:
        ld (ix+0),OBJ_BOSS
        ld (ix+6),OBJF_BOSS_SLEEP
.boss_common:
        ld a,BOSS_HP
        ld (boss_hp),a
        xor a
        ld (boss_inv),a
        ld a,1
        ld (hud_dirty),a
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
        ld a,(freeze_t)                 ; stopwatch: enemies and their
        or a                            ; fireballs stand still
        jr z,.moving
        ld a,(ix+0)
        cp OBJ_ZOMBIE
        jr c,.moving
        cp OBJ_FIREBALL+1
        jr nc,.moving
        call frozen_update
        jp .next
.moving:
        ld a,(ix+0)
        cp OBJ_BRAZIER
        jr nz,.not_brazier
        call brazier_update
        jp .next
.not_brazier:
        cp OBJ_CANDLE
        jr nz,.not_candle
        call candle_update
        jp .next
.not_candle:
        cp OBJ_BURST
        jr nz,.not_burst
        call burst_update
        jp .next
.not_burst:
        cp OBJ_ZOMBIE
        jr nz,.not_zombie
        call zombie_update
        jp .next
.not_zombie:
        cp OBJ_PANTHER
        jr nz,.not_panther
        call panther_update
        jp .next
.not_panther:
        cp OBJ_BAT
        jr nz,.not_bat
        call bat_update
        jp .next
.not_bat:
        cp OBJ_FISH
        jr nz,.not_fish
        call fish_update
        jp .next
.not_fish:
        cp OBJ_FIREBALL
        jr nz,.not_fireball
        call fireball_update
        jp .next
.not_fireball:
        cp OBJ_BOSS
        jr nz,.not_boss
        call boss_update
        jp .next
.not_boss:
        cp OBJ_ORB
        jr nz,.not_orb
        call orb_update
        jp .next
.not_orb:
        cp OBJ_DAGGER
        jr nz,.not_dagger
        call dagger_update
        jp .next
.not_dagger:
        cp OBJ_AXE
        jr nz,.not_axe
        call axe_update
        jp .next
.not_axe:
        cp OBJ_HOLY
        jr nz,.not_holy
        call holy_update
        jp .next
.not_holy:
        cp OBJ_KNIGHT
        jr nz,.not_knight
        call knight_update
        jp .next
.not_knight:
        cp OBJ_MHEAD
        jr nz,.not_mhead
        call mhead_update
        jp .next
.not_mhead:
        cp OBJ_HBAT
        jr nz,.not_hbat
        call hbat_update
        jp .next
.not_hbat:
        cp OBJ_MEDUSA
        jr nz,.not_medusa
        call medusa_update
        jp .next
.not_medusa:
        cp OBJ_SNAKE
        jr nz,.not_snake
        call snake_update
        jp .next
.not_snake:
        cp OBJ_FLEA
        jr c,.not_block3
        call block3_update
        jp .next
.not_block3:
        cp OBJ_ITEM
        call z,item_update
.next:
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        dec b
        jp nz,.lp
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
        call weapon_hits
        ret nc
        ld a,(ix+8)                     ; destroyed for good
        call candle_bit
        ld a,(hl)
        or b
        ld (hl),a
        ld a,SND_HIT                    ; (struck: candle or enemy)
        call sfx_play
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
        call item_subweapon             ; the sub-weapon Simon already holds:
        jr z,.not_held                  ; a heart instead (NES)
        ld hl,subweapon
        cp (hl)
        jr nz,.not_held
        ld (ix+5),ITEM_SMALLHEART
.not_held:
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

; A = the sub-weapon number of item (IX+5), Z if it is not a sub-weapon
item_subweapon:
        ld a,(ix+5)
        cp ITEM_DAGGER
        jr z,.dagger
        sub ITEM_AXE
        jr c,.none
        cp 3
        jr nc,.none
        add a,2                         ; axe 2, holy water 3, stopwatch 4
        ret
.dagger:
        ld a,1
        or a
        ret
.none:
        xor a
        ret

item_frames:
        db OBJF_WHIPUP, OBJF_HEART, OBJF_DAGGER, OBJF_SMALLHEART, OBJF_AXE_ITEM, OBJF_HOLY_ITEM
        db OBJF_WATCH_ITEM

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
        jr c,.in_view
        cp 256-32                       ; (y 224-255: still above the top, from
        jp c,.gone                      ; a candle high on a wall): else a pit
.in_view:
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

        ld a,(ix+5)                     ; collected: hearts have their own
        cp ITEM_HEART                   ; sound, the rest share one
        ld b,SND_HEART
        jr z,.snd
        cp ITEM_SMALLHEART
        jr z,.snd
        ld b,SND_ITEM
.snd:
        ld a,b
        call sfx_play
        ld a,(ix+5)
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
        call item_subweapon             ; sub-weapons: dagger 1, axe 2, holy water 3,
        jr z,.gone                      ; stopwatch 4
        ld (subweapon),a
        ld a,1
        ld (hud_dirty),a
        push ix
        call load_sub_patterns          ; its sprites into the window
        pop ix
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
        ld a,(ix+9)
        or a
        jr nz,.falling
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
        call zombie_ground              ; walked off a platform's edge: it
        jr c,.no_step                   ; drops to the floor below (NES)
        ld (ix+9),1
        ld (ix+10),0
        ld (ix+11),0
        jr .no_step
.falling:                               ; straight down, vy += g, y += vy / 16
        ld a,(ix+10)
        add a,ZOMBIE_GRAVITY
        cp ZOMBIE_VMAX+1
        jr c,.vy_ok
        ld a,ZOMBIE_VMAX
.vy_ok:
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
        jp nc,.gone                     ; fell out of the playfield
        call zombie_ground
        jr nc,.no_step
        ld a,(ix+3)                     ; landed: stand on the tile, walk on
        add a,32
        and 0xF8
        sub 32
        ld (ix+3),a
        ld (ix+9),0
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

        call weapon_hits
        jr nc,.touch
        ld a,SND_HIT                    ; (struck: candle or enemy)
        call sfx_play
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ld a,SCORE_ZOMBIE
        call add_score
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

        call weapon_hits
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
        ld a,SND_HIT                    ; (struck: candle or enemy)
        call sfx_play
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ld (ix+7),KIND_BRAZIER
        ld a,SCORE_PANTHER
        call add_score
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

; Carry if there is floor under the zombie at IX (its middle, feet at y+32)
zombie_ground:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,32
        ld e,a
        ld d,0
        jr nc,.in
        inc d
.in:
        jp solid_at

; ---------------------------------------------------------------------------
; Zombie spawners: while one is near the camera, a zombie appears every
; ZOMBIE_INTERVAL frames at alternating screen edges, in waves of ZOMBIE_MAX.
; Like the NES, the next wave starts only after the last one is gone
; (killed or walked off screen) plus a pause.
; ---------------------------------------------------------------------------
enemies_update:
        ld a,(freeze_t)                 ; stopwatch: no new enemies either
        or a
        ret nz
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
        cp ENEMY_FISH
        jp z,fish_spawner
        cp ENEMY_MEDUSA
        jp z,medusa_spawner
        ld a,(swap_boss)                ; (their patterns are the boss's now)
        or a
        ret nz
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
        ld (ix+10),0
        ld (ix+11),0
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
.checks:                                ; (also the hanging bat's and the heads')
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

        call weapon_hits
        jr nc,.touch
        ld a,(ix+0)                     ; (a Medusa head scores more)
        cp OBJ_MHEAD
        ld a,SCORE_BAT
        jr nz,.score
        ld a,SCORE_MEDUSA
.score:
        call add_score
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


; (Block 2's and block 3's enemies, Medusa: src/enemies2.asm, run from RAM)

; ---------------------------------------------------------------------------
; Fishman (measured in the NES stage 2 waterway). While fewer than FISH_MAX
; are about, one jumps out of the water every FISH_DELAY frames, from a
; spawner on the screen at least FISH_AWAY px from Simon. +9 = state:
;   0 in the air: starts at -86/16 px per frame up, gravity 2/16, it passes
;     through platforms going up and lands on one coming down (or falls back
;     into the water and is gone)
;   1 walks towards Simon, 3 px every 4 frames, legs every 24 frames; falls
;     off the end of a platform; after FISH_WALK frames it stops and
;   2 shoots: a fireball after 16 frames, walks again (towards Simon) after 32
; +10 = vertical speed (1/16 px), +11 = fraction.
; ---------------------------------------------------------------------------
fish_spawner:
        ld ix,obj_table                 ; fishmen about?
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
        ld c,0
.count:
        ld a,(ix+0)
        cp OBJ_FISH
        jr nz,.not_one
        inc c
.not_one:
        add ix,de
        djnz .count
        ld hl,fish_spawn_t
        ld a,c
        cp FISH_MAX
        jr c,.wait
        ld (hl),0
        ret
.wait:
        inc (hl)
        ld a,(hl)
        cp FISH_DELAY
        ret c
        ld (hl),0
        ld a,(hurt_state)
        or a
        ret nz
        ; try the spawners in turn, starting after the last one used
        ld hl,(area_hdr+AH_ENEMIES)
        ld b,(hl)                       ; B = count
        ld c,b                          ; C = tries left
.try:
        ld a,(fish_pick)
        inc a
        cp b
        jr c,.idx
        xor a
.idx:
        ld (fish_pick),a
        ld hl,(area_hdr+AH_ENEMIES)
        inc hl
        add a,a
        add a,a
        ld e,a
        ld d,0
        add hl,de                       ; HL = record (x, y, type)
        push bc
        call .candidate
        pop bc
        ret nc                          ; spawned
        dec c
        jr nz,.try
        ret
; HL = spawner record -> carry if it can't be used, else spawns (no carry)
.candidate:
        ld a,(hl)
        ld (tmp_w),a
        inc hl
        ld a,(hl)
        ld (tmp_w+1),a                  ; spawner x
        inc hl
        ld b,(hl)                       ; y
        inc hl
        ld a,(hl)
        cp ENEMY_FISH
        scf
        ret nz
        ld hl,(tmp_w)
        ld de,(cam_x)
        or a
        sbc hl,de                       ; screen x
        ld a,h
        or a
        scf
        ret nz
        ld a,l
        cp 16
        ret c
        cp 240
        ccf
        ret c
        ld hl,(tmp_w)                   ; far enough from Simon?
        ld de,(px)
        or a
        sbc hl,de
        ld de,-8
        add hl,de                       ; spawner x - Simon centre
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
        jr nz,.ok
        ld a,l
        cp FISH_AWAY
        ret c
.ok:
        push bc
        call obj_free_slot
        pop bc
        ret c
        ld hl,(tmp_w)
        ld de,-8
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+0),OBJ_FISH
        ld (ix+4),0
        ld (ix+5),1
        ld a,SND_SPLASH                 ; it leaps out of the water
        call sfx_play
        ld (ix+7),KIND_BRAZIER          ; 16x32 box
        ld (ix+8),0xFF
        ld (ix+9),0
        ld (ix+10),FISH_VY0
        ld (ix+11),0
        call fish_face
        call fish_frame
        or a
        ret

; +5 = towards Simon
fish_face:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld (ix+5),1
        ret nc
        ld (ix+5),-1
        ret

fish_update:
        inc (ix+4)
        ld a,(ix+9)
        or a
        jp nz,.on_ground
        ld a,(ix+10)                    ; in the air: vy += g (capped)
        add a,FISH_GRAVITY
        bit 7,a
        jr nz,.vy_ok                    ; still going up
        cp FISH_VMAX+1
        jr c,.vy_ok
        ld a,FISH_VMAX
.vy_ok:
        ld (ix+10),a
        ld c,a
        ld a,(ix+11)
        add a,c
        ld c,a
        sra a
        sra a
        sra a
        sra a
        add a,(ix+3)
        ld (ix+3),a
        ld a,c
        and 15
        ld (ix+11),a
        ld a,(ix+10)
        or a
        jp m,.drawn                     ; rising: through everything
        ld a,(ix+3)
        cp FISH_WATER_Y+8
        jr c,.landing
        cp 200                          ; (above the playfield top)
        jr nc,.landing
        ld (ix+0),OBJ_NONE              ; back into the water
        ret
.landing:
        call fish_feet_solid
        jr nc,.drawn
        ld a,(ix+3)                     ; stand on the tile
        add a,32
        and 0xF8
        sub 32
        ld (ix+3),a
        ld (ix+9),1
        ld (ix+4),0
        call fish_face
        jr .drawn

.on_ground:
        cp 2
        jr z,.shooting
        ld a,(ix+4)                     ; walk: 3 px in 4 frames
        and 3
        jr z,.walked
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
.walked:
        call fish_feet_solid            ; off the end of the platform: fall
        jr c,.ground
        ld (ix+9),0
        ld (ix+10),0
        ld (ix+11),0
        jr .drawn
.ground:
        ld a,(ix+4)
        cp FISH_WALK
        jr c,.drawn
        ld (ix+9),2
        ld (ix+4),0
        jr .drawn
.shooting:
        ld a,(ix+4)
        cp 16
        call z,fish_shoot
        ld a,(ix+4)
        cp 32
        jr c,.drawn
        ld (ix+9),1
        ld (ix+4),0
        call fish_face
.drawn:
        call fish_frame

        ld l,(ix+1)                     ; off the screen: gone
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

        call weapon_hits
        jp nc,zombie_update.touch
        ld a,SCORE_FISH
        call add_score
        ld a,SND_HIT                    ; (struck: candle or enemy)
        call sfx_play
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ld a,(ix+3)                     ; burst on its body
        add a,8
        ld (ix+3),a
        ret
.gone:
        ld (ix+0),OBJ_NONE
        ret

; carry if the tile under the fishman's feet (centre, y+32) is solid
fish_feet_solid:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,32
        ld e,a
        ld d,0
        jp solid_at

; walk 1/2 by (timer / 24) mod 2, shoot in state 2, +3 facing right
fish_frame:
        ld c,2
        ld a,(ix+9)
        cp 2
        jr z,.dir
        ld c,0
        or a
        jr z,.dir
        ld a,(ix+4)
.div24:
        sub 24
        jr c,.dir
        inc c
        res 1,c
        jr .div24
.dir:
        ld a,(ix+5)
        or a
        ld a,OBJF_FISH
        jp m,.left
        add a,3
.left:
        add a,c
        ld (ix+6),a
        ret

; a fireball from the fishman's mouth, the way it faces
fish_shoot:
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld b,(ix+3)
        ld c,(ix+5)
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
        ld (ix+9),0                     ; straight across
        ld (ix+10),0                    ; 7 px every 4 frames
.none:
        pop ix
        ret

; While hovering far from Simon (BOSS_FIRE_FAR px or more), the boss spits a
; slow fireball at him (seen in a video of the NES fight: 4 px every 3 frames,
; aimed at him; never when he is close). From its mouth, across towards him,
; and 1 px up or down every 2nd frame if he is above or below.
boss_fire_if_far:
        call boss_simon_dx
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
        jr nz,boss_shoot
        ld a,l
        cp BOSS_FIRE_FAR
        ret c
boss_shoot:
        push ix
        call boss_simon_dx
        ld c,1
        bit 7,h
        jr z,.dir
        ld c,-1
.dir:
        ld a,(py)                       ; his chest vs its mouth
        add a,8
        sub (ix+3)
        sub 12
        ld b,0
        jr z,.dy
        ld b,1
        jp p,.dy
        ld b,-1
.dy:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld a,(ix+3)
        add a,8
        ld e,a
        call obj_free_slot
        jr c,.none
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),e
        ld (ix+5),c
        ld (ix+9),b
        ld (ix+10),1                    ; the boss's are slower
        ld (ix+0),OBJ_FIREBALL
        ld (ix+4),0
        ld (ix+6),OBJF_FIREBALL
        ld (ix+7),KIND_FIREBALL
        ld (ix+8),0xFF
.none:
        pop ix
        ret

; Fireball: 7 px every 4 frames (fishman) or 4 every 3 (boss) the way it was shot. Hurts Simon on contact;
; the whip destroys it.
fireball_update:
        inc (ix+4)
        ld a,(ix+10)
        or a
        jr z,.fish
        cp 2
        jr nz,.boss_ball
        ld e,2                          ; bone pillar: 2 px per frame
        jr .dx
.boss_ball:
        ld a,(ix+4)                     ; boss: 4 px every 3 frames
.mod3:
        sub 3
        jr nc,.mod3
        inc a                           ; 0 every 3rd frame: one more pixel
        ld e,1
        jr nz,.dx
        ld e,2
        jr .dx
.fish:
        ld a,(ix+4)                     ; fishman: 7 px every 4 frames
        and 3
        ld e,2
        jr nz,.dx
        ld e,1
.dx:
        bit 7,(ix+5)
        jr z,.right
        ld a,e
        neg
        ld e,a
.right:
        ld a,e
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        bit 0,(ix+4)                    ; aimed up or down: 1 px every 2nd frame
        jr z,.no_dy
        ld a,(ix+3)
        add a,(ix+9)
        ld (ix+3),a
        cp MT_ROWS*16
        jr nc,.gone                     ; left the playfield
.no_dy:

        ld de,(cam_x)                   ; off the screen: gone
        or a
        sbc hl,de
        ld de,8
        add hl,de
        bit 7,h
        jr nz,.gone
        ld de,256+8+1
        or a
        sbc hl,de
        jr nc,.gone

        call weapon_hits
        jr c,.gone
.touch:                                 ; ball x+4..x+11 vs Simon px+3..px+12
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        ld hl,(px)
        ld de,3-11
        add hl,de                       ; Simon left - ball right
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        bit 7,h
        ret z                           ; Simon is right of it
        ld e,(ix+1)
        ld d,(ix+2)
        ld hl,(px)
        ld bc,12-4
        add hl,bc
        or a
        sbc hl,de                       ; Simon right - ball left
        ret c
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)                     ; ball y+4..y+11 vs Simon py..py+31
        add a,11
        ld hl,py
        sub (hl)
        ret c
        cp 32+7
        ret nc
        ld c,a                          ; crouching: his head is down at py+20,
        ld a,(crouching)                ; so a fireball at standing height
        or a                            ; passes over him
        ld a,c
        jr z,.hit
        cp CROUCH_TOP
        ret c
.hit:
        ld b,(ix+5)
        call simon_hurt
.gone:
        ld (ix+0),OBJ_NONE
        ret


; ---------------------------------------------------------------------------
; The stage 3 boss: a giant bat (measured on the NES). It hangs asleep (and
; can't be hurt) until Simon reaches the middle of the last screen, then the
; screen locks; it sinks a little, then repeats: hover for
; BOSS_HOVER frames, swoop at where Simon is (2 px per frame across and down,
; all the way to his height),
; fly back to a new spot (3 px every 4 frames). A whip hit takes BOSS_DAMAGE
; of its BOSS_HP health (then BOSS_INV frames without hits). At 0 it burns
; for 60 frames and leaves an orb that drops to the floor; touching the orb
; clears the stage. +9 = state: 0 asleep, 1 flying to (boss_tx, boss_ty),
; 2 hovering, 3 swooping, 4 burning.
; ---------------------------------------------------------------------------
boss_update:
        inc (ix+4)
        ld a,(ix+4)                     ; wings: open / up every 8 frames
        rrca
        rrca
        rrca
        and 1
        add a,OBJF_BOSS
        ld (ix+6),a
        ld a,(boss_inv)
        or a
        jr z,.no_inv
        dec a
        ld (boss_inv),a
.no_inv:
        call in_holy_fire               ; in holy water's fire: it can't move,
        jp c,.hits                      ; and the fire goes on hurting it (NES)
        ld a,(ix+9)
        or a
        jr z,.asleep
        cp 4
        jp z,.burning
        cp 2
        jp z,.hovering
        cp 3
        jp z,.swooping

        ; 1: fly to the target, 3 px every 4 frames, y 1 px every 2nd frame
        ld a,(ix+4)
        and 3
        jr z,.fly_y
        call boss_step_x
.fly_y:
        ld a,(ix+4)
        and 1
        call z,boss_step_y
        call boss_at_target
        jp nz,.hits
        ld (ix+9),2
        ld (ix+4),0
        jp .hits

.asleep:                                ; asleep it can't be hurt; it wakes
        ld (ix+6),OBJF_BOSS_SLEEP       ; when Simon's centre reaches the
        ld hl,(area_hdr+AH_MAXCAM)      ; middle of the last screen (its own)
        ld de,128-8
        add hl,de
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
.wake:
        push ix                         ; the zombies go; the boss's patterns
        ld ix,obj_table                 ; take their place (swap window)
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
.no_zombies:
        ld a,(ix+0)
        cp OBJ_ZOMBIE
        jr nz,.next_obj
        ld (ix+0),OBJ_NONE
.next_obj:
        add ix,de
        djnz .no_zombies
        ld a,1
        call load_swap_patterns
        pop ix
        ld a,SND_BOSS
        call music_restart
        ld hl,(cam_x)                   ; the screen locks: no way back
        ld (cam_min),hl
        ld a,1
        ld (cam_lock),a
        ld l,(ix+1)                     ; sink a little where it is
        ld h,(ix+2)
        ld (boss_tx),hl
        ld a,(ix+3)
        add a,22
        ld (boss_ty),a
        ld (ix+9),1
        jp .hits

.hovering:
        ld a,(ix+4)
        cp BOSS_FIRE_AT
        call z,boss_fire_if_far
        ld a,(ix+4)
        cp BOSS_HOVER
        jp c,.hits
        ld hl,(px)                      ; swoop at Simon: box centre on his
        ld de,-16                       ; centre, wings at his chest
        add hl,de
        ld (boss_tx),hl
        ld a,(py)
        sub 4
        ld (boss_ty),a
        ld (ix+9),3
        ld (ix+4),0
        jp .hits

.swooping:                              ; 2 px per frame on both axes, all
        call boss_step_x                ; the way down to where Simon was (on
        call boss_step_x                ; the floor too, as on the NES)
        call boss_step_y
        call boss_step_y
        ld a,(ix+4)
        cp BOSS_SWOOP_MAX
        jr nc,.swoop_done
        call boss_at_target
        jp nz,.hits
.swoop_done:
        ld a,r                          ; then back to a new spot up high
        ld hl,frame_count
        xor (hl)
        and 127
        add a,24
        ld e,a
        ld d,0
        ld hl,(cam_x)
        add hl,de
        ld (boss_tx),hl
        and 15
        add a,BOSS_HIGH_Y
        ld (boss_ty),a
        ld (ix+9),1
        jp .hits

.burning:                               ; burst frames on its body
        ld a,(ix+4)
        rrca
        rrca
        rrca
        and 3
        add a,OBJF_BURST
        ld (ix+6),a
        ld a,(ix+4)
        cp 60
        ret c
        ld (ix+0),OBJ_ORB               ; the orb, where it burned
        ld (ix+6),OBJF_ORB
        ld (ix+7),KIND_BAT
        ld (ix+4),0
        ret

.hits:
        ld a,(boss_inv)
        or a
        jr nz,.touch
        call weapon_hits
        jr nc,.touch
        ld a,BOSS_INV
        ld (boss_inv),a
        ld a,1
        ld (hud_dirty),a
        ld b,BOSS_DAMAGE
        ld a,(ix+0)
        cp OBJ_MEDUSA
        jr nz,.damage
        ld b,MEDUSA_DAMAGE
.damage:
        ld a,(boss_hp)
        sub b
        jr z,.dead
        jr c,.dead
        ld (boss_hp),a
        ret
.dead:
        xor a
        ld (boss_hp),a
        ld a,SCORE_BOSS
        call add_score
        ld (ix+9),4
        ld (ix+4),0
        ld l,(ix+1)                     ; burn at its centre (16x16 bursts)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+3)
        add a,4
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret
.touch:                                 ; body x+8..x+39, y+0..y+23
        ld a,(ix+9)
        or a
        ret z                           ; asleep: harmless
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        call boss_simon_dx
        ld de,22                        ; |dx| < 22 (16 + Simon's half body)
        add hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 44
        ret nc
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)                     ; boss y..y+23 vs Simon py..py+31
        add a,23
        ld hl,py
        sub (hl)
        ret c
        cp 32+23
        ret nc
        call boss_simon_dx
        ld b,1
        bit 7,h
        jp z,simon_hurt
        ld b,-1
        jp simon_hurt

; HL = Simon's centre - the boss's centre (x)
boss_simon_dx:
        ld hl,(px)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld de,8-24
        add hl,de
        ret

; one pixel across towards boss_tx (none if there)
boss_step_x:
        ld hl,(boss_tx)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret z
        ex de,hl
        jr c,.left
        inc hl
        jr .set
.left:
        dec hl
.set:
        ld (ix+1),l
        ld (ix+2),h
        ret

; one pixel up or down towards boss_ty
boss_step_y:
        ld a,(boss_ty)
        cp (ix+3)
        ret z
        jr c,.up
        inc (ix+3)
        ret
.up:
        dec (ix+3)
        ret

; Z if at (boss_tx, boss_ty)
boss_at_target:
        ld a,(boss_ty)
        cp (ix+3)
        ret nz
; Z if at boss_tx
boss_at_target_x:
        ld hl,(boss_tx)
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret

; The orb: falls 2 px per frame to the floor. Touching it clears the stage.
orb_update:
        inc (ix+4)
        ld l,(ix+1)                     ; on the ground? (bottom of its 16x16)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        call solid_at
        jr c,.landed
        ld a,(ix+3)
        add a,2
        ld (ix+3),a
.landed:
        ld hl,(px)                      ; Simon's box over it?
        ld de,12
        add hl,de
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ret c                           ; Simon left of it
        ld de,16+12+1-4
        or a
        sbc hl,de
        ret nc                          ; right of it
        ld a,(py+1)
        or a
        ret nz
        ld a,(ix+3)
        add a,15
        ld hl,py
        sub (hl)
        ret c
        cp 32+15
        ret nc
        ld (ix+0),OBJ_NONE
        ld a,HP_MAX                     ; stage clear: health back
        ld (hp),a
        ld a,1
        ld (hud_dirty),a
        ld a,CLEAR_JINGLE
        ld (clear_t),a
        ld a,1
        ld (clear_phase),a
        ld a,SND_CLEAR
        jp music_restart

; ---------------------------------------------------------------------------
; The dagger (sub-weapon): flies DAGGER_SPEED px per frame the way it was
; thrown until it leaves the screen or hits something (weapon_hits).
; ---------------------------------------------------------------------------
dagger_update:
        ld a,(dagger_on)
        or a
        jr z,.gone                      ; spent on a hit
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
        ld a,(ix+5)
        rlca
        and 1
        add a,OBJF_DAGGER_FLY
        ld (ix+6),a
        ld de,(cam_x)                   ; off the screen: gone
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
        jp dagger_box
.gone:
        xor a
        ld (dagger_on),a
        ld (ix+0),OBJ_NONE
        ret

; the dagger's hit box from its object (IX): x..x+15, y+4..y+11
dagger_box:
        ld l,(ix+1)
        ld h,(ix+2)
        ld (dagger_x1),hl
        ld de,15
        add hl,de
        ld (dagger_x1+2),hl
        ld a,(ix+3)
        add a,4
        ld l,a
        ld h,0
        ld (dagger_x1+4),hl
        ld de,7
        add hl,de
        ld (dagger_x1+6),hl
        ret


; ---------------------------------------------------------------------------
; The axe (measured on the NES): 2 px per frame forward, thrown up at
; AXE_VY0/16 px per frame and pulled down by AXE_GRAVITY/16 each frame; it
; turns (4 frames of 4) and goes through what it hits, off the screen.
;   +5 direction (+1/-1)   +9 vertical speed (1/16 px)   +10 fraction
; ---------------------------------------------------------------------------
axe_update:
        inc (ix+4)
        ld a,(ix+5)                     ; x: 2 px per frame
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
        ld a,(ix+9)                     ; y: speed += gravity, y += speed / 16
        add a,AXE_GRAVITY
        bit 7,a
        jr nz,.vy_ok                    ; still going up
        cp AXE_VMAX+1                   ; capped, so that speed + fraction stays
        jr c,.vy_ok                     ; a signed byte (it went back up)
        ld a,AXE_VMAX
.vy_ok:
        ld (ix+9),a
        call obj_fall_step
        ld a,(ix+4)                     ; turning: frame (timer / 4) mod 4
        rrca
        rrca
        and 3
        add a,OBJF_AXE
        ld (ix+6),a
        ld a,(ix+3)                     ; fell out of the playfield
        cp MT_ROWS*16
        jr c,.on_screen
        cp 256-32
        jp c,sub_gone
.on_screen:
        call sub_on_screen
        jp nc,sub_gone
        jp sub_box16

; Holy water (measured on the NES): the bottle is lobbed forward 3 px every
; 2 frames, up at HOLY_VY0/16 px per frame, gravity HOLY_GRAVITY/16; on the
; floor it breaks into fire that burns HOLY_BURN frames. +11: 0 flying, 1 fire
holy_update:
        inc (ix+4)
        ld a,(ix+11)
        or a
        jr nz,.burning
        ld a,(ix+4)                     ; x: 1 or 2 px (3 every 2 frames)
        and 1
        inc a
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
        ld a,(ix+9)
        add a,HOLY_GRAVITY
        ld (ix+9),a
        call obj_fall_step
        ld (ix+6),OBJF_BOTTLE
        call sub_on_screen
        jp nc,sub_gone
        ld a,(ix+9)                     ; coming down onto the floor?
        or a
        jp m,sub_box16
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        call solid_at
        jp nc,sub_box16
        ld a,(ix+3)                     ; it breaks: fire, standing on the tile
        add a,16                        ; (the flames are drawn 8 px down,
        and 0xF8                        ; like the bursts)
        sub 24
        ld (ix+3),a
        ld (ix+11),1
        ld (ix+4),0
        ld a,SND_HOLY
        call sfx_play
.burning:
        ld a,1
        ld (holy_fire),a
        ld a,(ix+4)
        cp HOLY_BURN
        jr nc,sub_gone
        rrca                            ; flames: (timer / 8) mod 5, NES order
        rrca
        rrca
        and 31
.mod5:
        sub 5
        jr nc,.mod5
        add a,5
        ld e,a
        ld d,0
        ld hl,flame_frames
        add hl,de
        ld a,(hl)
        ld (ix+6),a
        call sub_box16                  ; the fire: 16x16 from y+8
        ld hl,(dagger_x1+4)
        ld de,8
        add hl,de
        ld (dagger_x1+4),hl
        ld hl,(dagger_x1+6)
        add hl,de
        ld (dagger_x1+6),hl
        ret

flame_frames:
        db OBJF_FLAME, OBJF_FLAME+1, OBJF_FLAME+2, OBJF_FLAME4, OBJF_FLAME4+1

; Carry if holy water's fire touches the object at IX (multi-hit enemies are
; held in it)
in_holy_fire:
        ld a,(holy_fire)
        or a
        ret z
        ld a,(dagger_on)
        or a
        ret z
        ld hl,dagger_x1
        ld de,hit_x1
        ld bc,8
        ldir
        jp whip_hits_object

; the sub-weapon is gone
sub_gone:
        xor a
        ld (dagger_on),a
        ld (holy_fire),a
        ld (ix+0),OBJ_NONE
        ret

; carry if the object (16 px wide) is still (partly) on the screen
sub_on_screen:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        bit 7,h
        ret nz                          ; (no carry)
        ld de,256+16+1
        or a
        sbc hl,de
        ret                             ; carry: on screen

; the sub-weapon's hit box: the object's 16x16 (x..x+15, y..y+15)
sub_box16:
        ld l,(ix+1)
        ld h,(ix+2)
        ld (dagger_x1),hl
        ld de,15
        add hl,de
        ld (dagger_x1+2),hl
        ld l,(ix+3)
        ld h,0
        bit 7,l
        jr z,.y
        dec h
.y:
        ld (dagger_x1+4),hl
        add hl,de
        ld (dagger_x1+6),hl
        ret

; y += (+9) / 16 with the fraction in +10 (signed)
obj_fall_step:
        ld c,a
        ld a,(ix+10)
        add a,c
        ld c,a
        sra a
        sra a
        sra a
        sra a
        add a,(ix+3)
        ld (ix+3),a
        ld a,c
        and 15
        ld (ix+10),a
        ret


; A frozen enemy (stopwatch): it doesn't move or hurt, but weapons still kill it
frozen_update:
        call weapon_hits
        ret nc
        ld a,(ix+0)
        sub OBJ_ZOMBIE
        ld e,a
        ld d,0
        ld hl,frozen_score
        add hl,de
        ld a,(hl)
        or a
        call nz,add_score
        ld a,SND_HIT                    ; (struck: candle or enemy)
        call sfx_play
        ld (ix+0),OBJ_BURST
        ld (ix+4),0
        ld (ix+6),OBJF_BURST
        ld (ix+5),ITEM_NONE
        ret
frozen_score:
        db SCORE_ZOMBIE, SCORE_PANTHER, SCORE_BAT, SCORE_FISH, 0

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
; Carry if the whip (while it can hit) or the flying dagger hits the object at
; IX. A dagger that hits is spent.
weapon_hits:
        ld a,(whip_active)
        or a
        jr z,.dagger
        ld hl,whip_x1
        call .try
        ret c
.dagger:
        ld a,(dagger_on)
        or a
        ret z
        ld hl,dagger_x1
        call .try
        ret nc
        ld a,(sub_kind)                 ; the dagger is spent; the axe and the
        cp 1                            ; holy water's fire go on
        jr nz,.pierce
        xor a
        ld (dagger_on),a
.pierce:
        scf
        ret
.try:
        ld de,hit_x1
        ld bc,8
        ldir
        jp whip_hits_object

; Carry if the box at hit_x1..hit_y2 overlaps the object at IX
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
        cp KIND_FIREBALL
        jr nz,.not_fireball
        ld de,7
        ld bc,7*256 + 4
        ld l,(ix+1)                     ; box starts 4 px in
        ld h,(ix+2)
        inc hl
        inc hl
        inc hl
        inc hl
        jr .box_x
.not_fireball:
        cp KIND_BOSS
        jr nz,.not_boss
        ld de,31
        ld bc,23*256 + 0
        ld l,(ix+1)                     ; box starts 8 px in
        ld h,(ix+2)
        ld a,l
        add a,8
        ld l,a
        jr nc,.box_x
        inc h
        jr .box_x
.not_boss:
        cp KIND_CANDLE
        jr nz,.box_ready
        ld bc,15*256 + 8
.box_ready:
        ld l,(ix+1)
        ld h,(ix+2)
.box_x:
        push hl                         ; box left
        add hl,de
        ld de,(hit_x1)
        or a
        sbc hl,de                       ; box right - whip left
        pop de
        bit 7,h
        jr nz,.no
        ld hl,(hit_x2)
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
        ld de,(hit_y1)
        or a
        sbc hl,de                       ; box bottom - whip top
        pop de
        bit 7,h
        jr nz,.no
        ld hl,(hit_y2)
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
        cp OBJ_GHOST                    ; (a ghost not out yet: nothing)
        jr z,.hidden
        cp OBJ_MEDUSA                   ; asleep, Medusa is the statue in the
        jr nz,.drawn                    ; map: no sprites
.hidden:
        ld a,(ix+9)
        or a
        jp z,.next_obj
.drawn:
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
        call .page
        xor a
        call load_swap_patterns         ; the zombies' set
        jp load_sub_patterns
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

; The patterns of the sub-weapon Simon holds into the area's sub-weapon window
; (both sprite pages): only one sub-weapon can be in the air, so the dagger,
; the axe and holy water share these slots. Area load and pickups.
load_sub_patterns:
        ld a,(subweapon)
        dec a
        cp 3
        ret nc                          ; none, or the stopwatch (no sprites)
        add a,a
        ld e,a
        ld d,0
        ld hl,area_hdr+AH_SUB_SZ
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld a,b
        or c
        ret z                           ; not in this area
        ld (sub_len),bc
        ld hl,area_hdr+AH_SUB_SPT
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (sub_src),de
        ld a,(area_hdr+AH_SUB_SLOT)
load_window:                            ; (sub_src) bytes (sub_len) to pattern A
        ld (win_slot),a
        xor a
        call .page
        ld a,1
.page:
        push af
        ld a,(win_slot)
        add a,PLAYER_SPRITES
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_SPT
        add hl,de
        pop af
        di
        call vram_set_write_far
        ld hl,(sub_src)
        ld bc,(sub_len)
.lp:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.lp
        jp vram_r14_zero                ; (enables interrupts)

; Swap window set A (0: zombies, 1: the boss) into the area's swap window
; (both sprite pages); nothing in areas without one.
load_swap_patterns:
        ld (swap_boss),a
        add a,a
        ld e,a
        ld d,0
        ld hl,area_hdr+AH_SWAP_SZ
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld a,b
        or c
        ret z
        ld (sub_len),bc
        ld hl,area_hdr+AH_SWAP_SPT
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (sub_src),de
        ld a,(area_hdr+AH_SWAP_SLOT)
        jp load_window

; ---------------------------------------------------------------------------
; HUD: hearts counter (row 1, columns 25-26), written during VBLANK
; ---------------------------------------------------------------------------
HUD_HEARTS_ADDR equ VRAM_PNT + 32 + 24
HUD_HP_ADDR     equ VRAM_PNT + 32 + 3
HUD_EN_ADDR     equ VRAM_PNT + 32 + 14
HUD_SCORE_ADDR  equ VRAM_PNT + 7
HUD_TIME_ADDR   equ VRAM_PNT + 19
HUD_STAGE_ADDR  equ VRAM_PNT + 27
HUD_LIVES_ADDR  equ VRAM_PNT + 32 + 28
HUD_ICON_ADDR   equ VRAM_PNT + 30

; A = two BCD digits -> the VDP (write address already set)
hud_bcd:
        ld c,a
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,"0"
        out (VDP_DATA),a
        ld a,c
        and 15
        add a,"0"
        out (VDP_DATA),a
        ret

; Game over: the HUD's top line says so (VBLANK work done by the main loop)
hud_game_over:
        ld hl,game_over_text
        ld de,VRAM_PNT
        ld bc,32
        di
        call vram_copy
        ei
        ret
game_over_text:
        db "           GAME  OVER           "

hud_update:
        ld a,(hud_dirty)                ; a redraw is spread over three frames
        or a                            ; (bars; score, time, stage; lives,
        jr z,.pending                   ; icon, hearts) to keep VBLANK short
        xor a
        ld (hud_dirty),a
        ld a,7
        ld (hud_parts),a
.pending:
        ld a,(hud_parts)
        or a
        ret z
        ld hl,hud_parts
        bit 0,a
        jr nz,.part1
        bit 1,a
        jr nz,.part2
        ld (hl),0
        jp .part3
.part2:
        res 1,(hl)
        jp .part2_draw
.part1:
        res 0,(hl)
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
        ld hl,HUD_EN_ADDR               ; enemy (boss) bar
        call vram_set_write
        ld a,(boss_hp)
        ld c,a
        ld b,8
.ebar:
        ld a,c
        sub 8
        ld c,a
        ld a,HUDT_BAR_ENEMY
        jr nc,.efull
        ld a,HUDT_BAR_EMPTY
        ld c,0
.efull:
        out (VDP_DATA),a
        djnz .ebar
        ret
.part2_draw:
        ld hl,HUD_SCORE_ADDR            ; score: 6 digits
        call vram_set_write
        ld a,(score+2)
        call hud_bcd
        ld a,(score+1)
        call hud_bcd
        ld a,(score)
        call hud_bcd
        ld hl,HUD_TIME_ADDR             ; time: 4 digits
        call vram_set_write
        ld a,(time_bcd+1)
        call hud_bcd
        ld a,(time_bcd)
        call hud_bcd
        ld hl,HUD_STAGE_ADDR
        call vram_set_write
        ld a,(area_hdr+AH_STAGE)
        call hud_bcd
        ret
.part3:
        ld hl,HUD_LIVES_ADDR
        call vram_set_write
        ld a,(lives)
        add a,"0"
        out (VDP_DATA),a
        ld a,(subweapon)                ; sub-weapon icon: 2x2 tiles
        ld b," "
        ld c,b
        ld d,b
        ld e,b
        or a
        jr z,.icon
        dec a
        add a,a
        add a,a
        add a,HUDT_I_DAGGER_TL
        ld b,a
        inc a
        ld c,a
        inc a
        ld d,a
        inc a
        ld e,a
.icon:
        ld hl,HUD_ICON_ADDR
        call vram_set_write
        ld a,b
        out (VDP_DATA),a
        ld a,c
        out (VDP_DATA),a
        ld hl,HUD_ICON_ADDR+32
        call vram_set_write
        ld a,d
        out (VDP_DATA),a
        ld a,e
        out (VDP_DATA),a
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
