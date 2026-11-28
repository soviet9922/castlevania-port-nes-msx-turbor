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
OBJ_MUMMY       equ 26                  ; stage 9 boss: a mummy
OBJ_BANDAGE     equ 27                  ; its bandages
OBJ_EAGLE       equ 28                  ; block 4: an eagle carrying a fleaman
OBJ_RSKEL       equ 29                  ; the red skeleton
OBJ_DRAGON      equ 30                  ; the bone dragon (its root; the rest: parts)
OBJ_FRANK       equ 31                  ; stage 12's boss: Frankenstein's monster
OBJ_IGOR        equ 32                  ; ... and Igor
OBJ_AKNIGHT     equ 33                  ; blocks 5-6: the axe knight
OBJ_KAXE        equ 34                  ; ... its axe
OBJ_GBAT        equ 35                  ; the giant bat (stage 16)
OBJ_DEATH       equ 36                  ; stage 15's boss: Death
OBJ_SICKLE      equ 37                  ; ... his sickles
OBJ_DRAC        equ 38                  ; stage 18's boss: Dracula
OBJ_DEBRIS      equ 39                  ; ... the pieces of his first form

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
KIND_MUMMY      equ 14
KIND_RSKEL      equ 15                  ; candle list only: a red skeleton
KIND_DRAGON     equ 16                  ; candle list only: a bone dragon
KIND_EAGLE      equ 17                  ; 28x28 box at +2, +2
KIND_FRANK      equ 18                  ; candle list only: Frankenstein (and Igor)
KIND_AKNIGHT    equ 19                  ; the axe knight: 12x28 box at +2, +2
KIND_GBAT       equ 20                  ; the giant bat: 40x20 around its middle
KIND_DEATH      equ 21                  ; Death: 24x44 around his middle
KIND_DRACULA    equ 22                  ; candle list only: Dracula
KIND_DRAC1      equ 23                  ; his first form: 32x48 around his middle
KIND_DRAC2      equ 24                  ; the monster: 48x48 around its middle

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
OBJF_MUMMY      equ 84                  ; left, right
OBJF_BANDAGE    equ 86                  ; two pictures
OBJF_KNIGHT     equ 88                  ; legs 1-3 facing left, then right
OBJF_SKEL       equ 94                  ; two pictures facing left, then right
OBJF_MUMMY2     equ 98                  ; pictures 2-3 facing left, then right
OBJF_PILLAR_R   equ 102                 ; facing right; flashing left, right
OBJF_MUMMY_F    equ 105                 ; flickering: left, right
OBJF_FLEA2      equ 107                 ; the fleaman on the floor: left, right
OBJF_EAGLE      equ 109                 ; wings 1-2 left, then right
OBJF_RSKEL      equ 113                 ; walking 1-2 left, then right
OBJF_RPILE      equ 117                 ; the pile, half pile: left, then right
OBJF_DHEAD      equ 121                 ; the bone dragon: skull, open, vertebra
OBJF_FRANK      equ 124                 ; his walk 1-3 left, then right
OBJF_AKNIGHT    equ 130                 ; the axe knight 1-2 left, then right
OBJF_GBAT       equ 134                 ; the giant bat's two pictures
OBJF_DEATH      equ 136                 ; Death facing left, right
OBJF_SICKLE     equ 138                 ; a sickle's 4 pictures left, then right
OBJF_DRAC       equ 146                 ; Dracula: stand, cape, head left, then right
OBJF_MON        equ 152                 ; the monster's 7 pictures left, then right
OBJF_DEBRIS     equ 166
OBJF_BAG        equ 167                 ; money bags 100, 400, 700
OBJF_PORK       equ 170
OBJF_CROSS_ITEM equ 171
OBJF_ROSARY     equ 172
OBJF_POTION     equ 173
OBJF_SHOT       equ 174                 ; II, III
OBJF_POP        equ 176                 ; score popups 100, 400, 700
OBJF_CROSS      equ 179                 ; the flying cross: 3 spin frames
OBJF_TREASURE   equ 182                 ; hidden treasures: type * 4 + palette
OBJF_POP1000    equ 198
OBJF_POP2000    equ 199
OBJF_PLAT       equ 200

; items: the NES's obj_item codes ($EC16; a money bag's value in bits 4-5)
ITEM_SMALLHEART equ 0x00                ; (as a candle's code: candle_item decides)
ITEM_BAG        equ 0x01                ; 100, 400 ($11), 700 ($21)
ITEM_WHIPUP     equ 0x03
ITEM_HEART      equ 0x04
ITEM_PORK       equ 0x05
ITEM_DAGGER     equ 0x08
ITEM_CROSS      equ 0x09
ITEM_ROSARY     equ 0x0A
ITEM_HOLYWATER  equ 0x0B
ITEM_SHOT       equ 0x0C                ; double / triple shot
ITEM_AXE        equ 0x0D
ITEM_POTION     equ 0x0E
ITEM_STOPWATCH  equ 0x0F
ITEM_NONE       equ 0xFF                ; burst of an enemy: nothing drops
OBJ_POPUP       equ 40                  ; a money bag's score (32 frames)
OBJ_CROSS       equ 41                  ; the flying cross (sub-weapon 5)
OBJ_TREASURE    equ 42                  ; a hidden treasure (src/treasure.asm)
OBJ_PLATFORM    equ 43                  ; (plat_table only: src/platforms.asm)

SPAWN_LEFT      equ 16                  ; spawn when -16 <= box x - camera <= 272
SPAWN_RIGHT     equ 272
KEEP_LEFT       equ 48                  ; free the slot when < -48 or > 304
KEEP_RIGHT      equ 304

; Clear all objects and candle flags (area load / respawn).
objects_reset:
        xor a                           ; (no power-up item out now)
        ld (pwr_out),a
        ld hl,obj_table
        ld de,obj_table+1
        ld bc,OBJ_MAX*OBJ_SIZE-1
        ld (hl),0
        ldir
        ld hl,part_table
        ld de,part_table+1
        ld bc,PARTS_MAX*OBJ_SIZE-1
        ld (hl),0
        ldir
        ld hl,candle_dead
        ld de,candle_dead+1
        ld bc,MAX_CANDLES/4-1           ; candle_dead + candle_live
        ld (hl),0
        ldir
        ld hl,0xFFFF
        ld (spawn_last),hl
        ld hl,spawn_tick                ; spawners: timers 0, off the screen,
        ld de,spawn_tick+1              ; counters 0
        ld bc,3*SPAWNERS_MAX-1
        ld (hl),0
        ldir
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
        cp KIND_MEDUSA                  ; (not the bosses)
        jr z,.allowed
        cp KIND_MUMMY
        jr z,.allowed
        cp KIND_FRANK
        jr z,.allowed
        cp KIND_DEATH
        jr z,.allowed
        cp KIND_DRACULA
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
        xor a
        ld (ix+4),a                     ; x fraction
        ld (ix+9),a                     ; damage taken
        ld (ix+10),a                    ; (first turn after 256 frames)
        ld (ix+11),a                    ; state 0, not frozen
        call knight_face                ; it starts facing Simon
        jp knight_frame
.medusa:
        ld (ix+0),OBJ_MEDUSA
        ld (ix+6),OBJF_MEDUSA
        xor a
        ld (med_wake),a
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
        call item_effects               ; (the rosary, the potion)
        call count_subs                 ; (for weapon_hits)
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
        cp OBJ_CROSS
        jr nz,.not_cross
        call cross_update
        jp .next
.not_cross:
        cp OBJ_TREASURE
        jr nz,.not_treasure
        call treasure_update
        jp .next
.not_treasure:
        cp OBJ_POPUP
        jr nz,.not_popup
        call popup_update
        jp .next
.not_popup:
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
        ld c,1                          ; drawn in the background: its flame
        or a                            ; frame's tiles at each change
        jr z,.tiles
        cp 9
        jr nz,.frame
        inc c
.tiles:
        push af
        call ctile_rec
        ld a,c
        call nz,ctile_show
        pop af
.frame:
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
        call ctile_rec                  ; (in the background: the wall again)
        ld a,0
        call nz,ctile_show
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
        call candle_item                ; what it really is (NES $EB8A)
        ld (ix+0),OBJ_ITEM              ; the item appears
        xor a
        ld (ix+4),a
        ld (ix+9),a
        ld (ix+10),a
        ld (ix+11),a
        call obj_ext_of
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,(ix+5)
        or a
        jr nz,.not_small
        ld (ix+10),0xE0                 ; the small heart: sideways 7/8 px
.not_small:
        ld a,(ix+5)                     ; a power-up: its picture into the item
        call item_power_up              ; window (one is out at a time, NES $72)
        call nz,item_window_load
        call item_frame
        ld c,a
.frame:
        ld (ix+6),c
        ret

; What an item (IX+5, a candle's or an enemy's code) really is (NES $EB8A):
; a money bag, the pork chop as they are; code 0 (or $0C) after 10 hits of
; a sub-weapon: the double / triple shot; while a power-up item is out, or
; the sub-weapon Simon holds: a small heart or the 100 bag at random; code
; 0: a whip upgrade if hearts >= 8 and the whip below the morning star, or
; 4-7 hearts and the leather whip, else at random.
candle_item:
        ld a,(ix+5)
        and 15
        cp ITEM_BAG
        ret z
        cp ITEM_PORK
        jr c,.not57
        cp 8
        ret c
.not57:
        ld a,(ix+5)
        cp ITEM_SHOT
        jr z,.shot
        or a
        jr nz,.power
        ld a,(subhits)
        cp 10
        jr c,.code0
.shot:
        xor a
        ld (subhits),a
        ld a,(shot_n)
        cp 2
        jr nc,.code0
        ld (ix+5),ITEM_SHOT
        ret
.power:
        ld a,(pwr_out)
        or a
        jr nz,.random
        ld a,(ix+5)
        call item_subweapon
        jr z,.mark
        ld hl,subweapon
        cp (hl)
        jr z,.random
.mark:
        ld a,0xFF
        ld (pwr_out),a
        ret
.code0:
        ld a,(pwr_out)
        or a
        jr nz,.random
        ld a,(whip_level)
        ld c,a
        ld a,(hearts)
        cp 8
        jr c,.lt8
        ld a,c
        cp 2
        jr c,.whip
        jr .random
.lt8:
        cp 4
        jr c,.random
        ld a,c
        or a
        jr nz,.random
.whip:
        ld (ix+5),ITEM_WHIPUP
        ld a,0xFF
        ld (pwr_out),a
        ret
.random:
        ld a,(rng)
        and 1
        ld (ix+5),a
        ret

; NZ if item code A is a power-up (codes 2-4, 8-$0F but the shot)
item_power_up:
        and 15
        cp ITEM_SHOT
        jr z,.no
        cp 8
        jr nc,.yes
        cp 2
        jr c,.no
        cp ITEM_PORK
        jr nc,.no
.yes:
        or 1
        ret
.no:
        xor a
        ret

; load the picture of power-up item (IX+5) into the item window
item_window_load:
        ld a,(ix+5)
        and 15
        ld c,a
        ld hl,(area_hdr+AH_ITEM_TAB)
.find:
        ld a,(hl)
        inc hl
        cp 0xFF
        ret z                   ; no picture of its own
        cp c
        jr z,.found
        inc hl
        inc hl
        inc hl
        inc hl
        jr .find
.found:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld (sub_len),bc
        ld (sub_src),de
        ld a,(area_hdr+AH_ITEM_SLOT)
        push ix
        call load_window_far
        pop ix
        ret

; A = the picture of item (IX+5)
item_frame:
        ld a,(ix+5)
        ld c,a
        and 15
        cp ITEM_BAG
        jr nz,.table
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and 3
        add a,OBJF_BAG
        ret
.table:
        cp ITEM_SHOT
        jr nz,.t
        ld a,(shot_n)
        add a,OBJF_SHOT
        ret
.t:
        ld e,a
        ld d,0
        ld hl,item_frames
        add hl,de
        ld a,(hl)
        ret

; A = the port's sub-weapon number of NES item code A (1 dagger, 2 axe,
; 3 holy water, 4 stopwatch, 5 cross), Z if it is not a sub-weapon
item_subweapon:
        ld hl,.map
        ld b,5
.lp:
        cp (hl)
        jr z,.found
        inc hl
        djnz .lp
        xor a
        ret
.found:
        ld a,6
        sub b
        or a
        ret
.map:   db ITEM_DAGGER, ITEM_AXE, ITEM_HOLYWATER, ITEM_STOPWATCH, ITEM_CROSS

item_frames:                            ; by the code's low nibble
        db OBJF_SMALLHEART, OBJF_BAG, OBJF_WHIPUP, OBJF_WHIPUP, OBJF_HEART, OBJF_PORK
        db OBJF_ORB, OBJF_SMALLHEART, OBJF_DAGGER, OBJF_CROSS_ITEM, OBJF_ROSARY
        db OBJF_HOLY_ITEM, OBJF_SHOT, OBJF_AXE_ITEM, OBJF_POTION, OBJF_WATCH_ITEM

; An item (NES $DE1D): the small heart drifts down 1/2 px a frame on a
; spring (7/8 px across at first, pulled back by its offset/256 a frame:
; +-14 px, about 100 frames a swing) and can be taken from its 12th frame;
; the others fall 1/4 px a frame faster each frame and can be taken from their
; 2nd. On the floor they stay 180 frames (the rosary for good), then go.
;   +4 frames  +9 the heart's offset / landed  +10, +11 speed (8.8)
;   obj_ext: x fraction, y fraction
item_update:
        inc (ix+4)
        jr nz,.t
        dec (ix+4)                      ; (stays at 255)
.t:
        ld l,(ix+1)                     ; off the screen: gone
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,8
        add hl,de
        ld a,h
        or a
        jp nz,.culled
        ld a,(ix+5)
        or a
        jr nz,.other
        ld a,(ix+9)                     ; small heart
        cp 0x80
        jp z,.lying
        call item_on_ground
        jp c,.landed
        ld a,(ix+9)                     ; vx -= offset / 256
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+10)
        ld h,(ix+11)
        or a
        sbc hl,de
        ld (ix+10),l
        ld (ix+11),h
        call obj_ext_of                 ; x += vx
        ld a,(hl)
        add a,(ix+10)
        ld (hl),a
        ld a,(ix+11)
        adc a,0
        jr z,.ydrift
        ld b,a
        add a,(ix+9)
        ld (ix+9),a
        ld a,b
        call move_x_a
.ydrift:
        call obj_ext_of                 ; y += 1/2
        inc hl
        ld a,(hl)
        add a,0x80
        ld (hl),a
        jr nc,.take12
        inc (ix+3)
.take12:
        ld a,(ix+4)
        cp 12
        ret c
        jr .pickup
.other:
        ld a,(ix+9)
        or a
        jr nz,.lying
        call item_on_ground
        jr c,.landed
        ld l,(ix+10)                    ; vy += 1/4 (no cap)
        ld h,(ix+11)
        ld de,0x40
        add hl,de
        ld (ix+10),l
        ld (ix+11),h
        call obj_ext_of
        inc hl
        ld a,(hl)
        add a,(ix+10)
        ld (hl),a
        ld a,(ix+11)
        adc a,0
        jr z,.pickup
        ld b,a
.fall:                                  ; pixel by pixel onto the floor
        push bc
        call item_on_ground
        pop bc
        jr c,.landed
        inc (ix+3)
        ld a,(ix+3)
        cp MT_ROWS*16
        jr c,.in_view
        cp 256-32                       ; (above the top: from a candle high on
        jp c,.culled                    ; a wall): else a pit
.in_view:
        djnz .fall
        jr .pickup
.landed:
        ld (ix+9),0x80
        ld (ix+4),0
        jr .pickup
.lying:
        ld a,(ix+5)
        cp ITEM_ROSARY                  ; (the rosary stays)
        jr z,.pickup
        ld a,(ix+4)
        cp 180
        jr c,.pickup
        ld a,(ix+5)                     ; gone (but bags, the pork chop and
        call item_power                 ; the shot: another power-up may come)
        jr z,.gone
        xor a
        ld (pwr_out),a
        jr .gone
.culled:
        ld a,(ix+5)
        cp 2
        jr c,.gone
        xor a
        ld (pwr_out),a
        jr .gone

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
        jp item_collect
.gone:
        ld (ix+0),OBJ_NONE
        ret

; Z if item code A is a money bag, the pork chop or the double/triple shot
; (going, they don't free the power-up rule)
item_power:
        and 15
        cp ITEM_BAG
        ret z
        cp ITEM_PORK
        ret z
        cp ITEM_SHOT
        ret
; x += A (signed)
move_x_a:
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

; Simon takes item IX (NES $E76E)
item_collect:
        ld (ix+0),OBJ_NONE
        ld a,(ix+5)
        or a
        jr nz,.not_small
        ld c,1                          ; small heart: + 1
        jr .hearts
.not_small:
        cp ITEM_HEART
        jr nz,.not_big
        xor a
        ld (pwr_out),a
        ld c,5                          ; big heart: + 5
.hearts:
        ld a,SND_HEART
        call sfx_play
        ld a,(hearts)
        add a,c
        cp 100
        jr c,.h
        ld a,99
.h:
        ld (hearts),a
        jp .hud
.not_big:
        ld c,a
        and 15
        cp ITEM_BAG
        jr nz,.not_bag
        ld a,c                          ; a money bag: 100, 400, 700
        rrca
        rrca
        rrca
        rrca
        and 3
.bag:
        push af
        ld e,a
        ld d,0
        ld hl,bag_scores
        add hl,de
        ld a,(hl)
        call add_score
        ld hl,kills                     ; (not a kill)
        dec (hl)
        ld a,SND_MONEY
        call sfx_play
        pop af
        add a,OBJF_POP                  ; its score shows 32 frames by Simon
        ld (ix+6),a
        ld (ix+0),OBJ_POPUP
        ld (ix+4),32
        ld hl,(px)
        ld de,16
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(py)
        ld (ix+3),a
        ld (ix+7),KIND_BAT
        ret
.not_bag:
        cp ITEM_SHOT
        jr nz,.not_shot
        ld a,(subweapon)                ; double/triple shot: with a thrown
        or a                            ; sub-weapon (else a 700 bag)
        jr z,.shot_bag
        cp 4
        jr z,.shot_bag
        ld a,(ix+6)
        sub OBJF_SHOT-1
        ld (shot_n),a
        ld a,128
        ld (shot_blink),a
        ld a,SND_ITEM
        call sfx_play
        jr .hud
.shot_bag:
        ld a,2
        jr .bag
.not_shot:
        push af
        ld a,SND_ITEM
        call sfx_play
        xor a
        ld (pwr_out),a
        pop af
        cp ITEM_WHIPUP
        jr nz,.not_whip
        ld a,(whip_level)
        cp 2
        jr nc,.hud
        inc a
        ld (whip_level),a
        jr .hud
.not_whip:
        cp ITEM_PORK
        jr nz,.not_pork
        ld a,(hp)                       ; health + 24
        add a,24
        cp HP_MAX+1
        jr c,.hp
        ld a,HP_MAX
.hp:
        ld (hp),a
        jr .hud
.not_pork:
        cp ITEM_ROSARY
        jr nz,.not_rosary
        ld a,15                         ; 30 frames: every enemy bursts
        ld (rosary_t),a
        ret
.not_rosary:
        cp ITEM_POTION
        jr nz,.not_potion
        ld a,180                        ; 360 frames: nothing hurts Simon
        ld (potion_t),a
        ret
.not_potion:
        call item_subweapon             ; a sub-weapon: dagger 1, axe 2, holy
        ret z                           ; water 3, stopwatch 4, cross 5
        ld (subweapon),a
        xor a
        ld (shot_n),a
        ld (subhits),a
        ld (shot_blink),a
        push ix
        call load_sub_patterns          ; its sprites into the window
        pop ix
.hud:
        ld a,1
        ld (hud_dirty),a
        ret
bag_scores:     db 0x01, 0x04, 0x07

; a money bag's score popup: 32 frames
popup_update:
        dec (ix+4)
        ret nz
        ld (ix+0),OBJ_NONE
        ret

; The rosary (NES $FA71) and the potion, each frame: every other frame for
; 30 frames the screen flashes and every enemy (not a boss) and enemy shot
; bursts, without points or items; the potion counts down every other frame.
item_effects:
        ld hl,shot_blink                ; the shot mark blinks (every 4 frames)
        ld a,(hl)
        or a
        jr z,.no_blink
        dec (hl)
        ld a,(frame_count)
        and 3
        jr nz,.no_blink
        inc a
        ld (hud_dirty),a
.no_blink:
        ld a,(frame_count)
        and 1
        ret nz
        ld hl,potion_t
        ld a,(hl)
        or a
        jr z,.no_potion
        dec (hl)
.no_potion:
        ld hl,rosary_t
        ld a,(hl)
        or a
        ret z
        dec (hl)
        ld b,15                         ; (the backdrop flashes white)
        jr nz,.flash
        ld b,0
.flash:
        di
        ld a,b
        out (VDP_CTRL),a
        ld a,0x80|7
        out (VDP_CTRL),a
        ei
        push ix
        ld ix,obj_table
        ld b,OBJ_MAX
.lp:
        ld a,(ix+0)
        ld e,a
        ld d,0
        ld hl,rosary_kills
        add hl,de
        ld a,(hl)
        or a
        jr z,.next
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
; 1: an object type the rosary bursts (enemies and their shots; not bosses)
rosary_kills:
        db 0, 0, 0, 0, 0, 1, 1, 1, 1, 1         ; 0-9: zombie .. fireball
        db 0, 0, 0, 0, 0, 1, 1, 1, 0, 1         ; 10-19: knight, head, bat, snake
        db 1, 1, 1, 1, 1, 1, 0, 1, 1, 1         ; 20-29: flea .. ghost, bandage, eagle, red skeleton
        db 1, 0, 0, 1, 1, 1, 0, 1, 0, 0, 0      ; 30-40: dragon, axe knight, axe, giant bat, sickle

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
        jp z,.no_step                   ; rests 1 frame in 8
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
        ld de,8+16                      ; a wall 16 px ahead at its middle:
        bit 7,(ix+5)                    ; it turns round (NES 5:$8038)
        jr z,.wall
        ld de,8-16
.wall:
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        call solid_at
        jr nc,.no_wall
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jr .no_step
.no_wall:
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
        ld a,(ix+4)                     ; legs: every 16 frames (NES 17)
        rrca
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

        ld l,(ix+1)                     ; its middle off the screen: gone
        ld h,(ix+2)                     ; (NES: outside x 8..$F8)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jp nz,.gone
        ld a,l
        cp 241
        jp nc,.gone

        call weapon_hits
        jr nc,.touch
        ld a,SCORE_ZOMBIE
        ld c,0
        jp enemy_killed

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
        ld l,(ix+1)                     ; awake, its middle off the screen:
        ld h,(ix+2)                     ; gone (NES: outside x 8..$F8)
        ld de,8
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.gone_p
        ld a,l
        cp 241
        jr c,.on_screen
.gone_p:
        ld (ix+0),OBJ_NONE
        ret
.on_screen:
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
        ld (ix+7),KIND_BRAZIER
        ld a,SCORE_PANTHER
        ld c,0
        jp enemy_killed

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
; Enemy spawners, as the NES ($F382): every spawner whose place is on the
; screen (x 8..$F8 from the camera) runs, each with its own timer, counted
; down every other frame (a "tick" = 2 frames, $F4CA) while it is on the
; screen; spawn_st is 1 on the first frame it is on the screen, then 2.
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
        xor a
        ld (spawner_i),a
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
        ld (spawner_x),hl
        ld de,(cam_x)
        or a
        sbc hl,de
        ld (spawner_sx),hl              ; (its screen x)
        call spawner_slot               ; HL = its state, DE = its timer
        ld a,(spawner_sx+1)
        or a
        jr nz,.off
        ld a,(spawner_sx)
        cp 8
        jr c,.off
        cp 0xF9
        jr nc,.off
        ld a,(hl)                       ; on the screen: 1 the first frame,
        or a                            ; then 2
        ld a,1
        jr z,.st
        inc a
.st:
        ld (hl),a
        ld a,(frame_count)              ; its timer ticks every other frame
        and 1
        jr z,.run
        ld a,(de)
        or a
        jr z,.run
        dec a
        ld (de),a
.run:
        pop bc
        push bc
        ld a,(spawner_type)
        cp ENEMY_BAT
        call z,bat_spawner
        ld a,(spawner_type)
        cp ENEMY_FISH
        call z,fish_spawner
        ld a,(spawner_type)
        cp ENEMY_MEDUSA
        call z,medusa_spawner
        ld a,(spawner_type)
        cp ENEMY_ZOMBIE
        call z,zombie_spawner
        ld a,(spawner_type)
        cp ENEMY_EAGLE
        call z,eagle_spawner
        jr .next
.off:
        ld (hl),0                       ; off the screen (its timer is kept)
.next:
        ld hl,spawner_i
        inc (hl)
        pop bc
        pop hl
        djnz .lp
        ret

; HL = spawn_st + spawner_i, DE = spawn_tick + spawner_i (B, C kept)
spawner_slot:
        ld a,(spawner_i)
        and SPAWNERS_MAX-1
        ld e,a
        ld d,0
        ld hl,spawn_tick
        add hl,de
        push hl
        ld hl,spawn_st
        add hl,de
        pop de
        ret

; A = how many objects of type A there are (B, C kept)
count_type:
        push bc
        ld ix,obj_table
        ld de,OBJ_SIZE
        ld b,OBJ_MAX
        ld c,0
.lp:
        cp (ix+0)
        jr nz,.not
        inc c
.not:
        add ix,de
        djnz .lp
        ld a,c
        pop bc
        ret

; HL = the screen edge's left x (cam_x + 0 or + 240): A = 0 the right edge,
; else the left; but not the edge whose middle is within 64 px of Simon's
; middle: then the other. -> HL, and A = 0 right, 1 left
edge_away:
        or a
        ld a,0
        jr z,.r
        inc a
.r:
        push af
        call .x
        ld de,(px)
        or a
        sbc hl,de                       ; edge middle - Simon middle (both +8)
        call abs_hl
        ld a,h
        or a
        jr nz,.far
        ld a,l
        cp 64
        jr nc,.far
        pop af
        xor 1                           ; too near: the other edge
        push af
.far:
        pop af
.x:
        ld hl,(cam_x)
        or a
        ret nz
        ld de,240
        add hl,de
        ret

; HL = |HL|
abs_hl:
        bit 7,h
        ret z
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; --- zombies (NES 6:$805D): at most 3; a random edge (not the one within 64
; px of Simon), only if there is floor there; then 32 frames to the next,
; 288 after every third (zombie_wave, never reset, as the NES's $63) ---
zombie_spawner:
        ld a,(de)
        or a
        ret nz
        ld a,(swap_boss)                ; (their patterns are the boss's now)
        or a
        ret nz
        push de
        push bc
        ld a,OBJ_ZOMBIE
        call count_type
        cp 3
        jr nc,.no
        call obj_free_slot
        jr c,.no
        ld a,(rng)
        and 1
        call edge_away                  ; HL = left x, A = 1 left edge
        ld (ix+5),-1
        or a
        jr z,.dir
        ld (ix+5),1
.dir:
        pop bc
        push bc
        push hl
        ld de,8                         ; floor at the edge (its middle, y+36)?
        add hl,de
        ld a,c
        add a,36
        ld e,a
        ld d,0
        call solid_at
        pop hl
        jr nc,.no
        ld (ix+1),l
        ld (ix+2),h
        pop bc
        ld (ix+3),c
        ld (ix+0),OBJ_ZOMBIE
        ld (ix+4),0
        ld (ix+10),0
        ld (ix+11),0
        ld (ix+7),KIND_BRAZIER          ; 16x32 box for the whip
        ld (ix+8),0xFF
        ld (ix+9),0
        pop de
        ld hl,zombie_wave
        ld a,(hl)
        inc (hl)
        cp 3
        ld a,16                         ; 32 frames
        jr c,.t
        ld (hl),1
        ld a,144                        ; 288 frames after a third
.t:
        ld (de),a
        ret
.no:
        pop bc
        pop de
        ret

; ---------------------------------------------------------------------------
; Bat (NES 6:$80E7): every 384 frames while its spawner is on the screen, at
; most 3, not while Simon is on the stairs: at the edge Simon faces (the
; other when that one is within 64 px of him), at his middle -19, -11, -3 or
; +1 (by the frame), flying at him 1 1/8 px a frame, dipping 18 px and back
; every ~100 frames. Wings: 3 frames of 9 (1 2 3 2). Touching Simon hurts
; him and kills the bat; the whip kills it.
;   +4 timer   +5 direction   +9 start y   +10 x fraction
; ---------------------------------------------------------------------------
bat_spawner:
        ld a,(de)
        or a
        ret nz
        push de
        ld a,OBJ_BAT
        call count_type
        pop de
        cp 3
        ret nc
        ld a,(stair_state)              ; not while Simon is on the stairs
        cp 2
        ret z
        push de
        call obj_free_slot
        pop de
        ret c
        ld a,BAT_EVERY/2
        ld (de),a
        ld a,(facing)                   ; facing right (0): the right edge
        call edge_away
        ld (ix+5),-1
        or a
        jr z,.place
        ld (ix+5),1
.place:
        ld (ix+1),l
        ld (ix+2),h
        ld a,(frame_count)
        and 3
        ld e,a
        ld d,0
        ld hl,bat_heights
        add hl,de
        ld a,(py)
        add a,8
        add a,(hl)
        ld (ix+3),a
        ld (ix+9),a
        ld (ix+0),OBJ_BAT
        ld (ix+4),0
        ld (ix+7),KIND_BAT
        ld (ix+8),0xFF
        ld (ix+10),0
        jp bat_frame
bat_heights:    db -19, -11, -3, 1

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
        jp nz,.gone
        ld de,256+16+1
        or a
        sbc hl,de
        jp nc,.gone
.hits:
        call weapon_hits
        jr nc,.touch
        ld a,(ix+0)                     ; (a Medusa head scores more,
        cp OBJ_SNAKE                    ; a snake less)
        ld a,SCORE_SNAKE
        jr z,.score
        ld a,(ix+0)
        cp OBJ_MHEAD
        ld a,SCORE_BAT
        jr nz,.score
        ld a,SCORE_MEDUSA
.score:
        ld c,0
        jp enemy_killed
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
        ld a,(ix+0)                     ; a Medusa head or a snake goes on; a
        cp OBJ_MHEAD                    ; bat dies as if whipped (NES $E72B)
        ret z
        cp OBJ_SNAKE
        ret z
        ld a,SCORE_BAT
        ld c,0
        jp enemy_killed
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
; Fishman (NES 6:$8182, ai_fishman $F08D). Each spawner: 168 frames after it
; comes on the screen, then every 510 frames, while fewer than FISH_MAX are
; about and Simon is FISH_AWAY px or more from it, one leaps out. +9 = state:
;   0 in the air: starts at -88/16 px per frame up, gravity 2/16, it passes
;     through platforms going up and lands on one coming down (on a 16-px row)
;     or falls back into the water and is gone
;   3 stands 8 frames, then
;   1 walks towards Simon, 3 px every 4 frames, legs every 24 frames; falls
;     off the end of a platform; after 79, 121, 93 or 144 frames (random,
;     NES $F11D) it stops and
;   2 shoots: a fireball after 16 frames, walks again (towards Simon) after 32
; +10 = vertical speed (1/16 px), +11 = fraction.
; ---------------------------------------------------------------------------
fish_spawner:
        ld a,(hl)                       ; on the screen: first 168 frames
        cp 1
        jr nz,.timer
        ld a,84
        ld (de),a
        ret
.timer:
        ld a,(de)
        or a
        ret nz
        push de
        push bc
        ld a,OBJ_FISH
        call count_type
        cp FISH_MAX
        jr nc,.no
        ld hl,(spawner_x)               ; not within 40 px of Simon
        ld de,(px)
        or a
        sbc hl,de
        ld de,-8
        add hl,de                       ; spawner x - Simon's middle
        call abs_hl
        ld a,h
        or a
        jr nz,.ok
        ld a,l
        cp FISH_AWAY
        jr c,.no
.ok:
        call obj_free_slot
        jr c,.no
        pop bc
        pop de
        ld a,255                        ; then 510 frames
        ld (de),a
        ld hl,(spawner_x)
        ld de,-8
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),c
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
        jp fish_frame
.no:
        pop bc
        pop de
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
        ld a,(ix+3)                     ; on the tile (a 16-px row, NES)
        and 0xF0
        ld (ix+3),a
        ld (ix+9),3                     ; stands 8 frames
        ld (ix+4),0
        call fish_face
        jr .drawn

.on_ground:
        cp 2
        jr z,.shooting
        cp 3
        jr nz,.walking
        ld a,(ix+4)                     ; standing after landing
        cp 8
        jr c,.drawn
        call fish_walk_on
        jr .drawn
.walking:
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
        cp (ix+10)                      ; its walk's length
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
        call fish_face
        call fish_walk_on
.drawn:
        call fish_frame

        ld l,(ix+1)                     ; its middle off the screen: gone
        ld h,(ix+2)                     ; (NES: outside x 8..$F8)
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        jp nz,.gone
        ld a,l
        cp 241
        jp nc,.gone
.hits:
        call weapon_hits
        jp nc,zombie_update.touch
        ld a,(ix+3)                     ; burst on its body
        add a,8
        ld (ix+3),a
        ld a,SCORE_FISH
        ld c,1                          ; (a big heart)
        jp enemy_killed
.gone:
        ld (ix+0),OBJ_NONE
        ret

; walk: towards its facing for 79, 121, 93 or 144 frames (NES $F11D)
fish_walk_on:
        ld (ix+9),1
        ld (ix+4),0
        ld a,(rng)
        and 3
        ld e,a
        ld d,0
        ld hl,fish_walks
        add hl,de
        ld a,(hl)
        ld (ix+10),a
        ret
fish_walks:     db 79, 121, 93, 144

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
        ld (ix+3),b                     ; (its middle 8 px above the fishman's)
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
        call ball_step                  ; the boss's: aimed (vx +11, vy +9)
        jp .no_dy
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
.no_dy:
        ld a,(ix+3)
        cp MT_ROWS*16
        jp nc,.gone                     ; left the playfield
        ld l,(ix+1)
        ld h,(ix+2)

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
        jr nc,.touch
        ld a,SCORE_SNAKE                ; whipped: 100 points (NES $E0A2)
        ld c,2
        jp enemy_killed
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
        jp simon_hurt                   ; it flies on (NES)
.gone:
        ld (ix+0),OBJ_NONE
        ret


; ---------------------------------------------------------------------------
; The stage 3 boss: a giant bat, from the NES code (bank 5 $80EF). It hangs
; asleep until Simon reaches the last screen's middle; then the screen
; locks, and after 120 more frames asleep (no hits, no harm):
;  - spot: it flies in a straight line, 3/4 px a frame on the long axis, to
;    Simon's middle +72 or -73 across (by the frame; the other side when that
;    is off the screen's 16..239) and 41 px above him, until across it is
;    within 4 px; then hovers 123, 32, 61 or 199 frames (by the frame);
;  - every 16 frames of a hover, if Simon faces it within 88 px across and
;    20 px of its height, it rises 2 1/2 px a frame for 7 frames (a dodge);
;  - at the hover's (or dodge's) end: Simon's middle above its middle: a
;    fireball at him (1 1/2 px a frame), 24 frames, a new spot; else a swoop:
;    aimed at 25 px below Simon's middle (2 px a frame across, or 1 1/2 down),
;    the downward speed falling 6/256 px a frame: a U through and past him,
;    turning at screen x 16 / 240, until it rises above NES y 112: a new spot.
; A hit takes the weapon's damage (6 leather, 8 chain/morning star) from its
; BOSS_HP and stops it 8 frames. At 0 it burns 60 frames and the orb appears
; at the screen's middle (orb_update). +9 = state: 0 asleep, 1 waking, 2 to
; its spot, 3 hovering, 4 burning, 5 dodging, 6 swooping, 7 after a fireball.
; Its middle is (x+24, y+7); speeds in boss_vx / boss_vy (8.8, vy signed).
; ---------------------------------------------------------------------------
boss_update:
        ld a,(boss_frz)                 ; stopped by a hit (no wings either)
        or a
        jr z,.go
        dec a
        ld (boss_frz),a
        jp .hits
.go:
        ld a,(freeze_t)                 ; (the stopwatch holds it)
        or a
        jp nz,.hits
        inc (ix+4)
        ld a,(ix+4)                     ; wings: open / up every 9 frames
        ld c,0
.div9:
        sub 9
        jr c,.d9
        inc c
        jr .div9
.d9:
        ld a,c
        and 1
        add a,OBJF_BOSS
        ld (ix+6),a
        call in_holy_fire               ; in holy water's fire: it can't move,
        jp c,.hits                      ; and the fire goes on hurting it
        ld a,(ix+9)
        or a
        jr z,.asleep
        cp 4
        jp z,.burning
        dec a
        jr z,.waking
        dec a
        jr z,.to_spot
        dec a
        jp z,.hovering
        dec a
        dec a
        jp z,.dodging
        dec a
        jp z,.swooping
        ld hl,boss_t                    ; 7: after a fireball
        dec (hl)
        jp nz,.hits
        call boss_spot
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
        ld a,120                        ; 120 frames more asleep
        ld (boss_t),a
        xor a
        ld (boss_frz),a
        ld (ix+9),1
        ret
.waking:
        ld (ix+6),OBJF_BOSS_SLEEP
        ld hl,boss_t
        dec (hl)
        ret nz
        jp boss_spot

.to_spot:
        call boss_move
        ld hl,(boss_tx)                 ; there when within 4 px across
        call boss_dx_hl
        call abs_hl
        ld a,h
        or a
        jp nz,.hits
        ld a,l
        cp 4
        jp nc,.hits
        ld a,(frame_count)
        and 3
        ld e,a
        ld d,0
        ld hl,boss_hovers
        add hl,de
        ld a,(hl)
        ld (boss_t),a
        ld (ix+9),3
        jp .hits

.hovering:
        ld a,(frame_count)              ; the dodge test every 16 frames
        and 15
        call z,boss_dodge_test
        ret c                           ; (dodging now)
        ld hl,boss_t
        dec (hl)
        jp nz,.hits
        call boss_attack
        jp .hits

.dodging:
        ld hl,boss_t
        dec (hl)
        jr z,.dodge_end
        call boss_move_y
        jp .hits
.dodge_end:
        call boss_attack
        jp .hits

.swooping:
        ld hl,(boss_vy)                 ; the downward speed falls 6/256
        ld de,-6
        add hl,de
        ld (boss_vy),hl
        bit 7,h
        jr z,.dive
        ld a,(ix+3)                     ; rising and above NES y 112: done
        add a,7
        cp 112-48
        jr nc,.dive
        call boss_spot
        jp .hits
.dive:
        call boss_move
        ld l,(ix+1)                     ; turn at screen x 16 / 240 (middle)
        ld h,(ix+2)
        ld de,24
        add hl,de
        ld de,(cam_x)
        or a
        sbc hl,de
        ld de,16
        bit 7,h
        jr nz,.clamp
        ld a,h
        or a
        jr nz,.right
        ld a,l
        cp 16
        jr c,.clamp
        cp 240
        jr c,.hits
.right:
        ld de,240
.clamp:
        ld hl,(cam_x)
        add hl,de
        ld de,-24
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+5)
        neg
        ld (ix+5),a
        jr .hits

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
        ld hl,(cam_x)                   ; the orb: at the screen's middle (NES
        ld de,120                       ; $DD66: (128, 128)), hidden 60
        add hl,de                       ; frames, flashing 32, then it falls
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),128-48-7
        ld (ix+0),OBJ_ORB
        ld (ix+6),OBJF_ORB
        ld (ix+7),KIND_BAT
        ld (ix+4),0
        ld (ix+9),0                     ; (hidden)
        ld (ix+10),0
        ld (ix+11),0
        ret

.hits:
        ld a,(ix+9)                     ; asleep or waking: no hits, no harm
        cp 2
        ret c
        call weapon_hits
        jp nc,.touch
        ld a,1
        ld (hud_dirty),a
        call hit_damage                 ; the weapon's damage (holy water's
        rrca                            ; fire: 1 every 4 frames)
        rrca
        and 0x3F
        ld b,a
        ld a,(hit_src)
        cp 3
        jr nz,.dmg
        ld b,0
        ld a,(frame_count)
        and 3
        jr nz,.dmg
        inc b
.dmg:
        ld a,BOSS_FREEZE
        ld (boss_frz),a
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
.touch:                                 ; |dx| < 24, |dy| < 22 (middles)
        ld a,(invuln_t)
        or a
        ret nz
        ld a,(hurt_state)
        or a
        ret nz
        call boss_simon_dx
        call abs_hl
        ld a,h
        or a
        ret nz
        ld a,l
        cp 24
        ret nc
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)                       ; Simon's middle py+16, its y+7
        add a,16-7
        sub (ix+3)
        jr nc,.dyp
        neg
.dyp:
        cp 22
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

boss_hovers:    db 123, 32, 61, 199

; HL = HL - the boss's middle x (x + 24)
boss_dx_hl:
        ld e,(ix+1)
        ld d,(ix+2)
        or a
        sbc hl,de
        ld de,-24
        add hl,de
        ret

; a new spot: Simon's middle +72 or -73 across (the other side when off the
; screen's 16..239), 41 px above him; 3/4 px a frame on the long axis
boss_spot:
        ld a,(frame_count)
        and 1
        call .side
        jr nc,.ok
        ld a,(frame_count)
        and 1
        xor 1
        call .side
.ok:
        ld (boss_tx),hl
        ld a,(py)                       ; Simon's middle - 41
        add a,16-41
        ld de,0x00C0
        call boss_aim
        ld (ix+9),2
        ret
.side:                                  ; HL = the target x; carry if off
        ld hl,(px)
        ld de,8+72
        or a
        jr z,.s
        ld de,8-73
.s:
        add hl,de
        push hl
        ld de,(cam_x)
        or a
        sbc hl,de
        ld a,h
        or a
        scf
        jr nz,.out
        ld a,l
        cp 16
        jr c,.out
        cp 240
        ccf
.out:
        pop hl
        ret

; aim at (HL = x, A = y) (middles): DE = the long axis's speed (8.8) ->
; facing, boss_vx, boss_vy (signed: + down)
boss_aim:
        push de
        push af
        call boss_dx_hl
        ld (ix+5),1
        bit 7,h
        jr z,.dxp
        ld (ix+5),-1
.dxp:
        call abs_hl
        ld a,h
        or a
        ld b,l
        jr z,.bx
        ld b,255
.bx:
        pop af
        sub 7
        sub (ix+3)                      ; dy = target - its middle
        ld c,0                          ; C bit 0: up
        jr nc,.dyp
        neg
        inc c
.dyp:
        pop de
        push bc                         ; B = |dx|, C = up
        ld l,a                          ; L = |dy|
        cp b
        jr nc,.y_long
        ld (boss_vx),de                 ; x is the long axis
        ld a,b
        or a
        jr z,.zero
        ld a,l
        ld l,b
        call boss_muldiv
        ld (boss_vy),hl
        jr .sign
.zero:
        ld hl,0
        ld (boss_vy),hl
        jr .sign
.y_long:
        ld (boss_vy),de
        ld a,l
        or a
        jr z,.zero_x
        ld a,b
        call boss_muldiv
        ld (boss_vx),hl
        jr .sign
.zero_x:
        ld hl,0
        ld (boss_vx),hl
.sign:
        pop bc
        bit 0,c
        ret z
        ld hl,(boss_vy)                 ; up: vy negative
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ld (boss_vy),hl
        ret

; HL = DE * A / L (L > 0)
boss_muldiv:
        ld c,l
        push bc
        ld hl,0
        ld c,0
        ld b,8
.mul:
        add hl,hl
        rl c
        rla
        jr nc,.mn
        add hl,de
        jr nc,.mn
        inc c
.mn:
        djnz .mul
        pop de                          ; E = the divisor
        ld d,e
        ld e,c                          ; E:HL = the product
        xor a
        ld b,24
.div:
        add hl,hl
        rl e
        rla
        jr c,.sub
        cp d
        jr c,.nx
.sub:
        sub d
        inc l
.nx:
        djnz .div
        ret

; x += boss_vx along the facing, y += boss_vy (8.8 with fractions)
boss_move:
        ld a,(boss_xf)
        ld hl,(boss_vx)
        add a,l
        ld (boss_xf),a
        ld a,h
        adc a,0
        ld e,a
        ld d,0
        bit 7,(ix+5)
        jr z,.xr
        xor a
        sub e
        ld e,a
        sbc a,a
        ld d,a
.xr:
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
boss_move_y:
        ld a,(boss_yf)
        ld hl,(boss_vy)
        add a,l
        ld (boss_yf),a
        ld a,(ix+3)
        adc a,h
        ld (ix+3),a
        ret

; carry if Simon faces it within 88 px across and 20 px of its height: then
; it dodges (rises 2 1/2 px a frame for 7 frames)
boss_dodge_test:
        ld a,(py+1)
        or a
        ret nz
        ld a,(py)
        add a,16-7
        sub (ix+3)
        jr nc,.dy
        neg
.dy:
        cp 20
        ccf
        ret c
        call boss_simon_dx
        ld c,0                          ; C = 1: Simon is left of it
        bit 7,h
        jr z,.r
        inc c
.r:
        call abs_hl
        ld a,h
        or a
        ret nz
        ld a,l
        cp 88
        ccf
        ret c
        ld a,(facing)                   ; facing it: his facing differs from
        cp c                            ; "he is left of it"
        ret z
        ld hl,-0x0280
        ld (boss_vy),hl
        ld a,8
        ld (boss_t),a
        ld (ix+9),5
        or a
        ret

; the hover's end: Simon's middle above its middle: a fireball; else a swoop
boss_attack:
        ld a,(py)
        add a,16-7
        cp (ix+3)
        jr nc,.swoop
        ld a,(py+1)
        or a
        jr nz,.swoop
        call boss_shoot
        ld a,24
        ld (boss_t),a
        ld (ix+9),7
        ret
.swoop:
        ld hl,(px)                      ; at 25 px below Simon's middle: 2 px
        ld de,8                         ; across, or 1 1/2 down when the
        add hl,de                       ; height is the long axis
        ld a,(py)
        add a,16+25
        ld de,0x0200
        call boss_aim
        ld a,(boss_vy+1)                ; (y long: 1 1/2 px down)
        cp 2
        jr nz,.swooping
        ld hl,0x0180
        ld (boss_vy),hl
.swooping:
        ld (ix+9),6
        ret

; a fireball from its middle at Simon's middle, 1 1/2 px a frame on the
; long axis (NES shoot_at_simon $EC94)
boss_shoot:
        ld hl,(px)
        ld de,8
        add hl,de
        ld a,(py)
        add a,16
        ld de,0x0180
        call boss_aim
        push ix
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,16
        add hl,de
        ld a,(ix+3)
        sub 1
        ld b,a
        ld c,(ix+5)
        call obj_free_slot
        jr c,.none
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+3),b
        ld (ix+5),c
        ld (ix+0),OBJ_FIREBALL
        ld (ix+4),0
        ld (ix+6),OBJF_FIREBALL
        ld (ix+7),KIND_FIREBALL
        ld (ix+8),0xFF
        ld (ix+10),1                    ; (the boss's: aimed)
        ld hl,(boss_vx)                 ; speeds in 1/64 px (up to 1 1/2:
        sra h                           ; 96; signed for vy)
        rr l
        sra h
        rr l
        ld (ix+11),l
        ld hl,(boss_vy)
        sra h
        rr l
        sra h
        rr l
        ld (ix+9),l
        call obj_ext_of
        ld (hl),0
        inc hl
        ld (hl),0
.none:
        pop ix
        ret

; the boss's fireball: x += vx (+11, 1/64 px) along its facing, y += vy (+9,
; signed 1/64 px), fractions (0-63) in obj_ext
ball_step:
        call obj_ext_of
        push hl
        ld a,(hl)
        add a,(ix+11)                   ; (at most 63 + 96)
        ld c,a
        and 63
        ld (hl),a
        ld a,c
        rlca
        rlca
        and 3                           ; whole px
        bit 7,(ix+5)
        jr z,.xr
        neg
.xr:
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld l,(ix+1)
        ld h,(ix+2)
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        pop hl
        inc hl
        ld a,(ix+9)                     ; y: signed
        ld e,a
        rla
        sbc a,a
        ld d,a                          ; DE = vy
        ld a,(hl)
        add a,e
        ld c,a
        ld a,d
        adc a,0
        ld b,a                          ; B:C = fraction + vy (signed)
        ld a,c
        and 63
        ld (hl),a
        ld a,c                          ; whole = B:C >> 6 (signed)
        rlca
        rlca
        and 3
        ld c,a
        ld a,b
        add a,a
        add a,a
        or c
        ld b,a
        ld a,(ix+3)
        add a,b
        ld (ix+3),a
        ret

; The orb: falls 2 px per frame to the floor. Touching it clears the stage.
orb_update:
        inc (ix+4)
        ld a,(ix+4)                     ; hidden 60 frames, flashing 32
        cp 60
        jr nc,.shown
        ld (ix+9),0
        ret
.shown:
        cp 92
        jr nc,.fall
        and 1
        ld (ix+9),a
        ret
.fall:
        ld (ix+4),92
        ld (ix+9),1
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
        ld a,4                          ; falling: 1/4 px a frame faster each
        call fall_step                  ; frame (vy in +10, 1/16 px)
        jr c,.out
        jr .touch
.landed:
        ld a,(ix+3)                     ; on the tile
        add a,16
        and 0xF8
        sub 16
        ld (ix+3),a
.touch:
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
.out:
        ld (ix+3),MT_ROWS*16-16         ; (fell out: on the playfield's floor)
        ret

; ---------------------------------------------------------------------------
; The dagger (sub-weapon): flies DAGGER_SPEED px per frame the way it was
; thrown until it leaves the screen or hits something (weapon_hits).
; ---------------------------------------------------------------------------
dagger_update:
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
        ret c
.gone:
        jp sub_gone


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
        and 15                          ; (its sound each turn, NES sound 9)
        cp 1
        ld a,SND_AXE
        call z,sfx_play
        ld a,(ix+4)
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
        ret

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
        ret m
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld a,(ix+3)
        add a,16
        ld e,a
        ld d,0
        call solid_at
        ret nc
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
        ld a,(ix+4)
        cp HOLY_BURN
        jp nc,sub_gone
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
        ret

flame_frames:
        db OBJF_FLAME, OBJF_FLAME+1, OBJF_FLAME+2, OBJF_FLAME4, OBJF_FLAME4+1

; ---------------------------------------------------------------------------
; The cross (NES $DC6A): 2 px a frame for 64 frames, then it slows by 1/8 px
; a frame, turns, speeds up again to 2 px and flies back; Simon catches it
; as it passes him (|dx| < 8, |dy| < 16), else it flies off the screen. On the
; way out, the screen's edge turns it at once. It spins every 9 frames (3
; pictures of 3 frames) with NES sound 7.
;   +4 frames left (state 1)  +5 direction (+1/-1)  +9 speed (1/8 px)
;   +10 fraction  +11 state: 1 out, 2 slowing, 3 back and speeding up, 4 back
; ---------------------------------------------------------------------------
cross_update:
        ld a,(ix+11)
        cp 4
        jp z,.back
        cp 1
        jr nz,.not_out
        dec (ix+4)                      ; 1: out at 2 px
        jr nz,.two
        ld (ix+11),2
.two:
        ld a,2
        jr .move
.not_out:
        cp 2
        jr nz,.speeding
        ld a,(ix+9)                     ; 2: slowing down
        sub 1
        jr nc,.speed
        ld (ix+9),0                     ; stopped: it turns
        ld a,(ix+5)
        neg
        ld (ix+5),a
        ld (ix+11),3
        jr .edge
.speeding:
        ld a,(ix+9)                     ; 3: back, faster and faster
        inc a
        cp 16
        jr c,.speed
        ld (ix+11),4                    ; (2 px again: state 4; it can hit
        ld (ix+7),0xFF                  ; what it hit on the way out again)
        ld (ix+8),0xFF
        ld a,16
.speed:
        ld (ix+9),a
        add a,(ix+10)                   ; pixels this frame: (speed + fraction) / 8
        ld c,a
        and 7
        ld (ix+10),a
        ld a,c
        rrca
        rrca
        rrca
        and 31
.move:
        call .step
.edge:                                  ; states 1-3: the screen's edge
        ld l,(ix+1)                     ; (NES: its middle at 8 / $F8)
        ld h,(ix+2)
        ld de,(cam_x)
        or a
        sbc hl,de
        bit 7,h
        jr nz,.left_edge
        ld a,h
        or a
        jr nz,.right_edge
        ld a,l
        cp 0xF0
        jr c,.anim
.right_edge:
        ld hl,0xF0
        ld a,-1
        jr .turn
.left_edge:
        ld hl,0
        ld a,1
.turn:
        add hl,de
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+5),a
        ld (ix+9),16
        ld (ix+11),4
        ld (ix+7),0xFF
        ld (ix+8),0xFF
        jr .anim
.back:
        ld a,2                          ; 4: back at 2 px
        call .step
        ld l,(ix+1)                     ; caught as it passes Simon
        ld h,(ix+2)
        ld de,(px)
        or a
        sbc hl,de
        ld de,8
        add hl,de
        ld de,16
        or a
        sbc hl,de
        jr nc,.not_caught               ; |dx| >= 8
        ld a,(pyoff)                    ; (his throwing height)
        rrca
        ld b,a
        ld a,(py)
        add a,b
        sub (ix+3)
        add a,16
        cp 32
        jp c,sub_gone
.not_caught:
        call sub_on_screen
        jp nc,sub_gone
.anim:                                  ; (frame count mod 9) / 3; facing left
        ld a,(frame_count)              ; the second and third the other way
.mod9:
        sub 9
        jr nc,.mod9
        add a,9
        jr nz,.no_sound
        push af
        ld a,SND_CROSS
        call sfx_play
        pop af
.no_sound:
        ld c,0
.div3:
        sub 3
        jr c,.pic
        inc c
        jr .div3
.pic:
        ld a,c
        or a
        jr z,.set
        bit 7,(ix+5)
        jr z,.set
        xor 3                           ; 1 <-> 2
.set:
        add a,OBJF_CROSS
        ld (ix+6),a
        ret
.step:                                  ; x += A along +5
        bit 7,(ix+5)
        jr z,.fwd
        neg
.fwd:
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

; Carry if holy water's fire touches the object at IX (multi-hit enemies are
; held in it)
in_holy_fire:
        ld a,(sub_out)
        or a
        ret z
        push iy
        ld iy,obj_table
        ld b,OBJ_MAX
.lp:
        ld a,(iy+0)
        cp OBJ_HOLY
        jr nz,.next
        ld a,(iy+11)                    ; (burning, not flying)
        or a
        jr z,.next
        push bc
        call sub_box
        ld (hit_src),a
        call whip_hits_object
        pop bc
        jr c,.yes
.next:
        ld de,OBJ_SIZE
        add iy,de
        djnz .lp
        pop iy
        or a
        ret
.yes:
        pop iy
        ret

; the sub-weapon is gone
sub_gone:
        ld (ix+0),OBJ_NONE
        ret

; -> A = (sub_out) = the sub-weapons flying (dagger, axe, holy water, cross)
count_subs:
        ld hl,obj_table
        ld de,OBJ_SIZE
        ld bc,OBJ_MAX*256
.lp:
        ld a,(hl)
        cp OBJ_CROSS
        jr z,.one
        sub OBJ_DAGGER
        cp OBJ_HOLY-OBJ_DAGGER+1
        jr nc,.next
.one:
        inc c
.next:
        add hl,de
        djnz .lp
        ld a,c
        ld (sub_out),a
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

; The hit box of the sub-weapon at IY into hit_x1..hit_y2: the dagger
; x..x+15, y+4..y+11; holy water's fire 16x16 from y+8; the others 16x16.
; -> A = its hit_src (1 dagger, 2 axe, 3 holy water, 5 cross)
sub_box:
        ld l,(iy+1)
        ld h,(iy+2)
        ld (hit_x1),hl
        ld de,15
        add hl,de
        ld (hit_x2),hl
        ld l,(iy+3)
        ld h,0
        bit 7,l
        jr z,.y
        dec h
.y:
        ld a,(iy+0)
        cp OBJ_DAGGER
        jr nz,.not_dagger
        ld e,4
        add hl,de                       ; (D = 0)
        ld (hit_y1),hl
        ld e,7
        add hl,de
        ld (hit_y2),hl
        ld a,1
        ret
.not_dagger:
        cp OBJ_HOLY
        jr nz,.square
        ld a,(iy+11)
        or a
        jr z,.square
        ld e,8
        add hl,de
.square:
        ld (hit_y1),hl
        ld e,15
        add hl,de
        ld (hit_y2),hl
        ld a,(iy+0)
        cp OBJ_CROSS
        ld a,5
        ret z
        ld a,(iy+0)
        sub OBJ_DAGGER-1                ; axe 2, holy water 3
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
; Carry if the whip (while it can hit) or a flying sub-weapon hits the object
; at IX (hit_src: what hit). A dagger that hits is spent; the axe, the cross
; and holy water go on. Each sub-weapon hit counts towards the shot item
; (NES $79).
weapon_hits:
        xor a
        ld (hit_src),a
        ld a,(whip_active)
        or a
        jr z,.subs
        ld hl,whip_x1
        ld de,hit_x1
        ld bc,8
        ldir
        call whip_hits_object
        ret c
.subs:
        ld a,(sub_out)
        or a
        ret z
        push iy
        ld iy,obj_table
        ld b,OBJ_MAX
.lp:
        ld a,(iy+0)
        cp OBJ_CROSS
        jr z,.sub
        sub OBJ_DAGGER
        cp OBJ_HOLY-OBJ_DAGGER+1
        jr nc,.next
.sub:
        ld a,(iy+0)                     ; the axe and the cross hit each object
        cp OBJ_AXE                      ; once a throw (NES obj_ydir: the slot
        jr z,.once                      ; they hit last; the cross forgets it
        cp OBJ_CROSS                    ; on its way back)
        jr nz,.any
.once:
        push ix
        pop hl
        ld a,l
        cp (iy+8)
        jr nz,.any
        ld a,h
        cp (iy+7)
        jr z,.next
.any:
        push bc
        call sub_box
        ld (hit_src),a
        call whip_hits_object
        pop bc
        jr c,.hit
.next:
        ld de,OBJ_SIZE
        add iy,de
        djnz .lp
        xor a
        ld (hit_src),a                  ; (no carry)
        pop iy
        ret
.hit:
        ld hl,subhits
        inc (hl)
        jr nz,.counted
        dec (hl)                        ; (it stays at 255)
.counted:
        ld a,(hit_nomark)               ; (the axe's and the cross's: this
        or a                            ; object; not Dracula's body, NES
        jr nz,.marked                   ; $E684)
        push ix
        pop hl
        ld (iy+7),h
        ld (iy+8),l
.marked:
        ld a,(hit_src)
        dec a
        jr nz,.pierce
        ld (iy+0),OBJ_NONE              ; the dagger is spent
.pierce:
        pop iy
        scf
        ret

; A = the damage of the hit weapon_hits found, in the NES's units x 4
; ($E5E5: the whip 6 at level 0, 8 at levels 1-2; the dagger 6, the axe 8,
; the holy water's fire 1/4 a frame)
hit_damage:
        ld a,(hit_src)
        or a
        jr nz,.sub
        ld a,(whip_level)
        or a
        ld a,24
        ret z
        ld a,32
        ret
.sub:
        cp 1
        ld a,24                         ; the dagger 6
        ret z
        ld a,(hit_src)
        cp 3
        ld a,1                          ; holy water's fire 1/4 a frame (NES
        ret z                           ; $E6BD; bosses take it their own way)
        ld a,32                         ; the axe, the cross 8
        ret

; Carry if the box at hit_x1..hit_y2 overlaps the object at IX
whip_hits_object:
        ld a,(ix+7)
        ld de,15                        ; DE = box width - 1
        ld bc,31*256 + 0                ; B = height - 1, C = top offset
        cp KIND_PANTHER                 ; (the brazier and the candle first:
        jr nc,.not_small                ; most of the objects)
        or a
        jp z,.box_ready
        ld bc,15*256 + 8
        jp .box_ready
.not_small:
        cp KIND_PANTHER
        jr nz,.not_wide
        ld de,31
        ld b,15
        jp .box_ready
.not_wide:
        cp KIND_BAT
        jr nz,.not_bat
        ld b,15
        jp .box_ready
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
        jp .box_x
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
        jp nc,.box_x
        inc h
        jp .box_x
.not_boss:
        cp KIND_MEDUSA                  ; Medusa: 28x28 around her middle
        jr nz,.not_medusa
        ld de,27
        ld bc,27*256 + 2
        ld l,(ix+1)
        ld h,(ix+2)
        ld a,l
        add a,10
        ld l,a
        jp nc,.box_x
        inc h
        jp .box_x
.not_medusa:
        cp KIND_EAGLE                   ; the eagle: 28x28 at +2, +2
        jr nz,.not_eagle
        ld de,27
        ld bc,27*256 + 2
        ld l,(ix+1)
        ld h,(ix+2)
        inc hl
        inc hl
        jp .box_x
.not_eagle:
        cp KIND_MUMMY                   ; a mummy: 16x44 from its top + 2
        jr nz,.not_mummy
        ld bc,43*256 + 2
        jr .box_ready
.not_mummy:
        cp KIND_AKNIGHT                 ; the axe knight: 12x28 at +2, +2
        jr nz,.not_aknight
        ld de,11
        ld bc,27*256 + 2
        ld l,(ix+1)
        ld h,(ix+2)
        inc hl
        inc hl
        jr .box_x
.not_aknight:
        cp KIND_GBAT                    ; the giant bat: 40x20 around its
        jr nz,.not_gbat                 ; middle (x + 8, top + 8)
        ld de,39
        ld bc,19*256 + (-2 & 255)
        ld l,(ix+1)
        ld h,(ix+2)
        push de
        ld de,-12
        add hl,de
        pop de
        jr .box_x
.not_gbat:
        cp KIND_DEATH                   ; Death: 24x44 around his middle
        jr nz,.not_death                ; (x + 8, top + 24)
        ld de,23
        ld bc,43*256 + 2
        ld l,(ix+1)
        ld h,(ix+2)
        dec hl
        dec hl
        dec hl
        dec hl
        jp .box_x
.not_death:
        cp KIND_DRAC1                   ; Dracula: 32x48 / 48x48 around his
        jr c,.not_drac                  ; middle (x + 8, top + 24)
        cp KIND_DRAC2+1
        jr nc,.not_drac
        ld de,31
        ld bc,47*256 + 0
        ld l,(ix+1)
        ld h,(ix+2)
        dec hl
        dec hl
        dec hl
        dec hl
        dec hl
        dec hl
        dec hl
        dec hl
        cp KIND_DRAC2
        jp nz,.box_x
        ld de,-8
        add hl,de
        ld de,47
        jp .box_x
.not_drac:
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
        call draw_obj
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
        ld ix,part_table                ; then the parts of big enemies (the
        ld b,PARTS_MAX                  ; bone dragon's neck): drawn only
.part:
        push bc
        call draw_obj
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        djnz .part
        ld ix,plat_table                ; and the moving platforms
        ld b,PLAT_MAX
.plat:
        push bc
        call draw_obj
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        djnz .plat
        ld iy,(spr_sat_ptr)
        ret

draw_obj:
        ld a,(ix+0)
        or a
        ret z
        cp OBJ_GHOST                    ; (most objects: two compares)
        jr nc,.late
        cp OBJ_ORB                      ; (an orb not shown yet / flashing)
        jr z,.hidden
        cp OBJ_MEDUSA                   ; asleep, Medusa is the statue in the
        jr nz,.drawn                    ; map: no sprites
        jr .hidden
.late:
        jr z,.hidden                    ; (a ghost not out yet: nothing)
        cp OBJ_AKNIGHT
        jr c,.drawn
        cp OBJ_GBAT+1                   ; (the axe knight, the giant bat: not
        jr c,.out                       ; out yet; not the knight's axe)
        cp OBJ_DEATH                    ; (until he appears)
        jr nz,.not_death
        ld a,(ix+9)
        cp 3
        ret c
        jr .drawn
.out:
        cp OBJ_KAXE
        jr nz,.hidden
        jr .drawn
.not_death:
        cp OBJ_SICKLE                   ; (appearing: even frames only)
        jr nz,.not_sickle
        ld a,(ix+9)
        or a
        jr nz,.drawn
        ld a,(frame_count)
        rrca
        ret c
        jr .drawn
.not_sickle:
        cp OBJ_DRAC                     ; (Dracula: drac_vis)
        jr nz,.drawn
        ld a,(drac_vis)
        or a
        ret z
        jr .drawn
.hidden:
        ld a,(ix+9)
        or a
        ret z
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
        ret nz
        ld a,l
        cp 0xE0
        ret c
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
        or a                            ; (none: a frame this area doesn't
        jr z,.empty                     ; have, e.g. a sub-weapon's)
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
        ret
.empty:
        pop ix
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
; (both sprite pages): only the one Simon holds can be in the air, so the
; dagger, the axe, holy water and the cross share these slots. Area load and
; pickups.
load_sub_patterns:
        ld a,(subweapon)
        cp 5
        jr z,.cross
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
        ld hl,area_hdr+AH_SUB_SPT
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        jr .got
.cross:
        ld de,(area_hdr+AH_SUB5_SPT)
        ld bc,(area_hdr+AH_SUB5_SZ)
.got:
        ld a,b
        or c
        ret z                           ; not in this area
        ld (sub_len),bc
        ld (sub_src),de
        ld a,(area_hdr+AH_SUB_SLOT)
        jp load_window_far
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
load_swap_patterns:                     ; A = the set (AH_SWAP_TAB)
        ld (swap_boss),a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,(area_hdr+AH_SWAP_TAB)
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld a,b
        or c
        ret z
        ld (sub_len),bc
        ld (sub_src),de
        ld a,(area_hdr+AH_SWAP_SLOT)
; load_window from the area's far bank when it has one (AH_SWAP_BANK: its
; window pictures in a bank of their own, mapped while they are copied; the
; sound interrupt restores page2_bank)
load_window_far:
        ld b,a
        ld a,(area_hdr+AH_SWAP_BANK)
        or a
        ld a,b
        jp z,load_window
        ld a,(area_hdr+AH_SWAP_BANK)
        di
        ld hl,page2_bank
        ld c,(hl)
        ld (hl),a
        ld (ASCII16_PAGE2),a
        push bc
        ld a,b
        call load_window
        pop bc
        di
        ld a,c
        ld (page2_bank),a
        ld (ASCII16_PAGE2),a
        ei
        ret

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
        push bc
        ld hl,HUD_ICON_ADDR+32-1        ; the double / triple shot's mark
        call vram_set_write             ; (blinking after a change)
        ld a,(shot_n)
        or a
        jr z,.no_mark
        add a,HUDT_SHOT2-1
        ld b,a
        ld a,(shot_blink)
        or a
        jr z,.mark
        ld a,(frame_count)
        and 4
        jr nz,.no_mark
.mark:
        ld a,b
        jr .put_mark
.no_mark:
        ld a," "
.put_mark:
        out (VDP_DATA),a
        pop bc
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
