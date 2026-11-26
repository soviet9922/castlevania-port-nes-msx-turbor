; ---------------------------------------------------------------------------
; Engine configuration: screen layout, VRAM map, physics constants
; See docs/DESIGN.md for the reasoning behind these values.
; ---------------------------------------------------------------------------

; Screen layout (Screen 4 / Graphic 3, 256x192, 32x24 tiles)
HUD_ROWS        equ 2                   ; fixed (non-scrolling) tile rows at the top
PF_ROWS         equ MT_ROWS*2           ; playfield tile rows (22 = NES playfield height)
PF_TOP_PX       equ HUD_ROWS*8          ; first playfield scanline
SPLIT_LINE      equ PF_TOP_PX-3         ; line interrupt: switch HUD scroll -> playfield scroll
                                        ; (fires inside the blank bottom of the HUD so
                                        ;  interrupt latency jitter is invisible)
        ASSERT HUD_ROWS + PF_ROWS == 24

; VRAM map (standard Screen 4 layout)
VRAM_PGT        equ 0x0000              ; pattern generator, 3 bands x 2 KB
VRAM_PNT        equ 0x1800              ; name table 32x24
VRAM_SCT        equ 0x1C00              ; sprite colour table (SAT - 512)
VRAM_SAT        equ 0x1E00              ; sprite attribute table
VRAM_CT         equ 0x2000              ; colour table, 3 bands x 2 KB
VRAM_SPT        equ 0x3800              ; sprite patterns
                                        ; (sprite page 1 = page 0 + 0x4000, see vdp.asm)
BAND_SIZE       equ 0x0800
BG_TILE_BASE    equ 0x60                ; background tiles use pattern numbers 0x60-0xFF

; Camera
CAM_LEAD        equ 120                 ; player screen x the camera tries to keep

; Area header (tools/areas_asm.py), copied to area_hdr in RAM
AH_PALETTE      equ 0
AH_PGT0         equ 2
AH_CT0          equ 4
AH_PGT1         equ 6
AH_CT1          equ 8
AH_PGT2         equ 10
AH_CT2          equ 12
AH_BGSZ0        equ 14
AH_BGSZ1        equ 16
AH_BGSZ2        equ 18
AH_TILES        equ 20                  ; name-table bytes, PF_ROWS per 8-px column
AH_COLL         equ 22                  ; solidity, PF_ROWS per 8-px column
AH_TCOLS        equ 24                  ; 8-px columns in the area
AH_MAXCAM       equ 26
AH_STARTX       equ 28
AH_STARTY       equ 30
AH_CANDLES      equ 32
AH_OBJSPT       equ 34
AH_OBJSPTSZ     equ 36
AH_OBJSCT       equ 38
AH_OBJFRAMES    equ 40
AH_EXITX        equ 42                  ; 0xFFFF = no exit
AH_NEXT         equ 44
AH_BLANK        equ 45
AH_STAIRS       equ 46                  ; count, then 7 bytes per staircase
AH_ENEMIES      equ 48                  ; count, then 4 bytes per spawner (x, y, type)
AH_EXITY        equ 50                  ; exit only when py <= this (0xFF = any)
AH_BELOW        equ 51                  ; area below (stairs down), 0xFF = none
AH_ABOVE        equ 52                  ; area above (stairs up), 0xFF = none
AH_RESPAWN      equ 53                  ; area to restart in after a fall/death
AH_STAGE        equ 54                  ; stage number shown in the HUD (BCD)
AH_EXIT_KIND    equ 55                  ; 0 at once, 1 castle gate, 2 door
AH_DOOR_COL     equ 56                  ; door: tile column (2 bytes)
AH_DOOR_CAM     equ 58                  ; door: camera x while it opens (2 bytes)
AH_DOOR_VCOL    equ 60                  ; door: its 6 extra tile columns (half open, open)
AH_WALK_END     equ 62                  ; door: Simon walks on to this x (2 bytes)
AH_CAM_END      equ 64                  ; door: the screen scrolls on to this x (2 bytes)
AH_SUB_SPT      equ 66                  ; patterns of the flying dagger, axe, holy water
AH_SUB_SZ       equ 72                  ; their sizes in bytes (0 = not in this area)
AH_SUB_SLOT     equ 78                  ; first object pattern of the sub-weapon window
AH_SWAP_SPT     equ 79                  ; swap window: zombies' patterns, the boss's
AH_SWAP_SZ      equ 83                  ; their sizes in bytes (0 = no swapping here)
AH_SWAP_SLOT    equ 87                  ; first object pattern of the swap window
AH_MINCAM       equ 88                  ; least camera x (2 bytes)
AH_MUSIC        equ 90                  ; the area's music (SND_ number)
AH_FACE         equ 91                  ; Simon's facing at the start (1 = left)
AH_EXIT_LEFT    equ 92                  ; 1 = the exit (door) is at the left end
AH_DOOR_ROW     equ 93                  ; the door's top playfield row
AH_CRUSHERS     equ 94                  ; ceiling crushers: count, then x, phase, cycle
AH_CRUSH_VCOL   equ 96                  ; their hidden tile columns (4 per spike row)
AH_SIZE         equ 98
CRUSH_FIRST_ROW equ 8                   ; playfield rows the crushers rewrite (NES
CRUSH_ROWS      equ 8                   ; nametable rows 14-21)
CRUSH_MAX       equ 4

; Exit sequences (measured on the NES)
GATE_FRAMES     equ 120                 ; walking into the castle gate, 1 px every 3 frames
DOOR_ROW        equ 2                   ; the door: 6 tiles from playfield row 2 (NES nametable row 8)
DOOR_ROWS       equ 6
DOOR_HALF_OPEN  equ 16                  ; frames half open before it opens
DOOR_HALF_SHUT  equ 8                   ; frames half open again after Simon

; Sections: a staircase that leaves the bottom of the playfield continues in
; the area below (and the other way). As on the NES, x stays, y moves by
; SECTION_DY and the new area is drawn around Simon.
SECTION_DY      equ 158
SECTION_DOWN_Y  equ 144                 ; going down: switch when py >= this
SECTION_UP_Y    equ -15                 ; going up: switch when py <= this

; Stair records (tools/convert_stage.py): foot x, foot y, top x, top y, dir
ST_FOOTX        equ 0
ST_FOOTY        equ 2
ST_TOPX         equ 3
ST_TOPY         equ 5
ST_DIR          equ 6                   ; +1 rises to the right, -1 to the left
ST_SIZE         equ 7
STAIR_REACH     equ 8                   ; UP/DOWN this close to an end takes the stairs

; Player movement (same model as the NES game)
WALK_SPEED      equ 1                   ; px per frame
JUMP_LEN        equ 20                  ; jump table entries (rising half)
JUMP_TUCK_FROM  equ 3                   ; tucked pose from this jump frame ...
JUMP_TUCK_TO    equ JUMP_LEN+11         ; ... until this one
FALL_START      equ JUMP_LEN+11         ; walking off a ledge joins the arc here
MAX_FALL_PX     equ 5                   ; px per frame after the arc ends
WALK_FRAME_TIME equ 7                   ; frames per walk animation step
TUCK_Y          equ 4                   ; tucked pose is drawn this much lower
CROUCH_Y        equ 8                   ; crouching pose is drawn this much lower

; Player metasprites (see tools/msx_sprites.py)
PLAYER_SPRITES  equ 12                  ; hardware sprites / pattern slots reserved
NPOSES          equ 38                  ; poses per facing direction
POSE_WALK1      equ 1
POSE_TUCK       equ 3
POSE_STAIR      equ 12                  ; climbing (alternates with walk1)
POSE_HURT       equ 13                  ; knocked back
POSE_DEAD1      equ 14                  ; dying: falling down
POSE_DEAD2      equ 15                  ; dying: lying (32 px wide)
POSE_CHAIN      equ 16                  ; whip1-4, whip1c-4c with the chain whip
POSE_STAR       equ 24                  ; ... with the morning star (longer)
POSE_THROW      equ 32                  ; throw1-3, throw1c-3c (a sub-weapon)
STAR_EXTRA      equ 16                  ; the morning star reaches 16 px further
DAGGER_SPEED    equ 4                   ; px per frame (NES)
AXE_VY0         equ -68                 ; 1/16 px per frame: up 4.25 (NES)
AXE_GRAVITY     equ 4                   ; 1/16 px per frame per frame (NES)
AXE_VMAX        equ 112                 ; fastest fall: 7 px per frame
HOLY_VY0        equ -20                 ; the bottle's low lob (NES)
HOLY_GRAVITY    equ 2
HOLY_BURN       equ 77                  ; frames the fire burns (NES)
STOPWATCH_COST  equ 5                   ; hearts (NES)
STOPWATCH_FRAMES equ 178                ; enemies stand still (NES)

; Game rules (measured on the NES: RAM $42/$43 timer, $7FC score, $2A lives)
TIME_START      equ 0x0300              ; BCD, a new game (stage 1); a death or a new
                                        ; block restarts at stage_time (NES $C9F6)
TIME_TICK       equ 64                  ; frames per timer step
LIVES_START     equ 3                   ; shown as P-3
DEATH_FRAMES    equ 97                  ; death animation (NES: 97 frames)
DEATH_POSE1     equ 16                  ; frames of the falling pose, then lying
GAME_OVER_FRAMES equ 180
; points / 100, BCD. Zombie and panther measured on the NES; the others are
; estimates until they are measured
SCORE_ZOMBIE    equ 0x01
SCORE_PANTHER   equ 0x02
SCORE_BAT       equ 0x02
SCORE_FISH      equ 0x03
SCORE_BOSS      equ 0x30
SCORE_KNIGHT    equ 0x04                ; block 2, measured on the NES
SCORE_MEDUSA    equ 0x03
SCORE_EAGLE     equ 0x03                ; block 4 (NES $DF35)
SCORE_DRAGON    equ 0x10
SCORE_FRANK     equ 0x50                ; stage 12's boss: 5000
SCORE_SNAKE     equ 0x01                ; snake, bandage, bone, fireball: 100

; Health and getting hit (measured in the NES entrance hall)
HP_MAX          equ 64                  ; 16 bar segments of 4 on the NES, 8 HUD tiles here
ZOMBIE_DAMAGE   equ 8
DAMAGE_LATE     equ 12                  ; an enemy's touch from stage 7 (NES $E74A)
DAMAGE_LAST     equ 16                  ; ... from stage 12
ENEMY_ZOMBIE    equ 0x01                ; spawner types (NES enemy records)
ENEMY_BAT       equ 0x02
ENEMY_EAGLE     equ 0x12                ; block 4: an eagle carrying a fleaman
BAT_EVERY       equ 384                 ; frames from a bat to the next (NES $C0 ticks)
CROUCH_TOP      equ 20
BOSS_HP         equ 64                  ; the boss's health (the NES's $01A9)
BOSS_FREEZE     equ 8                   ; frames a hit stops the bat boss
                                        ; (NES video: fireballs only from afar)                  ; box top of the spots it flies back to
; Stage clear after the orb (NES game mode $0C, measured)
CLEAR_JINGLE    equ 223                 ; frames of the jingle before the tally
CLEAR_HEART_WAIT equ 56                ; then the timer (1 a frame, 10 points each),
CLEAR_HEART_STEP equ 8                 ; a pause, the hearts (one per 8 frames, 100 each)
CLEAR_OUTRO     equ 115                 ; and a pause before the next block
ENEMY_FISH      equ 0x03
ENEMY_MEDUSA    equ 0x06                ; block 2: Medusa heads
; Block 2's enemies (measured on the NES in stages 4 and 5)
MEDUSA_EVERY    equ 128                 ; frames between Medusa heads (NES: $40 ticks of 2)
MEDUSA_MAX      equ 3                   ; at most this many (NES slots 9-11)
KNIGHT_TURN     equ 192                 ; NES: it turns or faces Simon every 192 frames
; Medusa (stage 6 boss, recorded on the NES)
MEDUSA_WAKE_T   equ 180                 ; frames from the camera lock to her start (NES $B4)
MEDUSA_TOP      equ 103                 ; a flight starts once she is above this (NES y $A8)
MEDUSA_FREEZE   equ 8                   ; frames a hit freezes her
MEDUSA_PAUSE    equ 60                  ; she hovers still this long between flights
SNAKE_MAX       equ 4                   ; (NES: as many as free slots 8-13)
; Block 3's enemies (recorded on the NES in stages 7-9; hits and points of the
; ghost, the pillar and the skeleton are estimates)
WAKE_DX         equ 96                  ; (the mummies' turn test)
FLEA_HIGH       equ -56                 ; fleaman hops (1/16 px a frame up): facing Simon near
FLEA_LONG       equ -16                 ; ... else the long low hop (2 1/4 px across)
FLEA_GRAVITY    equ 2
FLEA_REST       equ 8                   ; frames on the floor between hops
PILLAR_HP       equ 192                 ; damage (hit_damage units) that breaks a bone pillar
SCORE_FLEA      equ 0x05                ; (NES $DF35: 500)
SCORE_GHOST     equ 0x03
SCORE_SKEL      equ 0x03
SCORE_PILLAR    equ 0x04
SCORE_RAVEN     equ 0x02
; The mummies (stage 9 boss, recorded on the NES): two, sharing the HUD's bar
MUMMY_HP        equ 32                  ; each (the bar shows both: 64)
MUMMY_FREEZE    equ 8                   ; frames a hit stops a mummy
FISH_MAX        equ 2                   ; fishmen about at once
FISH_AWAY       equ 40                  ; not within this of Simon (NES $28)
FISH_VY0        equ -88                 ; jump speed, 1/16 px per frame (NES 5 1/2)
FISH_GRAVITY    equ 2
FISH_VMAX       equ 64
FISH_WATER_Y    equ 120                 ; box top when it leaves the water
HIT_FREEZE      equ 6                   ; frames frozen when hit
STUN_FRAMES     equ 16                  ; crouched after landing from the knock-back
INVULN_FRAMES   equ 140                 ; blinking, cannot be hit again
HURT_FREEZE     equ 1                   ; hurt_state values
HURT_FLY        equ 2
HURT_STUN       equ 3

; Zombies (spawn at the screen edges while a zombie spawner is near)
SPAWNERS_MAX    equ 8                   ; spawners in an area's list (at most)
SPAWNER_LEFT    equ 64                  ; spawner active within camera-64 .. camera+320
SPAWNER_RIGHT   equ 320

; Black panther (measured in the NES entrance hall)
PANTHER_WAKE    equ 64                  ; wakes when Simon is this close (x)
PANTHER_SPEED   equ 2                   ; px per frame, running and leaping
PANTHER_VY0     equ -24                 ; leap: vertical speed in 1/16 px ...
PANTHER_GRAVITY equ 2                   ; ... gravity in 1/16 px per frame ...
PANTHER_VMAX    equ 64                  ; ... and terminal speed (4 px)
PANTHER_DAMAGE  equ 8
POSE_WHIP       equ 4                   ; whip1..whip4, then +4 for the crouched set
SAT_END_Y       equ 216                 ; sprite mode 2 "end of list" Y value
MAX_SPRITES     equ 32                  ; hardware sprites in total

; Objects (src/objects.asm)
OBJ_MAX         equ 8
PARTS_MAX       equ 7                   ; drawn-only parts (the bone dragon's)
OBJ_SIZE        equ 12
MAX_CANDLES     equ 64                  ; per area (flag bits)
SPRITE_HIDE_Y   equ 212                 ; parks a sprite below the visible area

; Whip timing in frames (as recorded from the NES game)
WHIP_P2         equ 6                   ; frames 1-5 wind-up
WHIP_P3         equ 13                  ; frames 6-12 swing
WHIP_P4         equ 22                  ; frames 13-21 strike (hits)
WHIP_END        equ 24
WHIP_HIT_T      equ 17                  ; the one strike frame that hits (NES $E40B)                  ; frames 22-23 recovery
; Whip hit box while striking, facing right, relative to the player box
WHIP_HIT_X1     equ 20
WHIP_HIT_X2     equ 43
WHIP_HIT_Y1     equ 11
WHIP_HIT_Y2     equ 15

; a zombie that walks off a platform falls (NES stage 3: 64 px in about 28
; frames, without moving across); 1/16 px units
ZOMBIE_GRAVITY  equ 2
ZOMBIE_VMAX     equ 64


; sound steps the main loop may run in one frame to catch up after running late
; (keeps the music's tempo; 1 = never catch up)
SOUND_CATCH_UP  equ 1
