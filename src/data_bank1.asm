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
player_spt:     INCBIN "player_spt.bin"
jump_table:     INCBIN "player_jump.bin"        ; JUMP_LEN signed dy, rising half
level_tiles:    INCBIN "level_tiles.bin"        ; PF_ROWS bytes per 8-px column
level_coll:     INCBIN "level_coll.bin"         ; MT_ROWS bytes per 16-px column
