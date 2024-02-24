# Richard James Howe
# TCL Script for GTKWave on tb.ghw
#

gtkwave::/Edit/Set_Trace_Max_Hier 0
gtkwave::/Time/Zoom/Zoom_Amount -27.0
gtkwave::/View/Show_Filled_High_Values 1
#gtkwave::setFromEntry 170ns

set names {
	top.tb.rst
	top.tb.clk
	top.tb.uut.cpu.a
	top.tb.uut.cpu.c.state
	top.tb.uut.cpu.c.a[15:0]
	top.tb.uut.cpu.c.la[15:0]
	top.tb.uut.cpu.c.b[15:0]
	top.tb.uut.cpu.c.lb[15:0]
	top.tb.uut.cpu.c.c[15:0]
	top.tb.uut.cpu.c.pc[15:0]
	top.tb.uut.cpu.c.input
	top.tb.uut.cpu.c.output
	top.tb.tx
	top.tb.rx
}

gtkwave::addSignalsFromList $names

foreach v $names {
	set a [split $v .]
	set a [lindex $a end]
	gtkwave::highlightSignalsFromList $v
	gtkwave::/Edit/Alias_Highlighted_Trace $a
	gtkwave::/Edit/UnHighlight_All $a
}

