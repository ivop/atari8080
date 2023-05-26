
CPMFILES = \
	cpm2-plm/STAT.COM \
	cpm2-plm/DUMP.COM \
	cpm2-plm/PIP.COM \
	tests/*.COM \
#	cpm2-plm/MAC.COM \
#	cpm2-plm/LOAD.COM \
#	tests/*.ASM \
#	tests/*.MAC \

CFLAGS += -O3

all: atari8080

atari8080: atari8080.c Makefile bootdisk.img tables/tables.h
	$(CC) $(CFLAGS) -o $@ $< -lm

atari8080-bios-debug: atari8080.c Makefile bootdisk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -o $@ $< -lm

atari8080-debug: atari8080.c Makefile bootdisk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -DDEBUG -o $@ $< -lm

bios.bin: bios.asm
	asl -D origin=0fa00h -o bios.p bios.asm
	p2bin -k -l '$$00' -r '$$fa00-$$faff' bios.p bios.bin

bootsectors.bin: cpm22/ccp.sys cpm22/bdos.sys
	cat cpm22/ccp.sys cpm22/bdos.sys > bootsectors.bin

bootdisk.img: bootsectors.bin Makefile
	dd if=/dev/zero of=bootdisk.img bs=128 count=2002
	mkfs.cpm -f ibm-3740-noskew bootdisk.img
	dd if=bootsectors.bin of=bootdisk.img bs=128 count=52 conv=notrunc
	cpmcp -f ibm-3740-noskew bootdisk.img $(CPMFILES) 0:

tables/tables.h: tables/tablegen tables/tablegen.c
	$(MAKE) -C tables tables.h

clean:
	make -C tables clean
	rm -f atari8080 atari8080-debug atari8080-bios-debug bootsectors.bin bootdisk.img *.img *~ */*~ */*/*~
