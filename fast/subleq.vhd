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
use std.textio.all;

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
		clk:           in std_ulogic;
		rst:           in std_ulogic;
		o:            out std_ulogic_vector(N - 1 downto 0);
		i:             in std_ulogic_vector(N - 1 downto 0);
		a:            out std_ulogic_vector(N - 1 downto 0);
		we, re:       out std_ulogic;
		obyte:        out std_ulogic_vector(7 downto 0); -- UART output byte
		ibyte:         in std_ulogic_vector(7 downto 0); -- UART input byte
		obsy, ihav:    in std_ulogic; -- Output busy / Have input
		io_we, io_re: out std_ulogic; -- Write and read enable
		pause:         in std_ulogic;
		halt:         out std_ulogic);
end;

architecture rtl of subleq is
	type state_t is (
		S_RESET, 
		S_A, S_B, S_C, S_LA, S_LB, 
		S_STORE, 
		S_JMP, S_NJMP, 
		S_IN, S_IN_STORE, S_OUT, 
		S_HALT);

	type registers_t is record
		a:  std_ulogic_vector(N - 1 downto 0);
		b:  std_ulogic_vector(N - 1 downto 0);
		c:  std_ulogic_vector(N - 1 downto 0);
		la: std_ulogic_vector(N - 1 downto 0);
		lb: std_ulogic_vector(N - 1 downto 0);
		pc: std_ulogic_vector(N - 1 downto 0);
		res: std_ulogic_vector(N - 1 downto 0);
		state:  state_t;
		stop: std_ulogic;
		input, output: std_ulogic;
	end record;

	constant registers_default: registers_t := (
		a  => (others => '0'),
		b  => (others => '0'),
		c  => (others => '0'),
		la => (others => '0'),
		lb => (others => '0'),
		pc => (others => '0'),
		res => (others => '0'),
		state => S_RESET,
		stop => '0',
		input => '0',
		output => '0');

	signal c, f: registers_t := registers_default;
	signal leq, neg, high, io: std_ulogic := '0';
	signal sub, npc: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1');

	-- Obviously this does not synthesize, which is why synthesis is turned
	-- off for the body of this function, it does make debugging much easier
	-- though, we will be able to see which instructions are executed and do so
	-- by name.
	procedure print_debug_info is
		variable ll: line;

		function hx(slv: in std_ulogic_vector) return string is -- std_ulogic_vector to hex string
			constant cv: string := "0123456789ABCDEF";
			constant qu: integer := slv'length   / 4;
			constant rm: integer := slv'length mod 4;
			variable rs: string(1 to qu);
			variable sl: std_ulogic_vector(3 downto 0);
		begin
			assert rm = 0 severity failure;
			for l in 0 to qu - 1 loop
				sl := slv((l * 4) + 3 downto (l * 4));
				rs(qu - l) := cv(to_integer(unsigned(sl)) + 1);
			end loop;
			return rs;
		end function;
	begin
		-- synthesis translate_off
		if debug > 0 then
			write(ll, hx(c.pc)  & ": ");
			write(ll, state_t'image(c.state) & HT);
			write(ll, hx(c.a)   & " ");
			write(ll, hx(c.b)   & " ");
			write(ll, hx(c.c)   & " ");
			write(ll, hx(c.la)  & " ");
			write(ll, hx(c.lb)  & " ");
			write(ll, hx(c.res) & " ");
			writeline(OUTPUT, ll);
			if debug > 1 then
				write(ll, state_t'image(c.state) & " => ");
				write(ll, state_t'image(f.state));
				writeline(OUTPUT, ll);
			end if;
		end if;
		-- synthesis translate_on
	end procedure;
begin
	npc   <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	sub   <= std_ulogic_vector(unsigned(i) - unsigned(c.la)) after delay;
	leq   <= '1' when c.res(c.res'high) = '1' or c.res = AZ else '0' after delay;
	o     <= c.res after delay;
	obyte <= c.la(obyte'range) after delay;
	neg   <= '1' when strict_io and i = AO else '0' after delay;
	high  <= '1' when (not strict_io) and i(i'high) = '1' else '0' after delay;
	io    <= '1' when neg = '1' or high = '1' else '0' after delay;

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

	process (c, i, npc, io, leq, sub, ibyte, obsy, ihav, pause) begin
		f <= c after delay;
		halt <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		we <= '0' after delay;
		re <= '0' after delay;
		a <= c.pc after delay;
		if c.pc(c.pc'high) = '1' then f.stop <= '1' after delay; end if;

		case c.state is
		when S_RESET => 
			f <= registers_default after delay;
			f.state <= S_A after delay;
			a <= (others => '0') after delay;
			re <= '1' after delay;
		when S_A =>
			f.state <= S_B after delay;
			f.a <= i after delay;
			re <= '1' after delay;
			a <= npc after delay;
			f.pc <= npc after delay;
			f.input <= '0';
			if io = '1' then
				f.input <= '1';
			end if;
			if c.stop = '1' then
				f.state <= S_HALT after delay;
			elsif pause = '1' then
				f.state <= S_A;
			end if;
		when S_B =>
			f.state <= S_C after delay;
			f.b <= i after delay;
			re <= '1' after delay;
			a <= npc after delay;
			f.pc <= npc after delay;
			f.output <= '0';
			if io = '1' then
				f.output <= '1';
			end if;
		when S_C =>
			f.state <= S_LA after delay;
			f.c <= i after delay;
			re <= '1' after delay;
			a <= c.a after delay;
			f.pc <= npc after delay;
		when S_LA =>
			f.state <= S_LB after delay;
			f.la <= i after delay;
			a <= c.b after delay;
			re <= '1' after delay;
		when S_LB =>
			f.state <= S_STORE after delay;
			f.lb <= i after delay;
			f.res <= sub after delay;
			a <= c.b after delay;
			re <= '1' after delay;
			if c.input = '1' then
				f.state <= S_IN after delay;
				f.res <= (others => '0');
				f.res(ibyte'range) <= ibyte;
			elsif c.output = '1' then
				f.state <= S_OUT after delay;
			end if;
		when S_STORE =>
			f.state <= S_NJMP after delay;
			a <= c.b after delay;
			we <= '1' after delay;
			if leq = jump_leq then
				f.state <= S_JMP after delay;
			end if;
		when S_JMP =>
			f.state <= S_A after delay;
			a <= c.c after delay;
			f.pc <= c.c after delay;
			re <= '1' after delay;
		when S_NJMP =>
			f.state <= S_A after delay;
			re <= '1' after delay;
		when S_IN =>
			a <= c.b after delay; -- hold address
			f.res <= (others => '0');
			f.res(ibyte'range) <= ibyte;
			if ihav = '1' then
				f.state <= S_IN_STORE after delay;
				io_re <= '1' after delay;
			elsif non_blocking_input then
				f.state <= S_IN_STORE after delay;
				f.res <= (others => '1');
			end if;
		when S_IN_STORE =>
			f.state <= S_NJMP after delay;
			a <= c.b after delay; -- hold address
			we <= '1' after delay;
		when S_OUT =>
			a <= c.pc after delay;
			re <= '1' after delay;
			if obsy = '0' then
				f.state <= S_A after delay;
				io_we <= '1' after delay;
			end if;
		when S_HALT =>
			halt <= '1' after delay;
		end case;
	end process;
end architecture;
