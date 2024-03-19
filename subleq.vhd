-- File:        subleq.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- License:     MIT / Public Domain
-- Description: SUBLEQ CPU
--
-- This is a SUBLEQ CPU, or a One Instruction Set Computer (OISC), it
-- is Turing complete and capable of running a Forth interpreter (with
-- the appropriate image). See <https://github.com/howerj/subleq> for
-- the source of the eForth image, another one of my projects.
--
-- A version that uses both ports of a Dual Port Block RAM would have
-- fewer states and would operate faster (the operands `a` and `b`
-- could be loaded in one cycle, then `mem[a]` and `mem[b]` the next
-- cycle instead of the four cycles it takes in this implementation).
--
-- There are advantages to this single port design however. It means
-- that if a Dual Port Block RAM was to host the SUBLEQ program then
-- this CPU would only use one of the I/O channels for it, the other
-- channel could be used for other circuitry allowing it to communicate
-- with the SUBLEQ CPU and program. Input and Output is quite the
-- weakness in this design, only a single byte of input and output
-- is allowed which is really only suitable for a UART.
--
-- It would be nice to make as much configurable as possible (via
-- generics) to make the design more flexible. This has been done to
-- an extent where it is easy (for example you can invert the jump
-- condition if you want and input can be made to be non-blocking).
--
-- Extra things that could be done:
--
-- * Turn this file into a design with multiple components that can
-- just be placed down, including default SUBLEQ programs (such as
-- the mentioned Forth interpreter). This would mean moving the
-- Block RAM component into here, and the UART would need simplifying.
-- * Improve Input/Output capabilities allowing multiple peripherals
-- to be hung off of the design.
-- * The simulation could be sped up by not simulating the UART,
-- instead just doing byte oriented I/O.
-- * The design could be optimized somewhat.
--
library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- Used for debug only (turned off for synthesis)

entity subleq is
	generic (
		asynchronous_reset: boolean    := true;   -- use asynchronous reset if true, synchronous if false
		delay:              time       := 0 ns;   -- simulation only, gate delay
		N:                  positive   := 16;     -- size the CPU
		jump_leq:           std_ulogic := '1';    -- '1' to jump on less-than-or-equal, '0' on positive
		non_blocking_input: boolean    := false;  -- if true, input will be -1 if there is no input
		strict_io:          boolean    := true;   -- if true, I/O happens when `a` or `b` are -1, else when high bit set
		debug:              natural    := 0);     -- debug level, 0 = off
	port (
		clk:           in std_ulogic; -- Guess what this is?
		rst:           in std_ulogic; -- Can be sync or async
		o:            out std_ulogic_vector(N - 1 downto 0);
		i:             in std_ulogic_vector(N - 1 downto 0);
		a:            out std_ulogic_vector(N - 1 downto 0);
		we, re:       out std_ulogic; -- Write and read enable for memory only
		obyte:        out std_ulogic_vector(7 downto 0); -- UART output byte
		ibyte:         in std_ulogic_vector(7 downto 0); -- UART input byte
		obsy, ihav:    in std_ulogic; -- Output busy / Have input
		io_we, io_re: out std_ulogic; -- Write and read enable for I/O (UART)
		pause:         in std_ulogic; -- pause the CPU in the `S_A` state
		blocked:      out std_ulogic; -- is the CPU paused, or blocking on I/O?
		halted:       out std_ulogic); -- Is the system halted?
end;

architecture rtl of subleq is
	type state_t is (
		S_RESET, 
		S_A, S_B, S_LA, S_LB,
		S_STORE,
		S_JMP, S_NJMP,
		S_IN, S_OUT,
		S_HALT);

	type registers_t is record
		b:  std_ulogic_vector(N - 1 downto 0);
		c:  std_ulogic_vector(N - 1 downto 0);
		la: std_ulogic_vector(N - 1 downto 0);
		pc: std_ulogic_vector(N - 1 downto 0);
		state:  state_t;
		stop: std_ulogic;
		input, output: std_ulogic;
	end record;

	constant registers_default: registers_t := (
		b  => (others => '0'),
		c  => (others => '0'),
		la => (others => '0'),
		pc => (others => '0'),
		state => S_RESET,
		stop => '0',
		input => '0',
		output => '0');

	signal c, f: registers_t := registers_default; -- All state is captured in here
	signal leq0, ones, high, io: std_ulogic := '0'; -- CPU Flags
	signal sub, npc: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1');

	-- Obviously this does not synthesize, which is why synthesis is turned
	-- off for the body of this function, it does make debugging much easier
	-- though, we will be able to see which instructions are executed and do so
	-- by name.
	procedure print_debug_info is
		variable oline: line;
		function int(slv: in std_ulogic_vector) return string is
		begin
			return integer'image(to_integer(signed(slv)));
		end function;
	begin
		-- synthesis translate_off
		if debug >= 2 then
			write(oline, int(c.pc)  & ": ");
			write(oline, state_t'image(c.state) & HT);
			write(oline, int(c.b)   & " ");
			write(oline, int(c.c)   & " ");
			write(oline, int(c.la)  & " ");
			if debug >= 3 and c.state /= f.state then
				write(oline, state_t'image(c.state) & " => ");
				write(oline, state_t'image(f.state));
			end if;
			writeline(OUTPUT, oline);
		end if;
		-- synthesis translate_on
	end procedure;
begin
	npc   <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	sub   <= std_ulogic_vector(unsigned(i) - unsigned(c.la)) after delay;
	leq0  <= '1' when c.la(c.la'high) = '1' or c.la = AZ else '0' after delay;
	o     <= c.la after delay;
	obyte <= c.la(obyte'range) after delay;
	ones  <= '1' when strict_io and i = AO else '0' after delay;
	high  <= '1' when (not strict_io) and i(i'high) = '1' else '0' after delay;
	io    <= '1' when ones = '1' or high = '1' else '0' after delay;

	process (clk, rst) begin
		if rst = '1' and asynchronous_reset then
			c.state <= S_RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.state <= S_RESET after delay;
			else
				print_debug_info;
			end if;
		end if;
	end process;

	process (c, i, npc, io, leq0, sub, ibyte, obsy, ihav, pause) begin
		f <= c after delay;
		halted <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		we <= '0' after delay;
		re <= '0' after delay;
		a <= c.pc after delay;
		blocked <= '0' after delay;
		if c.pc(c.pc'high) = '1' then f.stop <= '1' after delay; end if;

		case c.state is
		when S_RESET => 
			f <= registers_default after delay;
			f.state <= S_A after delay;
			a <= (others => '0') after delay;
			re <= '1' after delay;
		when S_A =>
			f.state <= S_B after delay;
			f.la <= i after delay;
			re <= '1' after delay;
			a <= npc after delay;
			f.pc <= npc after delay;
			f.input <= '0' after delay;
			f.output <= '0' after delay;
			if io = '1' then
				f.input <= '1' after delay;
			end if;
			if c.stop = '1' then
				f.state <= S_HALT after delay;
			elsif pause = '1' then
				blocked <= '1' after delay;
				f.state <= S_A after delay;
			end if;
		when S_B =>
			f.state <= S_LA after delay;
			f.b <= i after delay;
			re <= '1' after delay;
			a <= c.la after delay;
			f.pc <= npc after delay;
			if io = '1' then
				f.output <= '1' after delay;
			end if;
			if c.input = '1' then -- skip S_LA
				a <= i after delay;
				f.state <= S_IN after delay;
				f.la <= (others => '0') after delay;
				f.la(ibyte'range) <= ibyte after delay;
			end if;
		when S_LA =>
			f.state <= S_LB after delay;
			f.la <= i after delay;
			a <= c.b after delay;
			re <= '1' after delay;
			if c.output = '1' then
				a <= c.pc after delay;
				f.state <= S_OUT after delay;
			end if;
		when S_LB =>
			f.state <= S_STORE after delay;
			f.la <= sub after delay;
			re <= '1' after delay;
			a <= c.pc after delay;
		when S_STORE =>
			f.state <= S_NJMP after delay;
			f.c <= i after delay;
			a <= c.b after delay;
			we <= '1' after delay;
			if leq0 = jump_leq and c.input = '0' then
				f.state <= S_JMP after delay;
			end if;
		when S_JMP =>
			f.state <= S_A after delay;
			a <= c.c after delay;
			f.pc <= c.c after delay;
			re <= '1' after delay;
		when S_NJMP =>
			f.state <= S_A after delay;
			f.pc <= npc after delay;
			a <= npc after delay;
			re <= '1' after delay;
		when S_IN =>
			a <= c.b after delay;
			f.la <= (others => '0');
			f.la(ibyte'range) <= ibyte after delay;
			blocked <= '1' after delay;
			if ihav = '1' then
				f.state <= S_STORE after delay;
				io_re <= '1' after delay;
				blocked <= '0' after delay;
			elsif non_blocking_input then
				f.state <= S_STORE after delay;
				f.la <= (others => '1');
				blocked <= '0' after delay;
			end if;
		when S_OUT =>
			a <= npc after delay;
			f.pc <= npc after delay;
			re <= '1' after delay;
			blocked <= '1' after delay;
			if obsy = '0' then
				f.state <= S_A after delay;
				io_we <= '1' after delay;
				blocked <= '0' after delay;
			end if;
		when S_HALT =>
			halted <= '1' after delay;
		end case;
	end process;
end architecture;
