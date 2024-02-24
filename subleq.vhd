-- File:        subleq.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- License:     MIT / Public Domain
-- Description: SUBLEQ CPU
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
	type state_t is (S_RESET, S_A, S_B, S_C, S_LA, S_LB, S_RESULT, S_STORE, S_JMP, S_NJMP, S_IN, S_IN_STORE, S_OUT, S_HALT);

	type registers_t is record
		a:  std_ulogic_vector(N - 1 downto 0);
		b:  std_ulogic_vector(N - 1 downto 0);
		c:  std_ulogic_vector(N - 1 downto 0);
		la: std_ulogic_vector(N - 1 downto 0);
		lb: std_ulogic_vector(N - 1 downto 0);
		pc: std_ulogic_vector(N - 1 downto 0);
		res: std_ulogic_vector(N - 1 downto 0);
		state:  state_t;
		input: std_ulogic;
		output: std_ulogic;
		stop: std_ulogic;
	end record;

	constant registers_default: registers_t := (
		a  => (others => '0'),
		b  => (others => '0'),
		c  => (others => '0'),
		la => (others => '0'),
		lb => (others => '0'),
		pc => (others => '0'),
		res => (others => '0'),
		state  => S_RESET,
		input  => '0',
		output => '0',
		stop => '0'
	);

	signal c, f: registers_t := registers_default;
	signal neg1, leq, stop: std_ulogic := '0';
	signal sub, npc: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1');
begin
	npc <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	neg1 <= '1' when i = AO else '0' after delay;
	stop <= '1' when c.pc(c.pc'high) = '1' else '0' after delay;
	sub <= std_ulogic_vector(unsigned(c.lb) - unsigned(c.la)) after delay;
	leq <= '1' when c.res(c.res'high) = '1' or c.res = AZ else '0' after delay;
	o <= c.res after delay;
	obyte <= c.la(obyte'range) after delay;

	process (clk, rst) begin
		if rst = '1' and asynchronous_reset then
			c.state <= S_RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.state <= S_RESET after delay;
			else
				null;
				-- Debugging goes here
			end if;
		end if;
	end process;

	process (c, i, npc, neg1, leq, sub, ibyte, obsy, ihav, pause, stop) begin
		f <= c after delay;
		halt <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		we <= '0' after delay;
		re <= '0' after delay;
		a <= c.pc after delay;
		if stop = '1' then f.stop <= '1' after delay; end if;

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
			if c.stop = '1' then
				f.state <= S_HALT after delay;
			end if;
		when S_B =>
			f.state <= S_C after delay;
			f.b <= i after delay;
			re <= '1' after delay;
			a <= npc after delay;
			f.pc <= npc after delay;
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
			f.state <= S_RESULT after delay;
			f.lb <= i after delay;
			a <= c.b after delay;
			re <= '1' after delay;
		when S_RESULT =>
			f.state <= S_STORE after delay;
			f.res <= sub after delay;
			a <= c.b after delay;
			if c.a = AO then
				f.state <= S_IN after delay;
				f.res <= (others => '0');
				f.res(ibyte'range) <= ibyte;
			elsif c.b = AO then
				f.state <= S_OUT after delay;
			end if;
		when S_STORE =>
			f.state <= S_NJMP after delay;
			a <= c.b after delay;
			we <= '1' after delay;
			if leq = '1' then
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
			end if;
		when S_IN_STORE =>
			f.state <= S_NJMP after delay;
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
