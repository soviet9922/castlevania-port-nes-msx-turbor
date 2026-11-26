; Code that runs from RAM (see src/enemies2.asm), stored in Simon's bank and
; copied to RAMCODE by init (src/main.asm).
ramcode_src:
        DISP RAMCODE
ramcode_start:
        INCLUDE "enemies2.asm"
ramcode_end:
        ENT
RAMCODE_LEN     equ ramcode_end - ramcode_start
        ASSERT RAMCODE + RAMCODE_LEN <= RAMCODE_TOP
