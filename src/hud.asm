; ---------------------------------------------------------------------------
; HUD: two fixed tile rows at the top of the screen.
; Column 0 is hidden by the V9958 left-border mask, so text starts at col 1.
; The NES shows the same information on three lines; it is compacted here
; so the full 176-pixel NES playfield fits below it.
; ---------------------------------------------------------------------------

hud_draw:
        ld hl,hud_text
        ld de,VRAM_PNT
        ld bc,HUD_ROWS*32
        jp vram_copy

hud_text:
        ;    0         1         2         3
        ;    01234567890123456789012345678901
        db  " SCORE-000000 TIME 0300 STAGE01 "
.row1:
        db  " PL"
        ds  8, HUDT_BAR_PLAYER
        db  " EN"
        ds  8, HUDT_BAR_ENEMY
        db  " ", HUDT_HEART, "-05 P-3 "
.end:
        ASSERT .row1 - hud_text == 32
        ASSERT .end - hud_text == HUD_ROWS*32
