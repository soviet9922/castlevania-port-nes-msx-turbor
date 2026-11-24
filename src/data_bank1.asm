; ---------------------------------------------------------------------------
; Bank 1 (mapped at 0x8000): graphics and level data.
; Currently the ORIGINAL placeholder assets from tools/gen_placeholder_assets.py.
; ---------------------------------------------------------------------------

palette:        INCBIN "palette.bin"
bg_pgt:         INCBIN "bg_pgt.bin"
bg_ct:          INCBIN "bg_ct.bin"
metatiles:      INCBIN "metatiles.bin"
mt_solid:       INCBIN "mt_solid.bin"
hud_pgt:        INCBIN "hud_pgt.bin"
hud_ct:         INCBIN "hud_ct.bin"
player_spt:     INCBIN "player_spt.bin"
level_map:      INCBIN "level1.bin"
