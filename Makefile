
CPMFILES = \
	cpm2-plm/STAT.COM \
	cpm2-plm/DUMP.COM \
	cpm2-plm/PIP.COM \
	tests/*.COM \
	misc/* \
#	cpm2-plm/MAC.COM \
#	cpm2-plm/LOAD.COM \
#	tests/*.ASM \

CFLAGS += -O3

all: atari8080 atari8080-debug 8080.xex 8080.ovl

atari8080: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -o $@ $< -lm

atari8080-bios-debug: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -o $@ $< -lm

atari8080-debug: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -DDEBUG -o $@ $< -lm

disk.img: Makefile
	dd if=/dev/zero of=disk.img bs=128 count=2002
	mkfs.cpm -f atarihd disk.img
	cpmcp -f atarihd disk.img $(CPMFILES) 0:

tables/tables.h: tables/tablegen tables/tablegen.c
	$(MAKE) -C tables tables.h

8080.xex: 8080.s cio.s tables/tables.s Makefile
	mads -d:TEST=1 -o:8080.xex 8080.s

8080.ovl: 8080.s cio.s tables/tables.s Makefile
	mads -d:CPM65=1 -o:8080.ovl 8080.s

tables/tables.s: tables/tablegen2 tables/tablegen2.c
	$(MAKE) -C tables tables.s

clean:
	make -C tables clean
	rm -f atari8080 atari8080-debug atari8080-bios-debug disk.img *.img *~ */*~ */*/*~ *.xex
