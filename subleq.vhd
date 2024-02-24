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
	type state_t is (S_RESET, S_A, S_LA, S_B, S_LB, S_C, S_NJMP, S_IN, S_OUT, S_HALT);

	type registers_t is record
		a:  std_ulogic_vector(N - 1 downto 0);
		la: std_ulogic_vector(N - 1 downto 0);
		b:  std_ulogic_vector(N - 1 downto 0);
		lb: std_ulogic_vector(N - 1 downto 0);
		c:  std_ulogic_vector(N - 1 downto 0);
		pc: std_ulogic_vector(N - 1 downto 0);
		state:  state_t;
		input: std_ulogic;
		output: std_ulogic;
	end record;

	constant registers_default: registers_t := (
		a  => (others => '0'),
		la => (others => '0'),
		b  => (others => '0'),
		lb => (others => '0'),
		c  => (others => '0'),
		pc => (others => '0'),
		state  => S_RESET,
		input  => '0',
		output => '0'
	);

	signal c, f: registers_t := registers_default;
	signal zero, neg1, leq, stop: std_ulogic := '0';
	signal res, npc: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1');
begin
	npc <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	neg1 <= '1' when i = AO else '0' after delay;
	zero <= '1' when i = AZ else '0' after delay;
	stop <= '1' when c.pc(c.pc'high) = '1' else '0' after delay;

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

	process (c, i, npc, zero, neg1, leq, ibyte, obsy, ihav, pause, stop) begin
		f <= c after delay;
		halt <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		we <= '0' after delay;
		re <= '0' after delay;
		a <= c.pc after delay;
		o <= (others => '0') after delay;
		obyte <= (others => '0') after delay;

		case c.state is
		when S_RESET => 
			f <= registers_default after delay;
			f.state <= S_A after delay;
		when S_A =>
			f.a <= i after delay;
			if stop = '1' then
				f.state <= S_HALT after delay;
			elsif neg1 = '1' then
				f.state <= S_B after delay;
				f.input <= '1' after delay;
			else
				f.state <= S_LA after delay;
				re <= '1' after delay;
				a <= i after delay;
				f.input <= '0' after delay;
			end if;
		when S_LA =>
			f.state <= S_B after delay;
			f.la <= i after delay;
			f.pc <= npc after delay;
			re <= '1' after delay;
		when S_B =>
			f.b <= i after delay;
			f.output <= '0' after delay;
			f.state <= S_LB after delay;
			if neg1 = '1' then
				f.state <= S_OUT after delay;
				f.output <= '1' after delay;
			else
				re <= '1' after delay;
				a <= i after delay;
			end if;
		when S_LB =>
			if leq = '1' then
				f.state <= S_C after delay;
				re <= '1' after delay;
				f.pc <= npc after delay;
			else
				f.pc <= npc after delay;
				f.state <= S_NJMP after delay;
			end if;
		when S_C =>
			f.c <= i after delay;
			f.pc <= i after delay;
			f.state <= S_A after delay;
		when S_NJMP =>
			f.state <= S_A after delay;
			f.pc <= npc after delay;
		when S_IN =>
			if ihav = '1' then
				f.state <= S_A after delay;
			end if;
		when S_OUT =>
			if obsy = '0' then
				f.state <= S_A after delay;
			end if;
		when S_HALT =>
			halt <= '1' after delay;
		end case;

	end process;

end architecture;
