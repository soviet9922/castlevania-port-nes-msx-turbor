; ---------------------------------------------------------------------------
; Bank 1 (mapped at 0x8000): graphics and the current area.
; The area comes either from tools/gen_placeholder_assets.py (original art)
; or from tools/convert_stage.py (converted from the user's own NES ROM).
; ---------------------------------------------------------------------------

palette:        INCBIN "palette.bin"
bg_pgt_b0:      INCBIN "bg_pgt_b0.bin"
bg_ct_b0:       INCBIN "bg_ct_b0.bin"
bg_pgt_b1:      INCBIN "bg_pgt_b1.bin"
bg_ct_b1:       INCBIN "bg_ct_b1.bin"
bg_pgt_b2:      INCBIN "bg_pgt_b2.bin"
bg_ct_b2:       INCBIN "bg_ct_b2.bin"
hud_pgt:        INCBIN "hud_pgt.bin"
hud_ct:         INCBIN "hud_ct.bin"
player_spt:     INCBIN "player_spt.bin"         ; 32 bytes per 16x16 pattern
player_sct:     INCBIN "player_sct.bin"         ; 16 colour bytes per sprite
player_frames:  INCBIN "player_frames.bin"      ; count, then (dy, dx, pattern, colour)
        INCLUDE "player_frames.inc"             ; player_frame_table
obj_spt:        INCBIN "obj_spt.bin"            ; object patterns (resident)
obj_sct:        INCBIN "obj_sct.bin"
obj_frames:     INCBIN "obj_frames.bin"
        INCLUDE "obj_frames.inc"                ; obj_frame_table
candle_list:    INCBIN "candles.bin"            ; count, then (x lo, x hi, y, drop)
jump_table:     INCBIN "player_jump.bin"        ; JUMP_LEN signed dy, rising half
level_tiles:    INCBIN "level_tiles.bin"        ; PF_ROWS bytes per 8-px column
level_coll:     INCBIN "level_coll.bin"         ; MT_ROWS bytes per 16-px column
