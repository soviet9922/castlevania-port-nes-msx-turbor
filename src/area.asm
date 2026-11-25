; ---------------------------------------------------------------------------
; Areas
;
; Each area (courtyard, entrance hall, ...) lives in its own 16 KB ROM bank
; (area n = bank n+1) that starts with a header (tools/areas_asm.py). The
; current area's bank stays mapped at 0x8000 while it is played, because
; column streaming and collision read its map directly. The header is copied
; to area_hdr so the engine can use its values without banking.
; ---------------------------------------------------------------------------

; A = area number. Loads everything and restarts the player at the start
; (or, with keep_player set, keeps him where he is: section change).
load_area:
        ld (cur_area),a
        inc a
        ld (ASCII16_PAGE2),a            ; ASCII16: bank seen at 0x8000
        ld hl,0x8000
        ld de,area_hdr
        ld bc,AH_SIZE
        ldir

        di
        ld a,(RG1SAV)                   ; display off while loading
        and 0xBF
        ld b,a
        ld c,1
        call vdp_wreg

        ld bc,0x0010                    ; palette
        call vdp_wreg
        ld hl,(area_hdr+AH_PALETTE)
        ld b,32
        ld c,VDP_PAL
        otir

        ld hl,(area_hdr+AH_PGT0)        ; background tiles, band by band
        ld de,(area_hdr+AH_CT0)
        ld bc,(area_hdr+AH_BGSZ0)
        xor a
        call load_band
        ld hl,(area_hdr+AH_PGT1)
        ld de,(area_hdr+AH_CT1)
        ld bc,(area_hdr+AH_BGSZ1)
        ld a,1
        call load_band
        ld hl,(area_hdr+AH_PGT2)
        ld de,(area_hdr+AH_CT2)
        ld bc,(area_hdr+AH_BGSZ2)
        ld a,2
        call load_band

        call objects_load_patterns      ; (enables interrupts)
        di
        ld hl,0
        ld (cam_x),hl
        xor a
        ld (cam_lock),a
        ld (freeze_t),a
        ld (dagger_on),a
        call objects_reset
        ld a,(keep_player)
        or a
        jr nz,.keep
        call player_reset
        jr .placed
.keep:
        call camera_update              ; camera around Simon's position
.placed:
        call full_redraw
        ld a,0xFF
        ld (loaded_frames),a            ; Simon's patterns must be streamed again
        ld (loaded_frames+1),a
        ld hl,sct_cache                 ; and all object colours rewritten
        ld de,sct_cache+1
        ld bc,2*MAX_SPRITES-1
        ld (hl),a
        ldir
        call objects_spawn
        call build_sat
        call write_player_sprites       ; (enables interrupts)
        di

        ld a,(RG1SAV)                   ; display on
        or 0x40
        ld b,a
        ld c,1
        call vdp_wreg
        ei
        ret

; Copy one band's background tiles.  A = band, HL = patterns, DE = colours,
; BC = size in bytes. Tiles start at pattern BG_TILE_BASE of the band.
load_band:
        push de
        push bc
        push hl
        add a,a
        add a,a
        add a,a                         ; band * 8 = high byte of band * 0x800
        ld h,a
        ld l,0
        ld de,BG_TILE_BASE*8
        add hl,de
        ld (tmp_w),hl
        ex de,hl                        ; DE = VRAM pattern address
        pop hl
        pop bc
        push bc
        call vram_copy
        pop bc
        pop hl                          ; colours
        ld de,(tmp_w)
        push hl
        ld hl,VRAM_CT
        add hl,de
        ex de,hl
        pop hl
        jp vram_copy

; Walking into the area's exit (the castle gate) enters the next area.
check_area_exit:
        ld a,(on_ground)                ; only standing on the ground: not in
        or a                            ; a jump, on stairs or knocked back
        ret z                           ; (a sequence walks him along the floor)
        ld a,(stair_state)
        ld hl,hurt_state
        or (hl)
        ld hl,jump_idx
        or (hl)
        ret nz
        ld hl,(area_hdr+AH_EXITX)
        ld a,h
        and l
        inc a
        ret z                           ; 0xFFFF: this area has no exit
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
        ld a,(area_hdr+AH_EXITY)        ; on the right floor? (the hall's door
        cp 0xFF                         ; is on the upper floor)
        jr z,.go
        ld hl,(py)
        bit 7,h
        jr nz,.go                       ; above the playfield
        ld e,a
        ld d,0
        ex de,hl
        or a
        sbc hl,de                       ; exit y - py
        ret c
.go:
        ld a,(area_hdr+AH_EXIT_KIND)    ; the castle gate and the doors play
        or a                            ; a short sequence first
        jr z,.now
        ld (seq_kind),a
        xor a
        ld (seq_phase),a
        ld (whip_t),a
        ld (whip_active),a
        ld (facing),a
        ld hl,0
        ld (seq_t),hl
        ret
.now:
        ld a,(area_hdr+AH_NEXT)
        jp load_area

; ---------------------------------------------------------------------------
; Exit sequences, one frame each (main loop, instead of the game logic).
;  castle gate: Simon walks into the gate, 1 px every 3 frames
;  door: the screen scrolls 1 px per frame to AH_DOOR_CAM while Simon stands;
;        the door opens, he walks through (1 px per frame), it closes, he
;        walks on to AH_WALK_END with the screen following; then the next area
; ---------------------------------------------------------------------------
seq_tick:
        ld hl,(seq_t)
        inc hl
        ld (seq_t),hl
        ld a,(seq_kind)
        cp 1
        jr nz,door_tick
        ; --- the castle gate ---
        ld a,l                          ; every 3rd frame a step
        ld b,3
.mod3:
        sub b
        jr nc,.mod3
        add a,b
        jr nz,.no_step
        ld hl,(px)
        inc hl
        ld (px),hl
.no_step:
        ld hl,(area_hdr+AH_DOOR_COL)    ; behind the gate's pillar: out of sight
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,-8
        add hl,de
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ld a,0
        jr c,.visible
        inc a
.visible:
        ld (seq_hidden),a
        ld a,(seq_t)
        rrca                            ; walk cycle at a third of the speed
        and 0x18
        call walk_pose
        ld hl,(seq_t)
        ld de,GATE_FRAMES
        or a
        sbc hl,de
        ret c
        jp seq_next_area

door_tick:
        ld a,(seq_phase)
        or a
        jr nz,.phase1
        xor a                           ; 0: standing while the screen scrolls
        ld (pframe),a
        ld hl,(cam_x)
        ld de,(area_hdr+AH_DOOR_CAM)
        or a
        sbc hl,de
        jr nc,.half_open
        ld hl,(cam_x)
        inc hl
        jp camera_goto
.half_open:
        ld a,1                          ; the door swings: half open
        jr .next_phase
.phase1:
        cp 1
        jr nz,.phase2
        ld hl,(seq_t)                   ; 1: half open, still standing
        ld a,l
        cp DOOR_HALF_OPEN
        ret c
        ld a,2                          ; open
        jr .next_phase
.phase2:
        call door_walk
        ld a,(seq_phase)
        cp 2
        jr nz,.phase3
        ld hl,(area_hdr+AH_DOOR_COL)    ; 2: open, he walks through
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,24
        add hl,de
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
        ld a,1                          ; past it: half open again
        ld (door_pending),a
        ld a,3
        ld (seq_phase),a
        ld hl,0
        ld (seq_t),hl
        ret
.phase3:
        cp 3
        jr nz,.phase4
        ld hl,(seq_t)                   ; 3: half open, he walks on
        ld a,l
        cp DOOR_HALF_SHUT
        ret c
        ld a,3                          ; shut
        ld (door_pending),a
        ld a,4
        ld (seq_phase),a
        ld hl,0
        ld (seq_t),hl
        ret
.phase4:
        ld hl,(cam_x)                   ; 4: walks on, the screen following,
        inc hl                          ; to AH_WALK_END (still on the floor
        call camera_goto                ; at the next stage's start)
        ld hl,(px)
        ld de,(area_hdr+AH_WALK_END)
        or a
        sbc hl,de
        ret c
        jr seq_next_area
.next_phase:
        ld (door_pending),a             ; door tiles: 1 half open, 2 open
        ld hl,seq_phase
        inc (hl)
        ld hl,0
        ld (seq_t),hl
        ret

; Simon walks right, 1 px per frame
door_walk:
        ld hl,(px)
        inc hl
        ld (px),hl
        ld a,(seq_t)
        rlca
        and 0x18
        jp walk_pose

seq_next_area:
        xor a
        ld (seq_kind),a
        ld (seq_hidden),a
        ld a,(area_hdr+AH_NEXT)
        jp load_area

; A = walk cycle step * 8 (0, 8, 16, 24): Simon's walk pose, facing right
walk_pose:
        rrca
        rrca
        rrca
        and 3
        ld e,a
        ld d,0
        ld hl,walk_cycle
        add hl,de
        ld a,(hl)
        ld (pframe),a
        xor a
        ld (facing),a
        ld (pyoff),a
        ret

; VBLANK: draw the door's 3 tile columns (DOOR_ROWS high): 1 half open, 2 open
; (from the area's extra columns at AH_DOOR_VCOL), 3 shut (the map's own)
door_vram:
        ld a,(door_pending)
        or a
        ret z
        ld c,a
        xor a
        ld (door_pending),a
        ld hl,(area_hdr+AH_DOOR_COL)
        ld a,c
        cp 3
        jr z,.src
        ld hl,(area_hdr+AH_DOOR_VCOL)
        dec a
        jr z,.src
        inc hl                          ; open: the second three
        inc hl
        inc hl
.src:
        ld (door_src),hl
        ld hl,(area_hdr+AH_DOOR_COL)
        ld (door_dst),hl
        ld b,3
.col:
        push bc
        call door_column
        ld hl,(door_src)
        inc hl
        ld (door_src),hl
        ld hl,(door_dst)
        inc hl
        ld (door_dst),hl
        pop bc
        djnz .col
        ret

; one column: map column door_src (rows DOOR_ROW..) -> screen column door_dst
door_column:
        ld hl,(door_src)                ; AH_TILES + col * PF_ROWS + DOOR_ROW
        ld d,h
        ld e,l
        add hl,hl                       ; *2
        push hl
        add hl,hl
        add hl,hl                       ; *8
        push hl
        add hl,hl                       ; *16
        pop bc
        add hl,bc                       ; *24
        pop bc
        or a
        sbc hl,bc                       ; *22 (PF_ROWS)
        ld de,(area_hdr+AH_TILES)
        add hl,de
        ld de,DOOR_ROW
        add hl,de
        ex de,hl                        ; DE = first map tile
        ld a,(door_dst)
        and 31
        ld l,a
        ld h,0
        ld bc,VRAM_PNT+(HUD_ROWS+DOOR_ROW)*32
        add hl,bc                       ; HL = its name-table address
        ld b,DOOR_ROWS
.lp:
        push bc
        push hl
        call vram_set_write
        ld a,(de)
        out (VDP_DATA),a
        inc de
        pop hl
        ld bc,32
        add hl,bc
        pop bc
        djnz .lp
        ret

; ---------------------------------------------------------------------------
; Sections joined by stairs. Called after each vertical step on the stairs:
; past the bottom of the playfield (going down) or its top (going up), the
; area below or above is loaded, Simon keeps his x, his y moves by
; SECTION_DY, and he stays on the same staircase, which continues there.
; ---------------------------------------------------------------------------
section_link:
        ld a,(stair_going)
        or a
        jp m,.down
        ld a,(area_hdr+AH_ABOVE)
        cp 0xFF
        ret z
        ld b,a
        ld hl,(py)
        ld a,h
        inc a
        ret nz                          ; py >= 0
        ld a,l
        cp (SECTION_UP_Y & 0xFF)+1
        ret nc                          ; py > SECTION_UP_Y
        ld de,SECTION_DY
        jr .switch
.down:
        ld a,(area_hdr+AH_BELOW)
        cp 0xFF
        ret z
        ld b,a
        ld hl,(py)
        ld a,h
        or a
        ret nz
        ld a,l
        cp SECTION_DOWN_Y
        ret c
        ld de,-SECTION_DY
.switch:
        add hl,de
        ld (py),hl
        ld a,1
        ld (keep_player),a
        ld a,b
        call load_area
        xor a
        ld (keep_player),a
        ; find the staircase that continues here: the one whose x range has Simon
        ld hl,(area_hdr+AH_STAIRS)
        ld a,(hl)
        inc hl
        or a
        jr z,.lost
        ld b,a
.find:
        push hl
        pop ix
        ld e,(ix+ST_FOOTX)
        ld d,(ix+ST_FOOTX+1)
        ld l,(ix+ST_TOPX)
        ld h,(ix+ST_TOPX+1)
        ex de,hl                        ; HL = foot x, DE = top x
        or a
        sbc hl,de
        jr c,.ordered
        add hl,de                       ; foot x > top x: swap
        ex de,hl
        jr .range
.ordered:
        add hl,de                       ; HL = smaller x, DE = larger x
.range:
        push de
        ld de,(px)
        ex de,hl                        ; HL = px, DE = smaller x
        or a
        sbc hl,de
        pop de
        jr c,.next                      ; px < smaller x
        ld hl,(px)
        ex de,hl
        or a
        sbc hl,de
        jr c,.next                      ; larger x < px
        ld (stair_ptr),ix
        ld a,(ix+ST_DIR)
        ld (stair_dir),a
        ret
.next:
        ld de,ST_SIZE
        add ix,de
        push ix
        pop hl
        djnz .find
.lost:
        xor a                           ; no staircase here (bad data): drop him
        ld (stair_state),a
        ret
