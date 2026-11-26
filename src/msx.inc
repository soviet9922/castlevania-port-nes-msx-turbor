; ---------------------------------------------------------------------------
; MSX system definitions (BIOS entry points, system variables, I/O ports)
; ---------------------------------------------------------------------------

; BIOS (main ROM, page 0)
CGTABL          equ 0x0004      ; word: address of the BIOS 8x8 font
ENASLT          equ 0x0024      ; select slot H (page) / A (slot id)
MSXVER          equ 0x002D      ; 0=MSX1 1=MSX2 2=MSX2+ 3=turbo R
GTSTCK          equ 0x00D5      ; A=port (0=cursor keys) -> A=direction 0..8
GTTRIG          equ 0x00D8      ; A=trigger id -> A=0xFF if pressed
RSLREG          equ 0x0138      ; read primary slot register
SNSMAT          equ 0x0141      ; A=keyboard matrix row -> A=bits (0 = pressed)
CHGCPU          equ 0x0180      ; turbo R only: A=0x80|mode (0 Z80, 1 R800 ROM, 2 R800 DRAM)

; System variables
RG0SAV          equ 0xF3DF      ; BIOS shadow of VDP R#0
RG1SAV          equ 0xF3E0      ; BIOS shadow of VDP R#1
RG8SAV          equ 0xFFE7      ; BIOS shadow of VDP R#8 (MSX2)
EXPTBL          equ 0xFCC1      ; slot expanded flags, 4 bytes
SLTTBL          equ 0xFCC5      ; secondary slot register shadows, 4 bytes
H_KEYI          equ 0xFD9A      ; hook: every interrupt (before VBLANK check)
H_TIMI          equ 0xFD9F      ; hook: VBLANK interrupt

; VDP ports (V9938 / V9958)
VDP_DATA        equ 0x98
VDP_CTRL        equ 0x99
VDP_PAL         equ 0x9A
VDP_IND         equ 0x9B

; ASCII16 MegaROM mapper bank select registers
ASCII16_PAGE1   equ 0x6000      ; selects the bank seen at 0x4000-0x7FFF
ASCII16_PAGE2   equ 0x77FF      ; selects the bank seen at 0x8000-0xBFFF (0x7000-0x77FF)
; Emulators and flash-cartridge loaders guess the mapper by scanning the ROM
; for LD (nnnn),A instructions. 0x7000 also counts for Konami SCC and ASCII8,
; while 0x77FF counts for ASCII16 only, so we always use 0x77FF.

; Keyboard matrix / GTTRIG ids
TRIG_SPACE      equ 0
TRIG_JOY1_A     equ 1
TRIG_JOY1_B     equ 3
CLIKSW          equ 0xF3DB              ; key click on/off (BIOS work area)
