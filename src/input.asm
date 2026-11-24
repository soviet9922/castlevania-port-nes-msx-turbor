; ---------------------------------------------------------------------------
; Input: cursor keys or joystick 1; SPACE or joystick button A = jump;
;        M, X or joystick button B = whip.
; ---------------------------------------------------------------------------

read_input:
        xor a
        call GTSTCK                     ; cursor keys
        push af
        ld a,1
        call GTSTCK                     ; joystick 1
        pop bc                          ; B = keyboard direction
        or a
        jr nz,.have
        ld a,b
.have:
        ld (stick),a

        ld a,TRIG_SPACE
        call GTTRIG
        push af
        ld a,TRIG_JOY1_A
        call GTTRIG
        pop bc
        or b                            ; A = 0xFF if either is held
        ld b,a
        ld a,(trig_prev)
        cpl
        and b                           ; pressed this frame only
        ld (jump_pressed),a
        ld a,b
        ld (trig_prev),a

        ; whip: joystick 1 button B, or the M / X keys
        ld a,TRIG_JOY1_B
        call GTTRIG
        push af
        ld a,4                          ; matrix row 4, bit 2 = M
        call SNSMAT
        cpl
        and 0x04
        ld b,a
        pop af
        or b
        push af
        ld a,5                          ; matrix row 5, bit 5 = X
        call SNSMAT
        cpl
        and 0x20
        ld b,a
        pop af
        or b
        jr z,.whip_up
        ld a,1
.whip_up:
        ld b,a                          ; B = 1 while held
        ld a,(whip_prev)
        xor 1
        and b
        ld (whip_pressed),a             ; 1 on the frame it is pressed
        ld a,b
        ld (whip_prev),a
        ret

; A = stick direction -> A = -1 / 0 / +1 horizontal
stick_to_dx:
        or a
        ret z
        cp 2
        jr c,.none                      ; 1 = up
        cp 5
        jr c,.right                     ; 2,3,4
        cp 6
        jr c,.none                      ; 5 = down
        ld a,-1                         ; 6,7,8
        ret
.right:
        ld a,1
        ret
.none:
        xor a
        ret
