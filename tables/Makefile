
all: tables.s

tablegen2: tablegen2.c
	$(CC) -o tablegen2 tablegen2.c

tables.s: tablegen2
	./tablegen2 > tables.s

clean:
	rm -f *~ tablegen2 tables.s
