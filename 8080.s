
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

PORTB = $d30b

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

; --------------------------------------------------------------------------

; We just assume we are on a 130XE for now. atari800 -xe 8080.xex

    org $d301

    .byte BANK0

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

    org $d301

    .byte BANK3

    org $4000+(BDOS&$3fff)  ; in bank 3

    ins 'cpm22/bdos.sys'

; Load BIOS. Implement same OUT port,A as in atari8080.c. CONOUT is enough
; to print messages.

    org $4000+(BIOS&$3fff)  ; in bank 3

    ins 'cpm22/bios.sys'

; --------------------------------------------------------------------------

    org $d301

    .byte NOBANK            ; start with extended banks disabled for
                            ; debugging purposes

; --------------------------------------------------------------------------

; BIOS HERE

; --------------------------------------------------------------------------

; MACROS HERE

; --------------------------------------------------------------------------

; MAIN EMULATION LOOP

    org $8000

run_emulator:
    rts

opcode_00:
    jmp run_emulator

opcode_01:
    jmp run_emulator

opcode_02:
    jmp run_emulator

opcode_03:
    jmp run_emulator

opcode_04:
    jmp run_emulator

opcode_05:
    jmp run_emulator

opcode_06:
    jmp run_emulator

opcode_07:
    jmp run_emulator

opcode_08:
    jmp run_emulator

opcode_09:
    jmp run_emulator

opcode_0a:
    jmp run_emulator

opcode_0b:
    jmp run_emulator

opcode_0c:
    jmp run_emulator

opcode_0d:
    jmp run_emulator

opcode_0e:
    jmp run_emulator

opcode_0f:
    jmp run_emulator

opcode_10:
    jmp run_emulator

opcode_11:
    jmp run_emulator

opcode_12:
    jmp run_emulator

opcode_13:
    jmp run_emulator

opcode_14:
    jmp run_emulator

opcode_15:
    jmp run_emulator

opcode_16:
    jmp run_emulator

opcode_17:
    jmp run_emulator

opcode_18:
    jmp run_emulator

opcode_19:
    jmp run_emulator

opcode_1a:
    jmp run_emulator

opcode_1b:
    jmp run_emulator

opcode_1c:
    jmp run_emulator

opcode_1d:
    jmp run_emulator

opcode_1e:
    jmp run_emulator

opcode_1f:
    jmp run_emulator

opcode_20:
    jmp run_emulator

opcode_21:
    jmp run_emulator

opcode_22:
    jmp run_emulator

opcode_23:
    jmp run_emulator

opcode_24:
    jmp run_emulator

opcode_25:
    jmp run_emulator

opcode_26:
    jmp run_emulator

opcode_27:
    jmp run_emulator

opcode_28:
    jmp run_emulator

opcode_29:
    jmp run_emulator

opcode_2a:
    jmp run_emulator

opcode_2b:
    jmp run_emulator

opcode_2c:
    jmp run_emulator

opcode_2d:
    jmp run_emulator

opcode_2e:
    jmp run_emulator

opcode_2f:
    jmp run_emulator

opcode_30:
    jmp run_emulator

opcode_31:
    jmp run_emulator

opcode_32:
    jmp run_emulator

opcode_33:
    jmp run_emulator

opcode_34:
    jmp run_emulator

opcode_35:
    jmp run_emulator

opcode_36:
    jmp run_emulator

opcode_37:
    jmp run_emulator

opcode_38:
    jmp run_emulator

opcode_39:
    jmp run_emulator

opcode_3a:
    jmp run_emulator

opcode_3b:
    jmp run_emulator

opcode_3c:
    jmp run_emulator

opcode_3d:
    jmp run_emulator

opcode_3e:
    jmp run_emulator

opcode_3f:
    jmp run_emulator

opcode_40:
    jmp run_emulator

opcode_41:
    jmp run_emulator

opcode_42:
    jmp run_emulator

opcode_43:
    jmp run_emulator

opcode_44:
    jmp run_emulator

opcode_45:
    jmp run_emulator

opcode_46:
    jmp run_emulator

opcode_47:
    jmp run_emulator

opcode_48:
    jmp run_emulator

opcode_49:
    jmp run_emulator

opcode_4a:
    jmp run_emulator

opcode_4b:
    jmp run_emulator

opcode_4c:
    jmp run_emulator

opcode_4d:
    jmp run_emulator

opcode_4e:
    jmp run_emulator

opcode_4f:
    jmp run_emulator

opcode_50:
    jmp run_emulator

opcode_51:
    jmp run_emulator

opcode_52:
    jmp run_emulator

opcode_53:
    jmp run_emulator

opcode_54:
    jmp run_emulator

opcode_55:
    jmp run_emulator

opcode_56:
    jmp run_emulator

opcode_57:
    jmp run_emulator

opcode_58:
    jmp run_emulator

opcode_59:
    jmp run_emulator

opcode_5a:
    jmp run_emulator

opcode_5b:
    jmp run_emulator

opcode_5c:
    jmp run_emulator

opcode_5d:
    jmp run_emulator

opcode_5e:
    jmp run_emulator

opcode_5f:
    jmp run_emulator

opcode_60:
    jmp run_emulator

opcode_61:
    jmp run_emulator

opcode_62:
    jmp run_emulator

opcode_63:
    jmp run_emulator

opcode_64:
    jmp run_emulator

opcode_65:
    jmp run_emulator

opcode_66:
    jmp run_emulator

opcode_67:
    jmp run_emulator

opcode_68:
    jmp run_emulator

opcode_69:
    jmp run_emulator

opcode_6a:
    jmp run_emulator

opcode_6b:
    jmp run_emulator

opcode_6c:
    jmp run_emulator

opcode_6d:
    jmp run_emulator

opcode_6e:
    jmp run_emulator

opcode_6f:
    jmp run_emulator

opcode_70:
    jmp run_emulator

opcode_71:
    jmp run_emulator

opcode_72:
    jmp run_emulator

opcode_73:
    jmp run_emulator

opcode_74:
    jmp run_emulator

opcode_75:
    jmp run_emulator

opcode_76:
    jmp run_emulator

opcode_77:
    jmp run_emulator

opcode_78:
    jmp run_emulator

opcode_79:
    jmp run_emulator

opcode_7a:
    jmp run_emulator

opcode_7b:
    jmp run_emulator

opcode_7c:
    jmp run_emulator

opcode_7d:
    jmp run_emulator

opcode_7e:
    jmp run_emulator

opcode_7f:
    jmp run_emulator

opcode_80:
    jmp run_emulator

opcode_81:
    jmp run_emulator

opcode_82:
    jmp run_emulator

opcode_83:
    jmp run_emulator

opcode_84:
    jmp run_emulator

opcode_85:
    jmp run_emulator

opcode_86:
    jmp run_emulator

opcode_87:
    jmp run_emulator

opcode_88:
    jmp run_emulator

opcode_89:
    jmp run_emulator

opcode_8a:
    jmp run_emulator

opcode_8b:
    jmp run_emulator

opcode_8c:
    jmp run_emulator

opcode_8d:
    jmp run_emulator

opcode_8e:
    jmp run_emulator

opcode_8f:
    jmp run_emulator

opcode_90:
    jmp run_emulator

opcode_91:
    jmp run_emulator

opcode_92:
    jmp run_emulator

opcode_93:
    jmp run_emulator

opcode_94:
    jmp run_emulator

opcode_95:
    jmp run_emulator

opcode_96:
    jmp run_emulator

opcode_97:
    jmp run_emulator

opcode_98:
    jmp run_emulator

opcode_99:
    jmp run_emulator

opcode_9a:
    jmp run_emulator

opcode_9b:
    jmp run_emulator

opcode_9c:
    jmp run_emulator

opcode_9d:
    jmp run_emulator

opcode_9e:
    jmp run_emulator

opcode_9f:
    jmp run_emulator

opcode_a0:
    jmp run_emulator

opcode_a1:
    jmp run_emulator

opcode_a2:
    jmp run_emulator

opcode_a3:
    jmp run_emulator

opcode_a4:
    jmp run_emulator

opcode_a5:
    jmp run_emulator

opcode_a6:
    jmp run_emulator

opcode_a7:
    jmp run_emulator

opcode_a8:
    jmp run_emulator

opcode_a9:
    jmp run_emulator

opcode_aa:
    jmp run_emulator

opcode_ab:
    jmp run_emulator

opcode_ac:
    jmp run_emulator

opcode_ad:
    jmp run_emulator

opcode_ae:
    jmp run_emulator

opcode_af:
    jmp run_emulator

opcode_b0:
    jmp run_emulator

opcode_b1:
    jmp run_emulator

opcode_b2:
    jmp run_emulator

opcode_b3:
    jmp run_emulator

opcode_b4:
    jmp run_emulator

opcode_b5:
    jmp run_emulator

opcode_b6:
    jmp run_emulator

opcode_b7:
    jmp run_emulator

opcode_b8:
    jmp run_emulator

opcode_b9:
    jmp run_emulator

opcode_ba:
    jmp run_emulator

opcode_bb:
    jmp run_emulator

opcode_bc:
    jmp run_emulator

opcode_bd:
    jmp run_emulator

opcode_be:
    jmp run_emulator

opcode_bf:
    jmp run_emulator

opcode_c0:
    jmp run_emulator

opcode_c1:
    jmp run_emulator

opcode_c2:
    jmp run_emulator

opcode_c3:
    jmp run_emulator

opcode_c4:
    jmp run_emulator

opcode_c5:
    jmp run_emulator

opcode_c6:
    jmp run_emulator

opcode_c7:
    jmp run_emulator

opcode_c8:
    jmp run_emulator

opcode_c9:
    jmp run_emulator

opcode_ca:
    jmp run_emulator

opcode_cb:
    jmp run_emulator

opcode_cc:
    jmp run_emulator

opcode_cd:
    jmp run_emulator

opcode_ce:
    jmp run_emulator

opcode_cf:
    jmp run_emulator

opcode_d0:
    jmp run_emulator

opcode_d1:
    jmp run_emulator

opcode_d2:
    jmp run_emulator

opcode_d3:
    jmp run_emulator

opcode_d4:
    jmp run_emulator

opcode_d5:
    jmp run_emulator

opcode_d6:
    jmp run_emulator

opcode_d7:
    jmp run_emulator

opcode_d8:
    jmp run_emulator

opcode_d9:
    jmp run_emulator

opcode_da:
    jmp run_emulator

opcode_db:
    jmp run_emulator

opcode_dc:
    jmp run_emulator

opcode_dd:
    jmp run_emulator

opcode_de:
    jmp run_emulator

opcode_df:
    jmp run_emulator

opcode_e0:
    jmp run_emulator

opcode_e1:
    jmp run_emulator

opcode_e2:
    jmp run_emulator

opcode_e3:
    jmp run_emulator

opcode_e4:
    jmp run_emulator

opcode_e5:
    jmp run_emulator

opcode_e6:
    jmp run_emulator

opcode_e7:
    jmp run_emulator

opcode_e8:
    jmp run_emulator

opcode_e9:
    jmp run_emulator

opcode_ea:
    jmp run_emulator

opcode_eb:
    jmp run_emulator

opcode_ec:
    jmp run_emulator

opcode_ed:
    jmp run_emulator

opcode_ee:
    jmp run_emulator

opcode_ef:
    jmp run_emulator

opcode_f0:
    jmp run_emulator

opcode_f1:
    jmp run_emulator

opcode_f2:
    jmp run_emulator

opcode_f3:
    jmp run_emulator

opcode_f4:
    jmp run_emulator

opcode_f5:
    jmp run_emulator

opcode_f6:
    jmp run_emulator

opcode_f7:
    jmp run_emulator

opcode_f8:
    jmp run_emulator

opcode_f9:
    jmp run_emulator

opcode_fa:
    jmp run_emulator

opcode_fb:
    jmp run_emulator

opcode_fc:
    jmp run_emulator

opcode_fd:
    jmp run_emulator

opcode_fe:
    jmp run_emulator

opcode_ff:
    jmp run_emulator

; --------------------------------------------------------------------------

; SETUP EMULATOR

run:
    lda #0
    sta LMARGN
    sta COLCRS
    sta $02c6

    ; print banner

    bput 0, banner_len, banner

    ; 8080 memory is already setup by the loader

    ; set PC to test program

    lda #0
    sta PCL
    lda #$01
    sta PCH
    sta PCHa
    lda #BANK0
    sta curbank
    sta PORTB

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
:64 .byte BANK0
:64 .byte BANK1
:64 .byte BANK2
:64 .byte BANK3

; include instruction_length and zsp_table tables

    icl 'tables/tables.s'

; --------------------------------------------------------------------------

    run run

