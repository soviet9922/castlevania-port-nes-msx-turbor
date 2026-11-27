; ---------------------------------------------------------------------------
; Areas
;
; Each area (courtyard, entrance hall, ...) lives in its own 16 KB ROM bank
; (area_bank: areas 0-5 in banks 1-6, the others from bank 16, after Simon's
; and the sound banks) that starts with a header (tools/areas_asm.py). The
; current area's bank stays mapped at 0x8000 while it is played, because
; column streaming and collision read its map directly. The header is copied
; to area_hdr so the engine can use its values without banking.
; ---------------------------------------------------------------------------

; A = area number. Loads everything and restarts the player at the start
; (or, with keep_player set, keeps him where he is: section change).
load_area:
        ld (cur_area),a
        call area_bank
        ld (page2_bank),a               ; (for the sound interrupt)
        ld (ASCII16_PAGE2),a            ; ASCII16: bank seen at 0x8000
        ld hl,0x8000
        ld de,area_hdr
        ld bc,AH_SIZE
        ldir

        di
        call load_overlay
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
        ld a,(area_hdr+AH_MUSIC)        ; the stage's music (carries on if
        call music_play                 ; it is already playing)
        di
        ld hl,0
        ld (cam_x),hl
        xor a
        ld (cam_lock),a
        ld (freeze_t),a
        ld (sub_out),a
        call objects_reset
        call crushers_reset
        ld a,(keep_player)
        or a
        jr nz,.keep
        call player_reset
.keep:
        call camera_update              ; camera around Simon's position
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

; A = area number -> A = its ROM bank (tools/areas_asm.py)
; Copy the RAM overlay the area's stage needs to OVL_BASE (src/overlays.asm):
; 1 for stages up to 12, 2 for stages 13-18 (AH_STAGE is BCD). Interrupts off.
load_overlay:
        ld a,(area_hdr+AH_STAGE)
        cp 0x13
        ld a,1
        jr c,.n
        inc a
.n:
        ld hl,cur_ovl
        cp (hl)
        ret z                           ; (already there)
        ld (hl),a
        dec a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld a,OVL_BANK
        ld (ASCII16_PAGE2),a
        ld hl,ovl_table
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
        jr z,.done                      ; (an empty overlay)
        ex de,hl
        ld de,OVL_BASE
        ldir
.done:
        ld a,(page2_bank)
        ld (ASCII16_PAGE2),a
        ret

area_bank:
        inc a
        cp 7
        ret c                           ; areas 0-5: banks 1-6
        add a,16-7                      ; areas 6 and up: banks 16 and up
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
        ld a,(area_hdr+AH_EXIT_KIND)    ; kind 3: a point on the stairs (stage
        cp 3                            ; 10's end, NES $FC19)
        jr z,.anywhere
        ld a,(on_ground)                ; only standing on the ground: not in
        or a                            ; a jump, on stairs or knocked back
        ret z                           ; (a sequence walks him along the floor)
        ld a,(stair_state)
        ld hl,hurt_state
        or (hl)
        ld hl,jump_idx
        or (hl)
        ret nz
.anywhere:
        ld hl,(area_hdr+AH_EXITX)
        ld a,h
        and l
        inc a
        ret z                           ; 0xFFFF: this area has no exit
        ex de,hl                        ; DE = exit x
        ld hl,(px)
        ld a,(area_hdr+AH_EXIT_LEFT)
        or a                            ; (clears carry)
        jr nz,.left_exit
        sbc hl,de                       ; px >= exit x
        ret c
        jr .at_exit
.left_exit:
        ex de,hl                        ; a door at the left end: px <= exit x
        sbc hl,de
        ret c
.at_exit:
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
        cp 3
        jr z,.now
        ld (seq_kind),a
        xor a
        ld (seq_phase),a
        ld (whip_t),a
        ld (whip_active),a
        ld a,(area_hdr+AH_EXIT_LEFT)
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
;        walks on to AH_WALK_END and the screen scrolls on to AH_CAM_END, so that
;        both match the next area's start; then the next area
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
        ld hl,(area_hdr+AH_DOOR_COL)    ; behind the gate's pillar: he is cut
        add hl,hl                       ; off there, one column of pixels at a
        add hl,hl                       ; time (width = pillar x - px, 0..16)
        add hl,hl
        ld de,(px)
        or a
        sbc hl,de
        ld a,16
        jr c,.gone
        ld a,h
        or a
        ld a,16
        jr nz,.width
        ld a,l
        cp 16
        jr c,.width
        ld a,16
        jr .width
.gone:
        xor a
.width:
        call set_clip
        ld a,0xFF                       ; patterns streamed again each frame
        ld (loaded_frames),a
        ld (loaded_frames+1),a
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
        ld de,(area_hdr+AH_DOOR_CAM)
        call cam_toward
        ret nz
.half_open:
        ld a,SND_DOOR
        call sfx_play
        ld a,1                          ; the door swings: half open
        jp .next_phase
.phase1:
        cp 1
        jr nz,.phase2
        ld hl,(seq_t)                   ; 1: half open, still standing
        ld a,l
        cp DOOR_HALF_OPEN
        ret c
        ld a,2                          ; open
        jp .next_phase
.phase2:
        cp 4
        jr z,.phase4
        call door_walk
        ld a,(seq_phase)
        cp 2
        jr nz,.phase3
        ld hl,(area_hdr+AH_DOOR_COL)    ; 2: open, he walks through
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(area_hdr+AH_EXIT_LEFT)
        or a
        jr nz,.through_left
        ld de,24
        add hl,de
        ex de,hl
        ld hl,(px)
        or a
        sbc hl,de
        ret c
        jr .through
.through_left:
        ld de,-32                       ; (left door: px + 16 <= its right edge - 24)
        add hl,de
        ld de,(px)
        or a
        sbc hl,de
        ret c
.through:
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
        ; 4: he walks on to AH_WALK_END (where he starts in the next stage)
        ; and the screen scrolls on to AH_CAM_END (where the next stage's
        ; map begins): then the next stage loads without a jump
        call walk_left_to_go           ; HL = distance left to walk
        ld a,h
        or l
        jr z,.stand
        call door_walk
        jr .scroll
.stand:
        xor a
        ld (pframe),a
.scroll:
        ld de,(area_hdr+AH_CAM_END)
        call cam_toward
        ret nz
        call walk_left_to_go
        ld a,h
        or l
        ret nz
        jr seq_next_area
.next_phase:
        ld (door_pending),a             ; door tiles: 1 half open, 2 open
        ld hl,seq_phase
        inc (hl)
        ld hl,0
        ld (seq_t),hl
        ret

; HL = how far Simon still walks to AH_WALK_END (0 = there or past it)
walk_left_to_go:
        ld hl,(px)
        ld de,(area_hdr+AH_WALK_END)
        ld a,(area_hdr+AH_EXIT_LEFT)
        or a
        jr nz,.left
        ex de,hl                        ; walking right: end - px
.left:
        or a
        sbc hl,de                       ; walking left: px - end
        ret nc
        ld hl,0
        ret

; Scroll the camera 1 px toward DE (the door sequence's direction).
; NZ while it is still moving, Z when it is there.
cam_toward:
        ld hl,(cam_x)
        or a
        sbc hl,de
        ret z
        ld hl,(cam_x)
        ld a,(area_hdr+AH_EXIT_LEFT)
        or a
        jr nz,.dec
        inc hl
        jr .go
.dec:
        dec hl
.go:
        call camera_goto
        or 1                            ; NZ: still moving
        ret

; Simon walks through the door, 1 px per frame (left at a left door)
door_walk:
        ld hl,(px)
        ld a,(area_hdr+AH_EXIT_LEFT)
        or a
        jr nz,.left
        inc hl
        jr .step
.left:
        dec hl
.step:
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

; A = visible width of Simon (0..16 px from his left): pattern masks
set_clip:
        ld b,a
        cp 8
        jr c,.narrow
        sub 8                           ; 8..16: all of the left half, part of
        call .mask                      ; the right
        ld (clip_r),a
        ld a,0xFF
        ld (clip_l),a
        ret
.narrow:
        call .mask                      ; 0..7: part of the left half only
        ld (clip_l),a
        xor a
        ld (clip_r),a
        ret
.mask:                                  ; A = n (0..8) -> the n left bits set
        ld c,a
        xor a
        inc c
.lp:
        dec c
        ret z
        scf
        rra
        jr .lp

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
        ld a,(seq_kind)                 ; at a left door he faces left
        cp 2
        ld a,0
        jr nz,.face
        ld a,(area_hdr+AH_EXIT_LEFT)
.face:
        ld (facing),a
        xor a
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
        ld a,(area_hdr+AH_EXIT_LEFT)    ; a left door's 3 columns: its own
        or a                            ; and the 2 to its left
        jr z,.dst
        dec hl
        dec hl
        ld a,c                          ; (shut: the map's own columns too)
        cp 3
        jr nz,.dst
        ld (door_src),hl
.dst:
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

; one column: map column door_src (rows AH_DOOR_ROW..) -> screen column door_dst
door_column:
        ld hl,(door_src)                ; AH_TILES + col * PF_ROWS + door row
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
        ld a,(area_hdr+AH_DOOR_ROW)
        ld e,a
        ld d,0
        add hl,de
        push de
        ex de,hl                        ; DE = first map tile
        pop hl                          ; HL = door row * 32
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(door_dst)
        and 31
        ld c,a
        ld b,0
        add hl,bc
        ld bc,VRAM_PNT+HUD_ROWS*32
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

; ---------------------------------------------------------------------------
; Ceiling crushers (stage 6, recorded on the NES): background tiles. Each one
; steps through its cycle (AH_CRUSHERS: spike row and frames per step: down a
; row every 4 frames, up a row every 16); its 4 tile columns are copied from
; the area's hidden columns (AH_CRUSH_VCOL, 4 per spike row) into the name
; table, one crusher per VBLANK. Spikes that reach Simon kill him at once.
; ---------------------------------------------------------------------------

; IX -> crusher record (x lo, x hi, phase, steps, (row, frames)...); A = index
; -> HL = its state (step, frames left)
crush_state_of:
        add a,a
        ld e,a
        ld d,0
        ld hl,crush_state
        add hl,de
        ret

; HL = the record after the one at IX
crush_skip:
        push ix
        pop hl
        ld e,(ix+3)
        ld d,0
        inc hl
        inc hl
        inc hl
        inc hl
        add hl,de
        add hl,de
        ret

; one frame of the crusher at IX, state at HL
crush_step:
        dec (hl)                        ; (frames left are at HL+1: see below)
        ret

crushers_reset:
        xor a
        ld (crush_next),a
        call crushers_redraw
        ld ix,(area_hdr+AH_CRUSHERS)
        ld a,(ix+0)
        or a
        ret z
        ld b,a
        inc ix
        ld c,0
.lp:
        push bc
        ld a,c
        call crush_state_of
        ld (hl),0                       ; step 0, its frames
        inc hl
        ld a,(ix+5)
        ld (hl),a
        ld b,(ix+2)                     ; then run the phase
        inc b
        jr .run
.adv:
        push bc
        push hl
        call crush_tick_one
        pop hl
        pop bc
.run:
        djnz .adv
        call crush_skip
        push hl
        pop ix
        pop bc
        inc c
        djnz .lp
        ret

; advance the crusher at IX (its frames-left byte at HL, step at HL-1)
crush_tick_one:
        dec (hl)
        ret nz
        dec hl
        ld a,(hl)
        inc a
        cp (ix+3)
        jr c,.ok
        xor a
.ok:
        ld (hl),a
        inc hl
        add a,a
        ld e,a
        ld d,0
        push ix
        add ix,de
        ld a,(ix+5)                     ; this step's frames
        pop ix
        ld (hl),a
        ret

; IX = crusher, A = its index -> A = spike row (0 = highest)
crush_row:
        call crush_state_of
        ld a,(hl)
        add a,a
        ld e,a
        ld d,0
        push ix
        add ix,de
        ld a,(ix+4)
        pop ix
        ret

crushers_tick:
        ld ix,(area_hdr+AH_CRUSHERS)
        ld a,(ix+0)
        or a
        ret z
        ld b,a
        inc ix
        ld c,0
.lp:
        push bc
        ld a,c
        call crush_state_of
        inc hl
        call crush_tick_one
        pop bc
        push bc
        ld a,c
        call crush_row                  ; spikes on Simon?
        add a,CRUSH_FIRST_ROW+1
        add a,a
        add a,a
        add a,a                         ; A = spikes' bottom y
        sub 2
        ld d,a
        ld a,(py+1)
        or a
        jr nz,.next                     ; above the playfield
        ld a,(py)
        cp d
        jr nc,.next                     ; below the spikes
        ld l,(ix+0)                     ; crusher x+0..x+31 vs Simon px+3..px+12
        ld h,(ix+1)
        ld de,31
        add hl,de
        ld de,(px)
        inc de
        inc de
        inc de
        or a
        sbc hl,de
        jr c,.next
        ld hl,(px)
        ld de,12
        add hl,de
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        jr c,.next
        ld a,(dying_t)
        or a
        jr nz,.next
        ld a,1                          ; crushed: dead whatever his health
        ld (player_dead),a
.next:
        call crush_skip
        push hl
        pop ix
        pop bc
        inc c
        djnz .lp
        ret

; all crushers drawn again (the map's columns show them at rest)
crushers_redraw:
        ld hl,crush_drawn
        ld b,CRUSH_MAX
.lp:
        ld (hl),0xFF
        inc hl
        djnz .lp
        ret

; VBLANK: the HUD when it has something to redraw, else a crusher
hud_or_crusher:
        ld a,(hud_dirty)
        ld hl,hud_parts
        or (hl)
        jp nz,hud_update
        ; (fall through)

; VBLANK: copy one crusher's 4 columns (CRUSH_ROWS rows) to the name table
crusher_vram:
        ld ix,(area_hdr+AH_CRUSHERS)
        ld a,(ix+0)
        or a
        ret z
        ld b,a
        ld a,(crush_next)
        cp b
        jr c,.idx
        xor a
.idx:
        ld c,a
        inc a
        ld (crush_next),a
        inc ix
        ld a,c                          ; find crusher C
        or a
        jr z,.found
.find:
        push bc
        call crush_skip
        push hl
        pop ix
        pop bc
        dec c
        jr nz,.find
        ld a,(crush_next)
        dec a
.found:
        ld c,a
        call crush_row                  ; drawn like that already?
        ld b,0
        ld hl,crush_drawn
        add hl,bc
        cp (hl)
        ret z
        ld (hl),a
        add a,a                         ; source column: AH_CRUSH_VCOL + 4*row
        add a,a
        ld e,a
        ld d,0
        ld hl,(area_hdr+AH_CRUSH_VCOL)
        add hl,de
        ld (door_src),hl                ; (the door's work variables: no door here)
        ld l,(ix+0)                     ; destination: the crusher's tile column
        ld h,(ix+1)
        call hl_shr3
        ld (door_dst),hl
        ld hl,(cam_x)                   ; all 4 columns on the screen, in one
        call hl_shr3                    ; piece of the name table ring? Then
        inc hl                          ; a row at a time
        ex de,hl
        ld hl,(door_dst)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.slow
        ld a,l
        cp 32-3
        jr nc,.slow
        ld a,(door_dst)
        and 31
        cp 32-3
        jp c,crush_rows
.slow:
        ld b,4
.col:
        push bc
        ld hl,(cam_x)                   ; on the screen? (cam/8 + 1 .. + 32)
        call hl_shr3
        inc hl
        ex de,hl
        ld hl,(door_dst)
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.skip
        ld a,l
        cp 32
        jr nc,.skip
        call crush_column
.skip:
        ld hl,(door_src)
        inc hl
        ld (door_src),hl
        ld hl,(door_dst)
        inc hl
        ld (door_dst),hl
        pop bc
        djnz .col
        ret

; one column: map column door_src rows CRUSH_FIRST_ROW.. -> screen column door_dst
crush_column:
        ld hl,(door_src)                ; AH_TILES + col * PF_ROWS + first row
        ld d,h
        ld e,l
        add hl,hl
        push hl
        add hl,hl
        add hl,hl
        push hl
        add hl,hl
        pop bc
        add hl,bc
        pop bc
        or a
        sbc hl,bc                       ; *22 (PF_ROWS)
        ld de,(area_hdr+AH_TILES)
        add hl,de
        ld de,CRUSH_FIRST_ROW
        add hl,de
        ex de,hl
        ld a,(door_dst)
        and 31
        ld l,a
        ld h,0
        ld bc,VRAM_PNT+(HUD_ROWS+CRUSH_FIRST_ROW)*32
        add hl,bc
        ld b,CRUSH_ROWS
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

; the crusher's 4 columns, row by row (all on the screen, no ring wrap):
; map columns door_src.. rows CRUSH_FIRST_ROW.. -> screen columns door_dst..
crush_rows:
        ld hl,(door_src)                ; AH_TILES + col * PF_ROWS + first row
        add hl,hl
        push hl
        add hl,hl
        add hl,hl
        push hl
        add hl,hl
        pop bc
        add hl,bc
        pop bc
        or a
        sbc hl,bc                       ; *22 (PF_ROWS)
        ld de,(area_hdr+AH_TILES)
        add hl,de
        ld de,CRUSH_FIRST_ROW
        add hl,de
        ex de,hl                        ; DE = first map tile
        ld a,(door_dst)
        and 31
        ld l,a
        ld h,0
        ld bc,VRAM_PNT+(HUD_ROWS+CRUSH_FIRST_ROW)*32
        add hl,bc
        ld b,CRUSH_ROWS
.row:
        push bc
        push hl
        push de
        call vram_set_write
        ex de,hl
        ld bc,PF_ROWS
        ld a,(hl)
        out (VDP_DATA),a
        add hl,bc
        ld a,(hl)
        out (VDP_DATA),a
        add hl,bc
        ld a,(hl)
        out (VDP_DATA),a
        add hl,bc
        ld a,(hl)
        out (VDP_DATA),a
        pop de
        inc de
        pop hl
        ld bc,32
        add hl,bc
        pop bc
        djnz .row
        ret
