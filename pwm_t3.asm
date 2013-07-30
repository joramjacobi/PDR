; Pole Dance Revolution 2006 - Thread 3
;
; Thread 3 Overview
;
; Thread 3 handles all incoming SPI transactions from the host.
;
; Unlike in 2005, the thread is immediately awake in ResetMode.  The address is 
; hard coded to avoid the reset problems we had in 2005.
; 
; After we receive each word over the SPI lines, check the address that the
; command is sent to, comparing it to our own.  If the address doesn't match, 
; we're done, we clear PAUX so we transmit no data on the next transaction, and 
; then we wait for the next transaction.
;
; As soon as we verify the received data is addressed to us, we set PAUX bit 11
; to drive data next round.  We next determine which command we've received.
;
; Commands are executed by looking up the high 4 bits in a jump table.  Red,
; Green, and Blue PWM commands each occupy four positions in the table, since
; only the two high bits determine the PWM command.
;
; Red_PWM and Green_PWM command mask the data and copy it to temporary
; variables. Blue_PWM commands mask the data and then copy the Red and Green
; and Blue data to the active registers in thread 2.  This can cause a glitch,
; but is assumed to not be visible for the worst case 1/100th of a second the
; system needs to catch up.
; 
; Read_Register command immediately overwrites SPITX with the contents of the 
; specified register.
;
; Write_Register_Address and Write_Register_Low command copy the data to
; temporary variables.  Upon receipts of a Write_Register_High command, the
; received data, combined with the Write_Register_Low data, is written the the
; specified address.
;
; All commands (except Read_Register) then update SPITX with the current
; contents of SensorData, set the Stale bit of SensorData, and go back to the
; beginning.  For ResetMode, the Stale bit will occasionally set (and look like
; RawData).  However, ResetMode updates  SensorData so often that this should
; be fairly rare, so we may safely ignore these (i.e. not treat them as
; ResetMode events). However, if ResetMode is detected, these should not be
; taken as evidence of not being in ResetMode.
;
; In AddressColor and RawADC modes, the StaleBit is not visible.  It is up to
; the program to look at the ADC count to determine if data is stale.
;
; In AverageADC mode, the stale bit will OCCASIONALLY be set for non-stale
; data.  This is not catastrophic.  You will merely miss this data. 
; 
;
;
; During an SPI transaction, we require the following minimum times from
; the host:
;
; Packet type   Total cycle time        Time between end of packet and start of next
;                                       (the amount of time it takes data to become valid)
; Not for us      14us                    8us
; Read Reg        23us                    16us
; Write Reg Addr  24us                    17us
; Write Reg Low   24us                    17us
; Write Reg High  28us                    21us
; PWM red data    25us                    18us
; PWM green data  25us                    18us
; PWM blue data   29us                    22us
;
; The SSB low time does not contribute to the minimum cycle time.

t3_start:
        ; initialize this to a harmless value while testing.
        ; this prevents indexed writes to sanity check-ed registers, as
        ; well as accidental writes to registers we need.
        mov     A, #val t3_WriteRegisterAddress;
        mov     t3_WriteRegisterAddress, A
      
        call    t3_InitializePorts


; Current data is not addressed to us, so disable data out for next
; SPI transaction
t3_main_DoNotWrite:
        clr     A
        movn    PAUX, A         ; default to don't drive data next round
                                ; keep in mind, PAUX is not direct, and the rest of
                                ; PAUX ought to be clear anyway.
                        ; We DO have X available to us now.  Better to use it?
                        ; it wouldn't save us anything.

t3_main:
        ; thread sanity checking
        ifclr thr bit 1
          reset

        bset    POUT bit SSB    ; interrupt on IO6 low
        clr     ctime
        bclr    POUT bit SSB    ; interrupt on IO6 high (transaction complete)
        clr     ctime           ; New data is available in SPIRX


        ; we now have data
        mov     A, SPIRX
        mov     t3_CurrentData, A

        ;Check the address on the data to see if it's for us

        xor     A, t1_AddrTimes1000     ; check if it's for us
        and     A, #$F000
        ifnz                            ; data not for us - 
          jmp   t3_main_DoNotWrite      ; do nothing, but make sure we do not output data the next SPI transaction

DataForUs:
        ; we have data, and it's for us
        mov     A, #bitmask SDOUT
        mov     PAUX, A         ; drive data next round


        ; ...and now check to see what is was
; A PWM Sequence has the form:
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 0 | 0 |              RED PWM DATA             |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 0 | 1 |            GREEN PWM DATA             |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 1 | 0 |             BLUE PWM DATA             |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;
; The read register command has the following form:
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 1 | 1 | 0 | 0 |            REGISTER           |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

; The write register command has the following form:
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 1 | 1 | 0 | 1 |            REGISTER           |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 1 | 1 | 1 | 0 |           LOW 8 BITS          |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
;    |    ADDRESS    | 1 | 1 | 1 | 1 |          HIGH 8 BITS          |
;    |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|


        mov     A, high t3_CurrentData  ; get our data
        and     A, #$0F                 ; isolate the command

        add     PC, A

CommandJumpTable:

        jmp     t3_RedPWM               ; 0000
        jmp     t3_RedPWM               ; 0001
        jmp     t3_RedPWM               ; 0010
        jmp     t3_RedPWM               ; 0011
        jmp     t3_GreenPWM             ; 0100
        jmp     t3_GreenPWM             ; 0101
        jmp     t3_GreenPWM             ; 0110
        jmp     t3_GreenPWM             ; 0111
        jmp     t3_BluePWM              ; 1000
        jmp     t3_BluePWM              ; 1001
        jmp     t3_BluePWM              ; 1010
        jmp     t3_BluePWM              ; 1011
        jmp     t3_ReadRegister         ; 1100
        jmp     t3_WriteRegister        ; 1101
        jmp     t3_WriteDataLow         ; 1110
        jmp     t3_WriteDataHigh        ; 1111



t3_RedPWM:
        mov     A, t3_CurrentData             ; Store the received red value
        and     A, #$03FF
        mov     t3_Red_Data_Store, A

        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main

t3_GreenPWM:
        mov     A, t3_CurrentData             ; Store the received green value
        and     A, #$03FF
        mov     t3_Green_Data_Store, A

        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main

t3_BluePWM:
        ;Blue is received.  Copy the data directly to the Red, Green, Blue PWM
        ;registers. Assume any glitch that occurs is insignificant
        ;If we really want, we can have thread 2 copy the data, but that seems
        ;unnecessary
        mov     A, t3_CurrentData
        and     A, #$03FF
        mov     t2_Blue_Data, A
      
        mov     A, t3_Red_Data_Store
        mov     t2_Red_Data, A

        mov     A, t3_Green_Data_Store
        mov     t2_Green_Data, A

        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main

t3_ReadRegister:
        mov     A, t3_CurrentData
        mov     STATX, A            ; move register address into X
        mov     A, @X               ; read from register
        mov     SPITX, A            ; write register in next SPI transaction

        jmp     t3_main


t3_WriteRegister:
        ; store address
        mov     A, t3_CurrentData
        mov     t3_WriteRegisterAddress, A

        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main

t3_WriteDataLow:
        ; store low data
        mov     A, t3_CurrentData
        mov     low t3_WriteRegisterData, A

        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main

t3_WriteDataHigh:
        ; store high data and write to the specified register
      ; Low data and address are stored by earlier calls

      ; Store high data (and combine with low data)
        mov     A, t3_CurrentData
        mov     high t3_WriteRegisterData, A

        mov     A, t3_WriteRegisterAddress
        mov     STATX, A        ; move register address into X

        mov     A, t3_WriteRegisterData
        mov     @X, A           ; write to register

        ; Copy sensor data to the SPI transmit register
        ; these four instructions are repeated, but time is more important than ROM.
        mov     A, SensorData              
        bset    SensorData bit StaleDataBit   ; Make the current data stale as soon as possible
                                              ; There WILL be times when SensorData is updated
                                              ; just before the bit is set.
        mov     SPITX, A
    
        jmp     t3_main


        reset


        seg subr
        
t3_initializePorts:
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
