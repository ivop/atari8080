// -------------------------------------------------------------------------
//
// Intel 8080 Emulator
//
// Copyright © 2023 by Ivo van poorten
//
// Written with the idea in mind to implement a 6502 version in assembly
// for the Atari 130XE, where reading and writing memory is expensive as
// it has to bank in the right bank and has a window of 16kB.
// Current switched in bank is always right for the instruction fetcher.
// Other access might need to switch. Runs a minimal BIOS in C to boot
// be able to boot vanilla CP/M 2.2.
// Goal is to reach ca. 20 6502 instructions per 8080 instruction on
// average. But first, we need to get this C version working.
//
// -------------------------------------------------------------------------

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <termios.h>

// Sources:
//      * Intel 8080 Programmers Manual
//      * http://www.emulator101.com/reference/8080-by-opcode.html
//      and in the end I had a peek at:
//      * https://github.com/superzazu/8080
//      to iron out the last remaining bug in the aluop tests.
//      Parenthesis, parenthesis, parenthesis. Auxiliary carry is a pain.

// -------------------------------------------------------------------------

// Banked memory. Four banks of 16kB. Atari index is 0x4000-0x7fff
//
// During a 16-bit increment, the sign bit of the adjusted high byte
// can be used to detect bank overflow!
//
// inc PCL
// zif_eq
//      inc PCH
//      inc PCH_adjusted
//      bit PCH_adjusted
//      bpl 1f
//      // change bank here, set PCH_adjusted to 0
// 1f:
// zendif
//      // done

static uint8_t mem[4][16384];
static uint8_t curbank;

// 8080 registers on page zero.
//
// Atari: keep PC always adjusted. BC, DE, HL and SP only when needed. The
// latter is not used in this C implementation, but on the Atari we could
// implement four different functions for dereferencing BC, DE, HL or SP,
// avoiding the need to copy the low byte.

struct __attribute__((packed, aligned(1))) zp {
    uint8_t A;

    uint8_t B;
    uint8_t C;
    uint8_t B_adjusted;     // atari: (BC) ---> lda (C),y after adjust

    uint8_t D;
    uint8_t E;
    uint8_t D_adjusted;

    uint8_t H;
    uint8_t L;
    uint8_t H_adjusted;

    uint8_t SPH;
    uint8_t SPL;
    uint8_t SPH_adjusted;

    uint8_t PCH;
    uint8_t PCL;
    uint8_t PCH_adjusted;
} zp;

#define A       zp.A

#define B       zp.B
#define C       zp.C
#define Ba      zp.B_adjusted

#define D       zp.D
#define E       zp.E
#define Da      zp.D_adjusted

#define H       zp.H
#define L       zp.L
#define Ha      zp.H_adjusted

#define SPH     zp.SPH
#define SPL     zp.SPL
#define SPHa    zp.SPH_adjusted

#define PCH     zp.PCH
#define PCL     zp.PCL
#define PCHa    zp.PCH_adjusted

// PSW bits separate
//
// |S|Z|0|A|0|P|1|C|

// Or a single F later if the emulation is 100%
//
// Tradeoff: speed of checking flags (fast now) and (re)setting flags after
// an ALU operation (slow now). Perhaps the reverse is faster overall.

static uint8_t SF, ZF, AF, PF, CF;

#define SF_FLAG     0b10000000
#define ZF_FLAG     0b01000000
#define AF_FLAG     0b00010000
#define PF_FLAG     0b00000100
#define CF_FLAG     0b00000001

// Used during instruction fetch

static uint8_t instruction, byte2, byte3;

// used during memory access

#define byte1 instruction

// Assemble CCP.SYS and BDOS.SYS from https://github.com/brouhaha/cpm22
// Assembler: http://john.ccac.rwth-aachen.de:8000/as/
//
// Standard CP/M Memory layout:
//
// $E400 = CCP
// $EC00 = BDOS    (entry at $EC06)
// $FA00 = BIOS
//
// Trap BIOS calls with an unused 8080 instruction and use C functions
// to mimic its functions.

#define BIOS    0xfa00

#define BDOS    0xec00
#define BDOSE   (BDOS+6)

#define CPMB    0xe400          // base of cpm console processor

#define BOOTF   (BIOS+3*0)     // cold boot
#define WBOOTF  (BIOS+3*1)     // warm boot
#define CONSTF  (BIOS+3*2)     // console status, A=0 no char, A=ff char
#define CONINF  (BIOS+3*3)     // console input, result in A
#define CONOUTF (BIOS+3*4)     // console output, char in C
#define LISTF   (BIOS+3*5)     // list output (ignore)
#define PUNCHF  (BIOS+3*6)     // punch output (ignore)
#define READERF (BIOS+3*7)     // reader input (ignore, return A=^Z)
#define HOMEF   (BIOS+3*8)     // disk home (set track 0)
#define SELDSKF (BIOS+3*9)     // select disk (disk in C, return HL=dpbase or 0)
#define SETTRKF (BIOS+3*10)    // set track (track in C)
#define SETSECF (BIOS+3*11)    // set sector (sector in BC or C)
#define SETDMAF (BIOS+3*12)    // set dma (default=$80, input in BC)
#define READF   (BIOS+3*13)    // read record (return error in A, A=0=OK)
#define WRITEF  (BIOS+3*14)    // write record (return error in A, A=0=OK)
#define LISTSTF (BIOS+3*15)    // list status (ignore) (A=0=not ready)
#define SECTRAN (BIOS+3*16)    // sector translate (in BC, out in HL)

#define DPBASE  (BIOS + 17*3)  // see below

// -------------------------------------------------------------------------

#include "tables/tables.h"
#include "cpm22/bios.h"
#include "cpm22/bdos.h"
#include "cpm22/ccp.h"

// -------------------------------------------------------------------------

// Tons of debug output. Might cut down on it a little.

#ifdef BIOSDEBUG
#define biosprintf(...) fprintf(stderr, __VA_ARGS__)
#else
#define biosprintf(...)
#endif

#ifdef DEBUG

static int cpudump = 0, wbootcnt = 0;

static void debug_print_cpu_state(void) {
    if (cpudump) {
    fprintf(stderr, "PC:%02X%02X A:%02X B:%02X C:%02X D:%02X E:%02X H:%02X L:%02X "
           "SP:%02X%02X ", PCH, PCL, A, B, C, D, E, H, L, SPH, SPL);
    fprintf(stderr, "S:%d Z:%d A:%d P:%d C:%d\n", !!SF, !!ZF, !!AF, !!PF, !!CF);
    }
}

static void debug_print_instruction(void) {
    if (cpudump) {
    fprintf(stderr, ">>> %s ", mnemonics[instruction]);
    int mode = modes[instruction];
    switch (mode) {
    case MODE_D8:   fprintf(stderr, "%02XH", byte2);   break;
    case MODE_D16:
    case MODE_ADR:
    case MODE_JMP:  fprintf(stderr, "%02X%02XH", byte3, byte2); break;
    default:        break;
    }
    fprintf(stderr, "\n");
    }
}

#else

#define debug_print_cpu_state()
#define debug_print_instruction()

#endif

static void print_bdos_serial() {
    fprintf(stderr, "BDOS serial: ");
    for (int i=0; i<6; i++)
        fprintf(stderr, "%02X ", mem[3][(BDOS&0x3fff)+i]);
    fprintf(stderr, "\n");
}

// -------------------------------------------------------------------------

static void mem_write(uint8_t LOW, uint8_t HIGH, uint8_t VAL);
static uint8_t mem_read(uint8_t LOW, uint8_t HIGH);
static int kbhit();

static uint16_t dma_address;
static uint16_t drive_number;
static uint8_t track_number;
static uint16_t sector_number;
static FILE *dsk0;

static void bios_entry(int function) {
    int r;

    switch (function) {

    case 0:         // boot
        memcpy(&mem[3][CPMB & 0x3fff], ccp_sys, ccp_sys_len);
        memcpy(&mem[3][BDOS & 0x3fff], bdos_sys, bdos_sys_len);

        printf("\r\n64k CP/M vers 2.2\r\n");

        mem[0][0x0000] = 0xc3;   // JMP $FA03 WBOOT
        mem[0][0x0001] = WBOOTF & 0xff;
        mem[0][0x0002] = WBOOTF >> 8;

        mem[0][0x0005] = 0xc3;   // JMP $EC06 BDOSE
        mem[0][0x0006] = BDOSE & 0xff;
        mem[0][0x0007] = BDOSE >> 8;

        [[fallthrough]];

    case 1:         // wboot
        biosprintf("BIOS: WBOOT\n");

#ifdef DEBUG
        if (wbootcnt==1) cpudump++; else wbootcnt++;
#endif

        // reload CCP
        memcpy(&mem[3][CPMB & 0x3fff], ccp_sys, ccp_sys_len);
        // there's still something fishy that overwrites bdos (8080exm)
#ifndef DEBUG
        memcpy(&mem[3][BDOS & 0x3fff], bdos_sys, bdos_sys_len);
#else
        print_bdos_serial();
#endif

        memset(&zp, 0, sizeof(zp));

        PCL = CPMB & 0xff;      // JMP CPMB
        PCH = CPMB >> 8;
        PCHa = PCH & 0x3f;      // keep adjusted
        curbank = PCH>>6; 
        C = drive_number;
        biosprintf("NEWPC: %02X%02X\n", PCH, PCL);
        break;

        // Implement proper terminal with termios later so we can send
        // ^C et cetera... This is good enough for now.

    case 2:         // const
        if (kbhit())
            A = 0xff;
        else
            A = 0;      // no pending key, 0xff = pending
        break;

    case 3:         // conin
        A = getchar();
        if (A == 127) A = 8;
        if (A == 24) {      // ^X to exit emulator
            fclose(dsk0);
            exit(0);
        }
        break;

    case 4:         // conout
        printf("[32m%c[0m", C);     // we want some colors.
        fflush(stdout);
        break;

    case 5:         // list
        break;

    case 6:         // punch
        break;

    case 7:         // reader
        A = 26;     // return ^Z EOF
        break;

    case 8:         // settrk
        track_number = 0;
        C = 0;
        break;

    case 9:         // seldsk
        H = 0;
        L = 0;
        if (C == 0) {           // we have only one drive
            drive_number = C;
            H = DPBASE >> 8;    // return dpbase in HL
            L = DPBASE & 0xff;
        }
        break;

    case 10:        // settrk
        track_number = C;
        break;

    case 11:        // setsec
        sector_number = C;
        break;

    case 12:        // setdma
        dma_address = (B<<8) | C;
        L = C;
        H = B;
        break;

    case 13: {      // read
        int abssec = track_number * 26 + sector_number;
        int adr = dma_address;
        if (fseek(dsk0, abssec*128, SEEK_SET) == EINVAL) {
            A = 1;
            break;
        }
        if ((adr & 0x3fff) <= 0x3f80) {
            int bnk = adr>>(8+6);
            int ret = fread(&mem[bnk][adr&0x3fff], 1, 128, dsk0);
        } else {
            for (int i=0; i<128; i++) {
                mem_write(adr&0xff, adr>>8, fgetc(dsk0));
                adr++;
            }
        }
        A = 0;
        break; }

    case 14: {      // write
        int abssec = track_number * 26 + sector_number;
        int adr = dma_address;
        if (fseek(dsk0, abssec*128, SEEK_SET) == EINVAL) {
            biosprintf("FAILED\n");
            A = 1;
            break;
        }
        if ((adr & 0x3fff) <= 0x3f80) {
            int bnk = adr>>(8+6);
            int ret = fwrite(&mem[bnk][adr&0x3fff], 1, 128, dsk0);
        } else {
            for (int i=0; i<128; i++) {
                if (fputc(mem_read(adr&0xff, adr>>8), dsk0) < 0) {
                    fprintf(stderr, "WRITE ERROR\n");
                    exit(0);
                }
                adr++;
            }
        }
        biosprintf("OK\n");
        A = 0;
        break; }

    case 15:        // listst
        A = 0xff;   // always ready
        break;

    case 16:        // sectran
        A = C;      // no translation
        H = B;      // also return in HL
        L = C;
        break;
    default:
        biosprintf("BIOS: wrong entry!\n");
        exit(1);
        break;
    }
}

// -------------------------------------------------------------------------

static inline void increment_PC(void) {
    PCL++;
    if (PCL == 0) {
        PCH++;                      // skip on atari, calculate when needed
        PCHa++;
        if (PCHa == 0x40) {         // 0x80 on Atari, end of bank, BIT!
            PCHa = 0;
            curbank = PCH >> 6;     // table on Atari, switch bank
        }
    }
}

static void get_instruction(void) {
    // Atari: emulation code MUST live outside the 16kB window
    // The proper bank should always be selected, enforced by increment_PC
    // All instructions that change the PC (CALLs, RETs, JMPs) MUST do
    // this, too.

    debug_print_cpu_state();

    instruction = mem[curbank][(PCHa<<8) | PCL];
    increment_PC();

    int len = instruction_length[instruction];

    if (len > 1) {
        byte2 = mem[curbank][(PCHa<<8) | PCL];
        increment_PC();
    }
    if (len > 2) {
        byte3 = mem[curbank][(PCHa<<8) | PCL];
        increment_PC();
    }

    debug_print_instruction();
}

// Emulate 64kB banked RAM.
//
// Atari: these are less frequent than instruction fetch, so save and restore
// curbank.
//
static void mem_write(uint8_t LOW, uint8_t HIGH, uint8_t VAL) {
    uint16_t adr = (HIGH<<8)+LOW;
    uint16_t pc = (PCH<<8)+PCL;
#ifdef DEBUG
    if (adr >= BDOS && pc < CPMB) {
        fprintf(stderr, "write to BDOS area %04X from PC:%04X\n",adr,  pc);
    }
    if (adr >= BDOS && pc >= CPMB && pc < BDOS) {
        fprintf(stderr, "CPP writes to BDOS area %04X from PC:%04X\n",adr,  pc);
    }
//    if (adr >= BDOS && pc >= CPMB && pc > BDOS) {
//        fprintf(stderr, "BDOS writes to BDOS area %04X from PC:%04X\n",adr,  pc);
//    }
#endif

    uint8_t savebank = curbank;
                                    // atari: here is where we adjust B, D, H
    curbank = HIGH>>6;              // table lookup
    HIGH &= 0x3f;

    uint16_t ADR = (HIGH<<8) | LOW;

    mem[curbank][ADR] = VAL;        // sta (adr),y

    curbank = savebank;
}

static uint8_t mem_read(uint8_t LOW, uint8_t HIGH) {
    uint8_t savebank = curbank;
                                    // atari: here is where we adjust B, D, H
    curbank = HIGH>>6;              // table lookup
    HIGH &= 0x3f;
    
    uint16_t ADR = (HIGH<<8) | LOW;

    uint8_t VAL = mem[curbank][ADR];        // lda (adr),y or lda (reg),y

    curbank = savebank;

    return VAL;
}

// Or change this to a single combined table if I decide to go with a single
// F register. Decisions, decisions, decisions.
static void eval_zsp_flags(uint8_t VAL) {
                              // ldx VAL or tax or whatever
    ZF = zf_table[VAL];       // lda zf_table,x ! sta zflag
    SF = sf_table[VAL];       // lda sf_table,x ! sta sflag
    PF = pf_table[VAL];       // lda pf_table,x ! sta pflag
}

// -------------------------------------------------------------------------

static void run_emulator(void) {
    int x = 100;

    // temporary variables

    int16_t z;                      // signed for subraction
    uint8_t t8, M;
    int16_t t16;
    int32_t t32;
    uint16_t BC, DE, HL, SP;    // note that this are temporaries and do
                                // not directly reflect the state of the
                                // registers! only used by DAD

    while(1 /*x--*/) {
        get_instruction();

        switch(instruction) {       // atari jump table

        case 0x00: // NOP ---- Nothing
            break;

        // ######################### LXI #########################
        // LXI XY       X <- byte3; Y <- byte2

#define LXI(X,Y) X = byte3; Y = byte2;

        case 0x01: LXI(B,C); break;
        case 0x11: LXI(D,E); break;
        case 0x21: LXI(H,L); break;
        case 0x31: LXI(SPH,SPL); break;

        // ######################### STORE #########################
        //
        case 0x02: // STAX B ---- (BC) <- A
            mem_write(C, B, A);
            break;
        case 0x12: // STAX D ---- (DE) <- A
            mem_write(E, D, A);
            break;
        case 0x22: // SHLD adr ---- (adr) <-L;(adr+1) <- H
            mem_write(byte2, byte3, L);
            byte2++;
            if (byte2 == 0) byte3++;
            mem_write(byte2, byte3, H);
            break;
        case 0x32: // STA adr ---- (adr) <- A
            mem_write(byte2, byte3, A);
            break;

        // ######################### INX #########################
        // INX XY       XY <- XY+1

#define INX(X,Y) Y++; if (Y == 0) X++;

        case 0x03: INX(B,C); break;
        case 0x13: INX(D,E); break;
        case 0x23: INX(H,L); break;
        case 0x33: INX(SPH,SPL); break;

        // ######################### INR #########################
        // INR reg = reg + 1                [Z,S,P,AC]

#define INR(reg) reg+=1; AF = (reg&0x0f)==0 ? AF_FLAG:0; eval_zsp_flags(reg);

        case 0x04: INR(B); break;
        case 0x0c: INR(C); break;
        case 0x14: INR(D); break;
        case 0x1c: INR(E); break;
        case 0x24: INR(H); break;
        case 0x2c: INR(L); break;
        case 0x34: M = mem_read(L, H); INR(M); mem_write(L, H, M); break;
        case 0x3c: INR(A); break;

        // ######################### DCR #########################
        // DCR reg = reg - 1                [Z,S,P,AC]

#define DCR(reg) reg-=1; AF = (reg&0x0f)==0x0f ? 0:AF_FLAG; eval_zsp_flags(reg);

        case 0x05: DCR(B); break;
        case 0x0d: DCR(C); break;
        case 0x15: DCR(D); break;
        case 0x1d: DCR(E); break;
        case 0x25: DCR(H); break;
        case 0x2d: DCR(L); break;
        case 0x35: M = mem_read(L, H); DCR(M); mem_write(L, H, M); break;
        case 0x3d: DCR(A); break;

        // ######################### MVI #########################
        //

        case 0x06: B = byte2; break;
        case 0x0e: C = byte2; break;
        case 0x16: D = byte2; break;
        case 0x1e: E = byte2; break;
        case 0x26: H = byte2; break;
        case 0x2e: L = byte2; break;
        case 0x36: mem_write(L, H, byte2); break;
        case 0x3e: A = byte2; break;

        // ######################### DAD #########################
        //
        case 0x09: // DAD B ---- HL = HL + BC [CY]
            HL = (H<<8) | L;
            BC = (B<<8) | C;
            t32 = HL + BC;          // simple 16 bit addition, bcc/bcs
            H = t32 >> 8;
            L = t32 & 0xff;
            CF = (t32 & 0x00010000) ? CF_FLAG : 0;
            break;
        case 0x19: // DAD D ---- HL = HL + DE [CY]
            HL = (H<<8) | L;
            DE = (D<<8) | E;
            t32 = HL + DE;
            H = t32 >> 8;
            L = t32 & 0xff;
            CF = (t32 & 0x00010000) ? CF_FLAG : 0;
            break;
        case 0x29: // DAD H ---- HL = HL + HL [CY]
            HL = (H<<8) | L;
            t32 = HL + HL;
            H = t32 >> 8;
            L = t32 & 0xff;
            CF = (t32 & 0x00010000) ? CF_FLAG : 0;
            break;
        case 0x39: // DAD SP ---- HL = HL + SP [CY]
            HL = (H<<8) | L;
            SP = (SPH<<8) | SPL;
            t32 = HL + SP;
            H = t32 >> 8;
            L = t32 & 0xff;
            CF = (t32 & 0x00010000) ? CF_FLAG : 0;
            break;

        // ######################### LOAD #########################
        //
        case 0x0a: // LDAX B ---- A <- (BC)
            A = mem_read(C, B);
            break;
        case 0x1a: // LDAX D ---- A <- (DE)
            A = mem_read(E, D);
            break;
        case 0x2a: // LHLD adr ---- L <- (adr);H <- (adr+1)
            L = mem_read(byte2, byte3);
            byte2++;
            if (byte2 == 0) byte3++;
            H = mem_read(byte2, byte3);
            break;
        case 0x3a: // LDA adr ---- A <- (adr)
            A = mem_read(byte2, byte3);
            break;

        // ######################### DCX #########################
        // DCX reg
        case 0x0b:   C--; if (  C == 0xff) B--; break;
        case 0x1b:   E--; if (  E == 0xff) D--; break;
        case 0x2b:   L--; if (  L == 0xff) H--; break;
        case 0x3b: SPL--; if (SPL == 0xff) SPH--; break;

        // ######################### RRC/RAR/CMA/CMC #########################
        //
        case 0x0f: // RRC ---- A = A >> 1;bit 7 = prev bit 0;CY = prev bit 0 [CY]
            t8 = A & 1;
            A >>= 1;
            A |= t8 ? 0x80 : 0;
            CF = t8 ? CF_FLAG : 0;
            break;
        case 0x1f: // RAR ---- A = A >> 1;bit 7 = prev CY;CY = prev bit 0 [CY]
            t8 = !!(A & 0x01);
            A >>= 1;
            A |= CF ? 0x80 : 0;     // bit7 prev CF
            CF = t8 ? CF_FLAG : 0;
            break;
        case 0x2f: // CMA ---- A <- !A
            A = ~A;
            break;
        case 0x3f: // CMC ---- CY=!CY [CY]
            CF = CF ^ CF_FLAG;
            break;

        // ######################### MOV #########################
        //
        case 0x40: break;
        case 0x41: B = C; break;
        case 0x42: B = D; break;
        case 0x43: B = E; break;
        case 0x44: B = H; break;
        case 0x45: B = L; break;
        case 0x46: B = mem_read(L, H); break;
        case 0x47: B = A; break;

        case 0x48: C = B; break;
        case 0x49: break;
        case 0x4a: C = D; break;
        case 0x4b: C = E; break;
        case 0x4c: C = H; break;
        case 0x4d: C = L; break;
        case 0x4e: C = mem_read(L, H); break;
        case 0x4f: C = A; break;

        case 0x50: D = B; break;
        case 0x51: D = C; break;
        case 0x52: break;
        case 0x53: D = E; break;
        case 0x54: D = H; break;
        case 0x55: D = L; break;
        case 0x56: D = mem_read(L, H); break;
        case 0x57: D = A; break;

        case 0x58: E = B; break;
        case 0x59: E = C; break;
        case 0x5a: E = D; break;
        case 0x5b: break;
        case 0x5c: E = H; break;
        case 0x5d: E = L; break;
        case 0x5e: E = mem_read(L, H); break;
        case 0x5f: E = A; break;

        case 0x60: H = B; break;
        case 0x61: H = C; break;
        case 0x62: H = D; break;
        case 0x63: H = E; break;
        case 0x64: break;
        case 0x65: H = L; break;
        case 0x66: H = mem_read(L, H); break;
        case 0x67: H = A; break;

        case 0x68: L = B; break;
        case 0x69: L = C; break;
        case 0x6a: L = D; break;
        case 0x6b: L = E; break;
        case 0x6c: L = H; break;
        case 0x6d: break;
        case 0x6e: L = mem_read(L, H); break;
        case 0x6f: L = A; break;

        case 0x70: mem_write(L, H, B); break;
        case 0x71: mem_write(L, H, C); break;
        case 0x72: mem_write(L, H, D); break;
        case 0x73: mem_write(L, H, E); break;
        case 0x74: mem_write(L, H, H); break;
        case 0x75: mem_write(L, H, L); break;

        case 0x76:
            fprintf(stderr, "HALT PC: %04X\n", ((PCH<<8)|PCL)-1);
            if (PCH>=0xe4 && PCH<0xec) {
                fprintf(stderr, "serial check on bdos fail --> overwritten\n");
                print_bdos_serial();
                exit(1);
            }
            break;       // HLT, not MOV M,M we don't halt :)

        case 0x77: mem_write(L, H, A); break;

        case 0x78: A = B; break;
        case 0x79: A = C; break;
        case 0x7a: A = D; break;
        case 0x7b: A = E; break;
        case 0x7c: A = H; break;
        case 0x7d: A = L; break;
        case 0x7e: A = mem_read(L, H); break;
        case 0x7f: break;

        // ######################### ADD #########################
        // A = A + val                      [Z,S,P,CY,AC]

#define ADD(val, car) \
            z = A + (val) + (car); \
            CF = (((z ^ A ^ (val)) & 0x0100)) ? CF_FLAG : 0; \
            AF = (((z ^ A ^ (val)) & 0x0010)) ? AF_FLAG : 0; \
            A = z; \
            eval_zsp_flags(A);

        case 0x80: ADD(B,0); break;
        case 0x81: ADD(C,0); break;
        case 0x82: ADD(D,0); break;
        case 0x83: ADD(E,0); break;
        case 0x84: ADD(H,0); break;
        case 0x85: ADD(L,0); break;
        case 0x86: M = mem_read(L, H); ADD(M,0); break;
        case 0x87: ADD(A,0); break;

        // ######################### ADC #########################
        // A = A + val + carry              [Z,S,P,CY,AC]

        case 0x88: ADD(B, !!CF); break;
        case 0x89: ADD(C, !!CF); break;
        case 0x8a: ADD(D, !!CF); break;
        case 0x8b: ADD(E, !!CF); break;
        case 0x8c: ADD(H, !!CF); break;
        case 0x8d: ADD(L, !!CF); break;
        case 0x8e: M = mem_read(L, H); ADD(M, !!CF); break;
        case 0x8f: ADD(A, !!CF); break;

        // ######################### SUB #########################
        // A = A + ~val + !carry

#define SUB(val, car) ADD(~val, !car); CF = CF ^ CF_FLAG;

        case 0x90: SUB(B, 0); break;
        case 0x91: SUB(C, 0); break;
        case 0x92: SUB(D, 0); break;
        case 0x93: SUB(E, 0); break;
        case 0x94: SUB(H, 0); break;
        case 0x95: SUB(L, 0); break;
        case 0x96: M = mem_read(L, H); SUB(M, 0); break;
        case 0x97: SUB(A, 0); break;

        // ######################### SBB #########################
        // A = A + ~val + !carry
 
        case 0x98: SUB(B, !!CF); break;
        case 0x99: SUB(C, !!CF); break;
        case 0x9a: SUB(D, !!CF); break;
        case 0x9b: SUB(E, !!CF); break;
        case 0x9c: SUB(H, !!CF); break;
        case 0x9d: SUB(L, !!CF); break;
        case 0x9e: M = mem_read(L, H); SUB(M, !!CF); break;
        case 0x9f: SUB(A, !!CF); break;

        // ######################### ANA #########################
        // A = A & val                      [Z,S,P,CY,AC]

#define ANA(val) t8 = A & val; \
                 CF = 0; \
                 AF = (((A | val) & 0x08) != 0) ? AF_FLAG : 0; \
                 A = t8; \
                 eval_zsp_flags(A);

        case 0xa0: ANA(B); break;
        case 0xa1: ANA(C); break;
        case 0xa2: ANA(D); break;
        case 0xa3: ANA(E); break;
        case 0xa4: ANA(H); break;
        case 0xa5: ANA(L); break;
        case 0xa6: M = mem_read(L, H); ANA(M); break;
        case 0xa7: ANA(A); break;

        // ######################### XRA #########################
        // A = A ^ val                      [Z,S,P,CY,AC]

#define XRA(val) A = A^val; AF=0; CF=0; eval_zsp_flags(A);

        case 0xa8: XRA(B); break;
        case 0xa9: XRA(C); break;
        case 0xaa: XRA(D); break;
        case 0xab: XRA(E); break;
        case 0xac: XRA(H); break;
        case 0xad: XRA(L); break;
        case 0xae: M = mem_read(L, H); XRA(M); break;
        case 0xaf: XRA(A); break;

        // ######################### ORA #########################
        // A = A | val                      [Z,S,P,CY,AC]

#define ORA(val) A = A|val; AF=0; CF=0; eval_zsp_flags(A);

        case 0xb0: ORA(B); break;
        case 0xb1: ORA(C); break;
        case 0xb2: ORA(D); break;
        case 0xb3: ORA(E); break;
        case 0xb4: ORA(H); break;
        case 0xb5: ORA(L); break;
        case 0xb6: M = mem_read(L, H); ORA(M); break;
        case 0xb7: ORA(A); break;

        // ######################### CMP #########################
        // CMP                              [Z,S,P,CY,AC]

#define CMP(val) z = A - val; \
                 CF = (z>>8) ? CF_FLAG : 0; \
                 AF = (~(A ^ z ^ val)) & 0x10 ? AF_FLAG : 0; \
                 eval_zsp_flags(z&0xff);

        case 0xb8: CMP(B); break;
        case 0xb9: CMP(C); break;
        case 0xba: CMP(D); break;
        case 0xbb: CMP(E); break;
        case 0xbc: CMP(H); break;
        case 0xbd: CMP(L); break;
        case 0xbe: M = mem_read(L, H); CMP(M); break;
        case 0xbf: CMP(A); break;

        // ######################### RLC/RAL/DAA/STC #########################
        //
        case 0x07: // RLC ---- A = A << 1;bit 0 = prev bit 7;CY = prev bit 7 [CY]
            t8 = !!(A & 0x80);
            A <<= 1;                 // rol A ! adc#1 ! bcc/bcs for cflag
            A |= t8;                 // bit0 prev bit7
            CF = t8 ? CF_FLAG : 0;
            break;
        case 0x17: // RAL ---- A = A << 1;bit 0 = prev CY;CY = prev bit 7 [CY]
            t8 = !!(A & 0x80);
            A <<= 1;
            A |= !!CF;               // bit0 prev CF
            CF = t8 ? CF_FLAG : 0;
            break;

        case 0x27: // DAA ---- Decimal Adjust Accumulator [Z,S,P,CY,AC]
            uint8_t save_CF = CF;
            t8 = 0;
            if (((A & 0x0f) > 9) || AF)
                t8 += 0x06;
            if (((A & 0xf0) > 0x90) || CF || ((A&0xf0)>=0x90 && (A&0x0f)>9)) {
                t8 += 0x60;
                save_CF = CF_FLAG;
            }
            ADD(t8,0);
            CF = save_CF;
            break;
        case 0x37: // STC ---- CY	CY = 1
            CF = CF_FLAG;
            break;

        // ######################### RETCETERA #########################
        //
        case 0xc0: if (!ZF) goto RET; break;
        case 0xc8: if ( ZF) goto RET; break;
        case 0xd0: if (!CF) goto RET; break;
        case 0xd8: if ( CF) goto RET; break;
        case 0xe0: if (!PF) goto RET; break;
        case 0xe8: if ( PF) goto RET; break;
        case 0xf0: if (!SF) goto RET; break;
        case 0xf8: if ( SF) goto RET; break;
        case 0xc9: // RET ---- PC.lo <- (SP);PC.hi <- (SP+1);SP <- SP+2
RET:
            PCL = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            PCH = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            PCHa = PCH & 0x3f;      // adjust!!
            curbank = PCH>>6;
            break;

        // ######################### POP/PUSH #########################
        //
        case 0xc1: // POP B ---- C <- (SP);B <- (SP+1);SP <- SP+2
            C = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            B = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            break;
        case 0xd1: // POP D ---- E <- (SP);D <- (SP+1);SP <- SP+2
            E = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            D = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            break;
        case 0xe1: // POP H ---- L <- (SP);H <- (SP+1);SP <- SP+2
            L = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            H = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            break;
        case 0xf1: // POP PSW ---- flags <- (SP);A <- (SP+1);SP <- SP+2 [Z,S,P,CY,AC]
            t8 = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            A = mem_read(SPL, SPH);
            SPL++;
            if (SPL == 0) SPH++;
            ZF = t8 & ZF_FLAG;
            SF = t8 & SF_FLAG;
            PF = t8 & PF_FLAG;
            AF = t8 & AF_FLAG;
            CF = t8 & CF_FLAG;
            break;
        case 0xc5: // PUSH B ---- (SP-2) <- C;(SP-1) <- B;SP <- SP-2
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, B);
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, C);
            break;
        case 0xd5: // PUSH D ---- (SP-2) <- E;(SP-1) <- D;SP <- SP-2
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, D);
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, E);
            break;
        case 0xe5: // PUSH H ---- (SP-2) <- L;(SP-1) <- H;SP <- SP - 2
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, H);
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, L);
            break;
        case 0xf5: // PUSH PSW ---- (SP-2)<-flags;(SP-1)<-A;SP <- SP-2
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, A);
            SPL--;
            if (SPL == 0xff) SPH--;
            t8 = SF | ZF | AF | PF | CF | 0x02;
            mem_write(SPL, SPH, t8);
            break;


        // ######################### JMP #########################
        //
        case 0xc2: if (!ZF) goto JMP; break;
        case 0xca: if ( ZF) goto JMP; break;
        case 0xd2: if (!CF) goto JMP; break;
        case 0xda: if ( CF) goto JMP; break;
        case 0xe2: if (!PF) goto JMP; break;
        case 0xea: if ( PF) goto JMP; break;
        case 0xf2: if (!SF) goto JMP; break;
        case 0xfa: if ( SF) goto JMP; break;
        case 0xc3:
JMP:
            PCL = byte2;
            PCH = byte3;
            PCHa = PCH & 0x3f;      // adjust!
            curbank = PCH>>6;
            break;

        // ######################### CALL/RST #########################
        //
        case 0xc4: if (!ZF) goto CALL; break;
        case 0xcc: if ( ZF) goto CALL; break;
        case 0xd4: if (!CF) goto CALL; break;
        case 0xdc: if ( CF) goto CALL; break;
        case 0xe4: if (!PF) goto CALL; break;
        case 0xec: if ( PF) goto CALL; break;
        case 0xf4: if (!SF) goto CALL; break;
        case 0xfc: if ( SF) goto CALL; break;
        case 0xcd:
CALL:       
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, PCH);
            SPL--;
            if (SPL == 0xff) SPH--;
            mem_write(SPL, SPH, PCL);
            PCL = byte2;
            PCH = byte3;
            PCHa = PCH & 0x3f;      // adjust!
            curbank = PCH>>6;
            break;
        case 0xc7: byte2 = 0x00; byte3 = 0; goto CALL; break;
        case 0xcf: byte2 = 0x08; byte3 = 0; goto CALL; break;
        case 0xd7: byte2 = 0x10; byte3 = 0; goto CALL; break;
        case 0xdf: byte2 = 0x18; byte3 = 0; goto CALL; break;
        case 0xe7: byte2 = 0x20; byte3 = 0; goto CALL; break;
        case 0xef: byte2 = 0x28; byte3 = 0; goto CALL; break;
        case 0xf7: byte2 = 0x30; byte3 = 0; goto CALL; break;
        case 0xff: byte2 = 0x38; byte3 = 0; goto CALL; break;


        // ######################### IMMEDIATE #########################
        // xxx(byte2)
        case 0xc6: ADD(byte2, 0); break;    // ADI
        case 0xce: ADD(byte2, !!CF); break; // ACI
        case 0xd6: SUB(byte2, 0); break;    // SUI
        case 0xde: SUB(byte2, !!CF); break; // SBI
        case 0xe6: ANA(byte2); break;   // ANI
        case 0xee: XRA(byte2); break;   // XRI
        case 0xf6: ORA(byte2); break;   // ORI
        case 0xfe: CMP(byte2); break;   // CPI

        // ######################### XTHL/XCHG #########################
        //
        case 0xe3: // XTHL ---- L <-> (SP);H <-> (SP+1)
            t8 = mem_read(SPL, SPH);
            mem_write(SPL, SPH, L);
            L = t8;
            SPL++;
            if (SPL == 0) SPH++;
            t8 = mem_read(SPL, SPH);
            mem_write(SPL, SPH, H);
            H = t8;
            SPL--;
            if (SPL == 0xff) SPH--; // atari, see if this can be done faster
            break;
        case 0xeb: // XCHG ---- H <-> D;L <-> E
            t8 = H;
            H = D;
            D = t8;
            t8 = L;
            L = E;
            E = t8;
            break;

        // ######################### PCHL/SPHL #########################
        //
        case 0xe9: // PCHL ---- PC.hi <- H;PC.lo <- L
            PCL = L;
            PCH = H;
            PCHa = PCH & 0x3f;      // adjust!
            curbank = PCH>>6;
            break;
        case 0xf9: // SPHL ---- SP <- HL
            SPL = L;
            SPH = H;
            break;

        // ######################### OUT/IN #########################
        //
        case 0xd3: // OUT d8 ---- OUTput A to device num
            bios_entry(byte2);
            break;
        case 0xdb: // IN d8 ---- INput from device num to A
            break;

        // ######################### EI/DI #########################
        //
        case 0xf3: // DI ---- Disable Interrupts
            break;
        case 0xfb: // EI ---- Enable Interrupts
            break;

        case 0x08: // undefined
        case 0x10:
        case 0x18:
        case 0x20:
        case 0x28:
        case 0x30:
        case 0x38:
        case 0xcb:
        case 0xd9:
        case 0xdd:
        case 0xed:
        case 0xfd:
            printf("CPU: undefined opcode: %02x\n", instruction);
            exit(1);
            break;
        default:
            printf("CPU: unimplemented opcode %02X\n", instruction);
            exit(1);
            break;
        }
    }
}

// -------------------------------------------------------------------------

struct termios orig_termios;
static char *CLEAR     = "c";

static void reset_terminal_mode(void) {
    tcsetattr(0, TCSANOW, &orig_termios);
//    fputs(RESET, stdout);
}

static int kbhit() {
    struct timeval tv = { 0L, 0L };
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(0, &fds);
    return select(1, &fds, NULL, NULL, &tv) > 0;
}

int main(int argc, char **argv) {
    int r;

    memcpy(&mem[3][BIOS&0x3fff], bios_sys, bios_sys_len);

    if (argc != 2) {
        fprintf(stderr, "usage: atari8080 disk.img\n");
        return 1;
    }

    dsk0 = fopen(argv[1], "rb+");
    if (!dsk0) {
        fprintf(stderr, "unable to open %s\n", argv[1]);
        return 1;
    }

    struct termios new_termios;

    tcgetattr(0, &orig_termios);
    memcpy(&new_termios, &orig_termios, sizeof(new_termios));

    atexit(reset_terminal_mode);
    cfmakeraw(&new_termios);
    tcsetattr(0, TCSANOW, &new_termios);

//    fputs(CLEAR, stdout);
//    fflush(stdout);

    memset(&zp, 0, sizeof(zp));

    PCL = BOOTF & 0xff;
    PCH = BOOTF>>8;
    PCHa = PCH & 0x3f;
    curbank = 3;

    run_emulator();

    return 0;
}
