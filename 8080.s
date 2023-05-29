
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

SF_FLAG = %10000000
ZF_FLAG = %01000000
AF_FLAG = %00010000
PF_FLAG = %00000100
ON_FLAG = %00000010     ; always on!
CF_FLAG = %00000001

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

run_emulator:
    ldy #0
    lda (PCL),y                 ; retrieve instruction

    tax                         ; set trampoline
    lda jump_table_low,x
    sta trampoline
    lda jump_table_high,x
    sta trampoline+1

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

trampoline = *+1
    jmp opcode_00   ; upon entering the opcode emulation, Y is always 0

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
    bne no_inc_byte3
    inc byte3
no_inc_byte3:
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
    ; INR reg = reg + 1                 [Z,S,P,AC]

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
    INR regM
    txa             ; still in X
    sta (regL),y    ; mem_read has setup the adjusted register and bank
    lda curbank
    sta PORTB
    jmp run_emulator

opcode_3c:
    INR regA
    jmp run_emulator

    ; ------------------------ unimplemented ------------------

opcode_05:
    KIL
    jmp run_emulator

opcode_06:
    KIL
    jmp run_emulator

opcode_07:
    KIL
    jmp run_emulator

opcode_08:
    KIL
    jmp run_emulator

opcode_09:
    KIL
    jmp run_emulator

opcode_0a:
    KIL
    jmp run_emulator

opcode_0b:
    KIL
    jmp run_emulator

opcode_0d:
    KIL
    jmp run_emulator

opcode_0e:
    KIL
    jmp run_emulator

opcode_0f:
    KIL
    jmp run_emulator

opcode_10:
    KIL
    jmp run_emulator

opcode_15:
    KIL
    jmp run_emulator

opcode_16:
    KIL
    jmp run_emulator

opcode_17:
    KIL
    jmp run_emulator

opcode_18:
    KIL
    jmp run_emulator

opcode_19:
    KIL
    jmp run_emulator

opcode_1a:
    KIL
    jmp run_emulator

opcode_1b:
    KIL
    jmp run_emulator

opcode_1d:
    KIL
    jmp run_emulator

opcode_1e:
    KIL
    jmp run_emulator

opcode_1f:
    KIL
    jmp run_emulator

opcode_20:
    KIL
    jmp run_emulator

opcode_25:
    KIL
    jmp run_emulator

opcode_26:
    KIL
    jmp run_emulator

opcode_27:
    KIL
    jmp run_emulator

opcode_28:
    KIL
    jmp run_emulator

opcode_29:
    KIL
    jmp run_emulator

opcode_2a:
    KIL
    jmp run_emulator

opcode_2b:
    KIL
    jmp run_emulator

opcode_2d:
    KIL
    jmp run_emulator

opcode_2e:
    KIL
    jmp run_emulator

opcode_2f:
    KIL
    jmp run_emulator

opcode_30:
    KIL
    jmp run_emulator

opcode_35:
    KIL
    jmp run_emulator

opcode_36:
    KIL
    jmp run_emulator

opcode_37:
    KIL
    jmp run_emulator

opcode_38:
    KIL
    jmp run_emulator

opcode_39:
    KIL
    jmp run_emulator

opcode_3a:
    KIL
    jmp run_emulator

opcode_3b:
    KIL
    jmp run_emulator

opcode_3d:
    KIL
    jmp run_emulator

opcode_3e:
    KIL
    jmp run_emulator

opcode_3f:
    KIL
    jmp run_emulator

opcode_40:
    KIL
    jmp run_emulator

opcode_41:
    KIL
    jmp run_emulator

opcode_42:
    KIL
    jmp run_emulator

opcode_43:
    KIL
    jmp run_emulator

opcode_44:
    KIL
    jmp run_emulator

opcode_45:
    KIL
    jmp run_emulator

opcode_46:
    KIL
    jmp run_emulator

opcode_47:
    KIL
    jmp run_emulator

opcode_48:
    KIL
    jmp run_emulator

opcode_49:
    KIL
    jmp run_emulator

opcode_4a:
    KIL
    jmp run_emulator

opcode_4b:
    KIL
    jmp run_emulator

opcode_4c:
    KIL
    jmp run_emulator

opcode_4d:
    KIL
    jmp run_emulator

opcode_4e:
    KIL
    jmp run_emulator

opcode_4f:
    KIL
    jmp run_emulator

opcode_50:
    KIL
    jmp run_emulator

opcode_51:
    KIL
    jmp run_emulator

opcode_52:
    KIL
    jmp run_emulator

opcode_53:
    KIL
    jmp run_emulator

opcode_54:
    KIL
    jmp run_emulator

opcode_55:
    KIL
    jmp run_emulator

opcode_56:
    KIL
    jmp run_emulator

opcode_57:
    KIL
    jmp run_emulator

opcode_58:
    KIL
    jmp run_emulator

opcode_59:
    KIL
    jmp run_emulator

opcode_5a:
    KIL
    jmp run_emulator

opcode_5b:
    KIL
    jmp run_emulator

opcode_5c:
    KIL
    jmp run_emulator

opcode_5d:
    KIL
    jmp run_emulator

opcode_5e:
    KIL
    jmp run_emulator

opcode_5f:
    KIL
    jmp run_emulator

opcode_60:
    KIL
    jmp run_emulator

opcode_61:
    KIL
    jmp run_emulator

opcode_62:
    KIL
    jmp run_emulator

opcode_63:
    KIL
    jmp run_emulator

opcode_64:
    KIL
    jmp run_emulator

opcode_65:
    KIL
    jmp run_emulator

opcode_66:
    KIL
    jmp run_emulator

opcode_67:
    KIL
    jmp run_emulator

opcode_68:
    KIL
    jmp run_emulator

opcode_69:
    KIL
    jmp run_emulator

opcode_6a:
    KIL
    jmp run_emulator

opcode_6b:
    KIL
    jmp run_emulator

opcode_6c:
    KIL
    jmp run_emulator

opcode_6d:
    KIL
    jmp run_emulator

opcode_6e:
    KIL
    jmp run_emulator

opcode_6f:
    KIL
    jmp run_emulator

opcode_70:
    KIL
    jmp run_emulator

opcode_71:
    KIL
    jmp run_emulator

opcode_72:
    KIL
    jmp run_emulator

opcode_73:
    KIL
    jmp run_emulator

opcode_74:
    KIL
    jmp run_emulator

opcode_75:
    KIL
    jmp run_emulator

opcode_76:
    KIL
    jmp run_emulator

opcode_77:
    KIL
    jmp run_emulator

opcode_78:
    KIL
    jmp run_emulator

opcode_79:
    KIL
    jmp run_emulator

opcode_7a:
    KIL
    jmp run_emulator

opcode_7b:
    KIL
    jmp run_emulator

opcode_7c:
    KIL
    jmp run_emulator

opcode_7d:
    KIL
    jmp run_emulator

opcode_7e:
    KIL
    jmp run_emulator

opcode_7f:
    KIL
    jmp run_emulator

opcode_80:
    KIL
    jmp run_emulator

opcode_81:
    KIL
    jmp run_emulator

opcode_82:
    KIL
    jmp run_emulator

opcode_83:
    KIL
    jmp run_emulator

opcode_84:
    KIL
    jmp run_emulator

opcode_85:
    KIL
    jmp run_emulator

opcode_86:
    KIL
    jmp run_emulator

opcode_87:
    KIL
    jmp run_emulator

opcode_88:
    KIL
    jmp run_emulator

opcode_89:
    KIL
    jmp run_emulator

opcode_8a:
    KIL
    jmp run_emulator

opcode_8b:
    KIL
    jmp run_emulator

opcode_8c:
    KIL
    jmp run_emulator

opcode_8d:
    KIL
    jmp run_emulator

opcode_8e:
    KIL
    jmp run_emulator

opcode_8f:
    KIL
    jmp run_emulator

opcode_90:
    KIL
    jmp run_emulator

opcode_91:
    KIL
    jmp run_emulator

opcode_92:
    KIL
    jmp run_emulator

opcode_93:
    KIL
    jmp run_emulator

opcode_94:
    KIL
    jmp run_emulator

opcode_95:
    KIL
    jmp run_emulator

opcode_96:
    KIL
    jmp run_emulator

opcode_97:
    KIL
    jmp run_emulator

opcode_98:
    KIL
    jmp run_emulator

opcode_99:
    KIL
    jmp run_emulator

opcode_9a:
    KIL
    jmp run_emulator

opcode_9b:
    KIL
    jmp run_emulator

opcode_9c:
    KIL
    jmp run_emulator

opcode_9d:
    KIL
    jmp run_emulator

opcode_9e:
    KIL
    jmp run_emulator

opcode_9f:
    KIL
    jmp run_emulator

opcode_a0:
    KIL
    jmp run_emulator

opcode_a1:
    KIL
    jmp run_emulator

opcode_a2:
    KIL
    jmp run_emulator

opcode_a3:
    KIL
    jmp run_emulator

opcode_a4:
    KIL
    jmp run_emulator

opcode_a5:
    KIL
    jmp run_emulator

opcode_a6:
    KIL
    jmp run_emulator

opcode_a7:
    KIL
    jmp run_emulator

opcode_a8:
    KIL
    jmp run_emulator

opcode_a9:
    KIL
    jmp run_emulator

opcode_aa:
    KIL
    jmp run_emulator

opcode_ab:
    KIL
    jmp run_emulator

opcode_ac:
    KIL
    jmp run_emulator

opcode_ad:
    KIL
    jmp run_emulator

opcode_ae:
    KIL
    jmp run_emulator

opcode_af:
    KIL
    jmp run_emulator

opcode_b0:
    KIL
    jmp run_emulator

opcode_b1:
    KIL
    jmp run_emulator

opcode_b2:
    KIL
    jmp run_emulator

opcode_b3:
    KIL
    jmp run_emulator

opcode_b4:
    KIL
    jmp run_emulator

opcode_b5:
    KIL
    jmp run_emulator

opcode_b6:
    KIL
    jmp run_emulator

opcode_b7:
    KIL
    jmp run_emulator

opcode_b8:
    KIL
    jmp run_emulator

opcode_b9:
    KIL
    jmp run_emulator

opcode_ba:
    KIL
    jmp run_emulator

opcode_bb:
    KIL
    jmp run_emulator

opcode_bc:
    KIL
    jmp run_emulator

opcode_bd:
    KIL
    jmp run_emulator

opcode_be:
    KIL
    jmp run_emulator

opcode_bf:
    KIL
    jmp run_emulator

opcode_c0:
    KIL
    jmp run_emulator

opcode_c1:
    KIL
    jmp run_emulator

opcode_c2:
    KIL
    jmp run_emulator

opcode_c3:
    KIL
    jmp run_emulator

opcode_c4:
    KIL
    jmp run_emulator

opcode_c5:
    KIL
    jmp run_emulator

opcode_c6:
    KIL
    jmp run_emulator

opcode_c7:
    KIL
    jmp run_emulator

opcode_c8:
    KIL
    jmp run_emulator

opcode_c9:
    KIL
    jmp run_emulator

opcode_ca:
    KIL
    jmp run_emulator

opcode_cb:
    KIL
    jmp run_emulator

opcode_cc:
    KIL
    jmp run_emulator

opcode_cd:
    KIL
    jmp run_emulator

opcode_ce:
    KIL
    jmp run_emulator

opcode_cf:
    KIL
    jmp run_emulator

opcode_d0:
    KIL
    jmp run_emulator

opcode_d1:
    KIL
    jmp run_emulator

opcode_d2:
    KIL
    jmp run_emulator

opcode_d3:
    KIL
    jmp run_emulator

opcode_d4:
    KIL
    jmp run_emulator

opcode_d5:
    KIL
    jmp run_emulator

opcode_d6:
    KIL
    jmp run_emulator

opcode_d7:
    KIL
    jmp run_emulator

opcode_d8:
    KIL
    jmp run_emulator

opcode_d9:
    KIL
    jmp run_emulator

opcode_da:
    KIL
    jmp run_emulator

opcode_db:
    KIL
    jmp run_emulator

opcode_dc:
    KIL
    jmp run_emulator

opcode_dd:
    KIL
    jmp run_emulator

opcode_de:
    KIL
    jmp run_emulator

opcode_df:
    KIL
    jmp run_emulator

opcode_e0:
    KIL
    jmp run_emulator

opcode_e1:
    KIL
    jmp run_emulator

opcode_e2:
    KIL
    jmp run_emulator

opcode_e3:
    KIL
    jmp run_emulator

opcode_e4:
    KIL
    jmp run_emulator

opcode_e5:
    KIL
    jmp run_emulator

opcode_e6:
    KIL
    jmp run_emulator

opcode_e7:
    KIL
    jmp run_emulator

opcode_e8:
    KIL
    jmp run_emulator

opcode_e9:
    KIL
    jmp run_emulator

opcode_ea:
    KIL
    jmp run_emulator

opcode_eb:
    KIL
    jmp run_emulator

opcode_ec:
    KIL
    jmp run_emulator

opcode_ed:
    KIL
    jmp run_emulator

opcode_ee:
    KIL
    jmp run_emulator

opcode_ef:
    KIL
    jmp run_emulator

opcode_f0:
    KIL
    jmp run_emulator

opcode_f1:
    KIL
    jmp run_emulator

opcode_f2:
    KIL
    jmp run_emulator

opcode_f3:
    KIL
    jmp run_emulator

opcode_f4:
    KIL
    jmp run_emulator

opcode_f5:
    KIL
    jmp run_emulator

opcode_f6:
    KIL
    jmp run_emulator

opcode_f7:
    KIL
    jmp run_emulator

opcode_f8:
    KIL
    jmp run_emulator

opcode_f9:
    KIL
    jmp run_emulator

opcode_fa:
    KIL
    jmp run_emulator

opcode_fb:
    KIL
    jmp run_emulator

opcode_fc:
    KIL
    jmp run_emulator

opcode_fd:
    KIL
    jmp run_emulator

opcode_fe:
    KIL
    jmp run_emulator

opcode_ff:
    KIL
    jmp run_emulator

; --------------------------------------------------------------------------

; SETUP EMULATOR

run:
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

; --------------------------------------------------------------------------

; put tables before banked memory

    org $3000

jump_table_low:
    dta l(opcode_00), l(opcode_01), l(opcode_02), l(opcode_03)
    dta l(opcode_04), l(opcode_05), l(opcode_06), l(opcode_07)
    dta l(opcode_08), l(opcode_09), l(opcode_0a), l(opcode_0b)
    dta l(opcode_0c), l(opcode_0d), l(opcode_0e), l(opcode_0f)
    dta l(opcode_10), l(opcode_11), l(opcode_12), l(opcode_13)
    dta l(opcode_14), l(opcode_15), l(opcode_16), l(opcode_17)
    dta l(opcode_18), l(opcode_19), l(opcode_1a), l(opcode_1b)
    dta l(opcode_1c), l(opcode_1d), l(opcode_1e), l(opcode_1f)
    dta l(opcode_20), l(opcode_21), l(opcode_22), l(opcode_23)
    dta l(opcode_24), l(opcode_25), l(opcode_26), l(opcode_27)
    dta l(opcode_28), l(opcode_29), l(opcode_2a), l(opcode_2b)
    dta l(opcode_2c), l(opcode_2d), l(opcode_2e), l(opcode_2f)
    dta l(opcode_30), l(opcode_31), l(opcode_32), l(opcode_33)
    dta l(opcode_34), l(opcode_35), l(opcode_36), l(opcode_37)
    dta l(opcode_38), l(opcode_39), l(opcode_3a), l(opcode_3b)
    dta l(opcode_3c), l(opcode_3d), l(opcode_3e), l(opcode_3f)
    dta l(opcode_40), l(opcode_41), l(opcode_42), l(opcode_43)
    dta l(opcode_44), l(opcode_45), l(opcode_46), l(opcode_47)
    dta l(opcode_48), l(opcode_49), l(opcode_4a), l(opcode_4b)
    dta l(opcode_4c), l(opcode_4d), l(opcode_4e), l(opcode_4f)
    dta l(opcode_50), l(opcode_51), l(opcode_52), l(opcode_53)
    dta l(opcode_54), l(opcode_55), l(opcode_56), l(opcode_57)
    dta l(opcode_58), l(opcode_59), l(opcode_5a), l(opcode_5b)
    dta l(opcode_5c), l(opcode_5d), l(opcode_5e), l(opcode_5f)
    dta l(opcode_60), l(opcode_61), l(opcode_62), l(opcode_63)
    dta l(opcode_64), l(opcode_65), l(opcode_66), l(opcode_67)
    dta l(opcode_68), l(opcode_69), l(opcode_6a), l(opcode_6b)
    dta l(opcode_6c), l(opcode_6d), l(opcode_6e), l(opcode_6f)
    dta l(opcode_70), l(opcode_71), l(opcode_72), l(opcode_73)
    dta l(opcode_74), l(opcode_75), l(opcode_76), l(opcode_77)
    dta l(opcode_78), l(opcode_79), l(opcode_7a), l(opcode_7b)
    dta l(opcode_7c), l(opcode_7d), l(opcode_7e), l(opcode_7f)
    dta l(opcode_80), l(opcode_81), l(opcode_82), l(opcode_83)
    dta l(opcode_84), l(opcode_85), l(opcode_86), l(opcode_87)
    dta l(opcode_88), l(opcode_89), l(opcode_8a), l(opcode_8b)
    dta l(opcode_8c), l(opcode_8d), l(opcode_8e), l(opcode_8f)
    dta l(opcode_90), l(opcode_91), l(opcode_92), l(opcode_93)
    dta l(opcode_94), l(opcode_95), l(opcode_96), l(opcode_97)
    dta l(opcode_98), l(opcode_99), l(opcode_9a), l(opcode_9b)
    dta l(opcode_9c), l(opcode_9d), l(opcode_9e), l(opcode_9f)
    dta l(opcode_a0), l(opcode_a1), l(opcode_a2), l(opcode_a3)
    dta l(opcode_a4), l(opcode_a5), l(opcode_a6), l(opcode_a7)
    dta l(opcode_a8), l(opcode_a9), l(opcode_aa), l(opcode_ab)
    dta l(opcode_ac), l(opcode_ad), l(opcode_ae), l(opcode_af)
    dta l(opcode_b0), l(opcode_b1), l(opcode_b2), l(opcode_b3)
    dta l(opcode_b4), l(opcode_b5), l(opcode_b6), l(opcode_b7)
    dta l(opcode_b8), l(opcode_b9), l(opcode_ba), l(opcode_bb)
    dta l(opcode_bc), l(opcode_bd), l(opcode_be), l(opcode_bf)
    dta l(opcode_c0), l(opcode_c1), l(opcode_c2), l(opcode_c3)
    dta l(opcode_c4), l(opcode_c5), l(opcode_c6), l(opcode_c7)
    dta l(opcode_c8), l(opcode_c9), l(opcode_ca), l(opcode_cb)
    dta l(opcode_cc), l(opcode_cd), l(opcode_ce), l(opcode_cf)
    dta l(opcode_d0), l(opcode_d1), l(opcode_d2), l(opcode_d3)
    dta l(opcode_d4), l(opcode_d5), l(opcode_d6), l(opcode_d7)
    dta l(opcode_d8), l(opcode_d9), l(opcode_da), l(opcode_db)
    dta l(opcode_dc), l(opcode_dd), l(opcode_de), l(opcode_df)
    dta l(opcode_e0), l(opcode_e1), l(opcode_e2), l(opcode_e3)
    dta l(opcode_e4), l(opcode_e5), l(opcode_e6), l(opcode_e7)
    dta l(opcode_e8), l(opcode_e9), l(opcode_ea), l(opcode_eb)
    dta l(opcode_ec), l(opcode_ed), l(opcode_ee), l(opcode_ef)
    dta l(opcode_f0), l(opcode_f1), l(opcode_f2), l(opcode_f3)
    dta l(opcode_f4), l(opcode_f5), l(opcode_f6), l(opcode_f7)
    dta l(opcode_f8), l(opcode_f9), l(opcode_fa), l(opcode_fb)
    dta l(opcode_fc), l(opcode_fd), l(opcode_fe), l(opcode_ff)

jump_table_high:
    dta h(opcode_00), h(opcode_01), h(opcode_02), h(opcode_03)
    dta h(opcode_04), h(opcode_05), h(opcode_06), h(opcode_07)
    dta h(opcode_08), h(opcode_09), h(opcode_0a), h(opcode_0b)
    dta h(opcode_0c), h(opcode_0d), h(opcode_0e), h(opcode_0f)
    dta h(opcode_10), h(opcode_11), h(opcode_12), h(opcode_13)
    dta h(opcode_14), h(opcode_15), h(opcode_16), h(opcode_17)
    dta h(opcode_18), h(opcode_19), h(opcode_1a), h(opcode_1b)
    dta h(opcode_1c), h(opcode_1d), h(opcode_1e), h(opcode_1f)
    dta h(opcode_20), h(opcode_21), h(opcode_22), h(opcode_23)
    dta h(opcode_24), h(opcode_25), h(opcode_26), h(opcode_27)
    dta h(opcode_28), h(opcode_29), h(opcode_2a), h(opcode_2b)
    dta h(opcode_2c), h(opcode_2d), h(opcode_2e), h(opcode_2f)
    dta h(opcode_30), h(opcode_31), h(opcode_32), h(opcode_33)
    dta h(opcode_34), h(opcode_35), h(opcode_36), h(opcode_37)
    dta h(opcode_38), h(opcode_39), h(opcode_3a), h(opcode_3b)
    dta h(opcode_3c), h(opcode_3d), h(opcode_3e), h(opcode_3f)
    dta h(opcode_40), h(opcode_41), h(opcode_42), h(opcode_43)
    dta h(opcode_44), h(opcode_45), h(opcode_46), h(opcode_47)
    dta h(opcode_48), h(opcode_49), h(opcode_4a), h(opcode_4b)
    dta h(opcode_4c), h(opcode_4d), h(opcode_4e), h(opcode_4f)
    dta h(opcode_50), h(opcode_51), h(opcode_52), h(opcode_53)
    dta h(opcode_54), h(opcode_55), h(opcode_56), h(opcode_57)
    dta h(opcode_58), h(opcode_59), h(opcode_5a), h(opcode_5b)
    dta h(opcode_5c), h(opcode_5d), h(opcode_5e), h(opcode_5f)
    dta h(opcode_60), h(opcode_61), h(opcode_62), h(opcode_63)
    dta h(opcode_64), h(opcode_65), h(opcode_66), h(opcode_67)
    dta h(opcode_68), h(opcode_69), h(opcode_6a), h(opcode_6b)
    dta h(opcode_6c), h(opcode_6d), h(opcode_6e), h(opcode_6f)
    dta h(opcode_70), h(opcode_71), h(opcode_72), h(opcode_73)
    dta h(opcode_74), h(opcode_75), h(opcode_76), h(opcode_77)
    dta h(opcode_78), h(opcode_79), h(opcode_7a), h(opcode_7b)
    dta h(opcode_7c), h(opcode_7d), h(opcode_7e), h(opcode_7f)
    dta h(opcode_80), h(opcode_81), h(opcode_82), h(opcode_83)
    dta h(opcode_84), h(opcode_85), h(opcode_86), h(opcode_87)
    dta h(opcode_88), h(opcode_89), h(opcode_8a), h(opcode_8b)
    dta h(opcode_8c), h(opcode_8d), h(opcode_8e), h(opcode_8f)
    dta h(opcode_90), h(opcode_91), h(opcode_92), h(opcode_93)
    dta h(opcode_94), h(opcode_95), h(opcode_96), h(opcode_97)
    dta h(opcode_98), h(opcode_99), h(opcode_9a), h(opcode_9b)
    dta h(opcode_9c), h(opcode_9d), h(opcode_9e), h(opcode_9f)
    dta h(opcode_a0), h(opcode_a1), h(opcode_a2), h(opcode_a3)
    dta h(opcode_a4), h(opcode_a5), h(opcode_a6), h(opcode_a7)
    dta h(opcode_a8), h(opcode_a9), h(opcode_aa), h(opcode_ab)
    dta h(opcode_ac), h(opcode_ad), h(opcode_ae), h(opcode_af)
    dta h(opcode_b0), h(opcode_b1), h(opcode_b2), h(opcode_b3)
    dta h(opcode_b4), h(opcode_b5), h(opcode_b6), h(opcode_b7)
    dta h(opcode_b8), h(opcode_b9), h(opcode_ba), h(opcode_bb)
    dta h(opcode_bc), h(opcode_bd), h(opcode_be), h(opcode_bf)
    dta h(opcode_c0), h(opcode_c1), h(opcode_c2), h(opcode_c3)
    dta h(opcode_c4), h(opcode_c5), h(opcode_c6), h(opcode_c7)
    dta h(opcode_c8), h(opcode_c9), h(opcode_ca), h(opcode_cb)
    dta h(opcode_cc), h(opcode_cd), h(opcode_ce), h(opcode_cf)
    dta h(opcode_d0), h(opcode_d1), h(opcode_d2), h(opcode_d3)
    dta h(opcode_d4), h(opcode_d5), h(opcode_d6), h(opcode_d7)
    dta h(opcode_d8), h(opcode_d9), h(opcode_da), h(opcode_db)
    dta h(opcode_dc), h(opcode_dd), h(opcode_de), h(opcode_df)
    dta h(opcode_e0), h(opcode_e1), h(opcode_e2), h(opcode_e3)
    dta h(opcode_e4), h(opcode_e5), h(opcode_e6), h(opcode_e7)
    dta h(opcode_e8), h(opcode_e9), h(opcode_ea), h(opcode_eb)
    dta h(opcode_ec), h(opcode_ed), h(opcode_ee), h(opcode_ef)
    dta h(opcode_f0), h(opcode_f1), h(opcode_f2), h(opcode_f3)
    dta h(opcode_f4), h(opcode_f5), h(opcode_f6), h(opcode_f7)
    dta h(opcode_f8), h(opcode_f9), h(opcode_fa), h(opcode_fb)
    dta h(opcode_fc), h(opcode_fd), h(opcode_fe), h(opcode_ff)
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

    run run

