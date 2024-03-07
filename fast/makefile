CC=gcc
CFLAGS=-Wall -Wextra -std=c99 -O2 -pedantic
GHDL=ghdl
IMAGE=subleq

.PHONY: all run simulation viewer clean 

all: simulation

run: subleq ${IMAGE}.dec
	./subleq ${IMAGE}.dec

simulation: tb.ghw

viewer: tb.ghw signals.tcl
	gtkwave -S signals.tcl -f $< > /dev/null 2>&1 &

subleq: subleq.c
	${CC} ${CFLAGS} $< -o $@

%.o: %.vhd
	${GHDL} -a -g $<

%.hex: %.dec hex
	./hex $< > $@

top.o: top.vhd subleq.o util.o

tb.o: tb.vhd subleq.o top.o

tb: tb.o subleq.o top.o
	${GHDL} -e $@

${IMAGE}.hex: ${IMAGE}.dec hex
	./hex ${IMAGE}.dec > $@

tb.ghw: tb tb.cfg subleq.hex
	${GHDL} -r $< --wave=$<.ghw --max-stack-alloc=16384 --ieee-asserts=disable

clean:
	git clean -fdx .


