
CPMFILES = \
	cpm2-plm/STAT.COM \
	cpm2-plm/DUMP.COM \
	cpm2-plm/PIP.COM \
	tests/* \
	misc/* \
	software/wordstar33/* \
#	cpm2-plm/MAC.COM \
#	cpm2-plm/LOAD.COM \
#	tests/*.ASM \

CFLAGS += -O3

all: atari8080 atari8080-debug

atari8080: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -o $@ $< -lm

atari8080-bios-debug: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -o $@ $< -lm

atari8080-debug: atari8080.c Makefile disk.img tables/tables.h
	$(CC) $(CFLAGS) -DBIOSDEBUG -DDEBUG -o $@ $< -lm

disk.img: Makefile
	dd if=/dev/zero of=disk.img bs=128 count=8190
	mkfs.cpm -f atarihd disk.img
	cpmcp -f atarihd disk.img $(CPMFILES) 0:

tables/tables.h: tables/tablegen tables/tablegen.c
	$(MAKE) -C tables tables.h

clean:
	make -C tables clean
	rm -f atari8080 atari8080-debug atari8080-bios-debug disk.img *.img *~ */*~ */*/*~