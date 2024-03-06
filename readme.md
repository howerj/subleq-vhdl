# 16-bit SUBLEQ CPU written in VHDL with an eForth interpreter

* Author: Richard James Howe
* License: [The Unlicense](LICENSE) / Public Domain
* Email: <mailto:howe.r.j.89@gmail.com>
* Repo: <https://github.com/howerj/subleq-vhdl>

**This project is a work in progress. The VHDL simulation works, along
with the eForth interpreter that runs on it, but the project has not
been tested on an actual FPGA (it does synthesize).**.

This project contains a 16-bit SUBLEQ CPU written in VHDL that should
run on an FPGA (it is unlikely to be tested in actual hardware anytime
soon, instead being simulation only). It has be synthesized for a
Spartan-6 and there is nothing that stands out as indicating that the
design would not work, it has just not actually been run on one (yet).

If you feel like supporting the project you can buy a book from
Amazon, available [here](https://www.amazon.com/SUBLEQ-EFORTH-Forth-Metacompilation-Machine-ebook/dp/B0B5VZWXPL)
that describes how the eForth interpreter works and how to port a Forth to
a new platform.

There is a [simulator written in C](subleq.c) that can be used
to run the [eForth image](subleq.dec).

## Usage

Type:

	make run

To run the C simulator on the [subleq.dec][] image. (Requires make
and a C compiler, alternatively `cc subleq.c -o subleq && ./subleq subleq.dec`
will work.

Type `words` to see a list of defined Forth words.

	$ make run
	./subleq subleq.dec
	 ok
	words
	cold quit load evaluate set-input get-input list
	blank block buffer empty-buffers flush save-buffers
	update b/buf at-xy page bell ms [if] [else] [then]
	defined dump see compile-only immediate postpone \ .(
	( abort" $" ." exit rdrop r> >r marker does> >body user
	constant variable create next aft for else repeat while
	then again until if begin recurse ' :noname : ; [char]
	char word definitions +order -order (order) get-order
	interpret compile, literal compile find search-wordlist
	cfa nfa compare .s number? >number . u. u.r sign <# #s #
	#> hold parse -trailing query tib expect accept echo /
	mod /mod m/mod um/mod * um* d+ dnegate um+ abort throw
	catch space erase fill cmove type +string count c, ,
	allot align aligned source 2r> 2>r 2@ 2! source-id min
	max c! c@ lshift +! pick set-current get-current cr emit
	key key? ?exit execute cell- cells cell+ cell abs s>d
	negate within u<= u>= u> u< <= >= 0>= 0< > < 0<= 0<> 0>
	<> = 2dup 2drop -rot rot r@ ?dup tuck nip [ ] decimal hex
	rp! rp@ sp! sp@ here bl span >in state hld dpl base scr blk
	context #vocs pad this root-voc current <ok> ! @ 2/ and or
	xor invert over ) 1- 1+ 2* 0= rshift swap drop dup bye -
	+ eforth words only forth system forth-wordlist set-order

	bye

Hitting `ctrl-d` will not quit the interpreter, you must type `bye` (or
kill with `ctrl-c` if `ctrl-d` has been used to close the input stream
already).

Type:

	make

Or:

	make simulation

To run the VHDL simulation under GHDL.

	make viewer

Can be used to automatically run GTKWave on the simulation results.

To make something you can flash to a Spartan-6 FPGA for a Nexys-3 board:

	make synthesis implementation bitfile upload

This requires Xilinx ISE 14.7 which is horrendously out of date by now,
along with the fact that the Nexys-3 board is obsolete (I need a new
FPGA board).

Have fun!

## State machine diagram

The following shows a state-machine diagram for the SUBLEQ CPU, it is not
optimal, but it is *simple*. There are some obvious optimizations that could
be done (such as going straight from `a` to the `in` state if `a` is `-1`,
which would also perhaps allow us to reuse the `-1` check circuitry), these
I/O optimizations would not help *much* as most of the time is spent doing
computation. The `store` state could be skipped if the contents of the result
register is equal to what is loaded into the `lb` register.

![SUBLEQ State Machine](subleq.png)

This is the source for the above image, which is [Graphviz][] code, this
can be pasted into [GraphvizOnline][].

	digraph subleq {
	  reset -> a;
	  a -> b;
	  a -> a [label = "pause = 1"];
	  a -> halt;
	  b -> c;
	  c -> la;
	  la -> lb;
	  lb -> store;
	  lb -> in [label = "a = -1"];
	  lb -> out [label = "b = -1"];
	  halt -> halt;

	  store -> jmp [label="res <= 0"];
	  store -> njmp;

	  jmp -> a;
	  njmp -> a;

	  in -> in [label="ihav = '0'"];
	  in -> "in-store";
	  "in-store" -> njmp;

	  out -> a;
	  out -> out [label="obsy = '1'"];
	}

## To Do List

* [x] Do core implementation
  * [x] Debug application
* [x] Make small SUBLEQ test programs
* [x] Get implementation working in simulator with test programs
  * [x] `hi.dec`
  * [x] `hello.dec`
  * [x] `subleq.dec` (eForth interpreter)
    * [x] Test output
    * [x] Test input (requires better test bench)
  * [ ] `echo.dec` (optional)
  * [ ] `self.dec` with `hi.dec` (optional)
* Improve test bench
  * [x] Add more run time configuration options
  * [x] Add a UART that can print to STDOUT and read from STDIN (or a FILE)
* [x] Make cut-down and special SUBLEQ eForth image for the smaller (16KiB) BRAM
* [ ] Make one big VHDL file containing an initial Forth image and place it in `subleq.vhd`?
  * [x] Add a component that combines the Block RAM and SUBLEQ into one along
    with a test bench for it
  * [ ] Merge new module into main system.
* [ ] Optimize SUBLEQ design for slice area (and speed if possible)
* [ ] Get implementation working in hardware (need an FPGA board for this)
* [ ] Find way of interacting with other hardware
* [x] Using Graphviz online, make a state-machine diagram

## Other SUBLEQ projects

* <https://github.com/howerj/subleq>
* <https://github.com/howerj/subleq-forth>
* <https://github.com/howerj/subleq-js>
* <https://github.com/howerj/subleq-perl>
* <https://github.com/howerj/subleq-python>
* <https://github.com/pbrochard/subleq-eForthOS>

## References

* <https://en.wikipedia.org/wiki/Forth_(programming_language)>
* <https://en.wikipedia.org/wiki/One-instruction_set_computer>
* <https://github.com/howerj/bit-serial>
* <https://github.com/howerj/embed>
* <https://github.com/howerj/forth-cpu>
* <https://rosettacode.org/wiki/Subleq>
* <https://stackoverflow.com/questions/2982729>
* <https://stackoverflow.com/questions/34120161>
* <https://web.ece.ucsb.edu/~parhami/pubs_folder/parh88-ijeee-ultimate-risc.pdf>

[GraphvizOnline]: https://dreampuf.github.io/GraphvizOnline
[Graphviz]: https://graphviz.org/

