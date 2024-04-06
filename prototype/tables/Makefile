
all: tables.h

tablegen: tablegen.c
	$(CC) -o tablegen tablegen.c

tables.h: tablegen
	./tablegen > tables.h

clean:
	rm -f *~ tablegen tables.h
