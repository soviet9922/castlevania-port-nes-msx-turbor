; ---------------------------------------------------------------------------
; Objects: candles (braziers and wall candles), their burst when whipped,
; and the items they drop.
;
; OBJ_MAX slots of OBJ_SIZE bytes:
;   +0 type   +1/+2 world x (left of a 16-wide box)   +3 y (playfield)
;   +4 timer  +5 item id  +6 frame  +7 kind (0 brazier, 1 wall candle)
;   +8 candle index (0xFF: none)   +9 small heart sway offset
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

KIND_BRAZIER    equ 0
KIND_CANDLE     equ 1

; object frame numbers (OBJ_FRAMES in tools/convert_objects.py)
OBJF_BRAZIER    equ 0
OBJF_BURST      equ 2
OBJF_HEART      equ 6
OBJF_WHIPUP     equ 7
OBJF_DAGGER     equ 8
OBJF_CANDLE     equ 9
OBJF_SMALLHEART equ 11

ITEM_WHIPUP     equ 0
ITEM_HEART      equ 1
ITEM_DAGGER     equ 2
ITEM_SMALLHEART equ 3

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
        or a
        ld (ix+0),OBJ_BRAZIER
        ld (ix+6),OBJF_BRAZIER
        ret z
        ld (ix+0),OBJ_CANDLE
        ld (ix+6),OBJF_CANDLE
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
; (signed 16-bit compares: the whip box can be left of x = 0)
whip_hits_object:
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,15
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
        ld c,0                          ; box top offset / height by kind
        ld b,31
        ld a,(ix+7)
        cp KIND_CANDLE
        jr nz,.box
        ld c,8
        ld b,15
.box:
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
        ld ix,obj_table
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
        ld (spr_bx),hl
        ld a,h                          ; visible if -32 <= box x <= 255
        or a
        jr z,.on_screen
        inc a
        jr nz,.next_obj
        ld a,l
        cp 0xE0
        jr c,.next_obj
.on_screen:
        ld a,(ix+3)
        add a,PF_TOP_PX-1
        ld (spr_by),a
        ld a,(ix+6)
        push ix
        call obj_frame_address          ; IX = frame data
        ld b,(ix+0)
        inc ix
.spr:
        ld a,(spr_total)
        cp MAX_SPRITES
        jr nc,.frame_done               ; hardware limit: 32 sprites
        ld hl,(spr_bx)                  ; x = box x + dx (16-bit)
        ld a,(ix+1)
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
        ld a,h
        or a
        jr nz,.skip                     ; off the left or right edge
        ld a,(spr_by)
        add a,(ix+0)
        cp 192
        jr nc,.skip                     ; below the screen (and never Y = 216)
        ld (iy+0),a
        ld (iy+1),l
        ld a,(ix+2)
        add a,PLAYER_SPRITES            ; object patterns follow Simon's slots
        add a,a
        add a,a
        ld (iy+2),a
        ld a,(spr_total)                ; remember the colour column
        ld e,a
        ld d,0
        ld hl,obj_sct_list
        add hl,de
        ld a,(ix+3)
        ld (hl),a
        ld a,(spr_total)
        inc a
        ld (spr_total),a
        ld de,4
        add iy,de
.skip:
        ld de,4
        add ix,de
        djnz .spr
.frame_done:
        pop ix
.next_obj:
        ld de,OBJ_SIZE
        add ix,de
        pop bc
        dec b
        jp nz,.obj
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

hud_update:
        ld a,(hud_dirty)
        or a
        ret z
        xor a
        ld (hud_dirty),a
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
