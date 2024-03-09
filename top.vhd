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

	signal tx_fifo_full:  std_ulogic := '0';
	signal tx_fifo_empty: std_ulogic := '0';
	signal tx_fifo_we:    std_ulogic := '0';
	signal tx_fifo_data:  std_ulogic_vector(7 downto 0) := (others => '0');

	signal rx_fifo_full:  std_ulogic := '0';
	signal rx_fifo_empty: std_ulogic := '0';
	signal rx_fifo_re:    std_ulogic := '0';
	signal rx_fifo_data:  std_ulogic_vector(7 downto 0) := (others => '0');

	signal reg:             std_ulogic_vector(15 downto 0) := (others => '0');
	signal clock_reg_tx_we: std_ulogic := '0';
	signal clock_reg_rx_we: std_ulogic := '0';
	signal control_reg_we:  std_ulogic := '0';

	signal rst:        std_ulogic := '0';
	signal i, o, a:    std_ulogic_vector(N - 1 downto 0) := (others => 'U');
	signal bsy, hav, re, we, io_re, io_we: std_ulogic := 'U';
	signal obyte, ibyte: std_ulogic_vector(7 downto 0) := (others => 'U');
begin
	hav <= not rx_fifo_empty;
	bsy <= not tx_fifo_empty;

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

	uart: entity work.uart_top
		generic map (
			clock_frequency    => g.clock_frequency,
			delay              => g.delay,
			asynchronous_reset => g.asynchronous_reset,
			baud               => baud,
			fifo_depth         => uart_fifo_depth,
			use_cfg            => uart_use_cfg)
		port map(
			clk => clk, rst => rst,

			tx               =>  tx,
			tx_fifo_full     =>  tx_fifo_full,
			tx_fifo_empty    =>  tx_fifo_empty,
			tx_fifo_we       =>  io_we,
			tx_fifo_data     =>  obyte,

			rx               =>  rx,
			rx_fifo_full     =>  rx_fifo_full,
			rx_fifo_empty    =>  rx_fifo_empty,
			rx_fifo_re       =>  io_re,
			rx_fifo_data     =>  ibyte,

			reg              =>  reg,
			clock_reg_tx_we  =>  clock_reg_tx_we,
			clock_reg_rx_we  =>  clock_reg_rx_we,
			control_reg_we   =>  control_reg_we);
end architecture;


