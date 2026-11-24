; ---------------------------------------------------------------------------
; Objects: braziers, their burst when whipped, and the items they drop.
;
; OBJ_MAX slots of OBJ_SIZE bytes:
;   +0 type   +1/+2 world x (left of a 16x32 box)   +3 y (box top, playfield)
;   +4 timer  +5 drop code (0 whip upgrade, 4 big heart, 8 dagger)  +6 frame
;
; Behaviour follows the NES game (measured with record_courtyard.lua):
;   brazier  flame alternates every 8 frames; the whip's strike destroys it
;   burst    20 frames: 9 + 7 + 2 + 2
;   item     appears where the brazier was, waits 4 frames, then falls
;            (1 px per frame, 2 px from the 8th frame) onto solid ground;
;            touching it collects it
; ---------------------------------------------------------------------------

OBJ_NONE        equ 0
OBJ_BRAZIER     equ 1
OBJ_BURST       equ 2
OBJ_ITEM        equ 3

; object frame numbers (tools/convert_objects.py OBJ_FRAMES)
OBJF_BRAZIER    equ 0
OBJF_BURST      equ 2
OBJF_HEART      equ 6
OBJF_WHIPUP     equ 7
OBJF_DAGGER     equ 8

ITEM_WHIPUP     equ 0
ITEM_HEART      equ 4
ITEM_DAGGER     equ 8

; (Re)create the area's braziers from candle_list.
objects_init:
        ld hl,obj_table
        ld de,obj_table+1
        ld bc,OBJ_MAX*OBJ_SIZE-1
        ld (hl),0
        ldir
        ld hl,candle_list
        ld b,(hl)
        inc hl
        ld a,b
        or a
        ret z
        ld ix,obj_table
.lp:
        ld (ix+0),OBJ_BRAZIER
        ld a,(hl)
        ld (ix+1),a
        inc hl
        ld a,(hl)
        ld (ix+2),a
        inc hl
        ld a,(hl)
        ld (ix+3),a
        inc hl
        ld a,(hl)
        ld (ix+5),a
        inc hl
        ld de,OBJ_SIZE
        add ix,de
        djnz .lp
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
        ld a,(whip_active)
        or a
        ret z
        call whip_hits_object
        ret nc
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
        ld a,(ix+5)
        rrca
        rrca
        and 3
        ld e,a
        ld d,0
        ld hl,item_frames
        add hl,de
        ld c,(hl)
.frame:
        ld (ix+6),c
        ret

item_frames:
        db OBJF_WHIPUP, OBJF_HEART, OBJF_DAGGER, OBJF_HEART

item_update:
        inc (ix+4)
        ld a,(ix+4)
        cp 5
        jr c,.pickup                    ; hangs in the air for 4 frames
        ld b,1
        cp 8
        jr c,.fall
        inc b
.fall:                                  ; fall B pixels, one at a time
        push bc
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,8
        add hl,de
        ld e,(ix+3)
        ld d,0
        push hl
        ld hl,24                        ; item sprite spans y+8 .. y+23
        add hl,de
        ex de,hl
        pop hl
        call solid_at
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
        cp ITEM_HEART
        jr nz,.not_heart
        ld a,(hearts)
        add a,5
        cp 100
        jr c,.hearts_ok
        ld a,99
.hearts_ok:
        ld (hearts),a
        ld a,1
        ld (hud_dirty),a
        jr .gone
.not_heart:
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
.gone:
        ld (ix+0),OBJ_NONE
        ret

; Carry set if the whip's strike box overlaps the object's 16x32 box.
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
        ld l,(ix+3)
        ld h,0
        ld de,31
        add hl,de
        ld de,(whip_y1)
        or a
        sbc hl,de                       ; box bottom - whip top
        bit 7,h
        jr nz,.no
        ld hl,(whip_y2)
        ld e,(ix+3)
        ld d,0
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
        cp 32
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

; A = object frame -> IX = frame data
obj_frame_address:
        ld l,a
        ld h,0
        add hl,hl
        ld de,obj_frame_table
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        pop ix
        ret

; Copy the object sprite patterns into pattern slots PLAYER_SPRITES.. of
; both sprite pages (they stay resident).
objects_load_patterns:
        xor a
        call .page
        ld a,1
.page:
        di
        ld hl,VRAM_SPT + PLAYER_SPRITES*32
        call vram_set_write_far
        ld hl,obj_spt
        ld bc,OBJ_PATTERNS*32
.lp:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.lp
        call vram_r14_zero              ; (enables interrupts)
        ret

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
