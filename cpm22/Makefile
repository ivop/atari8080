
all: bios.h bdos.h ccp.h bios.sys bios-bbc.sys

bios.h:	bios2.sys
	xxd -i bios2.sys > bios.h

bios.sys: bios.asm
	asl -D origin=0fa00h -o bios.p bios.asm
	p2bin -k -l '$$00' -r '$$fa00-$$ffff' bios.p bios.sys

bios-bbc.sys: bios.asm
	asl -D origin=0fa00h,MASTER128=1 -o bios-bbc.p bios.asm
	p2bin -k -l '$$00' -r '$$fa00-$$ffff' bios-bbc.p bios-bbc.sys

bios2.sys: bios2.asm
	asl -D origin=0fa00h -o bios2.p bios2.asm
	p2bin -k -l '$$00' -r '$$fa00-$$ffff' bios2.p bios2.sys

bdos.h:	bdos.sys
	xxd -i bdos.sys > bdos.h

bdos.sys: bdos.asm
	asl -D origin=0ec00h -o bdos.p bdos.asm
	p2bin -k -l '$$00' -r '$$ec00-$$f9ff' bdos.p bdos.sys

ccp.h: ccp.sys
	xxd -i ccp.sys > ccp.h

ccp.sys: ccp.asm
	asl -D origin=0e400h -D noserial=1 -o ccp.p ccp.asm
	p2bin -k -l '$$00' -r '$$e400-$$ebff' ccp.p ccp.sys

clean:
	rm -f *.p *.bin *~ *.sys *.h
