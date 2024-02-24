-- File:        subleq.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- License:     MIT / Public Domain
-- Description: SUBLEQ CPU

-- digraph subleq { 
--   // https://dreampuf.github.io/GraphvizOnline/
--   /* State machine of a SUBLEQ One Instruction Set Computer.  Need three registers; PC, A, B. */
-- 
--   START -> A [label="PC=0"];
--   A -> B;
--   A -> GET [label="A=-1"];
--   GET -> GET [label="wait"]; /* Get a character from UART, waiting for it */
--   GET -> GSTB;
--   GSTB -> NEXT;  /* Store result back to [b] */
--   B -> PLDA [label="B=-1"]; /* Put a character to UART, need to fetch character first... */
--   PLDA -> PUT;
--   PUT -> PUT [label="wait"]; /* Wait for UART TX Queue to be empty */
--   PUT -> NEXT:
--   NEXT -> A; /* Increment Program Counter to next instruction */
--   NEXT -> HALT [label="PC<0"];
--   B -> STB;
--   STB -> C [label="LEQ"];
--   STB -> NEXT [label="GNEQ"];
--   C -> A;
--   C -> HALT [label="PC<0"];
-- 
--   START [shape=start]; /* Start or Reset State */
--   HALT [shape=end]; /* HALT state happens when Program Counter is negative */
-- }

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity subleq is
	generic (
		asynchronous_reset: boolean    := true;   -- use asynchronous reset if true, synchronous if false
		delay:              time       := 0 ns;   -- simulation only, gate delay
		N:                  positive   := 16;     -- size the CPU
		debug:              natural    := 0);     -- debug level, 0 = off
	port (
		clk:      in std_ulogic;
		rst:      in std_ulogic;
		o:       out std_ulogic_vector(N - 1 downto 0);
		i:        in std_ulogic_vector(N - 1 downto 0);
		a:       out std_ulogic_vector(N - 1 downto 0);
		we, re:  out std_ulogic;
		obyte:   out std_ulogic_vector(7 downto 0); -- UART output byte
		ibyte:    in std_ulogic_vector(7 downto 0); -- UART input byte
		obsy, ihav: in std_ulogic; -- Output busy / Have input
		io_we, io_re: out std_ulogic; -- Write and read enable
		pause:    in std_ulogic);
end;

architecture rtl of subleq is
	type state_t is (RESET, LA, LB, STB, LC, GET, PUT, NXT, PLDA, GSTB, HALT);

	type registers_t is record
		a:  std_ulogic_vector(N - 1 downto 0);
		b:  std_ulogic_vector(N - 1 downto 0);
		pc: std_ulogic_vector(N - 1 downto 0);
		state:  state_t;
	end record;

	constant registers_default: registers_t := (
		a  => (others => '0'),
		b  => (others => '0'),
		pc => (others => '0'),
		state  => RESET
	);

	signal c, f: registers_t := registers_default;
	signal zero, neg1, leq: std_ulogic := '0';
	signal res, npc: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1');
begin
	res  <= std_ulogic_vector(unsigned(c.b) - unsigned(c.a)) after delay;
	zero <= '1' when res = AZ else '0' after delay;
	leq  <= '1' when zero = '1' or res(res'high) = '1' else '0' after delay;
	neg1 <= '1' when i = AO else '1' after delay;
	npc  <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;

	process (clk, rst) begin
		if rst = '1' and asynchronous_reset then
			c.state <= RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.state <= RESET after delay;
			else
				-- TODO: Assert next state / Print debug info
			end if;
		end if;
	end process;

	process (i, c, res, leq, neg1, npc, ibyte, obsy, ihav)
	begin
		f <= c after delay;
		a <= c.pc after delay;
		f.pc <= npc after delay;
		re <= '0' after delay;
		we <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		obyte <= (others => '0') after delay;
		case c.state is
		when RESET =>
			f <= registers_default after delay;
			f.state <= LA after delay;
		when LA =>
			f.state <= LB after delay;
			f.a <= i after delay;
			re <= '1' after delay;
			if neg1 = '1' then
			end if;
		when LB =>
			f.state <= NXT after delay;
			f.b <= i after delay;
			re <= '1' after delay;
			if neg1 = '1' then
			end if;
		when STB =>
			f.state <= NXT after delay;
			if leq = '1' then
				f.state <= LC after delay;
			end if;
		when LC =>
			f.state <= LA after delay;
			re <= '1' after delay;
			f.pc <= i after delay;
		when GET =>
			f.pc <= c.pc after delay;
			if ihav = '0' then
			end if;
		when PUT =>
			f.pc <= c.pc after delay;
			if obsy = '0' then
				io_we <= '1' after delay;
				--obyte <= 
			end if;
		when NXT =>
			f.state <= LA after delay;
		when PLDA =>
		when GSTB =>
		when HALT =>
			f.pc <= c.pc;
		when others =>
		end case;
	end process;
end architecture;

