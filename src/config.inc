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
AH_SIZE         equ 48

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
NPOSES          equ 13                  ; poses per facing direction
POSE_WALK1      equ 1
POSE_TUCK       equ 3
POSE_STAIR      equ 12                  ; climbing (alternates with walk1)
POSE_WHIP       equ 4                   ; whip1..whip4, then +4 for the crouched set
SAT_END_Y       equ 216                 ; sprite mode 2 "end of list" Y value
MAX_SPRITES     equ 32                  ; hardware sprites in total

; Objects (src/objects.asm)
OBJ_MAX         equ 8
OBJ_SIZE        equ 10
MAX_CANDLES     equ 64                  ; per area (flag bits)
SPRITE_HIDE_Y   equ 212                 ; parks a sprite below the visible area

; Whip timing in frames (as recorded from the NES game)
WHIP_P2         equ 6                   ; frames 1-5 wind-up
WHIP_P3         equ 13                  ; frames 6-12 swing
WHIP_P4         equ 22                  ; frames 13-21 strike (hits)
WHIP_END        equ 24                  ; frames 22-23 recovery
; Whip hit box while striking, facing right, relative to the player box
WHIP_HIT_X1     equ 20
WHIP_HIT_X2     equ 43
WHIP_HIT_Y1     equ 11
WHIP_HIT_Y2     equ 15
