
all: tables.h tables.s

tablegen: tablegen.c
	$(CC) -o tablegen tablegen.c

tablegen2: tablegen2.c
	$(CC) -o tablegen2 tablegen2.c

tables.h: tablegen
	./tablegen > tables.h

tables.s: tablegen2
	./tablegen2 > tables.s

clean:
	rm -f *~ tablegen tables.h tablegen2 tables.s
