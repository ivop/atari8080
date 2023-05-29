
; Intel 8080 emulator for the Atari 130XE
; Copyright © 2023 by Ivo van Poorten
;
; mads assembler format

; bit 0 ROM, 0 = off, 1 = on
; bit 1 BASUC, 0 = on, 1 = off
; bits 2 and 3 select bank
; bits 4 and 5 enable bank switched in, bit 4 low is CPU, bit 5 low is ANTIC
; bit 6 unused
; bit 7 selftest, 0 = on, 1 = off

; set to $fe at boot (basic enabled), $ff basic disabled

    icl 'cio.s'

LMARGN = $52
RMARGN = $53
ROWCRS = $54
COLCRS = $55

COLOR2 = $02c6

PORTB = $d301

CCP   = $e400
BDOS  = $ec00
BDOSE = BDOS+6
BIOS  = $fa00

NOBANK = $ff

BANK0 = $e3 | $00 | $00
BANK1 = $e3 | $00 | $04
BANK2 = $e3 | $08 | $00
BANK3 = $e3 | $08 | $04

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
savebank = ZP+18

instruction = ZP+19     ; do we need this?
byte3       = ZP+20
byte2       = ZP+21
byte3a      = ZP+22     ; for SHLD for example (adr)<-L;(adr+1)<-H

regM    = ZP+23         ; temporary M register, optimize later
t8      = ZP+24
saveCF  = ZP+25

SF_FLAG = %10000000
ZF_FLAG = %01000000
AF_FLAG = %00010000
PF_FLAG = %00000100
ON_FLAG = %00000010     ; always on!
CF_FLAG = %00000001

ALL_FLAGS = (SF_FLAG|ZF_FLAG|AF_FLAG|PF_FLAG|ON_FLAG|CF_FLAG)

; --------------------------------------------------------------------------

; We just assume we are on a 130XE for now. atari800 -xe 8080.xex

    org $0600

set_bank0:
    lda #BANK0
    sta PORTB
    rts

    ini set_bank0

; setup low mem

    org $4000           ; 8080 memory at 00000h, bank 0

    .byte 0x76          ; HALT if WBOOT is called
    .word 0
    .byte 0xc3          ; JMP
    .word BDOSE

; load test program

    org $4100           ; 8080 memory at 00100h

    ins 'tests/8080PRE.COM'     ; 8080PRE.COM, TST8080.COM, 8080EXM.COM
                                ; CPUTEST.COM needs to be split in two
                                ; because it's larger than 03f00h bytes

; --------------------------------------------------------------------------

; Load BDOS, we don't need CCP for now.

    org $0680

set_bank3:
    lda #BANK3
    sta PORTB
    rts

    ini set_bank3

    org $4000+(BDOS&$3fff)  ; in bank 3

    ins 'cpm22/bdos.sys'

; Load BIOS. Implement same OUT port,A as in atari8080.c. CONOUT is enough
; to print messages.

    org $4000+(BIOS&$3fff)  ; in bank 3

    ins 'cpm22/bios.sys'

; --------------------------------------------------------------------------

; BIOS HERE

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

    org $8000

; Enter with Y=0!

; If an opcode really needs to use Y, it has to set it back to zero upon
; returning here!

run_emulator:
    lda (PCL),y                 ; retrieve instruction

    tax                         ; set trampoline
    lda jump_table_high,x
    pha
    lda jump_table_low,x
    pha

    lda instruction_length,x
    beq length1
    cmp #1
    beq length2

    .macro INCPC
        inc PCL             ; most of the time this is just inc+bne
        bne no_inc_pch
            inc PCH         ; each page crossing it's four instructions
            inc PCHa        ; longer
            bit PCHa
            bpl no_adjust   ; except for when we are at the end of the bank
                ldx PCH
                lda msb_to_bank,x
                sta curbank
                sta PORTB
                lda msb_to_adjusted,x
                sta PCHa
no_adjust:
no_inc_pch:
    .endm

length3:
    INCPC
    lda (PCL),y
    sta byte2

    INCPC
    lda (PCL),y
    sta byte3

    jmp length1

length2:
    INCPC
    lda (PCL),y
    sta byte2

    ; fallthrough

length1:
    INCPC

    rts            ; upon entering the opcode emulation, Y is always 0

                   ; shortest path is 12 6502 instructions

; --------------------------------------------------------------------------

opcode_00: ; NOP
    jmp run_emulator

    ; ######################### LXI #########################
    ; LXI XY       X <- byte3; Y <- byte2

    .macro LXI regX, regY
        lda byte3
        sta :regX
        lda byte2
        sta :regY
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
    mem_write_no_curbank_restore byte2, byte3, regL
    inc byte2
    bne @+
    inc byte3
@:
    mem_write byte2, byte3, regH        ; here curbank/PORTB is restored
    jmp run_emulator

opcode_32:  ; STA adr ---- (adr) <- A
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
        lda byte2
        sta :REG
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
    mem_read_no_curbank_restore byte2, byte3, regL
    inc byte2
    bne @+
    inc byte3
@:
    mem_read byte2, byte3, regH     ; restores curbank
    jmp run_emulator

opcode_3a:  ; // LDA adr ---- A <- (adr)
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
    DCX SPL,SPH
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
        lda :dst
        sta :src
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
        ora #~AF_FLAG

@4:
        and #~(SF_FLAG|ZF_FLAG|PF_FLAG)
        ora zsp_table,x
        sta regF

        stx regA
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
    clc
    rol regA
    lda regA
    adc #1
    sta regA
    bcc @1

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
    ora #~ON_FLAG
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
    beq _JMP
    jmp run_emulator

opcode_ca:
    lda regF
    and #ZF_FLAG
    bne _JMP
    jmp run_emulator

opcode_d2:
    lda regF
    and #CF_FLAG
    beq _JMP
    jmp run_emulator

opcode_da:
    lda regF
    and #CF_FLAG
    bne _JMP
    jmp run_emulator

opcode_e2:
    lda regF
    and #PF_FLAG
    beq _JMP
    jmp run_emulator

opcode_ea:
    lda regF
    and #PF_FLAG
    bne _JMP
    jmp run_emulator

opcode_f2:
    lda regF
    and #SF_FLAG
    beq _JMP
    jmp run_emulator

opcode_fa:
    lda regF
    and #SF_FLAG
    bne _JMP
    jmp run_emulator

_JMP:
opcode_c3: ; JMP
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
    beq CALL
    jmp run_emulator

opcode_cc:
    lda regF
    and #ZF_FLAG
    bne CALL
    jmp run_emulator

opcode_d4:
    lda regF
    and #CF_FLAG
    beq CALL
    jmp run_emulator

opcode_dc:
    lda regF
    and #CF_FLAG
    bne CALL
    jmp run_emulator

opcode_e4:
    lda regF
    and #PF_FLAG
    beq CALL
    jmp run_emulator

opcode_ec:
    lda regF
    and #PF_FLAG
    bne CALL
    jmp run_emulator

opcode_f4:
    lda regF
    and #SF_FLAG
    beq CALL
    jmp run_emulator

opcode_fc:
    lda regF
    and #SF_FLAG
    bne CALL
    jmp run_emulator

CALL:
opcode_cd:  ; CALL
    KIL
    jmp run_emulator

opcode_c7:  ; RST0
    lda #0
    sta byte3
    sta byte2
    beq CALL

opcode_cf:  ; etc...
    lda #0
    sta byte3
    lda #$08
    sta byte2
    bne CALL

opcode_d7:
    lda #0
    sta byte3
    lda #$10
    sta byte2
    bne CALL

opcode_df:
    lda #0
    sta byte3
    lda #$18
    sta byte2
    bne CALL

opcode_e7:
    lda #0
    sta byte3
    lda #$20
    sta byte2
    bne CALL

opcode_ef:
    lda #0
    sta byte3
    lda #$28
    sta byte2
    bne CALL

opcode_f7:
    lda #0
    sta byte3
    lda #$30
    sta byte2
    bne CALL

opcode_ff:
    lda #0
    sta byte3
    lda #$38
    sta byte2
    bne CALL

    ; ######################### IMMEDIATE #########################
    ; func byte2
opcode_c6:          ; ADI
    _ADD byte2
    jmp run_emulator

opcode_ce:          ; ACI
    _ADC byte2
    jmp run_emulator

opcode_d6:          ; SUI
    _SUB byte2
    jmp run_emulator

opcode_de:          ; SBI
    _SBC byte2
    jmp run_emulator

opcode_e6:          ; ANI
    ANA byte2
    jmp run_emulator

opcode_ee:          ; XRI
    XRA byte2
    jmp run_emulator

opcode_f6:          ; ORI
    _ORA byte2
    jmp run_emulator

opcode_fe:          ; CPI
    _CMP byte2
    jmp run_emulator

    ; ######################### XTHL/XCHG #########################
    ;
opcode_e3:  ; XTHL ---- L <-> (SP);H <-> (SP+1)
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
opcode_e9:
    KIL
    jmp run_emulator
opcode_f9:
    KIL
    jmp run_emulator

    ; ######################### OUT/IN #########################
    ;
opcode_d3:
    KIL
    jmp run_emulator

opcode_db:
    KIL
    jmp run_emulator

    ; ######################### EI/DI #########################
    ;
opcode_f3:
    KIL
    jmp run_emulator

opcode_fb:
    KIL
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
    bput 0, undefined_len, undefined
    rts

; --------------------------------------------------------------------------

; SETUP EMULATOR

main:
    lda #0
    sta LMARGN
    sta COLCRS
    sta COLOR2

    ; print banner

    bput 0, banner_len, banner

    ; 8080 memory is already setup by the loader

    ; set PC to test program

    lda #0
    sta PCL
    lda #$01
    sta PCH

    tax
    lda msb_to_adjusted,x
    sta PCHa
    lda msb_to_bank,x
    sta curbank
    sta PORTB

    lda #ON_FLAG            ; always on, never zeroed (if the code is correct)
    sta regF

    ldy #0                  ; Always enter emulation loop with Y=0

    jsr run_emulator

    bput 0, halted_len, halted

    jmp *

; --------------------------------------------------------------------------

banner:
    dta 'Intel 8080 Emulator for the 130XE', $9b
    dta 'Copyright (C) 2023 by Ivo van Poorten', $9b
banner_len = *-banner

halted:
    dta 'Emulator was halted.', $9b
halted_len = * - halted

undefined:
    dta 'Undefined opcode encountered.', $9b
undefined_len = *-undefined

; --------------------------------------------------------------------------

; put tables before banked memory

    org $3000

jump_table_low:
    dta l(opcode_00-1), l(opcode_01-1), l(opcode_02-1), l(opcode_03-1)
    dta l(opcode_04-1), l(opcode_05-1), l(opcode_06-1), l(opcode_07-1)
    dta l(opcode_08-1), l(opcode_09-1), l(opcode_0a-1), l(opcode_0b-1)
    dta l(opcode_0c-1), l(opcode_0d-1), l(opcode_0e-1), l(opcode_0f-1)
    dta l(opcode_10-1), l(opcode_11-1), l(opcode_12-1), l(opcode_13-1)
    dta l(opcode_14-1), l(opcode_15-1), l(opcode_16-1), l(opcode_17-1)
    dta l(opcode_18-1), l(opcode_19-1), l(opcode_1a-1), l(opcode_1b-1)
    dta l(opcode_1c-1), l(opcode_1d-1), l(opcode_1e-1), l(opcode_1f-1)
    dta l(opcode_20-1), l(opcode_21-1), l(opcode_22-1), l(opcode_23-1)
    dta l(opcode_24-1), l(opcode_25-1), l(opcode_26-1), l(opcode_27-1)
    dta l(opcode_28-1), l(opcode_29-1), l(opcode_2a-1), l(opcode_2b-1)
    dta l(opcode_2c-1), l(opcode_2d-1), l(opcode_2e-1), l(opcode_2f-1)
    dta l(opcode_30-1), l(opcode_31-1), l(opcode_32-1), l(opcode_33-1)
    dta l(opcode_34-1), l(opcode_35-1), l(opcode_36-1), l(opcode_37-1)
    dta l(opcode_38-1), l(opcode_39-1), l(opcode_3a-1), l(opcode_3b-1)
    dta l(opcode_3c-1), l(opcode_3d-1), l(opcode_3e-1), l(opcode_3f-1)
    dta l(opcode_40-1), l(opcode_41-1), l(opcode_42-1), l(opcode_43-1)
    dta l(opcode_44-1), l(opcode_45-1), l(opcode_46-1), l(opcode_47-1)
    dta l(opcode_48-1), l(opcode_49-1), l(opcode_4a-1), l(opcode_4b-1)
    dta l(opcode_4c-1), l(opcode_4d-1), l(opcode_4e-1), l(opcode_4f-1)
    dta l(opcode_50-1), l(opcode_51-1), l(opcode_52-1), l(opcode_53-1)
    dta l(opcode_54-1), l(opcode_55-1), l(opcode_56-1), l(opcode_57-1)
    dta l(opcode_58-1), l(opcode_59-1), l(opcode_5a-1), l(opcode_5b-1)
    dta l(opcode_5c-1), l(opcode_5d-1), l(opcode_5e-1), l(opcode_5f-1)
    dta l(opcode_60-1), l(opcode_61-1), l(opcode_62-1), l(opcode_63-1)
    dta l(opcode_64-1), l(opcode_65-1), l(opcode_66-1), l(opcode_67-1)
    dta l(opcode_68-1), l(opcode_69-1), l(opcode_6a-1), l(opcode_6b-1)
    dta l(opcode_6c-1), l(opcode_6d-1), l(opcode_6e-1), l(opcode_6f-1)
    dta l(opcode_70-1), l(opcode_71-1), l(opcode_72-1), l(opcode_73-1)
    dta l(opcode_74-1), l(opcode_75-1), l(opcode_76-1), l(opcode_77-1)
    dta l(opcode_78-1), l(opcode_79-1), l(opcode_7a-1), l(opcode_7b-1)
    dta l(opcode_7c-1), l(opcode_7d-1), l(opcode_7e-1), l(opcode_7f-1)
    dta l(opcode_80-1), l(opcode_81-1), l(opcode_82-1), l(opcode_83-1)
    dta l(opcode_84-1), l(opcode_85-1), l(opcode_86-1), l(opcode_87-1)
    dta l(opcode_88-1), l(opcode_89-1), l(opcode_8a-1), l(opcode_8b-1)
    dta l(opcode_8c-1), l(opcode_8d-1), l(opcode_8e-1), l(opcode_8f-1)
    dta l(opcode_90-1), l(opcode_91-1), l(opcode_92-1), l(opcode_93-1)
    dta l(opcode_94-1), l(opcode_95-1), l(opcode_96-1), l(opcode_97-1)
    dta l(opcode_98-1), l(opcode_99-1), l(opcode_9a-1), l(opcode_9b-1)
    dta l(opcode_9c-1), l(opcode_9d-1), l(opcode_9e-1), l(opcode_9f-1)
    dta l(opcode_a0-1), l(opcode_a1-1), l(opcode_a2-1), l(opcode_a3-1)
    dta l(opcode_a4-1), l(opcode_a5-1), l(opcode_a6-1), l(opcode_a7-1)
    dta l(opcode_a8-1), l(opcode_a9-1), l(opcode_aa-1), l(opcode_ab-1)
    dta l(opcode_ac-1), l(opcode_ad-1), l(opcode_ae-1), l(opcode_af-1)
    dta l(opcode_b0-1), l(opcode_b1-1), l(opcode_b2-1), l(opcode_b3-1)
    dta l(opcode_b4-1), l(opcode_b5-1), l(opcode_b6-1), l(opcode_b7-1)
    dta l(opcode_b8-1), l(opcode_b9-1), l(opcode_ba-1), l(opcode_bb-1)
    dta l(opcode_bc-1), l(opcode_bd-1), l(opcode_be-1), l(opcode_bf-1)
    dta l(opcode_c0-1), l(opcode_c1-1), l(opcode_c2-1), l(opcode_c3-1)
    dta l(opcode_c4-1), l(opcode_c5-1), l(opcode_c6-1), l(opcode_c7-1)
    dta l(opcode_c8-1), l(opcode_c9-1), l(opcode_ca-1), l(opcode_cb-1)
    dta l(opcode_cc-1), l(opcode_cd-1), l(opcode_ce-1), l(opcode_cf-1)
    dta l(opcode_d0-1), l(opcode_d1-1), l(opcode_d2-1), l(opcode_d3-1)
    dta l(opcode_d4-1), l(opcode_d5-1), l(opcode_d6-1), l(opcode_d7-1)
    dta l(opcode_d8-1), l(opcode_d9-1), l(opcode_da-1), l(opcode_db-1)
    dta l(opcode_dc-1), l(opcode_dd-1), l(opcode_de-1), l(opcode_df-1)
    dta l(opcode_e0-1), l(opcode_e1-1), l(opcode_e2-1), l(opcode_e3-1)
    dta l(opcode_e4-1), l(opcode_e5-1), l(opcode_e6-1), l(opcode_e7-1)
    dta l(opcode_e8-1), l(opcode_e9-1), l(opcode_ea-1), l(opcode_eb-1)
    dta l(opcode_ec-1), l(opcode_ed-1), l(opcode_ee-1), l(opcode_ef-1)
    dta l(opcode_f0-1), l(opcode_f1-1), l(opcode_f2-1), l(opcode_f3-1)
    dta l(opcode_f4-1), l(opcode_f5-1), l(opcode_f6-1), l(opcode_f7-1)
    dta l(opcode_f8-1), l(opcode_f9-1), l(opcode_fa-1), l(opcode_fb-1)
    dta l(opcode_fc-1), l(opcode_fd-1), l(opcode_fe-1), l(opcode_ff-1)

jump_table_high:
    dta h(opcode_00-1), h(opcode_01-1), h(opcode_02-1), h(opcode_03-1)
    dta h(opcode_04-1), h(opcode_05-1), h(opcode_06-1), h(opcode_07-1)
    dta h(opcode_08-1), h(opcode_09-1), h(opcode_0a-1), h(opcode_0b-1)
    dta h(opcode_0c-1), h(opcode_0d-1), h(opcode_0e-1), h(opcode_0f-1)
    dta h(opcode_10-1), h(opcode_11-1), h(opcode_12-1), h(opcode_13-1)
    dta h(opcode_14-1), h(opcode_15-1), h(opcode_16-1), h(opcode_17-1)
    dta h(opcode_18-1), h(opcode_19-1), h(opcode_1a-1), h(opcode_1b-1)
    dta h(opcode_1c-1), h(opcode_1d-1), h(opcode_1e-1), h(opcode_1f-1)
    dta h(opcode_20-1), h(opcode_21-1), h(opcode_22-1), h(opcode_23-1)
    dta h(opcode_24-1), h(opcode_25-1), h(opcode_26-1), h(opcode_27-1)
    dta h(opcode_28-1), h(opcode_29-1), h(opcode_2a-1), h(opcode_2b-1)
    dta h(opcode_2c-1), h(opcode_2d-1), h(opcode_2e-1), h(opcode_2f-1)
    dta h(opcode_30-1), h(opcode_31-1), h(opcode_32-1), h(opcode_33-1)
    dta h(opcode_34-1), h(opcode_35-1), h(opcode_36-1), h(opcode_37-1)
    dta h(opcode_38-1), h(opcode_39-1), h(opcode_3a-1), h(opcode_3b-1)
    dta h(opcode_3c-1), h(opcode_3d-1), h(opcode_3e-1), h(opcode_3f-1)
    dta h(opcode_40-1), h(opcode_41-1), h(opcode_42-1), h(opcode_43-1)
    dta h(opcode_44-1), h(opcode_45-1), h(opcode_46-1), h(opcode_47-1)
    dta h(opcode_48-1), h(opcode_49-1), h(opcode_4a-1), h(opcode_4b-1)
    dta h(opcode_4c-1), h(opcode_4d-1), h(opcode_4e-1), h(opcode_4f-1)
    dta h(opcode_50-1), h(opcode_51-1), h(opcode_52-1), h(opcode_53-1)
    dta h(opcode_54-1), h(opcode_55-1), h(opcode_56-1), h(opcode_57-1)
    dta h(opcode_58-1), h(opcode_59-1), h(opcode_5a-1), h(opcode_5b-1)
    dta h(opcode_5c-1), h(opcode_5d-1), h(opcode_5e-1), h(opcode_5f-1)
    dta h(opcode_60-1), h(opcode_61-1), h(opcode_62-1), h(opcode_63-1)
    dta h(opcode_64-1), h(opcode_65-1), h(opcode_66-1), h(opcode_67-1)
    dta h(opcode_68-1), h(opcode_69-1), h(opcode_6a-1), h(opcode_6b-1)
    dta h(opcode_6c-1), h(opcode_6d-1), h(opcode_6e-1), h(opcode_6f-1)
    dta h(opcode_70-1), h(opcode_71-1), h(opcode_72-1), h(opcode_73-1)
    dta h(opcode_74-1), h(opcode_75-1), h(opcode_76-1), h(opcode_77-1)
    dta h(opcode_78-1), h(opcode_79-1), h(opcode_7a-1), h(opcode_7b-1)
    dta h(opcode_7c-1), h(opcode_7d-1), h(opcode_7e-1), h(opcode_7f-1)
    dta h(opcode_80-1), h(opcode_81-1), h(opcode_82-1), h(opcode_83-1)
    dta h(opcode_84-1), h(opcode_85-1), h(opcode_86-1), h(opcode_87-1)
    dta h(opcode_88-1), h(opcode_89-1), h(opcode_8a-1), h(opcode_8b-1)
    dta h(opcode_8c-1), h(opcode_8d-1), h(opcode_8e-1), h(opcode_8f-1)
    dta h(opcode_90-1), h(opcode_91-1), h(opcode_92-1), h(opcode_93-1)
    dta h(opcode_94-1), h(opcode_95-1), h(opcode_96-1), h(opcode_97-1)
    dta h(opcode_98-1), h(opcode_99-1), h(opcode_9a-1), h(opcode_9b-1)
    dta h(opcode_9c-1), h(opcode_9d-1), h(opcode_9e-1), h(opcode_9f-1)
    dta h(opcode_a0-1), h(opcode_a1-1), h(opcode_a2-1), h(opcode_a3-1)
    dta h(opcode_a4-1), h(opcode_a5-1), h(opcode_a6-1), h(opcode_a7-1)
    dta h(opcode_a8-1), h(opcode_a9-1), h(opcode_aa-1), h(opcode_ab-1)
    dta h(opcode_ac-1), h(opcode_ad-1), h(opcode_ae-1), h(opcode_af-1)
    dta h(opcode_b0-1), h(opcode_b1-1), h(opcode_b2-1), h(opcode_b3-1)
    dta h(opcode_b4-1), h(opcode_b5-1), h(opcode_b6-1), h(opcode_b7-1)
    dta h(opcode_b8-1), h(opcode_b9-1), h(opcode_ba-1), h(opcode_bb-1)
    dta h(opcode_bc-1), h(opcode_bd-1), h(opcode_be-1), h(opcode_bf-1)
    dta h(opcode_c0-1), h(opcode_c1-1), h(opcode_c2-1), h(opcode_c3-1)
    dta h(opcode_c4-1), h(opcode_c5-1), h(opcode_c6-1), h(opcode_c7-1)
    dta h(opcode_c8-1), h(opcode_c9-1), h(opcode_ca-1), h(opcode_cb-1)
    dta h(opcode_cc-1), h(opcode_cd-1), h(opcode_ce-1), h(opcode_cf-1)
    dta h(opcode_d0-1), h(opcode_d1-1), h(opcode_d2-1), h(opcode_d3-1)
    dta h(opcode_d4-1), h(opcode_d5-1), h(opcode_d6-1), h(opcode_d7-1)
    dta h(opcode_d8-1), h(opcode_d9-1), h(opcode_da-1), h(opcode_db-1)
    dta h(opcode_dc-1), h(opcode_dd-1), h(opcode_de-1), h(opcode_df-1)
    dta h(opcode_e0-1), h(opcode_e1-1), h(opcode_e2-1), h(opcode_e3-1)
    dta h(opcode_e4-1), h(opcode_e5-1), h(opcode_e6-1), h(opcode_e7-1)
    dta h(opcode_e8-1), h(opcode_e9-1), h(opcode_ea-1), h(opcode_eb-1)
    dta h(opcode_ec-1), h(opcode_ed-1), h(opcode_ee-1), h(opcode_ef-1)
    dta h(opcode_f0-1), h(opcode_f1-1), h(opcode_f2-1), h(opcode_f3-1)
    dta h(opcode_f4-1), h(opcode_f5-1), h(opcode_f6-1), h(opcode_f7-1)
    dta h(opcode_f8-1), h(opcode_f9-1), h(opcode_fa-1), h(opcode_fb-1)
    dta h(opcode_fc-1), h(opcode_fd-1), h(opcode_fe-1), h(opcode_ff-1)

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

    run main

