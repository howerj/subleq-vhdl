CC=gcc
CFLAGS=-Wall -Wextra -std=c99 -O2 -pedantic
GHDL=ghdl
GOPTS=--max-stack-alloc=16384 --ieee-asserts=disable
USB?=/dev/ttyUSB0
BAUD?=115200
DIFF?=vimdiff
IMAGE=subleq
#BAUD?=9600

.PHONY: all run diff simulation viewer clean documentation synthesis implementation bitfile

all: subleq simulation

run: subleq ${IMAGE}.dec
	./subleq ${IMAGE}.dec

talk:
	picocom --omap delbs -e b -b ${BAUD} ${USB}

simulation: tb.ghw

viewer: tb.ghw signals.tcl
	gtkwave -S signals.tcl -f $< > /dev/null 2>&1 &

documentation: readme.htm

%.htm: %.md
	pandoc $< -o $@

subleq: subleq.c
	${CC} ${CFLAGS} $< -o $@

%.an: %.vhd
	${GHDL} -a -g $<
	touch $@

%.hex: %.dec hex
	./hex $< > $@

uart.an: uart.vhd util.an

top.an: top.vhd subleq.an util.an uart.an

tb.an: tb.vhd subleq.an top.an

tb: tb.an subleq.an top.an
	${GHDL} -e $@
	touch $@

subsys.an: subsys.vhd subleq.an util.an

fast_tb.an: util.an subsys.an subleq.an

fast_tb: fast_tb.an subleq.an subsys.an util.an
	${GHDL} -e $@
	touch $@

${IMAGE}.hex: ${IMAGE}.dec hex
	./hex ${IMAGE}.dec > $@

gforth.dec: eforth.txt
	gforth $< > $@

gforth: subleq gforth.dec
	./subleq gforth.dec

tb.ghw: tb tb.cfg subleq.hex
	${GHDL} -r $< --wave=$<.ghw ${GOPTS}

fast_tb.ghw: fast_tb tb.cfg subleq.hex
	${GHDL} -r $< --wave=$<.ghw ${GOPTS}


SOURCES = \
	top.vhd \
	subleq.vhd \
	uart.vhd \
	util.vhd

OBJECTS = ${SOURCES:.vhd=.o}

bitfile: design.bit

reports:
	@[ -d reports    ]    || mkdir reports
tmp:
	@[ -d tmp        ]    || mkdir tmp
tmp/_xmsgs:
	@[ -d tmp/_xmsgs ]    || mkdir tmp/_xmsgs

tmp/top.prj: tmp
	@rm -f tmp/top.prj
	@( \
	    for f in $(SOURCES); do \
	        echo "vhdl work \"$$f\""; \
	    done; \
	    echo "vhdl work \"top.vhd\"" \
	) > tmp/top.prj

tmp/top.lso: tmp
	@echo "work" > tmp/top.lso

tmp/top.xst: tmp tmp/_xmsgs tmp/top.lso tmp/top.lso
	@( \
	    echo "set -tmpdir \"tmp\""; \
	    echo "set -xsthdpdir \"tmp\""; \
	    echo "run"; \
	    echo "-lso tmp/top.lso"; \
	    echo "-ifn tmp/top.prj"; \
	    echo "-ofn top"; \
	    echo "-p xc6slx16-csg324-3"; \
	    echo "-top top"; \
	    echo "-opt_mode area"; \
	    echo "-opt_level 2" \
	) > tmp/top.xst

synthesis: subleq.hex reports tmp tmp/_xmsgs tmp/top.prj tmp/top.xst
	@echo "Synthesis running..."
	@${TIME} xst -intstyle silent -ifn tmp/top.xst -ofn reports/xst.log
	@mv _xmsgs/* tmp/_xmsgs
	@rmdir _xmsgs
	@mv top_xst.xrpt tmp
	@grep "ERROR\|WARNING" reports/xst.log | \
	 grep -v "WARNING.*has a constant value.*This FF/Latch will be trimmed during the optimization process." | \
	 cat
	@grep ns reports/xst.log | grep 'Clock period'

implementation: reports tmp
	@echo "Implementation running..."

	@[ -d tmp/xlnx_auto_0_xdb ] || mkdir tmp/xlnx_auto_0_xdb

	@${TIME} ngdbuild -intstyle silent -quiet -dd tmp -uc top.ucf -p xc6slx16-csg324-3 top.ngc top.ngd
	@mv top.bld reports/ngdbuild.log
	@mv _xmsgs/* tmp/_xmsgs
	@rmdir _xmsgs
	@mv xlnx_auto_0_xdb/* tmp
	@rmdir xlnx_auto_0_xdb
	@mv top_ngdbuild.xrpt tmp

	@${TIME} map -intstyle silent -detail -p xc6slx16-csg324-3 -convert_bram8 -pr b -c 100 -w -o top_map.ncd top.ngd top.pcf
	@mv top_map.mrp reports/map.log
	@mv _xmsgs/* tmp/_xmsgs
	@rmdir _xmsgs
	@mv top_usage.xml top_summary.xml top_map.map top_map.xrpt tmp

	@${TIME} par -intstyle silent -w -ol std top_map.ncd top.ncd top.pcf
	@mv top.par reports/par.log
	@mv top_pad.txt reports/par_pad.txt
	@mv _xmsgs/* tmp/_xmsgs
	@rmdir _xmsgs
	@mv par_usage_statistics.html top.ptwx top.pad top_pad.csv top.unroutes top.xpi top_par.xrpt tmp

design.bit: reports tmp/_xmsgs
	@echo "Generate bitfile running..."
	@touch webtalk.log
	@${TIME} bitgen -intstyle silent -w top.ncd
	@mv top.bit design.bit
	@mv top.bgn reports/bitgen.log
	@mv _xmsgs/* tmp/_xmsgs
	@rmdir _xmsgs
	@sleep 5
	@mv top.drc top_bitgen.xwbt top_usage.xml top_summary.xml webtalk.log tmp
	@grep -i '\(warning\|clock period\)' reports/xst.log

upload:
	djtgcfg prog -d Nexys3 -i 0 -f design.bit

design: clean simulation synthesis implementation bitfile

postsyn:
	@netgen -w -ofmt vhdl -sim ${NETLIST}.ngc post_synthesis.vhd
	@netgen -w -ofmt vhdl -sim ${NETLIST}.ngd post_translate.vhd
	@netgen  -pcf ${NETLIST}.pcf -w -ofmt vhdl -sim ${NETLIST}.ncd post_map.vhd

clean:
	git clean -fdx .


