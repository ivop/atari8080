
; Intel 8080 emulator for the Atari 130XE
; Copyright © 2023,2024 by Ivo van Poorten
;
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the LICENSE file in the root project directory for the full text.
;
; mads assembler format

; bit 0 ROM, 0 = off, 1 = on
; bit 1 BASUC, 0 = on, 1 = off
; bits 2 and 3 select bank
; bits 4 and 5 enable bank switched in, bit 4 low is CPU, bit 5 low is ANTIC
; bit 6 unused
; bit 7 selftest, 0 = on, 1 = off

; set to $fe at boot (basic enabled), $ff basic disabled

; Needed for standalone test

PORTB = $d301

; addresses inside virtual 8080 machine
CCP   = $e400
CPMB  = CCP
BDOS  = $ec00
BDOSE = BDOS+6
BIOS  = $fa00

BOOTF  = (BIOS+( 0*3))
WBOOTF = (BIOS+( 1*3))
DPBASE = (BIOS+(17*3))

; OS ROM off, BASIC off
NOBANK = $fe
BANK0 = $e2 | $00 | $00
BANK1 = $e2 | $00 | $04
BANK2 = $e2 | $08 | $00
BANK3 = $e2 | $08 | $04

; --------------------------------------------------------------------------

; Zero Page

ZP = $e0

regA = ZP
regF = ZP+1

; adjusted variants MUST be at offset +2 from normal register

regB  = ZP+2
regC  = ZP+3
regBa = ZP+4        ; adjusted when needed. lda (regC),y to implement (BC)

regD  = ZP+5
regE  = ZP+6
regDa = ZP+7

regH  = ZP+8
regL  = ZP+9
regHa = ZP+10

SPH  = ZP+11
SPL  = ZP+12
SPHa = ZP+13

PCH  = ZP+14
PCL  = ZP+15
PCHa = ZP+16     ; keep PC always adjusted for fetch instruction!

curbank  = ZP+17    ; direct PORTB values

byte3       = ZP+18
byte2       = ZP+19
byte3a      = ZP+20     ; for SHLD for example (adr)<-L;(adr+1)<-H

regM    = ZP+21         ; temporary M register, optimize later
t8      = ZP+22
saveCF  = ZP+23

tmp16   = ZP+24

zp_len = 25             ; 32 max.

SF_FLAG = %10000000
ZF_FLAG = %01000000
AF_FLAG = %00010000
PF_FLAG = %00000100
ON_FLAG = %00000010     ; always on!
CF_FLAG = %00000001

ALL_FLAGS = (SF_FLAG|ZF_FLAG|AF_FLAG|PF_FLAG|ON_FLAG|CF_FLAG)

; --------------------------------------------------------------------------

; We just assume we are on a 130XE for now. atari800 -xe 8080.xex

    org $8000

set_bank0:
    lda #BANK0
    sta PORTB
    rts

    ini set_bank0

; setup low mem

    org $4000           ; 8080 memory at 00000h, bank 0

    .byte 0x76          ; HALT if WBOOT is called
    .byte 0
    .byte 0
    .word 0
    .byte 0xc3          ; JMP
    .word BDOSE

; --------------------------------------------------------------------------

; Load BDOS and BIOS directly to extended memory banks.

    org $8000

set_bank3:
    lda #BANK3
    sta PORTB
    rts

    ini set_bank3

    org $4000+(BDOS&$3fff)  ; in bank 3

    ins 'cpm22/bdos.sys'

    org $4000+(BIOS&$3fff)  ; in bank 3

    ins 'cpm22/bios.sys'

; --------------------------------------------------------------------------

; MACROS HERE

    ; Read value from LOC and write to address of which LOW and HIGH
    ; are its low and high byte POINTER (i.e. zero page locations).
    ;
    ; Assumes Y=0 on entry!
    ;
    ; It uses HIGH+2 for its adjusted high byte. Memory layout MUST be
    ;
    ; * HIGH
    ; * LOW = HIGH+1
    ; * HIGH_adjusted = HIGH+2
    ;
    ; This assures that (LOW),y points to the right memory location when
    ; the proper bank is selected.
    ; curbank is restored for instruction fetching afterwards.
    ;
    ; Most of the time LOC will denote a register, but it can be any
    ; zero page location.

    .macro mem_write LOW, HIGH, LOC     ; assume Y=0
        ldx :HIGH
        lda msb_to_adjusted,x
        sta :HIGH+2
        lda msb_to_bank,x
        sta PORTB
        lda :LOC
        sta (:LOW),y
        lda curbank
        sta PORTB
    .endm

    ; Same, but does not restore curbank at the end. Use with caution!

    .macro mem_write_no_curbank_restore LOW, HIGH, LOC     ; assume Y=0
        ldx :HIGH
        lda msb_to_adjusted,x
        sta :HIGH+2
        lda msb_to_bank,x
        sta PORTB
        lda :LOC
        sta (:LOW),y
    .endm

    ; Similar to mem_write, but READ from (LOW),y and store in LOC

    .macro mem_read LOW, HIGH, LOC
        ldx :HIGH
        lda msb_to_adjusted,x
        sta :HIGH+2
        lda msb_to_bank,x
        sta PORTB
        lda (:LOW),y            ; these are reversed!
        sta :LOC                ;
        lda curbank
        sta PORTB
    .endm

    ; Same, but does not restore curbank at the end. Use with caution!

    .macro mem_read_no_curbank_restore LOW, HIGH, LOC     ; assume Y=0
        ldx :HIGH
        lda msb_to_adjusted,x
        sta :HIGH+2
        lda msb_to_bank,x
        sta PORTB
        lda (:LOW),y
        sta :LOC
    .endm

    .macro KIL           ; used to stop 6502 emulation and jump to debugger   
        dta 2
    .endm

; --------------------------------------------------------------------------

; MAIN EMULATION LOOP

; Important:
; BIT: The N and V flags are set to match bits 7 and 6 respectively in the
; value stored at the tested address.

; Reserve 128 bytes after the banking window to allow overflow when
; reading a sector. The number of bytes overflowed need to be copied
; to the beginning of the next bank.

    org $8080

; Enter with Y=0!

; If an opcode really needs to use Y, it has to set it back to zero upon
; returning here!

run_emulator:

    .macro INCPC
        inc PCL             ; most of the time this is just inc+bne
        bne no_inc_pch
            inc PCH         ; each page crossing it's three instructions
            inc PCHa        ; longer
;            bit PCHa
            bpl no_adjust   ; except for when we are at the end of the bank
                ldx PCH
                lda msb_to_bank,x
                sta curbank
                sta PORTB
                lda msb_to_adjusted,x       ; isn't this always lda #$40 ?
                sta PCHa
no_adjust:
no_inc_pch:
    .endm

    lda (PCL),y                 ; retrieve instruction

    asl
    bcc do_tab1
    jmp do_tab2

do_tab1
    sta _jmp1+1

    INCPC

_jmp1   jmp (tab1)

do_tab2
    sta _jmp2+1

    INCPC

_jmp2   jmp (tab2)

    .macro get_byte2
        lda (PCL),y
        sta byte2
        INCPC
    .endm

    .macro get_byte23
        lda (PCL),y
        sta byte2
        INCPC
        lda (PCL),y
        sta byte3
        INCPC
    .endm

; --------------------------------------------------------------------------

opcode_00: ; NOP
    jmp run_emulator

    ; ######################### LXI #########################
    ; LXI XY       X <- byte3; Y <- byte2

    .macro LXI regX, regY
        lda (PCL),y
        sta :regY
        INCPC
        lda (PCL),y
        sta :regX
        INCPC
    .endm

opcode_01:
    LXI regB,regC
    jmp run_emulator

opcode_11:
    LXI regD,regE
    jmp run_emulator

opcode_21:
    LXI regH,regL
    jmp run_emulator

opcode_31:
    LXI SPH,SPL
    jmp run_emulator

    ; ######################### STORE #########################
    ;

opcode_02:  ; STAX B ---- (BC) <- A
    mem_write regC, regB, regA
    jmp run_emulator

opcode_12:  ; STAX D ---- (DE) <- A
    mem_write regE, regD, regA
    jmp run_emulator

opcode_22:  ; SHLD adr ---- (adr) <-L;(adr+1) <- H
    get_byte23
    mem_write_no_curbank_restore byte2, byte3, regL
    inc byte2
    bne @+
    inc byte3
@:
    mem_write byte2, byte3, regH        ; here curbank/PORTB is restored
    jmp run_emulator

opcode_32:  ; STA adr ---- (adr) <- A
    get_byte23
    mem_write byte2, byte3, regA
    jmp run_emulator

    ; ######################### INX #########################
    ; INX XY    XY <- XY+1

    .macro _INX regX, regY      ; inx is reserved keyword
        inc :regY
        bne no_inc_regX
        inc :regX
no_inc_regX
    .endm

opcode_03:
    _INX regB,regC
    jmp run_emulator

opcode_13:
    _INX regD,regE
    jmp run_emulator

opcode_23:
    _INX regH,regL
    jmp run_emulator

opcode_33:
    _INX SPH,SPL
    jmp run_emulator

    ; ######################### INR #########################
    ; INR reg  reg=reg+1                 [Z,S,P,AC]

    .macro INR REG
        inc :REG
        ldx :REG

        lda regF
        and #~(ZF_FLAG|SF_FLAG|PF_FLAG|AF_FLAG)
        ora inr_af_table,x          ; (reg&0x0f)==0
        ora zsp_table,x
        sta regF
    .endm

opcode_04:
    INR regB
    jmp run_emulator

opcode_0c:
    INR regC
    jmp run_emulator

opcode_14:
    INR regD
    jmp run_emulator

opcode_1c:
    INR regE
    jmp run_emulator

opcode_24:
    INR regH
    jmp run_emulator

opcode_2c:
    INR regL
    jmp run_emulator

opcode_34: ; INR M
    mem_read_no_curbank_restore regL, regH, regM
    INR regM        ; execute instruction and set flags
    txa             ; still in X
    sta (regL),y    ; mem_read has setup the adjusted register and bank
    lda curbank
    sta PORTB
    jmp run_emulator

opcode_3c:
    INR regA
    jmp run_emulator

    ; ######################### DCR #########################
    ; DCR reg   reg=reg-1               [Z,S,P,AC]

    .macro DCR REG
        dec :REG
        ldx :REG

        lda regF
        and #~(ZF_FLAG|SF_FLAG|PF_FLAG|AF_FLAG)
        ora dcr_af_table,x          ; !((reg&0x0f)==0x0f)
        ora zsp_table,x
        sta regF
    .endm

opcode_05:
    DCR regB
    jmp run_emulator

opcode_0d:
    DCR regC
    jmp run_emulator

opcode_15:
    DCR regD
    jmp run_emulator

opcode_1d:
    DCR regE
    jmp run_emulator

opcode_25:
    DCR regH
    jmp run_emulator

opcode_2d:
    DCR regL
    jmp run_emulator

opcode_35:  ; DCR M
    mem_read_no_curbank_restore regL, regH, regM
    DCR regM        ; execute instruction and set flags
    txa             ; still in X
    sta (regL),y    ; mem_read has setup the adjusted register and bank
    lda curbank
    sta PORTB
    jmp run_emulator

opcode_3d:
    DCR regA
    jmp run_emulator

    ; ######################### MVI #########################
    ; MVI reg       reg = byte2

    .macro MVI REG
        lda (PCL),y
        sta :REG
        INCPC
    .endm

opcode_06:
    MVI regB
    jmp run_emulator

opcode_0e:
    MVI regC
    jmp run_emulator

opcode_16:
    MVI regD
    jmp run_emulator

opcode_1e:
    MVI regE
    jmp run_emulator

opcode_26:
    MVI regH
    jmp run_emulator

opcode_2e:
    MVI regL
    jmp run_emulator

opcode_36:
    get_byte2                       ; direct (PCL),y is not possible due
                                    ; to possible bank switch for (HL)
    mem_write regL, regH, byte2
    jmp run_emulator

opcode_3e:
    MVI regA
    jmp run_emulator

    ; ######################### DAD #########################
    ; DAD XY                           HL = HL + XY    [CY]

    .macro DAD regX regY
        lda regL
        clc
        adc :regY
        sta regL
        lda regH
        adc :regX
        sta regH
        bcc clear_carry

        lda regF
        ora #CF_FLAG
        sta regF
        jmp run_emulator

clear_carry
        lda regF
        and #~CF_FLAG
        sta regF
        jmp run_emulator
    .endm

opcode_09:
    DAD regB,regC       ; macro does jmp run_emulator

opcode_19:
    DAD regD,regE

opcode_29:
    DAD regH,regL

opcode_39:
    DAD SPH,SPL

    ; ######################### LOAD #########################
    ;
opcode_0a:  ; LDAX B ---- A <- (BC)
    mem_read regC, regB, regA
    jmp run_emulator

opcode_1a:  ; LDAX D ---- A <- (DE)
    mem_read regE, regD, regA
    jmp run_emulator

opcode_2a:  ; LHLD adr ---- L <- (adr);H <- (adr+1)
    get_byte23
    mem_read_no_curbank_restore byte2, byte3, regL
    inc byte2
    bne @+
    inc byte3
@:
    mem_read byte2, byte3, regH     ; restores curbank
    jmp run_emulator

opcode_3a:  ; // LDA adr ---- A <- (adr)
    get_byte23
    mem_read byte2, byte3, regA
    jmp run_emulator

    ; ######################### DCX #########################
    ; DCX XY       XY <- XY-1

    .macro DCX regX, regY
        lda :regY
        bne @+
        dec :regX
@:
        dec :regY
    .endm

opcode_0b:
    DCX regB,regC
    jmp run_emulator

opcode_1b:
    DCX regD,regE
    jmp run_emulator

opcode_2b:
    DCX regH,regL
    jmp run_emulator

opcode_3b:
    DCX SPH,SPL
    jmp run_emulator

    ; ######################### RRC/RAR/CMA/CMC #########################
    ;
opcode_0f: ; RRC --- A = A >> 1;bit 7 = prev bit 0;CY = prev bit 0 [CY]
    lda regA
    lsr
    bcc @+

    ora #$80
    sta regA
    lda regF
    ora #CF_FLAG
    sta regF
    jmp run_emulator

@:
    sta regA
    lda regF
    and #~CF_FLAG
    sta regF
    jmp run_emulator

opcode_1f: ; RAR ---- A = A >> 1;bit 7 = prev CY;CY = prev bit 0 [CY]
    lda regF
    lsr                 ; abuse fact that CF_FLAG=1, C=bit0 of regF
    ror regA
    bcc @+

    lda regF
    ora #CF_FLAG
    sta regF
    jmp run_emulator

@:
    lda regF
    and #~CF_FLAG
    sta regF
    jmp run_emulator

opcode_2f: ; CMA ---- A <- !A
    lda regA
    eor #$ff
    sta regA
    jmp run_emulator

opcode_3f: ; CMC ---- CY=!CY [CY]
    lda regF
    eor #CF_FLAG
    sta regF
    jmp run_emulator

    ; ######################### MOV #########################
    ;

    .macro MOV dst, src
        lda :src
        sta :dst
    .endm

    ; MOV B,x   (for x in B,C,D,E,H,L,M,A)
opcode_40:
    jmp run_emulator

opcode_41:
    MOV regB,regC
    jmp run_emulator

opcode_42:
    MOV regB,regD
    jmp run_emulator

opcode_43:
    MOV regB,regE
    jmp run_emulator

opcode_44:
    MOV regB,regH
    jmp run_emulator

opcode_45:
    MOV regB,regL
    jmp run_emulator

opcode_46:
    mem_read regL,regH,regB
    jmp run_emulator

opcode_47:
    MOV regB,regA
    jmp run_emulator

    ; MOV C,x   (for x in B,C,D,E,H,L,M,A)
opcode_48:
    MOV regC,regB
    jmp run_emulator

opcode_49:
    jmp run_emulator

opcode_4a:
    MOV regC,regD
    jmp run_emulator

opcode_4b:
    MOV regC,regE
    jmp run_emulator

opcode_4c:
    MOV regC,regH
    jmp run_emulator

opcode_4d:
    MOV regC,regL
    jmp run_emulator

opcode_4e:
    mem_read regL,regH,regC
    jmp run_emulator

opcode_4f:
    MOV regC,regA
    jmp run_emulator

    ; MOV D,x   (for x in B,C,D,E,H,L,M,A)
opcode_50:
    MOV regD,regB
    jmp run_emulator

opcode_51:
    MOV regD,regC
    jmp run_emulator

opcode_52:
    jmp run_emulator

opcode_53:
    MOV regD,regE
    jmp run_emulator

opcode_54:
    MOV regD,regH
    jmp run_emulator

opcode_55:
    MOV regD,regL
    jmp run_emulator

opcode_56:
    mem_read regL,regH,regD
    jmp run_emulator

opcode_57:
    MOV regD,regA
    jmp run_emulator

    ; MOV E,x   (for x in B,C,D,E,H,L,M,A)
opcode_58:
    MOV regE,regB
    jmp run_emulator

opcode_59:
    MOV regE,regC
    jmp run_emulator

opcode_5a:
    MOV regE,regD
    jmp run_emulator

opcode_5b:
    jmp run_emulator

opcode_5c:
    MOV regE,regH
    jmp run_emulator

opcode_5d:
    MOV regE,regL
    jmp run_emulator

opcode_5e:
    mem_read regL,regH,regE
    jmp run_emulator

opcode_5f:
    MOV regE,regA
    jmp run_emulator

    ; MOV H,x   (for x in B,C,D,E,H,L,M,A)
opcode_60:
    MOV regH,regB
    jmp run_emulator

opcode_61:
    MOV regH,regC
    jmp run_emulator

opcode_62:
    MOV regH,regD
    jmp run_emulator

opcode_63:
    MOV regH,regE
    jmp run_emulator

opcode_64:
    jmp run_emulator

opcode_65:
    MOV regH,regL
    jmp run_emulator

opcode_66:
    mem_read regL,regH,regH
    jmp run_emulator

opcode_67:
    MOV regH,regA
    jmp run_emulator

    ; MOV L,x   (for x in B,C,D,E,H,L,M,A)
opcode_68:
    MOV regL,regB
    jmp run_emulator

opcode_69:
    MOV regL,regC
    jmp run_emulator

opcode_6a:
    MOV regL,regD
    jmp run_emulator

opcode_6b:
    MOV regL,regE
    jmp run_emulator

opcode_6c:
    MOV regL,regH
    jmp run_emulator

opcode_6d:
    jmp run_emulator

opcode_6e:
    mem_read regL,regH,regL
    jmp run_emulator

opcode_6f:
    MOV regL,regA
    jmp run_emulator

    ; MOV M,x   (for x in B,C,D,E,H,L,M,A)
opcode_70:
    mem_write regL,regH,regB
    jmp run_emulator

opcode_71:
    mem_write regL,regH,regC
    jmp run_emulator

opcode_72:
    mem_write regL,regH,regD
    jmp run_emulator

opcode_73:
    mem_write regL,regH,regE
    jmp run_emulator

opcode_74:
    mem_write regL,regH,regH
    jmp run_emulator

opcode_75:
    mem_write regL,regH,regL
    jmp run_emulator

opcode_76:  ; HaLT!
    rts     ; Leave emulation loop

opcode_77:
    mem_write regL,regH,regA
    jmp run_emulator

    ; MOV A,x   (for x in B,C,D,E,H,L,M,A)
opcode_78:
    MOV regA,regB
    jmp run_emulator

opcode_79:
    MOV regA,regC
    jmp run_emulator

opcode_7a:
    MOV regA,regD
    jmp run_emulator

opcode_7b:
    MOV regA,regE
    jmp run_emulator

opcode_7c:
    MOV regA,regH
    jmp run_emulator

opcode_7d:
    MOV regA,regL
    jmp run_emulator

opcode_7e:
    mem_read regL,regH,regA
    jmp run_emulator

opcode_7f:
    jmp run_emulator

    ; ######################### ADD #########################
    ; A = A + val                      [Z,S,P,CY,AC]

    .macro _ADD val         ; add is reserved keyword
        clc
        lda regA
        adc :val
        tax                 ; save temporarily, and we need it as index
        bcc @1              ; use 6502 carry to set/clear CF

        lda regF
        ora #CF_FLAG
        bne @2

@1:
        lda regF
        and #~CF_FLAG

@2:
        sta regF

        txa                 ; result z back in accu
        eor regA
        eor :val
        and #$10
        beq @3

        lda regF
        ora #AF_FLAG
;        sta regF
        bne @4

@3:
        lda regF
        and #~AF_FLAG
;        sta regF

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF
        stx regA
    .endm

opcode_80:
    _ADD regB
    jmp run_emulator

opcode_81:
    _ADD regC
    jmp run_emulator

opcode_82:
    _ADD regD
    jmp run_emulator

opcode_83:
    _ADD regE
    jmp run_emulator

opcode_84:
    _ADD regH
    jmp run_emulator

opcode_85:
    _ADD regL
    jmp run_emulator

opcode_86:
    mem_read regL,regH,regM
    _ADD regM
    jmp run_emulator

opcode_87:
    _ADD regA
    jmp run_emulator

    ; ######################### ADC #########################
    ; A = A + val + carry              [Z,S,P,CY,AC]

    .macro _ADC val         ; adc is reserved keyword
        lda regF
        lsr                 ; get carry from regF
        lda regA
        adc :val
        tax                 ; save temporarily, and we need it as index
        bcc @1              ; use 6502 to set/clear CF

        lda regF
        ora #CF_FLAG
        bne @2

@1:
        lda regF
        and #~CF_FLAG

@2:
        sta regF

        txa                 ; result z back in accu
        eor regA
        eor :val
        and #$10
        beq @3

        lda regF
        ora #AF_FLAG
;        sta regF
        bne @4

@3:
        lda regF
        and #~AF_FLAG
;        sta regF

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF
        stx regA
    .endm

opcode_88:
    _ADC regB
    jmp run_emulator

opcode_89:
    _ADC regC
    jmp run_emulator

opcode_8a:
    _ADC regD
    jmp run_emulator

opcode_8b:
    _ADC regE
    jmp run_emulator

opcode_8c:
    _ADC regH
    jmp run_emulator

opcode_8d:
    _ADC regL
    jmp run_emulator

opcode_8e:
    mem_read regL,regH,regM
    _ADC regM
    jmp run_emulator

opcode_8f:
    _ADC regA
    jmp run_emulator

    ; ######################### SUB #########################
    ; A = A + ~val + !carry             [Z,S,P,CY,AC]
    ; 6502: use sbc, carry flag is inverted compared to 8080(!)

    .macro _SUB val         ; sub is reserved keyword
        sec                 ; inverted!
        lda regA
        sbc :val
        tax                 ; save temporarily, and we need it as index
        bcs @1              ; use 6502 carry to set/clear CF (inverted!)

        lda regF
        ora #CF_FLAG
        bne @2

@1:
        lda regF
        and #~CF_FLAG

@2:
        sta regF

        txa                 ; result z back in accu
        eor regA
        eor :val
        and #$10
        bne @3

        lda regF
        ora #AF_FLAG
;        sta regF
        bne @4

@3:
        lda regF
        and #~AF_FLAG
;        sta regF

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF
        stx regA
    .endm

opcode_90:
    _SUB regB
    jmp run_emulator

opcode_91:
    _SUB regC
    jmp run_emulator

opcode_92:
    _SUB regD
    jmp run_emulator

opcode_93:
    _SUB regE
    jmp run_emulator

opcode_94:
    _SUB regH
    jmp run_emulator

opcode_95:
    _SUB regL
    jmp run_emulator

opcode_96:
    mem_read regL,regH,regM
    _SUB regM
    jmp run_emulator

opcode_97:
    _SUB regA
    jmp run_emulator

    ; ######################### SBB #########################
    ; A = A + ~val + !carry             [Z,S,P,CY,AC]

    ; 6502: use sbc, carry flag is inverted compared to 8080(!)

    .macro _SBC val         ; sbc is reserved keyword
        lda regF
        eor #$01            ; inverted!
        lsr
        lda regA
        sbc :val
        tax                 ; save temporarily, and we need it as index
        bcs @1              ; use 6502 carry to set/clear CF (inverted!)

        lda regF
        ora #CF_FLAG
        bne @2

@1:
        lda regF
        and #~CF_FLAG

@2:
        sta regF

        txa                 ; result z back in accu
        eor regA
        eor :val
        and #$10
        bne @3

        lda regF
        ora #AF_FLAG
;        sta regF
        bne @4

@3:
        lda regF
        and #~AF_FLAG
;        sta regF

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF
        stx regA
    .endm

opcode_98:
    _SBC regB
    jmp run_emulator

opcode_99:
    _SBC regC
    jmp run_emulator

opcode_9a:
    _SBC regD
    jmp run_emulator

opcode_9b:
    _SBC regE
    jmp run_emulator

opcode_9c:
    _SBC regH
    jmp run_emulator

opcode_9d:
    _SBC regL
    jmp run_emulator

opcode_9e:
    mem_read regL,regH,regM
    _SBC regM
    jmp run_emulator

opcode_9f:
    _SBC regA
    jmp run_emulator

    ; ######################### ANA #########################
    ; A = A & val                      [Z,S,P,CY,AC]

    .macro ANA val
        lda regA
        and :val
        tax

        lda regA
        ora :val
        and #$08
        bne @1

        lda regF
        and #~AF_FLAG
        bne @2

@1:
        lda regF
        ora #AF_FLAG

@2:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG|CF_FLAG)     ; clear carry here
        ora zsp_table,x
        sta regF
        stx regA
    .endm

opcode_a0:
    ANA regB
    jmp run_emulator

opcode_a1:
    ANA regC
    jmp run_emulator

opcode_a2:
    ANA regD
    jmp run_emulator

opcode_a3:
    ANA regE
    jmp run_emulator

opcode_a4:
    ANA regH
    jmp run_emulator

opcode_a5:
    ANA regL
    jmp run_emulator

opcode_a6:
    mem_read regL,regH,regM
    ANA regM
    jmp run_emulator

opcode_a7:
    ANA regA
    jmp run_emulator

    ; ######################### XRA #########################
    ; A = A ^ val                      [Z,S,P,CY,AC]

    .macro XRA val
        lda regA
        eor :val
        sta regA
        tax

        lda #ON_FLAG
        ora zsp_table,x
        sta regF
    .endm

opcode_a8:
    XRA regB
    jmp run_emulator

opcode_a9:
    XRA regC
    jmp run_emulator

opcode_aa:
    XRA regD
    jmp run_emulator

opcode_ab:
    XRA regE
    jmp run_emulator

opcode_ac:
    XRA regH
    jmp run_emulator

opcode_ad:
    XRA regL
    jmp run_emulator

opcode_ae:
    mem_read regL,regH,regM
    XRA regM
    jmp run_emulator

opcode_af:
    XRA regA
    jmp run_emulator
 
    ; ######################### ORA #########################
    ; A = A | val                      [Z,S,P,CY,AC]

    .macro _ORA val     ; ora is reserved keyword
        lda regA
        ora :val
        sta regA
        tax

        lda #ON_FLAG
        ora zsp_table,x
        sta regF
    .endm

opcode_b0:
    _ORA regB
    jmp run_emulator

opcode_b1:
    _ORA regC
    jmp run_emulator

opcode_b2:
    _ORA regD
    jmp run_emulator

opcode_b3:
    _ORA regE
    jmp run_emulator

opcode_b4:
    _ORA regH
    jmp run_emulator

opcode_b5:
    _ORA regL
    jmp run_emulator

opcode_b6:
    mem_read regL,regH,regM
    _ORA regM
    jmp run_emulator

opcode_b7:
    _ORA regA
    jmp run_emulator

    ; ######################### CMP #########################
    ; CMP val                           [Z,S,P,CY,AC]

    .macro _CMP val
        lda regA
        sec
        sbc :val
        tax
        bcs @1

        lda regF
        ora #CF_FLAG
        bne @2
@1:
        lda regF
        and #~CF_FLAG

@2:
        sta regF

        txa
        eor regA
        eor :val
        eor #$ff
        and #$10
        bne @3

        lda regF
        and #~AF_FLAG
        bne @4

@3:
        lda regF
        ora #AF_FLAG

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF
    .endm

opcode_b8:
    _CMP regB
    jmp run_emulator

opcode_b9:
    _CMP regC
    jmp run_emulator

opcode_ba:
    _CMP regD
    jmp run_emulator

opcode_bb:
    _CMP regE
    jmp run_emulator

opcode_bc:
    _CMP regH
    jmp run_emulator

opcode_bd:
    _CMP regL
    jmp run_emulator

opcode_be:
    mem_read regL,regH,regM
    _CMP regM
    jmp run_emulator

opcode_bf:
    _CMP regA
    jmp run_emulator

    ; ######################### RLC/RAL/DAA/STC #########################
    ;
opcode_07:  ; RLC ---- A = A << 1;bit 0 = prev bit 7;CY = prev bit 7 [CY]
    asl regA
    bcc @1

    inc regA
    lda regF
    ora #CF_FLAG
    bne @2

@1:
    lda regF
    and #~CF_FLAG

@2:
    sta regF
    jmp run_emulator

opcode_17:  ; RAL ---- A = A << 1;bit 0 = prev CY;CY = prev bit 7 [CY]
    lda regF
    lsr                 ; CF to carry bit
    rol regA
    bcc @3

    lda regF
    ora #CF_FLAG
    bne @4

@3:
    lda regF
    and #~CF_FLAG

@4:
    sta regF
    jmp run_emulator

opcode_27:  ; DAA ---- Decimal Adjust Accumulator [Z,S,P,CY,AC]
    lda regF
    and #CF_FLAG
    sta saveCF

    ldx regA
    lda #0
    sta t8

    lda regF
    and #AF_FLAG
    ora daa_table_cond1,x
    beq @5

    lda #$06
    sta t8

@5:
    lda regF
    and #CF_FLAG
    ora daa_table_cond2,x
    beq @6

    lda t8
    ora #$60
    sta t8
    lda #CF_FLAG
    sta saveCF

@6:
    _ADD t8
    lda regF
    and #~CF_FLAG
    ora saveCF
    sta regF
    jmp run_emulator

opcode_37:  ; STC ---- CY   CY = 1
    lda regF
    ora #CF_FLAG
    sta regF
    jmp run_emulator

    ; ######################### POP/PUSH #########################
    ; POP XY       Y <- (SP); X <- (SP+1); SP <- SP+2

    .macro POP regX, regY
        mem_read_no_curbank_restore SPL,SPH,:regY
        inc SPL
        bne @1
        inc SPH
@1:
        mem_read SPL,SPH,:regX
        inc SPL
        bne @2
        inc SPH
@2:
    .endm

opcode_c1:
    POP regB,regC
    jmp run_emulator

opcode_d1:
    POP regD,regE
    jmp run_emulator

opcode_e1:
    POP regH,regL
    jmp run_emulator

opcode_f1:
    POP regA,regF
    lda regF
    ora #ON_FLAG
    and #ALL_FLAGS
    sta regF
    jmp run_emulator

    ; PUSH XY      (SP-2) <- Y; (SP-1) <- X; SP <- SP-2

    .macro PUSH regX, regY
        lda SPL
        bne @1
        dec SPH
@1:
        dec SPL
        mem_write_no_curbank_restore SPL,SPH,:regX

        lda SPL
        bne @2
        dec SPH
@2:
        dec SPL
        mem_write SPL,SPH,:regY
    .endm

opcode_c5:
    PUSH regB,regC
    jmp run_emulator

opcode_d5:
    PUSH regD,regE
    jmp run_emulator

opcode_e5:
    PUSH regH,regL
    jmp run_emulator

opcode_f5:
    PUSH regA,regF
    jmp run_emulator

    ; ######################### RETCETERA #########################
    ;
opcode_c0:
    lda regF
    and #ZF_FLAG
    beq RET
    jmp run_emulator

opcode_c8:
    lda regF
    and #ZF_FLAG
    bne RET
    jmp run_emulator

opcode_d0:
    lda regF
    and #CF_FLAG
    beq RET
    jmp run_emulator

opcode_d8:
    lda regF
    and #CF_FLAG
    bne RET
    jmp run_emulator

opcode_e0:
    lda regF
    and #PF_FLAG
    beq RET
    jmp run_emulator

opcode_e8:
    lda regF
    and #PF_FLAG
    bne RET
    jmp run_emulator

opcode_f0:
    lda regF
    and #SF_FLAG
    beq RET
    jmp run_emulator

opcode_f8:
    lda regF
    and #SF_FLAG
    bne RET
    jmp run_emulator

RET:
opcode_c9: ; RET
    POP PCH,PCL
    ldx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB
    jmp run_emulator

    ; ######################### JMP #########################
    ; 
opcode_c2:
    lda regF
    and #ZF_FLAG
    jeq _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_ca:
    lda regF
    and #ZF_FLAG
    jne _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_d2:
    lda regF
    and #CF_FLAG
    jeq _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_da:
    lda regF
    and #CF_FLAG
    jne _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_e2:
    lda regF
    and #PF_FLAG
    jeq _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_ea:
    lda regF
    and #PF_FLAG
    jne _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_f2:
    lda regF
    and #SF_FLAG
    jeq _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_fa:
    lda regF
    and #SF_FLAG
    jne _JMP
    INCPC
    INCPC
    jmp run_emulator

opcode_c3: ; JMP
_JMP:
    get_byte23
    lda byte2
    sta PCL
    ldx byte3               ; use X, saves one instruction
    stx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB
    jmp run_emulator

    ; ######################### CALL/RST #########################
    ;
opcode_c4:
    lda regF
    and #ZF_FLAG
    jeq CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_cc:
    lda regF
    and #ZF_FLAG
    jne CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_d4:
    lda regF
    and #CF_FLAG
    jeq CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_dc:
    lda regF
    and #CF_FLAG
    jne CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_e4:
    lda regF
    and #PF_FLAG
    jeq CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_ec:
    lda regF
    and #PF_FLAG
    jne CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_f4:
    lda regF
    and #SF_FLAG
    jeq CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_fc:
    lda regF
    and #SF_FLAG
    jne CALL
    INCPC
    INCPC
    jmp run_emulator

opcode_cd:  ; CALL
CALL:
    get_byte23
    PUSH PCH,PCL
    lda byte2
    sta PCL
    ldx byte3
    stx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB
    jmp run_emulator

opcode_c7:  ; RST0
    lda #0
    sta byte3
    sta byte2
    jmp CALL

opcode_cf:  ; etc...
    lda #0
    sta byte3
    lda #$08
    sta byte2
    jmp CALL

opcode_d7:
    lda #0
    sta byte3
    lda #$10
    sta byte2
    jmp CALL

opcode_df:
    lda #0
    sta byte3
    lda #$18
    sta byte2
    jmp CALL

opcode_e7:
    lda #0
    sta byte3
    lda #$20
    sta byte2
    jmp CALL

opcode_ef:
    lda #0
    sta byte3
    lda #$28
    sta byte2
    jmp CALL

opcode_f7:
    lda #0
    sta byte3
    lda #$30
    sta byte2
    jmp CALL

opcode_ff:
    lda #0
    sta byte3
    lda #$38
    sta byte2
    jmp CALL

    ; ######################### IMMEDIATE #########################
    ; func byte2
opcode_c6:          ; ADI
    _ADD "(PCL),y"
    INCPC
    jmp run_emulator

opcode_ce:          ; ACI
    _ADC "(PCL),y"
    INCPC
    jmp run_emulator

opcode_d6:          ; SUI
    _SUB "(PCL),y"
    INCPC
    jmp run_emulator

opcode_de:          ; SBI
    _SBC "(PCL),y"
    INCPC
    jmp run_emulator

opcode_e6:          ; ANI
    ANA "(PCL),y"
    INCPC
    jmp run_emulator

opcode_ee:          ; XRI
    XRA "(PCL),y"
    INCPC
    jmp run_emulator

opcode_f6:          ; ORI
    _ORA "(PCL),y"
    INCPC
    jmp run_emulator

opcode_fe:          ; CPI
    _CMP "(PCL),y"
    INCPC
    jmp run_emulator

    ; ######################### XTHL/XCHG #########################
    ;
opcode_e3:  ; XTHL ---- L <-> (SP);H <-> (SP+1)
    mem_read_no_curbank_restore SPL,SPH,t8
    mem_write_no_curbank_restore SPL,SPH,regL
    lda t8
    sta regL

    inc SPL
    bne @7
    inc SPH
@7:
    mem_read_no_curbank_restore SPL,SPH,t8
    mem_write SPL,SPH,regH                      ; curbank/PORTB restored
    lda t8
    sta regH

    lda SPL
    bne @8

    dec SPH
@8:
    dec SPL
    jmp run_emulator

opcode_eb:  ; XCHG ---- H <-> D;L <-> E
    ldx regH
    lda regD
    sta regH
    stx regD

    ldx regL
    lda regE
    sta regL
    stx regE
    jmp run_emulator

    ; ######################### PCHL/SPHL #########################
    ;
opcode_e9:  ; PCHL ---- PC.hi <- H;PC.lo <- L
    lda regL
    sta PCL
    ldx regH
    stx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB
    jmp run_emulator

opcode_f9:  ; SPHL ---- SP <- HL
    lda regL
    sta SPL
    lda regH
    sta SPH
    jmp run_emulator

    ; ######################### OUT/IN #########################
    ;
opcode_d3:
    get_byte2
    jsr MY_BIOS
    jmp run_emulator

opcode_db:
    get_byte2
    jmp run_emulator

    ; ######################### DI/EI #########################
    ;
opcode_f3:  ; DI
    jmp run_emulator

opcode_fb:  ; EI
    jmp run_emulator

opcode_08:
opcode_10:
opcode_18:
opcode_20:
opcode_28:
opcode_30:
opcode_38:
opcode_cb:
opcode_d9:
opcode_dd:
opcode_ed:
opcode_fd:
    ldx #0
print_undefined:
    lda undefined,x
    ldy #CPM65_BIOS_CONOUT
    stx t8
    jsr CPM65BIOS
    ldx t8
    inx
    cpx #undefined_len
    bne print_undefined
    rts

; --------------------------------------------------------------------------

CPM65_BIOS_CONST    = 0
CPM65_BIOS_CONIN    = 1
CPM65_BIOS_CONOUT   = 2
CPM65_BIOS_SELDSK   = 3
CPM65_BIOS_SETSEC   = 4
CPM65_BIOS_SETDMA   = 5
CPM65_BIOS_READ     = 6
CPM65_BIOS_WRITE    = 7

; BIOS wrappers here

MY_BIOS:
    ldx byte2
    cpx #$11
    bcs too_high

    lda bios_jump_table_high,x
    pha
    lda bios_jump_table_low,x
    pha

; fallthrough, call our BIOS wrapper

too_high:           ; just ignore
    rts

bios_00:    ; BOOT

    ldx #0
print_cpmvers:
    lda cpmvers,x
    ldy #CPM65_BIOS_CONOUT
    stx t8
    jsr CPM65BIOS
    ldx t8
    inx
    cpx #cpmvers_len
    bne print_cpmvers

; set CP/M jump vectors in low memory

    lda #BANK0
    sta PORTB

    lda #$c3        ; 8080 JMP instruction
    sta $4000
    sta $4005
    lda #<WBOOTF
    sta $4001
    lda #>WBOOTF
    sta $4002
    lda #<BDOSE
    sta $4006
    lda #>BDOSE
    sta $4007

; fallthrough

bios_01:    ; WBOOT

; copy CCP to virtual 8080 memory

    lda #BANK3
    sta PORTB

    ldx #0
copy_ccp:
    lda CCP_LOAD_ADDRESS+(0*256),x
    sta CCP-$8000+(0*256),x
    lda CCP_LOAD_ADDRESS+(1*256),x
    sta CCP-$8000+(1*256),x
    lda CCP_LOAD_ADDRESS+(2*256),x
    sta CCP-$8000+(2*256),x
    lda CCP_LOAD_ADDRESS+(3*256),x
    sta CCP-$8000+(3*256),x
    lda CCP_LOAD_ADDRESS+(4*256),x
    sta CCP-$8000+(4*256),x
    lda CCP_LOAD_ADDRESS+(5*256),x
    sta CCP-$8000+(5*256),x
    lda CCP_LOAD_ADDRESS+(6*256),x
    sta CCP-$8000+(6*256),x
    lda CCP_LOAD_ADDRESS+(7*256),x
    sta CCP-$8000+(7*256),x
    inx
    bne copy_ccp

    ldx #zp_len
    lda #0
clear_zp:
    sta ZP,x
    dex
    bpl clear_zp

    lda #ON_FLAG
    sta regF

    lda #<CPMB
    sta PCL
    ldx #>CPMB
    stx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB

    lda drive_number
    sta regC

    ldy #0
    rts

bios_02:    ; CONST
    ldy #CPM65_BIOS_CONST
    jsr CPM65BIOS
    sta regA
    ldy #0
    rts

bios_03:    ; CONIN
    ldy #CPM65_BIOS_CONIN
    jsr CPM65BIOS
    cmp #127                ; DEL
    bne no_bs
    lda #8                  ; BS
no_bs:
    sta regA
    ldy #0
    rts

bios_04:    ; CONOUT
    lda regC
    ldy #CPM65_BIOS_CONOUT
    jsr CPM65BIOS
    ldy #0
    rts

bios_05:    ; LIST
bios_06:    ; PUNCH
    rts

bios_07:    ; READER
    lda #26                     ; ^Z EOF
    sta regA
    rts

bios_08:    ; HOME
    lda #0
    sta track_number
    sta track_number+1
    sta regC
    rts

bios_09:    ; SELDSK
    lda #0
    sta regH
    sta regL
    lda regC
    bne no_such_drive       ; returns 0 in HL

    sta drive_number
    lda #<DPBASE
    sta regL
    lda #>DPBASE
    sta regH

no_such_drive:
    rts

; We do not call CP/M-65 BIOS for settrk and setsec as settrk is unavailable
; and setsec needs the absolute sector number. Instead, we calculate the
; absolute sector number before doing a read or write, and do the appropriate
; BIOS call there because we do not know in which order the calling program
; calls settrk and setsec.

bios_0a:    ; SETTRK
    lda regC
    sta track_number
    lda regB
    sta track_number+1
    rts

bios_0b:    ; SETSEC
    lda regC
    sta sector_number
    rts

bios_0c:    ; SETDMA
    lda regC
    sta dma_address
    sta regL
    lda regB
    sta dma_address+1
    sta regH
    rts

bios_0d:    ; READ
    jsr calculate_abs_sector_number

    ; set CP/M-65 sector number

    lda #<abs_sector_number
    ldx #>abs_sector_number
    ldy #CPM65_BIOS_SETSEC
    jsr CPM65BIOS

    ; switch to proper bank, set CP/M-65 DMA inside memory bank

    ldx dma_address
    stx tmp16
    ldx dma_address+1
    lda msb_to_adjusted,x
    sta tmp16+1
    lda msb_to_bank,x
    sta PORTB

    lda tmp16
    ldx tmp16+1
    ldy #CPM65_BIOS_SETDMA
    jsr CPM65BIOS

    ; read sector

    ldy #CPM65_BIOS_READ
    jsr CPM65BIOS

    ; check for overflow, copy to start of next bank

    lda tmp16               ; contains adjusted address
    clc
    adc #128
    sta tmp16
    lda tmp16+1
    adc #0
    sta tmp16+1
    cmp #$80                ; check if we wrote to our overflow area
    bne no_overflow

    ldx dma_address+1
    inx                     ; next page should be next bank
    lda msb_to_bank,x
    sta PORTB

    ldx tmp16
    dex                     ; minus one is the last byte of overflown bytes
                            ; always <=127

copy_to_next_bank
    lda $8000,x
    sta $4000,x
    dex
    bpl copy_to_next_bank

no_overflow:

    ; restore emulator state

    lda curbank
    sta PORTB
    ldy #0
    sty regA
    rts

bios_0e:    ; WRITE
    jsr calculate_abs_sector_number

    ; set CP/M-65 sector number

    lda #<abs_sector_number
    ldx #>abs_sector_number
    ldy #CPM65_BIOS_SETSEC
    jsr CPM65BIOS

    ; switch to proper bank, set CP/M-65 DMA inside memory bank

    ldx dma_address
    stx tmp16
    ldx dma_address+1
    lda msb_to_adjusted,x
    sta tmp16+1
    lda msb_to_bank,x
    sta PORTB
    sta t8                  ; save for later in case of overflow

    lda tmp16
    ldx tmp16+1
    ldy #CPM65_BIOS_SETDMA
    jsr CPM65BIOS

    ; check if DMA passes end of bank, if so, copy data to overflow area

    lda tmp16
    clc
    adc #128
    sta tmp16
    lda tmp16+1
    adc #0
    sta tmp16+1
    cmp #$80
    bne no_overflow2

    ldx dma_address+1
    inx                     ; next page should be next bank
    lda msb_to_bank,x
    sta PORTB

    ldx tmp16
    dex                     ; minus one is the last byte of overflown bytes
                            ; always <=127

copy_to_overflow_area
    lda $4000,x
    sta $8000,x
    dex
    bpl copy_to_overflow_area

    lda t8                  ; restore bank where DMA starts
    sta PORTB

no_overflow2:

    ; write sector

    ldy #CPM65_BIOS_WRITE
    jsr CPM65BIOS

    ; restore emulator state

    lda curbank
    sta PORTB
    ldy #0
    sty regA
    rts

calculate_abs_sector_number:
    ; track number * 18

    ; *2 to tmp16 and abs_sector_number

    lda track_number
    asl
    sta abs_sector_number
    sta tmp16

    lda track_number+1
    rol
    sta abs_sector_number+1
    sta tmp16+1

    ; tmp16 *8 --> *16 total

    .rept 3
    asl tmp16
    rol tmp16+1
    .endr

    ; add *16 and *2 --> *18

    clc
    lda abs_sector_number
    adc tmp16
    sta abs_sector_number
    lda abs_sector_number+1
    adc tmp16+1
    sta abs_sector_number+1

    ; add sector_number

    clc
    lda abs_sector_number
    adc sector_number
    sta abs_sector_number
    lda abs_sector_number+1
    adc #0
    sta abs_sector_number+1

    rts

bios_0f:    ; LISTST
    lda #$ff                ; always ready
    sta regA
    rts

bios_10:    ; SECTRAN
    lda regC
    sta regA                ; no translation, also return in HL
    lda regB
    sta regH
    lda regC
    sta regL
    rts

bios_jump_table_low:
    dta l(bios_00-1), l(bios_01-1), l(bios_02-1), l(bios_03-1)
    dta l(bios_04-1), l(bios_05-1), l(bios_06-1), l(bios_07-1)
    dta l(bios_08-1), l(bios_09-1), l(bios_0a-1), l(bios_0b-1)
    dta l(bios_0c-1), l(bios_0d-1), l(bios_0e-1), l(bios_0f-1)
    dta l(bios_10-1)
bios_jump_table_high:
    dta h(bios_00-1), h(bios_01-1), h(bios_02-1), h(bios_03-1)
    dta h(bios_04-1), h(bios_05-1), h(bios_06-1), h(bios_07-1)
    dta h(bios_08-1), h(bios_09-1), h(bios_0a-1), h(bios_0b-1)
    dta h(bios_0c-1), h(bios_0d-1), h(bios_0e-1), h(bios_0f-1)
    dta h(bios_10-1)

drive_number:
    .byte 0
track_number:
    .word 0
sector_number:
    .byte 0
abs_sector_number:      ; 3-byte sector number (only 2 are used)
    .word 0
    .byte 0
dma_address:
    .word 0

; Entry point from CP/M-65. Enter with A=lsb X=msb of BIOS entrypoint

main:
    sta CPM65BIOS+1
    stx CPM65BIOS+2

    lda #$a0                ; set green background
    sta $02c6
    sta $02c8

    ldx #0
print_banner:
    lda banner,x
    ldy #CPM65_BIOS_CONOUT
    stx t8
    jsr CPM65BIOS
    ldx t8
    inx
    cpx #banner_len
    bne print_banner

    lda #<BOOTF             ; start with cold boot
    sta PCL
    ldx #>BOOTF
    stx PCH
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB

    ldy #0
    jsr run_emulator

    ldx #0
print_halted:
    lda halted,x
    ldy #CPM65_BIOS_CONOUT
    stx t8
    jsr CPM65BIOS
    ldx t8
    inx
    cpx #halted_len
    bne print_halted

    lda #0                  ; restore black background
    sta $02c6
    sta $02c8

    lda #NOBANK
    sta PORTB
    rts                     ; back to CP/M-65

CPM65BIOS:
    jmp $0000

; --------------------------------------------------------------------------

    .macro dta_EOL
        dta 13,10
    .endm

banner:
    dta 'Intel 8080 Emulator for the Atari 130XE'
    dta_EOL
    dta 'Copyright 2023,2024 by Ivo van Poorten'
    dta_EOL
    dta_EOL
banner_len = *-banner

halted:
    dta_EOL
    dta_EOL
    dta 'Emulator was halted.'
    dta_EOL
halted_len = * - halted

cpmvers:
    dta 'CP/M vers 2.2'
    dta_EOL
cpmvers_len = * - cpmvers

undefined:
    dta 'Undefined opcode encountered.'
    dta_EOL
undefined_len = *-undefined

; --------------------------------------------------------------------------

    .align $100
tab1
    .word opcode_00, opcode_01, opcode_02, opcode_03
    .word opcode_04, opcode_05, opcode_06, opcode_07
    .word opcode_08, opcode_09, opcode_0a, opcode_0b
    .word opcode_0c, opcode_0d, opcode_0e, opcode_0f
    .word opcode_10, opcode_11, opcode_12, opcode_13
    .word opcode_14, opcode_15, opcode_16, opcode_17
    .word opcode_18, opcode_19, opcode_1a, opcode_1b
    .word opcode_1c, opcode_1d, opcode_1e, opcode_1f
    .word opcode_20, opcode_21, opcode_22, opcode_23
    .word opcode_24, opcode_25, opcode_26, opcode_27
    .word opcode_28, opcode_29, opcode_2a, opcode_2b
    .word opcode_2c, opcode_2d, opcode_2e, opcode_2f
    .word opcode_30, opcode_31, opcode_32, opcode_33
    .word opcode_34, opcode_35, opcode_36, opcode_37
    .word opcode_38, opcode_39, opcode_3a, opcode_3b
    .word opcode_3c, opcode_3d, opcode_3e, opcode_3f
    .word opcode_40, opcode_41, opcode_42, opcode_43
    .word opcode_44, opcode_45, opcode_46, opcode_47
    .word opcode_48, opcode_49, opcode_4a, opcode_4b
    .word opcode_4c, opcode_4d, opcode_4e, opcode_4f
    .word opcode_50, opcode_51, opcode_52, opcode_53
    .word opcode_54, opcode_55, opcode_56, opcode_57
    .word opcode_58, opcode_59, opcode_5a, opcode_5b
    .word opcode_5c, opcode_5d, opcode_5e, opcode_5f
    .word opcode_60, opcode_61, opcode_62, opcode_63
    .word opcode_64, opcode_65, opcode_66, opcode_67
    .word opcode_68, opcode_69, opcode_6a, opcode_6b
    .word opcode_6c, opcode_6d, opcode_6e, opcode_6f
    .word opcode_70, opcode_71, opcode_72, opcode_73
    .word opcode_74, opcode_75, opcode_76, opcode_77
    .word opcode_78, opcode_79, opcode_7a, opcode_7b
    .word opcode_7c, opcode_7d, opcode_7e, opcode_7f
tab2
    .word opcode_80, opcode_81, opcode_82, opcode_83
    .word opcode_84, opcode_85, opcode_86, opcode_87
    .word opcode_88, opcode_89, opcode_8a, opcode_8b
    .word opcode_8c, opcode_8d, opcode_8e, opcode_8f
    .word opcode_90, opcode_91, opcode_92, opcode_93
    .word opcode_94, opcode_95, opcode_96, opcode_97
    .word opcode_98, opcode_99, opcode_9a, opcode_9b
    .word opcode_9c, opcode_9d, opcode_9e, opcode_9f
    .word opcode_a0, opcode_a1, opcode_a2, opcode_a3
    .word opcode_a4, opcode_a5, opcode_a6, opcode_a7
    .word opcode_a8, opcode_a9, opcode_aa, opcode_ab
    .word opcode_ac, opcode_ad, opcode_ae, opcode_af
    .word opcode_b0, opcode_b1, opcode_b2, opcode_b3
    .word opcode_b4, opcode_b5, opcode_b6, opcode_b7
    .word opcode_b8, opcode_b9, opcode_ba, opcode_bb
    .word opcode_bc, opcode_bd, opcode_be, opcode_bf
    .word opcode_c0, opcode_c1, opcode_c2, opcode_c3
    .word opcode_c4, opcode_c5, opcode_c6, opcode_c7
    .word opcode_c8, opcode_c9, opcode_ca, opcode_cb
    .word opcode_cc, opcode_cd, opcode_ce, opcode_cf
    .word opcode_d0, opcode_d1, opcode_d2, opcode_d3
    .word opcode_d4, opcode_d5, opcode_d6, opcode_d7
    .word opcode_d8, opcode_d9, opcode_da, opcode_db
    .word opcode_dc, opcode_dd, opcode_de, opcode_df
    .word opcode_e0, opcode_e1, opcode_e2, opcode_e3
    .word opcode_e4, opcode_e5, opcode_e6, opcode_e7
    .word opcode_e8, opcode_e9, opcode_ea, opcode_eb
    .word opcode_ec, opcode_ed, opcode_ee, opcode_ef
    .word opcode_f0, opcode_f1, opcode_f2, opcode_f3
    .word opcode_f4, opcode_f5, opcode_f6, opcode_f7
    .word opcode_f8, opcode_f9, opcode_fa, opcode_fb
    .word opcode_fc, opcode_fd, opcode_fe, opcode_ff

; --------------------------------------------------------------------------

msb_to_bank:
:64 dta BANK0
:64 dta BANK1
:64 dta BANK2
:64 dta BANK3

msb_to_adjusted:
:64 dta $40+#
:64 dta $40+#
:64 dta $40+#
:64 dta $40+#

; include instruction_length and zsp_table tables

    icl 'tables/tables.s'

; --------------------------------------------------------------------------

; Load CCP outside of virtual 8080 memory so it can be reloaded at will

CCP_LOAD_ADDRESS:
    ins 'cpm22/ccp.sys'

; --------------------------------------------------------------------------

    run main

