; Pole Dance Revolution - Thread 1
;
; Thread 1 code for PWM
; For the most part, thread 1 monitors the state of CHN to determine when
; new ADC data is available.  This data is either averaged or put into the
; output buffer.

org $0000
resetVector:
        jmp     t1_begin



mfgOscVectorAddr:
oscVector:

        assert  IS_T1005
        word    $FFFF   ; we're assuming unused RAM is '1'



t1_begin:
        nop     ; not needed, but does no harm
        nop

   if hasPackrat
        mov     A, #firmware_build_ID AND $FFFF
        mov     PackratIDLow, A

        mov     A, #(firmware_build_ID >> 16) AND $FFFF
        mov     PackratIDHigh, A

   endif hasPackrat

; Clear the RAM
        mov     X, #val reg $0B
        mov     A, #last_ram - reg $0B
clearLoop:
        clr     @X
        inc     X
        loop    a
            jmp clearLoop

; We only initialize the analog block once to our best guess values.
; Final servoing occurs via the host.
; Initializes OSC
        call    initAnalog


        ; Initialize Address Registers

        mov     a, #val wide StoreAddressWord
        lookup  a, a
        mov     t1_SaveAddress, a
        shl4    a
        shl4    a
        shl4    a
        mov     t1_AddrTimes1000, a


        ; In our implementation, thread 2 will run at all times, leaving thread 1 and 3
        ; 50% of the CPU time to do all necessary command receiving and processing.
        ; At least we don't care about power consumption.
        bset    TALT    ; Interleaved Mode - 
        bset    TPRI    ; threads 2 and 3 not eligible to run at same time


        mov     A, #$A000+val wide t2_start     ; start Thread 2 - lights will blink
        movn    TPC2, A
        bset    trdy2
        bset    ten2

        mov     A, #$A000+val wide t3_start     ; start Thread 3
        movn    TPC3, A
        bset    trdy3
        bset    ten3

        clrwdt  ; we may be here a while, and don't want to reset
    
        ; Initialize boxcar filter and counter
        clr t1_curSum
        mov A, #ADC_Sum_Count_00
        mov t1_CurCount, A





t1_ResetMode:
; Continually update SensorData with Mode_Reset_Data until we are no longer
; in ResetMode.  Occasionally, the data will look like raw ADC data - ignore these.
; It will look like Mode_Reset_Data soon enough.

; thread sanity checking
        skpset thr bit 0
         ifset thr bit 1
          reset

        clrwdt

        mov  a, #Mode_Reset_Data
        mov  SensorData, a

        tst t1_ModeReg
        ifz
           jmp t1_ResetMode
; We are NOT reset!!!
        jmp t1_main


t1_AddressColorMode:
; Continually update SensorData with Mode_AddressColor_Data until we are no longer
; in AddressColorMode.  Occasionally, the data will look like raw ADC data - ignore these.
; It will look like Mode_AddressColorMode_Data soon enough.

; thread sanity checking
        skpset thr bit 0
         ifset thr bit 1
          reset

        clrwdt

        mov  a, #Mode_AddressColor_Data
        mov  SensorData, a

	  skpclr t1_ModeReg  bit 0
	  ifset  t1_ModeReg  bit 1
           jmp t1_main

        jmp t1_AddressColorMode


t1_main:
; thread sanity checking
        skpset thr bit 0
         ifset thr bit 1
          reset

        clrwdt ; 10ms timeout - we should be fine


      ; Wait for CHN  == 0
        bankNormal XHCTL
        bset ind NCHN bit 1         ; Force NCHN to be at least NCHN=10

waitforCHN1:
        skpclr ind CHN bit 0
         ifset ind CHN bit 1
          jmp waitforCHN1

        ; We are in CHN1.  Get the value of XADC1 (which is from XCH0 in CHN1)
        mov a, XCH0
        mov t1_CurADC, a

        ; Retest CHN just to make sure we are still in CHN1
        ; This is the thread safe method Dave Gillespie recomments
        ; in the T1005 specification.  Probably overkill, but what the hell.

        skpclr ind CHN bit 0
         ifset ind CHN bit 1
          jmp waitforCHN1            ; We are not still CHN1, assume we missed it.

received_CHN1::

        ;Add just read value to the current sum of the average
        ; fortunately, our just read value is still in A.
        add  t1_CurSum, a

        loop t1_CurCount      ; Check to see if we've accumulate 16 values
           jmp eval_Mode	; Do not have 16 values yet.

generate_Avg_ADC:
      ; Average counter just counted down to 0
        
      ; Increment the current average counter (bits 13-10 of t1_CurAvg)
      ; It doesn't matter if the average count overflows, since the high
      ; two bits for averaged data are forced high and low, respectively

      mov a, #ADC_AvgCount_Inc
      add t1_CurAvg, a

      ; Clear the ADC bits (low 10) as well as the mode bits (14 and 15)
      ; of the average to report (bits 13-10 are the average count)
      mov a, #(not(ADCMask) & not(ModeBits_Mask))
      and t1_CurAvg, a

      ; Update the average store with the average
      shr4   a, t1_CurSum   ; Divide the current sum by 16

      ; Test AverageMode bits to see if we need to divide by more
	ifset  t1_ModeReg bit 2
         rrc  a

      ; Test the high bit to see if we need to divide by more
      ifset  t1_ModeReg bit 3
         rrc  a

      ;Definitely mask off the low 10 bits
      and  a,  #ADCMask

      or  t1_CurAvg, a  ; Update curAvg with the result of the average

      ; Reset average sum
      clr  t1_CurSum

      ;Reset the average counter
      ;I'm SURE there is a more elegant way of doing this particular bit -

      mov  a, t1_ModeReg     ; Move AverageCount into the two low bts
      rrc  a
      rrc  a
      and  a, #3
	add  a, #val narrow (average_count_table - average_count_lookup) - 1

average_count_lookup:
      lookup a,pc,a

      mov  t1_AvgCount_Reg, a		; Save the AvgCount value for diagnostic purposes
      mov  t1_CurCount, a

	; If we are in Mode_AverageADC, update the data value to be written out
	; Only do this right after a successful average is calculated

      skpclr t1_ModeReg  bit 0
	ifclr  t1_ModeReg  bit 1
           jmp eval_Mode

	; We are in Mode_AverageADC and we've just calculate a new average
	; Update SensorData with the new average and make sure the AverageData bit is set
	; and the Staledata bit is clear

       mov  a, t1_CurAvg
       bset a bit 15              ; Bit 15 high indicates AverageData
       bclr a bit 14              ; Bit 14 - low indicates fresh data
                                   ;        - high indicates stale data
       mov  SensorData, a      ; Occasionally, bit 14 will be set while the data is still fresh
       jmp  eval_Mode

average_count_table:
	 word   ADC_Sum_Count_00
	 word   ADC_Sum_Count_01
	 word   ADC_Sum_Count_10
	 word   ADC_Sum_Count_11


      ; Decide which mode we are in and what to do about it
eval_Mode:
      mov   a, t1_ModeReg
      and   a, #ModeMask

      add   pc, a

eval_Mode_JumpTable:
        jmp  t1_ResetMode
;        jmp  eval_Mode_AddressColor
        jmp  t1_AddressColorMode
        jmp  eval_Mode_RawData
        jmp  eval_Mode_AverageData

;eval_Mode_Reset:
;        jmp  t1_ResetMode

;eval_Mode_AddressColor:
;        mov  a, #Mode_AddressColor_Data
;        mov  SensorData, a
;
;        jmp Housekeeping


eval_Mode_RawData:
	  mov a, t1_CurCount		; Return decrementing counter (for ease - let the Pentium deal with it)
        shl4 a                      ; shift left by 10 bits, making sure the low bits
        shl4 a                      ; remain clear.
        add  a, a
        add  a, a

        or   a, t1_CurADC
	  bset a bit 14
        bclr a bit 15
;        or   a, #ModeBits_RawData    ; Assumes high bits are clear

        mov  SensorData, a
 
        jmp  Housekeeping


eval_Mode_AverageData:
        ; Only update Sensor data with the average right after a new average is calculate
	  ; This is handled in the average calculation
	  ; So - nothing happens here
;        mov  a, t1_CurAvg
;        bset a bit 15              ; Bit 15 high indicates AverageData
;        bclr a bit 14              ; Bit 14 - low indicates fresh data
                                   ;        - high indicates stale data
;        mov  SensorData, a      ; Occasionally, bit 14 will be set while the data is still fresh


Housekeeping:
        ; Renew whatever registers that it makes sense to renew here.

        ; OSC should be updated here probably
        mov     a, #val mfgOscVectorAddr
        lookup  A, A
        ifclr   A bit 15
          jmp   OscVectorStillInitialized
        mov     A, #baseOCTLmask
OscVectorStillInitialized:
        mov     OCTL, A

        mov     a, #val wide StoreAddressWord
        lookup  a, a
        mov     t1_SaveAddress, a
        shl4    a
        shl4    a
        shl4    a
        mov     t1_AddrTimes1000, a


WaitforCHNx:
        ; Wait for a CHN, any CHN, that is NOT 1
        ; It's ok if we miss the boundary (a'la Dave Gillespie's
        ; algorithm in the t1005 specification.  We are only looking
        ; to make sure we are still not in CHN0 at some point in time

        skpclr ind CHN bit 0
         ifset ind CHN bit 1
          jmp  CHNnotOne
        jmp waitforCHNx

CHNnotOne:


        ; CHN is NOT One
        jmp     t1_main


        ; should never get here!
        reset



        seg subr


initAnalog:

        mov     a, #val mfgOscVectorAddr
        lookup  A, A
        ifclr   A bit 15
          jmp   OscVectorInitialized
        mov     A, #baseOCTLmask
OscVectorInitialized:
        mov     OCTL, A

        mov     A, #psel_ground + bitmask pstr
        mov     TCTL, A

        mov     A, #baseXHCTLmask
        mov     XHCTL, A

        mov     A, #baseXLCTLmask
        mov     XLCTL, A

        mov     A, #baseYHCTLmask
        mov     YHCTL, A

        mov     A, #baseYLCTLmask
        mov     YLCTL, A

        ret

        seg code        