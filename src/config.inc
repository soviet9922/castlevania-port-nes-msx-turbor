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

; Level / camera
LEVEL_PX        equ LEVEL_W*16
LEVEL_TILE_COLS equ LEVEL_W*2
MAX_CAM         equ LEVEL_PX-256
CAM_LEAD        equ 120                 ; player screen x the camera tries to keep

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
NPOSES          equ 12                  ; poses per facing direction
POSE_TUCK       equ 3
POSE_WHIP       equ 4                   ; whip1..whip4, then +4 for the crouched set
SAT_END_Y       equ 216                 ; sprite mode 2 "end of list" Y value
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
