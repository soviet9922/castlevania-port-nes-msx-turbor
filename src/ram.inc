; ---------------------------------------------------------------------------
; RAM variables (page 3). Laid out as an equ chain: name, then size.
; Keep RAM_END below the BIOS work area (0xF380).
; ---------------------------------------------------------------------------

RAM_BASE        equ 0xC000

frame_ready     equ RAM_BASE            ; 1  set by VBLANK interrupt
frame_count     equ frame_ready+1       ; 2  total VBLANKs (debug / tests)
line_irq_count  equ frame_count+2       ; 2  total line interrupts (debug / tests)
scroll_r26      equ line_irq_count+2    ; 1  playfield horizontal scroll, coarse
scroll_r27      equ scroll_r26+1        ; 1  playfield horizontal scroll, fine

cam_x           equ scroll_r27+1        ; 2  camera world x (px)
cam_new         equ cam_x+2             ; 2  scratch
new_col         equ cam_new+2           ; 2  scratch

col_pending     equ new_col+2           ; 1  1 = col_buf must be uploaded
col_slot        equ col_pending+1       ; 1  name table column (0..31)
col_buf         equ col_slot+1          ; PF_ROWS tile numbers

stick           equ col_buf+PF_ROWS     ; 1  direction 0..8
trig_prev       equ stick+1             ; 1
jump_pressed    equ trig_prev+1         ; 1  non-zero on the frame jump is pressed

px              equ jump_pressed+1      ; 2  player world x (left edge of 16x32 box)
py              equ px+2                ; 2  player y in playfield px (signed)
jump_idx        equ py+2                ; 1  position in the jump arc (0..2*JUMP_LEN)
crouching       equ jump_idx+1          ; 1
pyoff           equ crouching+1         ; 1  sprite y offset for the current pose
anim_step       equ pyoff+1             ; 1  walk cycle position 0..3
on_ground       equ anim_step+1         ; 1
walk_dx         equ on_ground+1         ; 1  -1/0/+1 this frame
air_dx          equ walk_dx+1           ; 1  horizontal speed locked at take-off
facing          equ air_dx+1            ; 1  0 = right, 1 = left
pframe          equ facing+1            ; 1  animation frame 0..3
anim_t          equ pframe+1            ; 1
new_x           equ anim_t+1            ; 2  scratch
probe_off       equ new_x+2             ; 1  scratch

sat_buf         equ probe_off+1         ; (PLAYER_SPRITES+1)*4

RAM_END         equ sat_buf+(PLAYER_SPRITES+1)*4
        ASSERT RAM_END < 0xF380
