### Intel 8080 Emulator

This repository contains an Intel 8080 emulator for the Atari 130XE written in 6502 assembly.

The Makefile builds an overlay that is meant to be run on top of CP/M-65.
It translates all 8080 BIOS calls to their CP/M-65 equivalents. BDOS and CCP
run "natively" on the 8080 emulation.
The overlay loader is currently at https://github.com/ivop/cpm65/tree/8080ovl.

To assembly 8080.s into a binary you need the MADS Assembler which can be
found here: https://github.com/tebe6502/Mad-Assembler/ 

#### Possible Future work

##### Source to source translator

We could use the instruction emulation code to implement a 8080 to 6502
source to source translator. Each 8080 opcode is replaced by the
equivalent in 6502 instructions. We won't be using the extended memory
banks anymore, so memory access will also be faster. We do need a proper
(dis)assembly listing of the source program. One where data and code
is cleanly separated. Some constructs will need manual intervention,
like call 5 to access BDOS in CP/M or checks for the upper limit of the
TPA area by checking where BDOS starts. It has to be replaced by the CP/M-65
equivalent. After translation, the 6502 code could be run through a
peephole optimizer to remove redundant loads and stores. Another
possibility is to remove flag calculation code if the flags are changed
afterwards before they are evaluated by one of the jump instructions.

##### Dynamic recompiler

Right now, for a lot of instructions,
the overhead of the instruction dispatcher is huge.
For example, all MOV instructions, except when M is involved, are just
a single lda and a single sta in 6502 assembly.
Add to that at least 12 instructions for the instruction fetcher,
and it's obvious that that's a huge factor in slowing down the emulation.
It would be nice if multiple instructions could be executed after
eachother without the dispatcher slowing it down. However, the setup time
and maintaining a cache of recompiled instructions as to not having to
recompile them over and over again might become problematic and not
worth the effort.

#### Test suites

All four tests with the 6502 core are succesful!

![8080pre.png](images/8080pre.png) ![tst8080.png](images/tst8080.png)  
![cputest.png](images/cputest.png) ![8080exm.png](images/8080exm.png)  


The 8080 prototype core in C runs all validation sets correctly. Note that the BIOS handling might not have all the bugfixes the 6502 version got.  

Output:

```
$ ./atari8080 bootdisk.img 

64k CP/M vers 2.2

A>tst8080
MICROCOSM ASSOCIATES 8080/8085 CPU DIAGNOSTIC
 VERSION 1.0  (C) 1980

 CPU IS OPERATIONAL
A>cputest

DIAGNOSTICS II V1.2 - CPU TEST
COPYRIGHT (C) 1981 - SUPERSOFT ASSOCIATES

ABCDEFGHIJKLMNOPQRSTUVWXYZ
CPU IS 8080/8085
BEGIN TIMING TEST
END TIMING TEST
CPU TESTS OK

A>8080pre
8080 Preliminary tests complete
A>8080exm
8080exm
8080 instruction exerciser
dad <b,d,h,sp>................  PASS! crc is:14474ba6
aluop nn......................  PASS! crc is:9e922f9e
aluop <b,c,d,e,h,l,m,a>.......  PASS! crc is:cf762c86
<daa,cma,stc,cmc>.............  PASS! crc is:bb3f030c
<inr,dcr> a...................  PASS! crc is:adb6460e
<inr,dcr> b...................  PASS! crc is:83ed1345
<inx,dcx> b...................  PASS! crc is:f79287cd
<inr,dcr> c...................  PASS! crc is:e5f6721b
<inr,dcr> d...................  PASS! crc is:15b5579a
<inx,dcx> d...................  PASS! crc is:7f4e2501
<inr,dcr> e...................  PASS! crc is:cf2ab396
<inr,dcr> h...................  PASS! crc is:12b2952c
<inx,dcx> h...................  PASS! crc is:9f2b23c0
<inr,dcr> l...................  PASS! crc is:ff57d356
<inr,dcr> m...................  PASS! crc is:92e963bd
<inx,dcx> sp..................  PASS! crc is:d5702fab
lhld nnnn.....................  PASS! crc is:a9c3d5cb
shld nnnn.....................  PASS! crc is:e8864f26
lxi <b,d,h,sp>,nnnn...........  PASS! crc is:fcf46e12
ldax <b,d>....................  PASS! crc is:2b821d5f
mvi <b,c,d,e,h,l,m,a>,nn......  PASS! crc is:eaa72044
mov <bcdehla>,<bcdehla>.......  PASS! crc is:10b58cee
sta nnnn / lda nnnn...........  PASS! crc is:ed57af72
<rlc,rrc,ral,rar>.............  PASS! crc is:e0d89235
stax <b,d>....................  PASS! crc is:2b0471e9
Tests complete
A>dir
A: STAT     COM : DUMP     COM : PIP      COM : 8080EXM  COM
A: 8080PRE  COM : CPUTEST  COM : TST8080  COM
A>stat dsk:

    A: Drive Characteristics
 1944: 128 Byte Record Capacity
  243: Kilobyte Drive  Capacity
   64: 32  Byte Directory Entries
   64: Checked  Directory Entries
  128: Records/ Extent
    8: Records/ Block
   26: Sectors/ Track
    2: Reserved Tracks

A>
```

Copyright © 2023 by Ivo van Poorten, see LICENSE for details.
