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
		file_name:       string          := "subleq.hex";
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
		halt:       out std_ulogic;
		-- synthesis translate_on
		tx:         out std_ulogic;
		rx:          in std_ulogic);
end entity;

architecture rtl of top is
	constant data_length: positive := N;
	constant W:           positive := N - 3;
	constant addr_length: positive := W;

	signal tx_fifo_full:  std_ulogic;
	signal tx_fifo_empty: std_ulogic;
	signal tx_fifo_we:    std_ulogic;
	signal tx_fifo_data:  std_ulogic_vector(7 downto 0);

	signal rx_fifo_full:  std_ulogic;
	signal rx_fifo_empty: std_ulogic;
	signal rx_fifo_re:    std_ulogic;
	signal rx_fifo_data:  std_ulogic_vector(7 downto 0);

	signal reg:             std_ulogic_vector(15 downto 0);
	signal clock_reg_tx_we: std_ulogic;
	signal clock_reg_rx_we: std_ulogic;
	signal control_reg_we:  std_ulogic;


	signal rst:        std_ulogic := '0';
	signal i, o, a:    std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal bsy, hav, re, we, io_re, io_we: std_ulogic := 'X';
	signal obyte, ibyte: std_ulogic_vector(7 downto 0) := (others => 'X');
begin
	cpu: entity work.subleq
		generic map (
			asynchronous_reset => g.asynchronous_reset,
			delay              => g.delay,
			N                  => N,
			debug              => debug)
		port map (
			clk => clk, rst => rst,
			-- synthesis translate_off
			halt => halt,
			pause => '0',
			-- synthesis translate_on
			i => i,
			o => o, a => a, 
			obsy => bsy,
			ihav => hav,
			io_re => io_re,
			io_we => io_we,
			re => re,
			we => we,
			obyte => obyte,
			ibyte => ibyte
		);

	bram: entity work.single_port_block_ram
		generic map(
			g           => g,
			file_name   => file_name,
			file_type   => FILE_HEX,
			addr_length => addr_length,
			data_length => data_length)
		port map (
			clk  => clk,
			dwe  => we,
			addr => a(addr_length - 1 downto 0),
			dre  => re,
			din  => o,
			dout => i);

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
			tx_fifo_we       =>  tx_fifo_we,
			tx_fifo_data     =>  tx_fifo_data,

			rx               =>  rx,
			rx_fifo_full     =>  rx_fifo_full,
			rx_fifo_empty    =>  rx_fifo_empty,
			rx_fifo_re       =>  rx_fifo_re,
			rx_fifo_data     =>  rx_fifo_data,

			reg              =>  reg,
			clock_reg_tx_we  =>  clock_reg_tx_we,
			clock_reg_rx_we  =>  clock_reg_rx_we,
			control_reg_we   =>  control_reg_we);
end architecture;


