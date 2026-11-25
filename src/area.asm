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
;        walks on DOOR_WALK px with the screen following; then the next area
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
        ld a,(seq_t)
        rrca                            ; walk cycle at a third of the speed
        and 0x18
        call walk_pose
        ld hl,(seq_t)
        ld de,GATE_FRAMES
        or a
        sbc hl,de
        ret c
        jr seq_next_area

door_tick:
        ld a,(seq_phase)
        or a
        jr nz,.walking
        xor a                           ; standing while the screen scrolls
        ld (pframe),a
        ld hl,(cam_x)
        ld de,(area_hdr+AH_DOOR_CAM)
        or a
        sbc hl,de
        jr nc,.open
        ld hl,(cam_x)
        inc hl
        jp camera_goto
.open:
        ld a,1
        ld (seq_phase),a
        ld (door_pending),a             ; open the door (VBLANK)
        ld hl,0
        ld (seq_t),hl
        ret
.walking:
        ld hl,(px)                      ; walks right, 1 px per frame
        inc hl
        ld (px),hl
        ld a,(seq_t)
        rlca
        and 0x18
        call walk_pose
        ld a,(seq_phase)
        cp 2
        jr z,.after
        ld hl,(area_hdr+AH_DOOR_COL)    ; past the door? close it behind him
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,8
        add hl,de
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
        ld a,2
        ld (seq_phase),a
        ld (door_pending),a             ; close the door (VBLANK)
        ld hl,0
        ld (seq_t),hl
        ret
.after:
        ld hl,(cam_x)                   ; the screen follows him
        inc hl
        call camera_goto
        ld hl,(seq_t)
        ld de,DOOR_WALK
        or a
        sbc hl,de
        ret c
seq_next_area:
        xor a
        ld (seq_kind),a
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

; VBLANK: open (blank tiles) or close (the map's tiles) the door's column
door_vram:
        ld a,(door_pending)
        or a
        ret z
        ld (door_mode),a
        xor a
        ld (door_pending),a
        ld hl,(area_hdr+AH_DOOR_COL)    ; map column: AH_TILES + col * PF_ROWS
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
        ex de,hl                        ; DE = the door's first map tile
        ld a,(area_hdr+AH_DOOR_COL)
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
        ld a,(door_mode)
        cp 1
        ld a,(area_hdr+AH_BLANK)
        jr z,.put
        ld a,(de)
.put:
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
