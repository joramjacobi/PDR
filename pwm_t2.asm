; Pole Dance Revolution - Thread 2
;
; Thread 2 handles the PWM of the LEDs.  During thread 2, we have a significant
; limitation.  Namely, we must have the analog block enabled, which in turn
; enables the analog interrupts.  Unfortunately, since the analog interrupts
; are enabled, we are unable to have any other interrupt sources from thread 2.
;
; In the first round of design, the PDR code handled the pulse width modulation
; in thread 3 in order to use CTIME.  Thread 2 then handled the SPI
; transactions.  Unfortunately, since the conversion interrupts could not be
; masked, we were unable to distinguish between an SPI interrupt and a
; conversion interrupt.  The best solution seemed to be to switch the thread 2
; and 3 functions, and have thread 2 deal with the pulse width modulation.  By
; using interleaved mode, we are able to leave thread 2 awake at all times, and
; threads 1 and 3 then share the remaining 50% of the CPU time.  In order to
; time the PWM, thread 2 sits in idle loops.
;
; In ResetMode, the LED's will blink black and then white at approxiametly 2Hz
;
; In AddressColorMode, the LED's display the color equivalent to the current address.
; In RawData and AveragedData modes, the LED's display the colors stored in the
; thread2 Red, Green, Blue registers.  These registers are asynchronously updated by
; thread 3.  It is assumed any glitch won't be visible.
;
; Thread 2 maintains a counter, of PWM cycles.  It is used by ResetMode to determine
; wheather to display black or white.
;
; Each PWM cycle, we
; reinitialize our working register from this thread 2 data buffer.  Then, each
; 10 * 2^N instructions, we rotate the working registers and update the LEDs
; based on the state of the carry flag.  
;
; Using this method, we are able to acheive 10 bits of resolution on our PWMs.
; We have 10us of resolution on updating the LEDs, and our cycle repeats at a
; frequency of approximately 100Hz (actually 97.7Hz).
;
;

seg code
t2_start:

        assert [t1_ModeReg] == 0

t2_main:
        ; this entire loop needs to take 10,000 instructions in
        ; order to acheive the PWM cycle frequency we want (100Hz).
        ; (actually takes 10,235 - close enough?)

        ifclr thr bit 0                 ; 1
          reset                         ; 2

      ; Increment the loop counter
      ; don't use loop unless you want to sometimes skip the next instruction =)
      ;  (loop does a decrement then skip if zero)
        inc t2_Time_Data                ; 3


      ; Copy color based on current Mode
        mov     a, t1_ModeReg           ; 4 get current mode (high bits)
        and     a, #ModeMask            ; 5 Isolate the mode bits

        add     PC, A                   ; 6

t2_ModeJumpTable:
        jmp     t2_ResetMode            ; 00  7
        jmp     t2_AddressColorMode     ; 01  7     ; t2_AddressColor is at the very end
        jmp     t2_RawDataMode          ; 10  7
        jmp     t2_AverageDataMode      ; 11  7

t2_ResetMode:
      ; See if we are in the bottom or top half of the second
      ;  64/100 of a second is close enough to 1/2 second, so just
      ;  and with 64

        mov A, t2_Time_Data             ; 8
        and A, #$40                     ; 9
    
    ;??? Does 'and' set the zero bits - yes
        ifnz                            ; 10
         jmp    t2_ResetModeWhite       ; 11

t2_ResetModeBlack:
        clr t2_Red_Rotate               ; 12 
        clr t2_Green_Rotate             ; 13
        clr t2_Blue_Rotate              ; 14
    
        jmp Do_PWM_16                   ; 15

t2_ResetModeWhite:
        ; sorry, we have no mov reg, immediate instruction
        mov A, #$3FF                    ; 12
        mov t2_Red_Rotate, A            ; 13 
        mov t2_Green_Rotate, A          ; 14
        mov t2_Blue_Rotate, A           ; 15
    
        jmp Do_PWM_17                   ; 16


;;;t2_AddressColorMode: - This is located at the END of this code, just to keep thing fairly clean
    
t2_RawDataMode:
        ; initialize t2 regs from whatever's stored in RAM

        mov A, t2_Red_Data              ; 8
        mov t2_Red_Rotate, A            ; 9

        mov A, t2_Green_Data            ; 10
        mov t2_Green_Rotate, A          ; 11

        mov A, t2_Blue_Data             ; 12
        mov t2_Blue_Rotate, A           ; 13

        jmp Do_PWM_15                   ; 14

t2_AverageDataMode:
        ; initialize t2 regs from whatever's stored in RAM
      ; This is currently the same as t2_RawDataMode, but
      ; let us keep them separate

        mov A, t2_Red_Data              ; 8
        mov t2_Red_Rotate, A            ; 9

        mov A, t2_Green_Data            ; 10
        mov t2_Green_Rotate, A          ; 11

        mov A, t2_Blue_Data             ; 12
        mov t2_Blue_Rotate, A           ; 13

        jmp Do_PWM_15                   ; 14


; we do a whole lot of footwork to have the setup take the same number of instructions
; regardless of your path through this code (whether our counter has timed out, we have
; new data to process, et cetera).  I'm probably being anal, but oh well...
Do_PWM_15:      nop             ;15
Do_PWM_16:      nop             ;16
Do_PWM_17:      nop             ;17
Do_PWM_18:      nop             ;18
Do_PWM_19:      nop             ;19
Do_PWM_20:      nop             ;20
Do_PWM_21:      nop             ;21
Do_PWM_22:      nop             ;22
Do_PWM_23:      nop             ;23     ; 24 instructions overhead (including jump to t2_main)

Do_PWM_24:
; now to update and sleep:
        call t2_UpdateLEDs              ; 15 instructions
; cycle 1: 10 instructions (sorry, it's going to be 15)

        call t2_UpdateLEDs              ; 15 instructions
; cycle 2: 20 instructions
        nop
        nop
        nop
        nop
        nop                             ; +5 = 20 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 3: 40 instructions
        mov A, #2                       ; 1 instruction
        call t2_Wait_10A_and_4          ; 24 instructions
                                        ;    = 40 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 4: 80 instructions
        mov A, #6                       ; 1 instruction
        call t2_Wait_10A_and_4          ; 64 instructions
                                        ;    = 80 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 5: 160 instructions
        mov A, #14                      ; 1 instruction
        call t2_Wait_10A_and_4          ; 144 instructions
                                        ;    = 160 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 6: 320 instructions
        mov A, #30                      ; 1 instruction
        call t2_Wait_10A_and_4          ; 304 instructions
                                        ;    = 320 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 7: 640 instructions
        mov A, #62                      ; 1 instruction
        call t2_Wait_10A_and_4          ; 624 instructions
                                        ;    = 640 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 8: 1280 instructions
        mov A, #126                     ; 1 instruction
        call t2_Wait_10A_and_4          ; 1264 instructions
                                        ;    = 1280 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 9: 2560 instructions
        mov A, #254                     ; 1 instruction
        call t2_Wait_10A_and_4          ; 2544 instructions
                                        ;    = 2560 instructions


        call t2_UpdateLEDs              ; 15 instructions
; cycle 10: 5120 instructions
                                        ; 24 instructions (overhead)
        call t2_InitializePorts         ; 15 instructions

        mov A, #wide(506)               ; 2 instructions
        call t2_Wait_10A_and_4          ; 5064 instructions

                                        ;   = 5120 instructions

        jmp t2_main

        ; should never get here!
        reset


        seg subr

t2_UpdateLEDs:
; We are relying on all LEDs being either in the low byte or the 
; high byte.
        mov A, #not(bitmask_PWMs)       ; assume no PWMs on

        rrc t2_Red_Rotate               ; turn on red?
        ifc
          bset  A bit PWM_Red

        rrc t2_Green_Rotate             ; turn on green?
        ifc
          bset  A bit PWM_Green

        rrc t2_Blue_Rotate              ; turn on blue?
        ifc
          bset  A bit PWM_Blue

        ; We can't read-modify-write POUT because thread 3 might
        ; be changing the state of POUT bit SSB.
        and POUT, A                     ; turn off any LED that should be off
        and A, #bitmask_PWMs
        or  POUT, A                     ; turn on any LEDs that should be on

        ret
        

t2_Wait_10A_and_4:                      ;       1 for the call
        nop                             ; 1
        nop                             ; 2
        nop                             ; 3
        nop                             ; 4
        nop                             ; 5
        nop                             ; 6
        nop                             ; 7
        nop                             ; 8
        loop A                          ; 9
          jmp   t2_Wait_10A_and_4       ; 10    10 * A + 1
        nop                             ;       10 * A + 2
        nop                             ;       10 * A + 3
        ret                             ;       10 * A + 4

t2_initializePorts:
; We're doing read-modify-writes on port registers while in TALT mode.
; Why is this safe?  Thread 2 only changes POUT of the PWMs, which are
; all protected from thread 3 by "preservePins_POUT".
;
; By the time thread 2 is allowed to call this routine, thread 3 is
; only changing PAUX (which isn't initialized here) and POUT bit SSB, 
; which is protected by preserve pins.

; Thread 3 regularly takes care of PAUX, and thread 2 isn't allowed to touch it.
;       mov A, #basePAUXmask
;       mov PAUX, A

        mov A, #basePDIRmask
        xor A, PDIR
        and A, #NOT(preservePins_PDIR)
        xor PDIR, A

        mov A, #basePCTLmask
        mov PCTL, A

        mov A, #basePIEmask
        mov PIE, A

        mov A, #basePOUTmask
        xor A, POUT
        and A, #NOT(preservePins_POUT)
        xor POUT, A

        ret

	seg code
; t2_AddressColorMode
; Set the color based on the address stored in MyAddress
; At the end of the routine, cycles are padded to 
; Routine jumps to Do_PWM when finished
; Starts at +8 instructions
t2_AddressColorMode:
        ; based on the value now in MyAddress, set the appropriate output color
        mov     A, #val wide StoreAddressWord       ;1
                                                    ;2
        lookup  A, A                                ;3
        and     A, #15                              ;4

        add     PC, A                               ;5

ColorJumpTable:
        jmp     Color0
        jmp     Color1
        jmp     Color2
        jmp     Color3
        jmp     Color4
        jmp     Color5
        jmp     Color6
        jmp     Color7
        jmp     Color8
        jmp     Color9
        jmp     Color10
        jmp     Color11
        jmp     Color12
        jmp     Color13
        jmp     Color14
        jmp     Color15

Color0:
Pink::          ; Address 0
        mov     A, #narrow Color_Pink_Amount_Red    ;6
        mov     t2_Red_Rotate, A                    ;7
        mov     A, #narrow Color_Pink_Amount_Green  ;8
        mov     t2_Green_Rotate, A                  ;9
        mov     A, #wide Color_Pink_Amount_Blue     ;10 & 11 (WIDE)
        mov     t2_Blue_Rotate, A                   ;12
;        nop		
        jmp     ColorSet                            ;13

Color1:
Red::           ; Address 1
        mov     A, #narrow Color_Red_Amount_Red     ;6
        mov     t2_Red_Rotate, A                    ;7
        mov     A, #narrow Color_Red_Amount_Green   ;8
        mov     t2_Green_Rotate, A                  ;9
        mov     A, #narrow Color_Red_Amount_Blue    ;10
        mov     t2_Blue_Rotate, A                   ;11
        nop                                         ;12

        jmp     ColorSet                            ;13

Color2:
Orange::        ; Address 2
        mov     A, #narrow Color_Orange_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #wide Color_Orange_Amount_Green  ; WIDE
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Orange_Amount_Blue
        mov     t2_Blue_Rotate, A
;        nop
        jmp     ColorSet

Color3:
Yellow::        ; Address 3
        mov     A, #narrow Color_Yellow_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Yellow_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Yellow_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color4:
Green::         ; Address 4
        mov     A, #narrow Color_Green_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Green_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Green_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color5:
Aqua::          ; Address 5
        mov     A, #narrow Color_Aqua_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Aqua_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Aqua_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color6:
Cyan::          ; Address 6
        mov     A, #narrow Color_Cyan_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Cyan_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Cyan_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color7:
Blue::          ; Address 7
        mov     A, #narrow Color_Blue_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Blue_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Blue_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color8:
BlueViolet::    ; Address 8
        mov     A, #narrow Color_BlueViolet_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_BlueViolet_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_BlueViolet_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color9:
Violet::        ; Address 9
        mov     A, #wide Color_Violet_Amount_Red       ; WIDE
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Violet_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Violet_Amount_Blue
        mov     t2_Blue_Rotate, A
;        nop
        jmp     ColorSet

Color10:
Magenta::       ; Address 10
        mov     A, #narrow Color_Magenta_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_Magenta_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_Magenta_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color11:
White_11::      ; Address 11 (not valid)
        mov     A, #narrow Color_White_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_White_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_White_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color12:
White_12::      ; Address 12 (not valid)
        mov     A, #narrow Color_White_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_White_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_White_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color13:
White_13::      ; Address 13 (not valid)
        mov     A, #narrow Color_White_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_White_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_White_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color14:
White_14::      ; Address 14 (not valid)
        mov     A, #narrow Color_White_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_White_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_White_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop
        jmp     ColorSet

Color15:
White_15::      ; Address 15 (not valid)
        mov     A, #narrow Color_White_Amount_Red
        mov     t2_Red_Rotate, A
        mov     A, #narrow Color_White_Amount_Green
        mov     t2_Green_Rotate, A
        mov     A, #narrow Color_White_Amount_Blue
        mov     t2_Blue_Rotate, A
        nop                 ; even those these two instructions don't seem needed,
        jmp     ColorSet    ; I'm leaving them in for timing purposes.


ColorSet:
      jmp       Do_PWM_22 ;14 (+8 initial so 22nd instruction)
    
        seg code