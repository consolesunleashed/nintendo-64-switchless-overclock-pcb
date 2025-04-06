    #include <p12f629.inc>
processor p12f629

; -----------------------------------------------------------------------
;   N64 'Overclock-Mod Multiplier Selector'
;
;   Copyright (C) 2014 by Peter Bartmann
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation; version 2 of the License only.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program; if not, write to the Free Software
;   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
;
; -----------------------------------------------------------------------
;
;   This program is designed to run on a PIC 12F629 microcontroller connected
;   to the PIF-NUS (Lockoutchip) of the N64. It allows you to select the
;   multiplier of the CPU via the reset button.
;
;   pin configuration: [PIF NUS / CPU]
;                              ,------_-----.
;    Vcc/3.3V [PIF-NUS Pin 28] |1          8| Vss/GND [PIF-NUS Pin 14]
;              LED-color 0 out |2  GP5 GP0 7| multiplier 0 out [CPU Pin 112]
;              LED-color 1 out |3  GP4 GP1 6| multiplier 1 out [CPU Pin 116]
;    Reset in [PIF-NUS Pad 27] |4  GP3 GP2 5| Reset out [PIF-NUS Pin 27]
;                              `------------'
;
;   As the internal oscillator is used, you should connect a capacitor of about 100nF between
;   Pin 1 (Vcc/+3.3V) and Pin 8 (Vss/GND) as close as possible to the PIC. This esures best
;   operation.
;
;   multiplier and their corresponding operating frequencies:
;
;        CPU Pin    |            | 
;       Assignment  | Multiplier |  Operating
;      116  |  112  |            |  Frequency
;    -------|-------|------------|--------------
;      GND  |  GND  |    1.0x    |   62.50 MHz   (not implemented here)
;      GND  | +3.3V |    1.5x    |   93.75 MHz   (default)
;     +3.3V |  GND  |    2.0x    |  125.00 MHz
;     +3.3V | +3.3V |    3.0x    |  187.50 MHz    
;
;
;   This program expects a dual-LED with a common cathod. Further, mode '0',
;   i.e., 62.50 MHz is not allowed. If you want to have the same program using
;   a LED with a common anode or doesn't skip mode '0', please change it on
;   your own or contact me.
;
; -----------------------------------------------------------------------
; Configuration bits: adapt to your setup and needs
    __CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _CPD_OFF

CA_LED      set 0 ; 0 = LED with common cathode, 1 = LED with common anode
MAX_MULT_3x set 0 ; 0 = max. mult. 2.0x        , 1 = max. mult. 3.0x

; -----------------------------------------------------------------------
; macros and definitions

M_movff macro   fromReg, toReg  ; move filereg to filereg
        movfw   fromReg
        movwf   toReg
        endm

M_movpf macro   fromPORT, toReg ; move PORTx to filereg
        movfw   fromPORT
        andlw   0x3f
        movwf   toReg
        endm

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_beff  macro   compReg1, compReg2, branch  ; branch if two fileregs are equal
        movfw   compReg1
        xorwf	compReg2, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_bepf  macro   compPORT, compReg, branch   ; brach if PORTx equals compReg (ignoring bit 6 and 7)
        movfw   compPORT
        xorwf   compReg, w
        andlw   0x3f
        btfsc   STATUS, Z
        goto    branch
        endm

M_belf  macro   literal, compReg, branch  ; branch if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_celf  macro   literal, compReg, call_func  ; call if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        call    call_func
        endm

M_delay_x5ms   macro   literal ; delay about literal x 5ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x5ms
                endm

M_push_reset    macro
                banksel TRISIO
                bcf     TRISIO, RESET_OUT
                banksel GPIO
                bcf     GPIO, RESET_OUT
                endm

M_release_reset macro
                bsf     GPIO, RESET_OUT
                banksel TRISIO
                bsf     TRISIO, RESET_OUT
                banksel GPIO
                endm

#define M_skipnext_rst_pressed  btfsc   GPIO, RESET_IN

; -----------------------------------------------------------------------
;gpio
MULT_0      EQU 0
MULT_1      EQU 1
RESET_OUT   EQU 2
RESET_IN    EQU 3
LED_1       EQU 4
LED_0       EQU 5

; registers
reg_overflow_cnt    EQU 0x20
reg_repetition_cnt  EQU 0x21
reg_current_mode    EQU 0x30
reg_maximum_mode    EQU 0x31

; codes and definitions
multiplier_1.0x EQU 0x00
multiplier_1.5x EQU 1<<MULT_0
multiplier_2.0x EQU 1<<MULT_1
if MAX_MULT_3x
  multiplier_3.0x EQU (1<<MULT_1) ^ (1<<MULT_0)
endif

if CA_LED
  led_1.0x    EQU (1<<LED_1) ^ (1<<LED_0)
  led_1.5x    EQU 1<<LED_1
  led_2.0x    EQU 1<<LED_0
  led_3.0x    EQU 0x00
else
  led_1.0x    EQU 0x00
  led_1.5x    EQU 1<<LED_0
  led_2.0x    EQU 1<<LED_1
  led_3.0x    EQU (1<<LED_1) ^ (1<<LED_0)
endif

; set here important constants for your need :
minimum_mode_number EQU multiplier_1.5x ; nobody wants to use the 1.0x mult; so start with 1.5x

if MAX_MULT_3x
  overflow_mode_number  EQU 0x04
else
  overflow_mode_number  EQU 0x03
endif

; and finally for time measurement
delay_5ms_t0_overflows  EQU 0x0a    ; prescaler T0 set to 1:2 @ 4MHz
repetitions_20ms        EQU 0x04
repetitions_100ms       EQU 0x14
repetitions_200ms       EQU 0x28
repetitions_240ms       EQU 0x30
repetitions_mode_delay  EQU 0x94    ; around 740ms

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf	STATUS		; 00h Page 0, Bank 0
	nop                 ; 01h
    nop                 ; 02h
    goto	start		; 03h begin program / Initializing

 org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

 org    0x0005
idle
    M_skipnext_rst_pressed
    goto    idle

    ; software debounce
    M_delay_x5ms   repetitions_20ms
    M_skipnext_rst_pressed
    goto    idle

    M_movlf repetitions_mode_delay, reg_repetition_cnt

check_rst_loop
    call    delay_5ms
    M_skipnext_rst_pressed
    goto    doreset
    decfsz  reg_repetition_cnt, 1
    goto    check_rst_loop

next_mode
    incf    reg_current_mode, 1
    M_celf  overflow_mode_number, reg_current_mode, reset_mode

mode_delay
    call    set_led  ; includes save_mode
    M_movlf repetitions_mode_delay, reg_repetition_cnt

mode_delay_loop
    call    delay_5ms
    M_skipnext_rst_pressed
    goto    idle
    decfsz  reg_repetition_cnt, 1
    goto    mode_delay_loop
    goto    next_mode

doreset
    M_push_reset
    M_delay_x5ms   repetitions_200ms
    M_release_reset
    goto    idle


set_led
    M_belf  multiplier_1.0x, reg_current_mode, set_led_10x
    M_belf  multiplier_1.5x, reg_current_mode, set_led_15x
    M_belf  multiplier_2.0x, reg_current_mode, set_led_20x
if MAX_MULT_3x
    M_belf  multiplier_3.0x, reg_current_mode, set_led_30x
endif
    call    reset_mode  ; should not appear
    goto    set_led

set_led_10x
    movfw   GPIO
    andlw   0x0f
    movwf   GPIO
    goto    save_mode

set_led_15x
    movfw   GPIO
    andlw   0x0f
    xorlw   led_1.5x
    movwf   GPIO
    goto    save_mode

set_led_20x
    movfw   GPIO
    andlw   0x0f
    xorlw   led_2.0x
    movwf   GPIO
if MAX_MULT_3x
    goto    save_mode

set_led_30x
    movfw   GPIO
    andlw   0x0f
    xorlw   led_3.0x
    movwf   GPIO
endif
;    goto    save_mode

save_mode
    movfw   reg_current_mode    ; load current mode to work
    banksel EEADR               ; save to EEPROM. note: banksels take two cycles each!
    movwf   EEDAT
    bsf     EECON1, WREN
    M_movlf 0x55, EECON2
    M_movlf 0xaa, EECON2
    bsf     EECON1, WR
    banksel	GPIO                ; two cycles again
    return

reset_mode
    M_movlf minimum_mode_number, reg_current_mode
    call    set_led_10x ; set LED off for a short moment
    M_delay_x5ms   repetitions_240ms
    return

delay_5ms
    M_movlf delay_5ms_t0_overflows, reg_overflow_cnt
    clrf    TMR0    ; start timer

delay_5ms_loop_pre
    bcf     INTCON, T0IF

delay_5ms_loop
    btfss   INTCON, T0IF
    goto    delay_5ms_loop
    decfsz  reg_overflow_cnt, 1
    goto    delay_5ms_loop_pre
    return

delay_x5ms
    call    delay_5ms
    decfsz  reg_repetition_cnt, 1
    goto    delay_x5ms
    return

start
    clrf    GPIO
    M_movlf 0x07, CMCON         ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 0x20, INTCON        ; enable interrupts: T0IE
    banksel TRISIO              ; Bank 1
    clrf    TRISIO              ; out out out out out out (console automatically in reset here)
    call    3FFh                ; Get the osccal value
    movwf   OSCCAL              ; Calibrate
    M_movlf (1<<RESET_OUT), WPU ; weak pull-up at GP2
    clrf    OPTION_REG          ; global pullup enable, prescaler T0 1:2
    banksel GPIO                ; Bank 0

load_mode
    clrf    reg_current_mode
    bcf     STATUS, C                   ; clear carry
    banksel EEADR                       ; fetch current mode from EEPROM
    clrf    EEADR                       ; address 0
    bsf     EECON1, RD
    movfw   EEDAT
    banksel GPIO
    andlw   (1<<MULT_0) ^ (1<<MULT_1)   ; just to be sure
    movwf   reg_current_mode            ; last mode saved

init_multiplier
    M_movff reg_current_mode, GPIO
    M_movlf overflow_mode_number, reg_maximum_mode
    M_beff  reg_current_mode, reg_maximum_mode, revert_multiplier   ; branch is taken only if current mode is 3.0x and 2.0x is maximum mode
    M_release_reset                                                 ; reset can be released
    call set_led                                                    ; includes save_mode
    goto idle

revert_multiplier
    M_movlf multiplier_1.5x, reg_current_mode
    goto init_multiplier

; eeprom data
DEEPROM	CODE
    de  multiplier_1.5x ; current mode (default: 1.5x -> 93.75MHz)

theend
    END
; ------------------------------------------------------------------------
