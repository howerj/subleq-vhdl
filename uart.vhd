-- PACKAGE: UART TX/RX
-- AUTHOR:  Nandland, changes (Richard James Howe)
-- LICENSE: MIT
-- REPO:    <https://github.com/howerj/subleq-vhdl>
--
-- Taken from <https://github.com/nandland/UART>, commit
-- 4ae04682b0e59f4b9d93a4f99b06990e5bcb5cc2, it is MIT licensed, and 
-- is smaller (and less featureful) than the UART I made at
-- <https://github.com/howerj/forth-cpu>. The original copyright
-- notice is:
--
-- TODO:
-- * [ ] Change naming conventions, style, whitespace
-- * [x] Integrate into main project
-- * [ ] Optional sync/async reset?
-- * [ ] Make system more configurable (N-Bit), invert, ...
--
-- -------------------------------------------------------------------------------
--
-- MIT License
-- 
-- Copyright (c) 2022 nandland
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- 
-- -------------------------------------------------------------------------------
-- 
-- A description of the module is available from <http://www.nandland.com>
-- as well.
-- 
library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uart_pkg is
	component uart_rx is
		generic (clks_per_bit : integer := 217);
		port (
			clk:          in  std_ulogic;
			i_rx_serial:  in  std_ulogic;
			o_rx_dv:     out std_ulogic;
			o_rx_byte:   out std_ulogic_vector(7 downto 0));
	end component;

	component uart_tx is
		generic (clks_per_bit: integer := 217);
		port (
			clk:          in  std_ulogic;
			i_tx_dv:      in  std_ulogic;
			i_tx_byte:    in  std_ulogic_vector(7 downto 0);
			o_tx_active: out std_ulogic;
			o_tx_serial: out std_ulogic;
			o_tx_done:   out std_ulogic);
	end component;

	component uart_rx_tb is
	end component;

	component uart_tb is
	end component;

	procedure uart_write_byte( -- Simulation only
		bit_period: in time; -- 8680 ns for 115200
		data_input_byte: in std_ulogic_vector(7 downto 0);
		signal tx_line: out std_ulogic);

--	procedure uart_write_byte( -- Simulation only
--		bit_period: in time; -- 8680 ns for 115200
--		data_input_byte: in character;
--		signal tx_line: out std_ulogic);
end package;

package body uart_pkg is
	procedure uart_write_byte(
		bit_period: in time; -- 8680 ns for 115200
		data_input_byte: in std_ulogic_vector(7 downto 0);
		signal tx_line: out std_ulogic) is -- Make sure to set to '1' during signal declaration.
	begin -- Test Bench Low Level UART Write byte (pretty neat) 8N1 format only
		tx_line <= '0'; -- Send Start Bit
		wait for bit_period;
		
		for i in 0 to data_input_byte'high loop -- Send Data Byte
			tx_line <= data_input_byte(i);
			wait for bit_period;
		end loop;
		
		tx_line <= '1'; -- Send Stop Bit
		wait for bit_period;
	end;

--	procedure uart_write_byte(
--		bit_period: in time; -- 8680 ns for 115200
--		data_input_byte: character;
--		signal tx_line: out std_ulogic) is -- Make sure to set to '1' during signal declaration.
--	begin
--		uart_write_byte(bit_period, std_ulogic_vector(to_unsigned(character'pos(data_input_byte), 8)), tx_line);
--	end;
end;

-- This file contains the UART Receiver.  This receiver is able to
-- receive 8 bits of serial data, one start bit, one stop bit,
-- and no parity bit.  When receive is complete o_rx_dv will be
-- driven high for one clock cycle.
-- 
-- Set Generic clks_per_bit as follows:
-- clks_per_bit = (Frequency of clk)/(Frequency of UART)
-- Example: 25 MHz Clock, 115200 baud UART
-- (25000000)/(115200) = 217
--
library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_rx is
	generic (clks_per_bit: integer := 217);
	port (
		clk: in std_ulogic;
		i_rx_serial: in std_ulogic;
		o_rx_dv: out std_ulogic;
		o_rx_byte: out std_ulogic_vector(7 downto 0));
end entity;

architecture rtl of uart_rx is
	type state_t is (s_idle, s_rx_start_bit, s_rx_data_bits, s_rx_stop_bit, s_cleanup);
	signal state: state_t := s_idle;

	signal r_clk_count: integer range 0 to clks_per_bit - 1 := 0;
	signal bit_index: integer range 0 to 7 := 0; -- 8 bits total
	signal r_rx_byte:   std_ulogic_vector(7 downto 0) := (others => '0');
	signal r_rx_dv:     std_ulogic := '0';
begin

	process (clk)
	begin
		if rising_edge(clk) then
			case state is
			when s_Idle =>
				r_rx_dv <= '0';
				r_clk_count <= 0;
				bit_index <= 0;
				if i_rx_serial = '0' then -- Start bit detected
					state <= s_rx_start_bit;
				else
					state <= s_idle;
				end if;
			when s_RX_Start_Bit => -- Check middle of start bit to make sure it's still low
				if r_clk_count = (clks_per_bit - 1) / 2 then
					if i_rx_serial = '0' then
						r_clk_count <= 0; -- reset counter since we found the middle
						state <= s_rx_data_bits;
					else
						state <= s_idle;
					end if;
				else
					r_clk_count <= r_clk_count + 1;
					state <= s_rx_start_bit;
				end if;
			when s_rx_data_bits => -- Wait clks_per_bit - 1 clock cycles to sample serial data
				if r_clk_count < clks_per_bit - 1 then
					r_clk_count <= r_clk_count + 1;
					state <= s_rx_data_bits;
				else
					r_clk_count <= 0;
					r_rx_byte(bit_index) <= i_rx_serial;
					
					-- Check if we have sent out all bits
					if bit_index < 7 then
						bit_index <= bit_index + 1;
						state <= s_rx_data_bits;
					else
						bit_index <= 0;
						state <= s_rx_stop_bit;
					end if;
				end if;
			when s_rx_stop_bit => -- Receive Stop bit. Stop bit = 1
				-- Wait clks_per_bit - 1 clock cycles for Stop bit to finish
				if r_clk_count < clks_per_bit - 1 then
					r_clk_count <= r_clk_count + 1;
					state <= s_rx_stop_bit;
				else
					r_rx_dv <= '1';
					r_clk_count <= 0;
					state <= s_cleanup;
				end if;
			when s_cleanup => -- Stay here 1 clock
				state <= s_idle;
				r_rx_dv <= '0';
			when others =>
				state <= s_idle;
			end case;
		end if;
	end process;

	o_rx_dv <= r_rx_dv;
	o_rx_byte <= r_rx_byte;
end RTL;

-- This file module contains the UART Transmitter.  This transmitter is able
-- to transmit 8 bits of serial data, one start bit, one stop bit,
-- and no parity bit.  When transmit is complete o_tx_done will be
-- driven high for one clock cycle.
--
-- Set Generic clks_per_bit as follows:
-- clks_per_bit = (Frequency of clk)/(Frequency of UART)
-- Example: 25 MHz Clock, 115200 baud UART
-- (25000000)/(115200) = 217
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_tx is
	generic (clks_per_bit: integer := 217);
	port (
		clk:          in std_ulogic;
		i_tx_dv:      in std_ulogic;
		i_tx_byte:    in std_ulogic_vector(7 downto 0);
		o_tx_active: out std_ulogic;
		o_tx_serial: out std_ulogic;
		o_tx_done:   out std_ulogic);
end entity;

architecture rtl of uart_tx is
	type state_t is (idle, tx_start_bit, tx_data_bits, tx_stop_bit, cleanup);
	signal state: state_t := idle;

	signal r_clk_count: integer range 0 to clks_per_bit - 1 := 0;
	signal bit_index: integer range 0 to i_tx_byte'high := 0;  -- 8 bits total
	signal r_tx_data: std_ulogic_vector(i_tx_byte'range) := (others => '0');
	signal r_tx_done: std_ulogic := '0';
begin
	process (clk)
	begin
		if rising_edge(clk) then
			r_tx_done <= '0'; -- Default assignment
			case state is
			when idle =>
				o_tx_active <= '0';
				o_tx_serial <= '1'; -- Drive Line High for Idle
				r_clk_count <= 0;
				bit_index <= 0;

				if i_tx_dv = '1' then
					r_tx_data <= i_tx_byte;
					state <= tx_start_bit;
				else
					state <= idle;
				end if;
			when tx_start_bit => -- Send out Start Bit. Start bit = 0
				o_tx_active <= '1';
				o_tx_serial <= '0';

				-- Wait clks_per_bit - 1 clock cycles for start bit to finish
				if r_clk_count < clks_per_bit - 1 then
					r_clk_count <= r_clk_count + 1;
					state <= tx_start_bit;
				else
					r_clk_count <= 0;
					state <= tx_data_bits;
				end if;
			when tx_data_bits => -- Wait clks_per_bit - 1 clock cycles for data bits to finish
				o_tx_serial <= r_tx_data(bit_index);
				
				if r_clk_count < clks_per_bit - 1 then
					r_clk_count <= r_clk_count + 1;
					state <= tx_data_bits;
				else
					r_clk_count <= 0;
					
					-- Check if we have sent out all bits
					if bit_index < i_tx_byte'high then
						bit_index <= bit_index + 1;
						state <= tx_data_bits;
					else
						bit_index <= 0;
						state <= tx_stop_bit;
					end if;
				end if;
			when tx_stop_bit => -- Send out Stop bit. Stop bit = 1
				o_tx_serial <= '1';

				-- Wait clks_per_bit - 1 clock cycles for Stop bit to finish
				if r_clk_count < clks_per_bit - 1 then
					r_clk_count <= r_clk_count + 1;
					state <= tx_stop_bit;
				else
					r_tx_done <= '1';
					r_clk_count <= 0;
					state <= cleanup;
				end if;
			when cleanup => -- Stay here 1 clock
				o_tx_active <= '0';
				state <= idle;
			when others =>
				state <= idle;
			end case;
		end if;
	end process;
	o_tx_done <= r_tx_done;
end architecture;
----------------------------------------------------------------------
-- Tests RX Behavior
----------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_rx_tb is
end uart_rx_tb;

architecture behave of uart_rx_tb is
	-- Test Bench uses a 25 MHz Clock
	constant clk_period: time := 40 ns;
	
	-- Want to interface to 115200 baud UART
	-- 25000000 / 115200 = 217 Clocks Per Bit.
	constant c_clks_per_bit: integer := 217;

	-- 1/115200:
	constant c_bit_period: time := 8680 ns;
	
	signal clk: std_ulogic := '0';
	signal w_rx_byte: std_ulogic_vector(7 downto 0);
	signal r_rx_serial: std_ulogic := '1';
begin
	uart_rx_inst: entity work.uart_rx
		generic map (clks_per_bit => c_clks_per_bit)
		port map (
			clk => clk,
			i_rx_serial => r_rx_serial,
			o_rx_dv => open,
			o_rx_byte => w_rx_byte);

	clk <= not clk after clk_period/2;
	
	process is
	begin
		-- Send a command to the UART
		wait until rising_edge(clk);
		uart_write_byte(c_bit_period, x"3F", r_rx_serial);
		wait until rising_edge(clk);

		-- Check that the correct command was received
		if w_rx_byte = x"3F" then
			report "Test Passed - Correct Byte Received" severity note;
		else 
			report "Test Failed - Incorrect Byte Received" severity note;
		end if;

		assert false report "Tests Complete" severity failure;
	end process;
end architecture;
----------------------------------------------------------------------
-- UART test bench
----------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_tb is
end uart_tb;

architecture behave of uart_tb is
	-- Test Bench uses a 25 MHz Clock
	constant clk_period: time := 40 ns;
	
	-- Want to interface to 115200 baud UART
	-- 25000000 / 115200 = 217 Clocks Per Bit.
	constant c_clks_per_bit: integer := 217;

	constant c_bit_period: time := 8680 ns;
	
	signal clk: std_ulogic := '0';
	signal r_tx_dv: std_ulogic := '0';
	signal r_tx_byte: std_ulogic_vector(7 downto 0) := (others => '0');
	signal w_tx_serial: std_ulogic;
	signal w_tx_done: std_ulogic;
	signal w_rx_dv: std_ulogic;
	signal w_rx_byte: std_ulogic_vector(7 downto 0);
	signal r_rx_serial: std_ulogic := '1';
begin
	uart_tx_inst: entity work.uart_tx
		generic map (clks_per_bit => c_clks_per_bit)
		port map (
			clk => clk,
			i_tx_dv => r_tx_dv,
			i_tx_byte => r_tx_byte,
			o_tx_active => open,
			o_tx_serial => w_tx_serial,
			o_tx_done => w_tx_done);

	uart_rx_inst: entity work.uart_rx
		generic map (clks_per_bit => c_clks_per_bit)
		port map (
			clk => clk,
			i_rx_serial => r_rx_serial,
			o_rx_dv => w_rx_dv,
			o_rx_byte => w_rx_byte);

	clk <= not clk after clk_period/2;
	
	process is
	begin
		-- Tell the UART to send a command.
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		r_tx_dv <= '1';
		r_tx_byte <= x"AB";
		wait until rising_edge(clk);
		r_tx_dv <= '0';
		wait until w_tx_done = '1';

		-- Send a command to the UART
		wait until rising_edge(clk);
		uart_write_byte(c_bit_period, x"37", r_rx_serial);
		wait until rising_edge(clk);

		-- Check that the correct command was received
		if w_rx_byte = x"37" then
			report "Test Passed - Correct Byte Received" severity note;
		else 
			report "Test Failed - Incorrect Byte Received" severity note;
		end if;

		assert false report "Tests Complete" severity failure;
	end process;
end architecture;

