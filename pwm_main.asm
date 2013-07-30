; PWM code for PDR
; written by Jora
; Modified by Kirk Hargreaves - 13 May 2006 to conform the
; 2006 PDR Pole Communications Protocol Document

processor t1005
include "regs.asm"
include "macros.asm"


;*************************************************************
; OPTIONS

; The address is now hardcoded to make resets more graceful.

;hasPackrat      equ true
hasPackrat      equ false

  if hasPackrat
firmware_build_ID       shell   "packrat --allocate"    ; get an identification number from the archiver
                        keepsym firmware_build_ID       ; make sure we keep it around

; This command will run after the assembler completes, assuming there are no prior errors.
                        shell   "packrat --open " ++ firmware_build_ID ++ \
                                " --hex " ++ _ASM_HEXNAME ++ \
                                " --file " ++ _ASM_LSTNAME,pass:post
  endif hasPackrat

AddressStoreLocation    equ $BF0


; define PWM IOs
PWM_Red_pin   equ 1
PWM_Green_pin equ 2
PWM_Blue_pin  equ 3


; Pole Dance Revolution Startup
;
; At powerup, initialize CCTL, OCTL, ...
; Addresses are now hard wired.
;

;Aux0 and Aux1 used to be know as SetAddressIn and SetAddressOut
;For now, set them to be inputs with their pull-up resistors 
;enabled
Aux0_pin        equ 0
Aux1_pin        equ 12

; estimates to get some sort of sensing data out (though we will
; be able to servo through software control)
bestGuessXRefHi         equ $30
bestGuessXRefLo         equ $10
SetBigRef               equ 1


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Our initial colors
Color_Pink_Amount_Red           equ $3FF
Color_Pink_Amount_Green         equ $080
Color_Pink_Amount_Blue          equ $180

Color_Red_Amount_Red            equ $3FF
Color_Red_Amount_Green          equ $000
Color_Red_Amount_Blue           equ $000

Color_Orange_Amount_Red         equ $3FF
Color_Orange_Amount_Green       equ $180
Color_Orange_Amount_Blue        equ $000

Color_Yellow_Amount_Red         equ $3FF
Color_Yellow_Amount_Green       equ $3FF
Color_Yellow_Amount_Blue        equ $000

Color_Green_Amount_Red          equ $000
Color_Green_Amount_Green        equ $3FF
Color_Green_Amount_Blue         equ $000

Color_Aqua_Amount_Red           equ $080
Color_Aqua_Amount_Green         equ $3FF
Color_Aqua_Amount_Blue          equ $200

Color_Cyan_Amount_Red           equ $000
Color_Cyan_Amount_Green         equ $3FF
Color_Cyan_Amount_Blue          equ $3FF

Color_Blue_Amount_Red           equ $000
Color_Blue_Amount_Green         equ $000
Color_Blue_Amount_Blue          equ $3FF

Color_BlueViolet_Amount_Red     equ $080
Color_BlueViolet_Amount_Green   equ $000
Color_BlueViolet_Amount_Blue    equ $3FF

Color_Violet_Amount_Red         equ $180
Color_Violet_Amount_Green       equ $000
Color_Violet_Amount_Blue        equ $3FF

Color_Magenta_Amount_Red        equ $3FF
Color_Magenta_Amount_Green      equ $000
Color_Magenta_Amount_Blue       equ $300

Color_White_Amount_Red          equ $3FF
Color_White_Amount_Green        equ $3FF
Color_White_Amount_Blue         equ $3FF





;*************************************************************
; VARIABLES


PackratIDLow            alloc reg $1E
PackratIDHigh           alloc reg $1F


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Thread 1 Variables

; thread 3 collects data from the host and immediately changes
; colors and writes to registers.  Upstream data is supplied 
; by thread 1.  Thread 2 controls all PWM functions


t1_ModeReg      alloc reg $10   ; our current mode, written to via write reg
t1_CurADC       alloc reg $11   ; Last read ADC value from channel X0
t1_CurSum       alloc reg $12   ; Sum of last N ADC values
t1_CurCount     alloc reg $13   ; Decrementing counter indicating # sums added to t1_CurSum
t1_CurAvg       alloc reg $14   ; Last average of ADC's actually calculated
                                ; Bits 13-10 keep a count of the current average, which is reported
                                ; by the firmware
t1_AvgCount_Reg alloc reg $15   ; Allows us to check the current average count (diagnostic purposes only)

SensorData      alloc reg $16   ; This is the register that thread 3 reports when it's written to

t1_SaveAddress          alloc reg $17   ; our address is stored here so we can read it using read reg
t1_AddrTimes1000        alloc reg $18   ; our address * $1000 (for thread 3's convenience)

ModeMask                equ $0003
Mode_Reset              equ $0000
Mode_AddressColor       equ $0001
Mode_RawData            equ $0002
Mode_AverageData        equ $0003

Mode_AvgCount_Mask	equ $000C
Mode_AvgCount_Reg		equ t1_ModeReg BITS 3:2


ADCMask                equ $03FF
ADC_AvgCount_Mask       equ $3C00
ADC_AvgCount_Inc        equ $0400

ADC_Sum_Count_00        equ 16
ADC_Sum_Count_01        equ 32
ADC_Sum_Count_10        equ 32
ADC_Sum_Count_11        equ 64


Mode_Reset_Data         equ $35A5
Mode_AddressColor_Data  equ $2A3C		


ModeBits_Mask           equ $C000
ModeBits_Reset          equ $0000
;ModeBits_AddressColor   equ $4000
ModeBits_RawData        equ $4000
ModeBits_AverageData    equ $8000

StaleDataBit            equ 14            ;Bit is set when data is stale
                                          ; Really only applies to AverageData
                                          ;ResetMode returns will occasionally look
                                          ; like RawData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Thread 2 Variables

; This is where thread 3 writes the current color setting to.
; Thread 2 displays these colors 
; time = used to blink on/off in reset mode
t2_Time_Data            alloc reg $20   ; used to keep track of time as we blink in reset mode
t2_Red_Data             alloc reg $21   ; write to these registers to change the color
t2_Green_Data           alloc reg $22
t2_Blue_Data            alloc reg $23

; to process the data, thread 2 cycles through its
; PWM loop, taking the lowest bit of data first
t2_Red_Rotate           alloc reg $24   ; thread 2's working registers
t2_Green_Rotate         alloc reg $25
t2_Blue_Rotate          alloc reg $26

t2_Jmp_Store		alloc reg $27

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Thread 3 Variables

; the data just received over the SPI port
t3_CurrentData          alloc reg $30

; the address to write to
t3_WriteRegisterAddress alloc reg $31
; the data to write to the address
t3_WriteRegisterData    alloc reg $32

; these registers store the red and green data until we have received the
; blue data, at which point they get copied over to the t2_red_data and
; t2_green_data registers.
t3_Red_Data_Store       alloc reg $33
t3_Green_Data_Store     alloc reg $34


;*************************************************************
; BITMASKS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; I/O Data
Aux0 equ PIN bit Aux0_pin
Aux1 equ PIN bit Aux1_pin

PWM_Red   equ POUT bit PWM_Red_pin
PWM_Green equ POUT bit PWM_Green_pin
PWM_Blue  equ POUT bit PWM_Blue_pin

bitmask_PWMs set 0
bitmask_PWMs set bitmask_PWMs | bitmask PWM_Red
bitmask_PWMs set bitmask_PWMs | bitmask PWM_Green
bitmask_PWMs set bitmask_PWMs | bitmask PWM_Blue

SSB   equ PIN bit 6
SDIN  equ PIN bit 7
SCLK  equ PIN bit 10
SDOUT equ POUT bit 11
bitmask_SPI_in  set (bitmask SSB) | (bitmask SDIN) | (bitmask SCLK)
bitmask_SPI_out set (bitmask SDOUT)
bitmask_SPI     set bitmask_SPI_in | bitmask_SPI_out

bitmask_unusedIOs  set $FFFF
bitmask_unusedIOs  set bitmask_unusedIOs & not(bitmask_SPI)
bitmask_unusedIOs  set bitmask_unusedIOs & not(bitmask_PWMs)
bitmask_unusedIOs  set bitmask_unusedIOs & not(bitmask Aux0)
bitmask_unusedIOs  set bitmask_unusedIOs & not(bitmask Aux1)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Port Masks
basePAUXmask    set 0

basePDIRmask    set 0
basePDIRmask    set basePDIRmask | bitmask_PWMs         ; always drive LEDs

preservePins_PDIR set 0

basePCTLmask    set 0
basePCTLmask    set basePCTLmask | bitmask Aux0         ; pullup on Aux0
basePCTLmask    set basePCTLmask | bitmask Aux1         ; pullup on Aux1
basePCTLmask    set basePCTLmask | bitmask_unusedIOs    ; pullups on unused IOs

basePIEmask     set 0
basePIEmask     set basePIEmask | bitmask SSB           ; interrupt on SSB transitions

basePOUTmask    set 0
basePOUTmask    set basePOUTmask | bitmask SDOUT        ; fully drive data out, gated by SSB

preservePins_POUT set 0
preservePins_POUT set preservePins_POUT | bitmask SSB   ; never change slave select level in init ports
preservePins_POUT set preservePins_POUT | bitmask_PWMs  ; never change LEDs in init ports


;*************************************************************
; ANALOG SETTINGS

baseOCTLmask    set     0
baseOCTLmask    set     baseOCTLmask | $20              ; set RCosc to 4 MHz
baseOCTLmask    set     baseOCTLmask | (bitmask AEN)    ; turn on analog block

baseXHCTLmask   set     0
baseXHCTLmask   set     baseXHCTLmask | $100            ; set the chip to 1 CHN mode
baseXHCTLmask   set     baseXHCTLmask | bestGuessXRefHi ; try servoing by estimation

baseXLCTLmask   set     0
baseXLCTLmask   set     baseXLCTLmask | (bitmask XSENSE); turn on X sensors
baseXLCTLmask   set     baseXLCTLmask | (bitmask XREFEN)
baseXLCTLmask   set     baseXLCTLmask | (bitmask XADCEN); turn on X ADCs
baseXLCTLmask   set     baseXLCTLmask | bestGuessXRefLo

baseYHCTLmask   set     0

baseYLCTLmask   set     0
  if SetBigRef
baseYLCTLmask   set     baseYLCTLmask | (bitmask BigRef)
  endif


;*************************************************************
; BEGIN CODE

include "pwm_t1.asm"

include "pwm_t2.asm"

include "pwm_t3.asm"


happy:  reset


        org AddressStoreLocation

StoreAddressWord:

        message "Do we want to change the default address?"
        word $0000

        org $0BFF
        word $2FFF

end

