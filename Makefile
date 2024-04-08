
all: 8080.ovl

8080.ovl: 8080.s cio.s tables/tables.s Makefile
	mads -o:8080.ovl 8080.s

tables/tables.s: tables/tablegen2 tables/tablegen2.c
	$(MAKE) -C tables tables.s

clean:
	make -C tables clean
	rm -f *~ */*~ */*/*~ *.ovl
