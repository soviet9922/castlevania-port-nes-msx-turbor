; ---------------------------------------------------------------------------
; RAM overlays: block-specific enemy code, stored in a bank of its own
; (tools/areas_asm.py: OVL_BANK) and copied by load_area (src/area.asm) to
; OVL_BASE, right after the resident RAM code (src/ramcode.asm). Only one is
; in RAM at a time; resident code calls an overlay's routines only for the
; objects of the blocks that load it.
;   overlay 1 (A): blocks 2-4 (stages 4-12)
;   overlay 2 (B): blocks 5-7 (stages 13-18)
; ---------------------------------------------------------------------------
ovl_a_src:
        DISP OVL_BASE
ovl_a_start:
        INCLUDE "ovl_a.asm"
ovl_a_end:
        ENT
OVL_A_LEN       equ ovl_a_end - ovl_a_start
        ASSERT OVL_BASE + OVL_A_LEN <= RAMCODE_TOP

ovl_b_src:
        DISP OVL_BASE
ovl_b_start:
        INCLUDE "ovl_b.asm"
ovl_b_end:
        ENT
OVL_B_LEN       equ ovl_b_end - ovl_b_start
        ASSERT OVL_BASE + OVL_B_LEN <= RAMCODE_TOP

; the overlays by number (1, 2): source, length
ovl_table:
        dw ovl_a_src, OVL_A_LEN
        dw ovl_b_src, OVL_B_LEN
