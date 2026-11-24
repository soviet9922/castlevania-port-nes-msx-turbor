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
BAND_SIZE       equ 0x0800
BG_TILE_BASE    equ 0x60                ; background tiles use pattern numbers 0x60-0xFF

; Level / camera
LEVEL_PX        equ LEVEL_W*16
LEVEL_TILE_COLS equ LEVEL_W*2
MAX_CAM         equ LEVEL_PX-256
CAM_LEAD        equ 120                 ; player screen x the camera tries to keep

; Player physics (8.8 fixed point for vertical motion)
WALK_SPEED      equ 1                   ; px per frame
GRAVITY         equ 0x0030
JUMP_VY         equ -0x0400
MAX_FALL        equ 0x0400

; Player sprite slots (2 layers x 2 halves = 4 hardware sprites)
PLAYER_SPRITES  equ 4
SAT_END_Y       equ 216                 ; sprite mode 2 "end of list" Y value
