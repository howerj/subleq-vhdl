-- File:        system.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- Email:       howe.r.j.89@gmail.com
-- License:     MIT
-- Description: system level entity; SUBLEQ CPU
--
-- This module instantiates the SUBLEQ CPU and a Block RAM with
-- a program file specified via a generic.
--
-- The main reason to have this module and not instantiate everything in
-- a top level module is for two reasons, firstly so that a test bench
-- can interact with this subsystem without simulating any I/O peripherals
-- (such as a UART) which is more expensive and so would slow down the
-- simulation (a slower test bench that encompasses I/O as well should
-- also be present) and secondly to make it easier to swap out I/O for
-- other implementations and mechanisms.
--

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;

entity system is
	generic (
		g:         common_generics := default_settings;
		file_name: string          := "subleq.dec";
		N:         positive        := 16;
		debug:     natural         := 0 -- will not synthesize if greater than zero (debug off = 0)
	);
	port (
		clk:           in std_ulogic;
		rst:           in std_ulogic;
		-- synthesis translate_off
		halted:       out std_ulogic;
		blocked:      out std_ulogic;
		-- synthesis translate_on
		obyte:        out std_ulogic_vector(7 downto 0);
		ibyte:         in std_ulogic_vector(7 downto 0);
		obsy, ihav:    in std_ulogic;
		io_we, io_re: out std_ulogic);
end entity;

architecture rtl of system is
	constant data_length: positive := N;
	constant addr_length: positive := N - 3;

	signal i, o, a: std_ulogic_vector(N - 1 downto 0) := (others => 'U');
	signal re, we:  std_ulogic := 'U';
begin
	cpu: entity work.subleq
		generic map (
			asynchronous_reset => g.asynchronous_reset,
			delay              => g.delay,
			N                  => N,
			debug              => debug)
		port map (
			clk     => clk, 
			rst     => rst,
			-- synthesis translate_off
			halted  => halted,
			blocked => blocked,
			-- synthesis translate_on
			pause   => '0',
			i       => i,
			o       => o, 
			a       => a, 
			obsy    => obsy,
			ihav    => ihav,
			io_re   => io_re,
			io_we   => io_we,
			re      => re,
			we      => we,
			obyte   => obyte,
			ibyte   => ibyte);

	bram: entity work.single_port_block_ram
		generic map(
			g           => g,
			file_name   => file_name,
			file_type   => FILE_DECIMAL,
			addr_length => addr_length,
			data_length => data_length)
		port map (
			clk  => clk,
			dwe  => we,
			addr => a(addr_length - 1 downto 0),
			dre  => re,
			din  => o,
			dout => i);
end architecture;


