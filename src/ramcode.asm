; Code that runs from RAM (see src/enemies2.asm), stored in Simon's bank and
; copied to RAMCODE by init (src/main.asm).
ramcode_src:
        DISP RAMCODE
ramcode_start:
        INCLUDE "enemies2.asm"
        INCLUDE "player2.asm"
        INCLUDE "platforms.asm"
        INCLUDE "ctiles2.asm"
        INCLUDE "area_tab.inc"          ; (generated: the areas' banks)
        IF DEBUG_MENU
        INCLUDE "debugmenu.asm"
        ENDIF
ramcode_end:
        ENT
OVL_BASE        equ ramcode_end             ; the RAM overlays (src/overlays.asm)
RAMCODE_LEN     equ ramcode_end - ramcode_start
        ASSERT RAMCODE + RAMCODE_LEN <= RAMCODE_TOP
