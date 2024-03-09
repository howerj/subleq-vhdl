-- File:        top.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- Email:       howe.r.j.89@gmail.com
-- License:     MIT
-- Description: Top level entity; SUBLEQ CPU

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;

entity top is
	generic (
		g:               common_generics := default_settings;
		file_name:       string          := "subleq.dec";
		N:               positive        := 16;
		baud:            positive        := 115200;
		debug:           natural         := 0; -- will not synthesize if greater than zero (debug off = 0)
		uart_use_cfg:    boolean         := false;
		uart_fifo_depth: natural         := 0
	);
	port (
		clk:         in std_ulogic;
		-- synthesis translate_off
--		rst:         in std_ulogic;
		halted:     out std_ulogic;
		blocked:    out std_ulogic;
		-- synthesis translate_on
		tx:         out std_ulogic;
		rx:          in std_ulogic);
end entity;

architecture rtl of top is
	constant data_length: positive := N;
	constant W:           positive := N - 3;
	constant addr_length: positive := W;
	constant clks_per_bit: integer := g.clock_frequency / baud;

	signal rst:        std_ulogic := '0';
	signal i, o, a:    std_ulogic_vector(N - 1 downto 0) := (others => 'U');
	signal bsy, hav, re, we, io_re, io_we: std_ulogic := 'U';
	signal obyte, ibyte: std_ulogic_vector(7 downto 0) := (others => 'U');
begin

	system: entity work.system
	generic map(
		g => g,
		file_name => file_name,
		N => N,
		debug => debug
	)
	port map (
		clk     => clk,
		rst     => rst,
		-- synthesis translate_off
		halted  => halted,
		blocked => blocked,
		-- synthesis translate_on
		obyte   => obyte,
		ibyte   => ibyte,
		obsy    => bsy,
		ihav    => hav,
		io_we   => io_we, 
		io_re   => io_re);

	uart_tx_0: entity work.uart_tx
		generic map(clks_per_bit => clks_per_bit)
		port map(
			clk => clk,
			i_tx_dv => io_we,
			i_tx_byte => obyte,
			o_tx_active => bsy,
			o_tx_serial => tx,
			o_tx_done => open);

	-- TODO: Capture contents in register...
	hav <= '0';
	uart_rx_0: entity work.uart_rx
		generic map(clks_per_bit => clks_per_bit)
		port map(
			clk => clk,
			i_rx_serial => rx,
			o_rx_dv => open,
			o_rx_byte => ibyte);

end architecture;


