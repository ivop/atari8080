
all: bdos.h ccp.h

bdos.h:	bdos.sys
	xxd -i bdos.sys > bdos.h

bdos.sys: bdos.asm
	asl -D origin=0ec00h -o bdos.p bdos.asm
	p2bin -k -l '$$00' -r '$$ec00-$$f9ff' bdos.p bdos.sys

ccp.h: ccp.sys
	xxd -i ccp.sys > ccp.h

ccp.sys: ccp.asm
	asl -D origin=0e400h -o ccp.p ccp.asm
	p2bin -k -l '$$00' -r '$$e400-$$ebff' ccp.p ccp.sys

clean:
	rm -f *.p *.bin *~ *.sys *.h
