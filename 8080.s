
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

msb_to_bank:
:64 .byte BANK0
:64 .byte BANK1
:64 .byte BANK2
:64 .byte BANK3

; include instruction_length and zsp_table tables

    icl 'tables/tables.s'

; --------------------------------------------------------------------------

    run run

